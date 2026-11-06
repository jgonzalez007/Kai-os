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

    /// Captures a display as JPEG, leaving out every window of the given app.
    public static func capture(displayID: CGDirectDisplayID?, excludingBundleIdentifier: String?) async throws -> Data {
        guard hasPermission else { throw KaiScreenCaptureError.needsPermission }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
            throw KaiScreenCaptureError.noDisplay
        }
        let excluded = content.applications.filter { $0.bundleIdentifier == excludingBundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = display.width * 2
        configuration.height = display.height * 2
        configuration.showsCursor = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        guard let data = KaiScreenImage.jpegData(from: image) else { throw KaiScreenCaptureError.encodingFailed }
        return data
    }
}
