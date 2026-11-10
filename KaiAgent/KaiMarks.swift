//
//  KaiMarks.swift
//  Kai Agent
//
//  Draws a small number on each clickable item of a screenshot, the same numbers as in the list the model is
//  given. The model then says "click 7" instead of guessing where something is from a picture. The numbers are
//  drawn on the copy sent to the local model only; the real screen is never touched.
//

import AppKit
import CoreGraphics
import Foundation
import ImageIO

public enum KaiMarks {
    public static func draw(on jpeg: Data, elements: [KaiAgentElement], pixelWidth: Int, pixelHeight: Int) -> Data {
        let list = KaiAgentElements.numbered(elements, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
        guard !list.isEmpty, let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return jpeg }
        let width = CGFloat(image.width), height = CGFloat(image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let fontSize = max(11, min(16, height / 62))
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: fontSize), .foregroundColor: NSColor.black]
        for (index, element) in list.enumerated() {
            let text = NSAttributedString(string: "\(index + 1)", attributes: attributes)
            let size = text.size()
            let box = CGRect(x: CGFloat(element.x) - size.width - 6, y: height - CGFloat(element.y) - size.height / 2 - 1,
                             width: size.width + 6, height: size.height + 2)
            NSColor(calibratedRed: 1, green: 0.85, blue: 0.1, alpha: 0.92).setFill()
            NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
            text.draw(at: CGPoint(x: box.minX + 3, y: box.minY + 1))
        }
        guard let marked = context.makeImage() else { return jpeg }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else { return jpeg }
        CGImageDestinationAddImage(destination, marked, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : jpeg
    }
}
