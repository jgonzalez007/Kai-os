//
//  KaiScreenGrabber.swift
//  Kai OS
//
//  Takes one still of a display when the user asks for it. There is no background capture.
//

import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit

public enum KaiScreenCaptureError: LocalizedError, Equatable, Sendable {
    case needsPermission
    case noDisplay
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .needsPermission:
            return "Kai OS needs Screen Recording permission. Turn it on in System Settings → Privacy & Security → Screen Recording, then quit and reopen Kai OS."
        case .noDisplay:
            return "No display is available to capture."
        case .encodingFailed:
            return "The screenshot couldn't be prepared."
        }
    }
}

public enum KaiScreenImage {
    /// Large enough to read on-screen text, and small enough for a local vision model.
    public static let defaultMaxLongEdge = 1600

    public static func jpegData(from image: CGImage, maxLongEdge: Int = defaultMaxLongEdge, quality: Double = 0.8) -> Data? {
        let longEdge = max(image.width, image.height)
        let scale = longEdge > maxLongEdge ? Double(maxLongEdge) / Double(longEdge) : 1
        let width = Int((Double(image.width) * scale).rounded())
        let height = Int((Double(image.height) * scale).rounded())
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, scaled, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}

public enum KaiScreenGrabber {
    public static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt once. macOS only applies a new grant after the app relaunches.
    public static func requestPermission() {
        _ = CGRequestScreenCaptureAccess()
    }

    /// A rough picture of the display as a grid of grey levels, for telling whether the screen is still changing.
    /// It is never saved or sent anywhere.
    public static func fingerprint(displayID: CGDirectDisplayID?, excludingBundleIdentifier: String?) async throws -> [UInt8] {
        guard hasPermission else { throw KaiScreenCaptureError.needsPermission }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else { throw KaiScreenCaptureError.noDisplay }
        let excluded = content.applications.filter { $0.bundleIdentifier == excludingBundleIdentifier }
        let configuration = SCStreamConfiguration()
        configuration.width = 128
        configuration.height = 80
        configuration.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: []), configuration: configuration)
        return grid(from: image)
    }

    /// 32 by 20 grey cells, each averaged from the image, so blinking carets and tiny changes barely register.
    static func grid(from image: CGImage, columns: Int = 32, rows: Int = 20) -> [UInt8] {
        var cells = [UInt8](repeating: 0, count: columns * rows)
        guard let context = CGContext(data: &cells, width: columns, height: rows, bitsPerComponent: 8, bytesPerRow: columns,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return cells }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: columns, height: rows))
        return cells
    }

    /// True when two grids differ in so few cells that the screen has, for our purpose, stopped changing.
    public static func isStable(_ a: [UInt8], _ b: [UInt8], tolerance: Double = 0.02) -> Bool {
        guard a.count == b.count, !a.isEmpty else { return false }
        let changed = zip(a, b).filter { abs(Int($0) - Int($1)) > 12 }.count
        return Double(changed) / Double(a.count) <= tolerance
    }

    /// Captures a display as JPEG, leaving out every window of the given app. With `maxLongEdge` the picture is taken
    /// at that size to begin with, which is quicker than taking it large and shrinking it.
    public static func capture(displayID: CGDirectDisplayID?, excludingBundleIdentifier: String?, maxLongEdge: Int? = nil) async throws -> Data {
        guard hasPermission else { throw KaiScreenCaptureError.needsPermission }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
            throw KaiScreenCaptureError.noDisplay
        }
        let excluded = content.applications.filter { $0.bundleIdentifier == excludingBundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        if let maxLongEdge {
            let scale = min(2.0, Double(maxLongEdge) / Double(max(display.width, display.height, 1)))
            configuration.width = max(Int((Double(display.width) * scale).rounded()), 1)
            configuration.height = max(Int((Double(display.height) * scale).rounded()), 1)
        } else {
            configuration.width = display.width * 2
            configuration.height = display.height * 2
        }
        configuration.showsCursor = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        guard let data = KaiScreenImage.jpegData(from: image, maxLongEdge: maxLongEdge ?? KaiScreenImage.defaultMaxLongEdge) else { throw KaiScreenCaptureError.encodingFailed }
        return data
    }
}
