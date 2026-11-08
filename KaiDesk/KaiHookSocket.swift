//
//  KaiHookSocket.swift
//  Kai Desk
//
//  The local channel between the `kai-hook` helper and the app: a Unix socket in the user's own
//  folder. No network port is opened. The server accepts only connections from the same user.
//

import Darwin
import Foundation

public enum KaiHookSocket {
    /// `~/Library/Application Support/Kai OS/kai.sock`
    /// `KAI_SOCKET_PATH` overrides it, so a test copy of the app never touches the real socket.
    public static var defaultPath: String {
        if let override = ProcessInfo.processInfo.environment["KAI_SOCKET_PATH"], !override.isEmpty { return override }
        return KaiDeskFile.supportFolder.appendingPathComponent("kai.sock").path
    }

    fileprivate static func address(_ path: String) -> (sockaddr_un, socklen_t)? {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        addr.sun_len = UInt8(length)
        return (addr, length)
    }

    fileprivate static func readAll(fd: Int32, limit: Int, deadline: Date) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let remaining = Int(deadline.timeIntervalSinceNow * 1000)
            if remaining <= 0 { return nil }
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pfd, 1, Int32(min(remaining, 1000)))
            if ready < 0 { if errno == EINTR { continue }; return nil }
            if ready == 0 { continue }
            let count = read(fd, &buffer, buffer.count)
            if count < 0 { if errno == EINTR || errno == EAGAIN { continue }; return nil }
            if count == 0 { return data }
            data.append(buffer, count: count)
            if data.count > limit { return nil }
        }
    }

    fileprivate static func writeAll(fd: Int32, _ data: Data) -> Bool {
        var offset = 0
        return data.withUnsafeBytes { raw -> Bool in
            while offset < data.count {
                let written = write(fd, raw.baseAddress! + offset, data.count - offset)
                if written < 0 { if errno == EINTR { continue }; return false }
                offset += written
            }
            return true
        }
    }
}

/// Used by the `kai-hook` helper.
public enum KaiHookClient {
    /// Sends one payload. With `waitForReply`, returns the reply (empty when the app gave no decision).
    /// Returns nil when the app is not running, the socket is not a socket owned by this user, or the
    /// wait ran out. Callers treat nil as "no decision", so Claude Code asks in the terminal as usual.
    public static func send(_ payload: Data, socketPath: String, waitForReply: Bool, timeout: TimeInterval) -> Data? {
        var info = stat()
        guard lstat(socketPath, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFSOCK,
              info.st_uid == geteuid(),
              let (addr, length) = KaiHookSocket.address(socketPath) else { return nil }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var target = addr
        let connected = withUnsafePointer(to: &target) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, length) }
        }
        guard connected == 0, KaiHookSocket.writeAll(fd: fd, payload) else { return nil }
        shutdown(fd, SHUT_WR)
        guard waitForReply else { return Data() }
        return KaiHookSocket.readAll(fd: fd, limit: 64 * 1024, deadline: Date().addingTimeInterval(timeout))
    }
}

/// Used by the app. Calls `handler` for each event. For a permission request the connection stays
/// open until the handler answers, or until `permissionTimeout` passes (then it closes with no decision).
public final class KaiHookServer: @unchecked Sendable {
    public typealias Handler = @Sendable (KaiHookEvent, @escaping @Sendable (KaiHookDecision?) -> Void) -> Void

    public static let permissionTimeout: TimeInterval = 56

    private let path: String
    private let permissionTimeout: TimeInterval
    private let handler: Handler
    private let queue = DispatchQueue(label: "ai.kai.hook-server", attributes: .concurrent)
    private var listenFD: Int32 = -1
    private var source: DispatchSourceRead?

    public init(path: String = KaiHookSocket.defaultPath,
                permissionTimeout: TimeInterval = KaiHookServer.permissionTimeout,
                handler: @escaping Handler) {
        self.path = path
        self.permissionTimeout = permissionTimeout
        self.handler = handler
    }

    public var isRunning: Bool { source != nil }

    public func start() throws {
        guard source == nil else { return }
        let folder = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        // Only replace a stale socket that this user owns.
        var info = stat()
        if lstat(path, &info) == 0 {
            guard (info.st_mode & S_IFMT) == S_IFSOCK, info.st_uid == geteuid() else {
                throw NSError(domain: "KaiHookServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(path) exists and is not a socket owned by you."])
            }
            unlink(path)
        }
        guard let (addr, length) = KaiHookSocket.address(path) else {
            throw NSError(domain: "KaiHookServer", code: 2, userInfo: [NSLocalizedDescriptionKey: "The socket path is too long."])
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw posixError("socket") }
        var target = addr
        let bound = withUnsafePointer(to: &target) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, length) }
        }
        guard bound == 0 else { close(fd); throw posixError("bind") }
        chmod(path, 0o600)
        guard listen(fd, 16) == 0 else { close(fd); unlink(path); throw posixError("listen") }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPending() }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    public func stop() {
        source?.cancel()
        source = nil
        listenFD = -1
        unlink(path)
    }

    private func posixError(_ what: String) -> NSError {
        NSError(domain: "KaiHookServer", code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "\(what): \(String(cString: strerror(errno)))"])
    }

    private func acceptPending() {
        while true {
            let client = accept(listenFD, nil, nil)
            if client < 0 { return }
            var noSigPipe: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
            var uid: uid_t = 0, gid: gid_t = 0
            guard getpeereid(client, &uid, &gid) == 0, uid == geteuid() else { close(client); continue }
            queue.async { [weak self] in self?.serve(client) }
        }
    }

    private func serve(_ client: Int32) {
        // The client sends the payload, then half-closes. The listening socket is non-blocking,
        // but accepted sockets may inherit that, so make this one blocking for poll-driven reads.
        _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
        guard let data = KaiHookSocket.readAll(fd: client, limit: 1_000_000, deadline: Date().addingTimeInterval(5)),
              let event = KaiHookEvent.parse(data) else {
            close(client)
            return
        }
        guard event.name == .permissionRequest else {
            handler(event) { _ in }
            close(client)
            return
        }
        let once = Once()
        let finish: @Sendable (KaiHookDecision?) -> Void = { decision in
            guard once.claim() else { return }
            if let decision { _ = KaiHookSocket.writeAll(fd: client, decision.outputJSON) }
            close(client)
        }
        handler(event, finish)
        queue.asyncAfter(deadline: .now() + permissionTimeout) { finish(nil) }
    }
}

/// Lets exactly one caller through.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if used { return false }
        used = true
        return true
    }
}
