//
//  KaiKnowledgeFolders.swift
//  Kai Knowledge
//
//  The folders the person chose for Kai to read, and the files they dropped in. The list is a small
//  private file; the rules for what is skipped (other people's code, build output, secrets) live here so
//  they can be tested. Kai reads only the folders on the list and never follows a link out of one.
//

import Foundation

public struct KaiKnowledgeFolder: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var path: String
    public var enabled: Bool
    /// More folder names to skip, besides the built-in ones.
    public var skipNames: [String]
    public var addedAt: Date

    public init(id: String = UUID().uuidString.prefix(8).lowercased().description, path: String, enabled: Bool = true,
                skipNames: [String] = [], addedAt: Date = Date()) {
        self.id = id
        self.path = path
        self.enabled = enabled
        self.skipNames = skipNames
        self.addedAt = addedAt
    }

    public var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
    public var name: String { url.lastPathComponent.isEmpty ? path : url.lastPathComponent }
}

/// What the last pass found in one folder.
public struct KaiFolderResult: Equatable, Sendable {
    public var indexed = 0
    /// Too big, no text in them, or named like a secret.
    public var skipped = 0
    public var available = true

    public init(indexed: Int = 0, skipped: Int = 0, available: Bool = true) {
        self.indexed = indexed
        self.skipped = skipped
        self.available = available
    }
}

public enum KaiKnowledgeFolders {
    public static let maxFolders = 12
    public static let maxFilesPerFolder = 4_000

    /// Folders that are only build output, caches or other people's code. Never read, in any folder.
    public static let skippedDirectories: Set<String> = [
        "node_modules", ".git", "build", "dist", "deriveddata", ".build", "pods", "venv", ".venv", "__pycache__",
        "library", "target", "vendor", "caches", ".trash", "site-packages", "bower_components",
    ]

    static let secretWords = ["password", "passwd", "secret", "credential", "private_key", "private-key", "id_rsa", "id_ed25519", "apikey", "api_key", "api-key", "token", "seed phrase", "recovery key"]
    static let secretExtensions: Set<String> = ["pem", "key", "p12", "pfx", "kdbx", "keychain", "keystore", "jks", "cer", "crt", "gpg", "asc"]

    /// A file named like something that holds a secret is never read, whatever is in it.
    public static func looksSecret(fileName: String) -> Bool {
        let lower = fileName.lowercased()
        if lower.hasPrefix(".env") || lower == "env" { return true }
        if secretExtensions.contains((lower as NSString).pathExtension) { return true }
        return secretWords.contains { lower.contains($0) }
    }

    public static func skips(directory name: String, extra: [String] = []) -> Bool {
        let lower = name.lowercased()
        return skippedDirectories.contains(lower) || extra.contains { $0.lowercased() == lower }
    }

    /// Why a folder can't be added, or nil if it can. The home folder, the system and Kai's own data are too broad or too private.
    public static func problem(adding url: URL, to existing: [KaiKnowledgeFolder], home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return "That isn't a folder." }
        let homePath = home.resolvingSymlinksInPath().standardizedFileURL.path
        let tooBroad: Set<String> = ["/", homePath, "/Users", "/System", "/Library", "/Applications", "/usr", "/bin", "/sbin", "/private", "/etc", "/var", "/opt",
                                     homePath + "/Library", homePath + "/Applications"]
        if tooBroad.contains(path) { return "That folder is too broad. Pick a folder with the files you want Kai to know about, such as Documents or a project." }
        if path.hasPrefix(homePath + "/Library/") || path.hasPrefix("/System/") || path.hasPrefix("/private/") {
            return "Kai doesn't read system or app data folders."
        }
        if existing.count >= maxFolders { return "Kai reads up to \(maxFolders) folders. Remove one first." }
        for folder in existing {
            let other = folder.url.resolvingSymlinksInPath().standardizedFileURL.path
            if other == path { return "That folder is already on the list." }
            if path.hasPrefix(other + "/") { return "That folder is already inside “\(folder.name)”." }
        }
        return nil
    }

    // MARK: Files dropped in

    /// Files the person gave Kai are copied here, inside the knowledge folder, so they stay theirs to open or delete.
    public static let uploadsFolderName = "Uploads"

    public struct UploadResult: Equatable, Sendable {
        public var copied: [String] = []
        public var rejected: [String] = []
        public init() {}
    }

    /// Copies supported files into `<knowledge folder>/Uploads`. A file with the same name gets a number, never overwrites.
    public static func upload(_ urls: [URL], into knowledgeFolder: URL) -> UploadResult {
        var result = UploadResult()
        let destination = knowledgeFolder.appendingPathComponent(uploadsFolderName, isDirectory: true)
        for url in urls {
            let name = url.lastPathComponent
            let ext = url.pathExtension.lowercased()
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard KaiFileReader.supports(ext) else { result.rejected.append("\(name): Kai can't read this kind of file yet."); continue }
            guard !looksSecret(fileName: name) else { result.rejected.append("\(name): the name looks like it holds a secret, so it is not added."); continue }
            guard size <= KaiFileReader.maxBytes(for: ext) else { result.rejected.append("\(name): too big."); continue }
            do {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                let base = url.deletingPathExtension().lastPathComponent
                var target = destination.appendingPathComponent(name)
                var counter = 2
                while FileManager.default.fileExists(atPath: target.path) {
                    target = destination.appendingPathComponent("\(base) \(counter).\(url.pathExtension)")
                    counter += 1
                }
                try FileManager.default.copyItem(at: url, to: target)
                result.copied.append(name)
            } catch {
                result.rejected.append("\(name): \(error.localizedDescription)")
            }
        }
        return result
    }
}

public struct KaiKnowledgeFolderList: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public static var standard: KaiKnowledgeFolderList {
        KaiKnowledgeFolderList(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kai OS", isDirectory: true).appendingPathComponent("knowledge-folders.json"))
    }

    public func load() -> [KaiKnowledgeFolder] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([KaiKnowledgeFolder].self, from: data)) ?? []
    }

    public func save(_ folders: [KaiKnowledgeFolder]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(folders).write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// How a search result is named when Kai shows or quotes where it came from.
public enum KaiKnowledgeCitation {
    /// "Files: Uploads/contract.pdf", "Folders (Projects): plan/roadmap.md", or just "Notes" for a source without a path.
    public static func label(source: String, sourceID: String, folders: [KaiKnowledgeFolder] = []) -> String {
        switch source {
        case KaiKnowledgeIndexer.folderSource:
            return "Files: \(sourceID)"
        case KaiKnowledgeIndexer.extraFoldersSource:
            let parts = sourceID.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return "Folders" }
            let folder = folders.first { $0.id == parts[0] }?.name ?? "folder"
            return "Folders (\(folder)): \(parts[1])"
        default:
            return ""
        }
    }
}
