import AppKit
import ImageIO
import LocalPortsCore

enum IconLoader {
    @MainActor
    static func appIcon(for listener: Listener, service: ServiceIdentity) -> NSImage? {
        if let bundle = service.appBundleURL { return NSWorkspace.shared.icon(forFile: bundle.path) }
        if let app = NSRunningApplication(processIdentifier: listener.process.pid), app.bundleURL != nil {
            return app.icon
        }
        return nil
    }

    static func faviconData(for listener: Listener, service: ServiceIdentity) async -> Data? {
        guard service.category == .development, let url = listener.suggestedWebURL else { return nil }
        if let directory = service.projectDirectory {
            let candidates = ["public/favicon.ico", "public/favicon.png", "public/favicon.svg",
                              "static/favicon.ico", "static/favicon.png", "static/favicon.svg",
                              "app/favicon.ico", "src/app/favicon.ico", "favicon.ico", "favicon.png"]
            for path in candidates {
                guard let handle = try? FileHandle(forReadingFrom: directory.appendingPathComponent(path)) else { continue }
                defer { try? handle.close() }
                if let data = try? handle.read(upToCount: 524_289), data.count <= 524_288,
                   let image = decode(data), image.isValid { return data }
            }
        }
        return await LocalFavicon.load(from: url)
    }

    static func decode(_ data: Data) -> NSImage? {
        if let text = String(data: data, encoding: .utf8), text.lowercased().contains("<svg") {
            guard FaviconPolicy.isSelfContainedSVG(data) else { return nil }
            return NSImage(data: data)
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 64,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: thumbnail, size: NSSize(width: 32, height: 32))
    }
}
