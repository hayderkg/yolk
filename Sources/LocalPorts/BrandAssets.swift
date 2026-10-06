import AppKit
import SwiftUI

/// Brand artwork. The menu bar symbol is the logo line redrawn at menu-bar scale as a template image.
enum BrandAssets {
    static let menuIcon = menuSymbol(badged: false)
    /// Same symbol with a dot in the free top-right corner, shown when new ports appear.
    static let menuIconBadged = menuSymbol(badged: true)

    private static func menuSymbol(badged: Bool) -> NSImage {
        let size = NSSize(width: 23, height: 18)
        let image = NSImage(size: size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            // The logo line, fitted to the width. It is wider than tall, hence the wider canvas.
            let bounds = logoOutline.cgPath.boundingBoxOfPath
            let scale = 21.4 / bounds.width
            context.saveGState()
            context.translateBy(x: (size.width - bounds.width * scale) / 2 - bounds.minX * scale,
                                y: (size.height - bounds.height * scale) / 2 - bounds.minY * scale)
            context.scaleBy(x: scale, y: scale)
            context.setFillColor(.black)
            context.setStrokeColor(.black)
            context.addPath(logoOutline.cgPath)
            context.fillPath()
            // Optical weight: at this scale the line alone is under a point wide.
            context.addPath(logoOutline.cgPath)
            context.setLineWidth(0.4 / scale)
            context.setLineJoin(.round)
            context.strokePath()
            context.setBlendMode(.clear)
            context.addPath(logoYolk.cgPath)
            context.fillPath()
            context.restoreGState()
            if badged {
                context.setBlendMode(.clear)
                context.fillEllipse(in: CGRect(x: 17.2, y: -0.7, width: 6.4, height: 6.4))
                context.setBlendMode(.normal)
                context.fillEllipse(in: CGRect(x: 18.4, y: 0.5, width: 4, height: 4))
            }
            return true
        }
        image.isTemplate = true
        return image
    }
    static let appIcon: NSImage? = {
        guard let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png", subdirectory: "Assets") else { return nil }
        return NSImage(contentsOf: url)
    }()
    /// The egg line and its yolk from `Brand/logo.svg`, on a 1024 pt canvas, so the theme can colour them.
    static let logoOutline = svgPath("M541.588 288.714C558.728 287.61 580.978 289.132 598.033 290.769C697.453 300.31 795.088 349.256 858.708 426.806C889.058 463.8 917.358 516.51 912.643 565.885C909.478 599.09 885.933 632.25 859.948 652.74C784.998 711.845 668.043 729.61 575.728 720.63C511.523 714.385 440.904 688.53 399.499 637.44C377.367 610.135 363.997 577.22 368.041 541.605C372.387 503.715 395.45 470.386 425.004 447.22C478.66 404.917 566.083 387.019 625.788 426.764C689.378 469.094 664.618 539.155 613.173 578.51C562.658 617.15 503.288 629.17 441.553 621.81C513.023 692.785 648.823 693.195 739.378 666.96C781.228 654.325 826.783 634.635 854.828 599.26C868.133 582.475 875.448 563.605 872.048 542.11C863.408 487.509 819.768 434.647 777.173 402.334C699.348 342.431 600.608 316.536 503.403 330.535C411.163 343.348 324.498 385.726 250.841 441.786C225.558 460.941 202.321 482.093 182.81 507.065C162.061 533.62 148.304 568.05 181.149 591.805C212.758 614.665 265.265 615.7 301.417 603.225C312.787 599.3 318.288 587.305 331.21 586.335C344.063 584.715 358.688 591.33 360.455 605.46C361.894 616.97 351.482 624.68 342.666 630.06C320.742 643.445 294.092 649.115 268.681 650.675C226.422 652.62 178.927 645.925 146.226 616.93C95.4755 571.935 120.004 511.4 159.003 469.163C179.321 447.158 199.445 430.014 223.317 412.268C284.963 366.443 355.545 328.691 429.47 307.395C466.004 296.896 503.623 290.628 541.588 288.714Z")
    static let logoYolk = svgPath("M542.249 444.215C561.824 443.056 586.444 448.763 602.029 461.043C644.074 494.176 598.004 542.645 566.089 561.805C540.664 577.065 516.939 584.495 487.618 587.91C460.918 590.755 440.593 588.08 415.355 579.095C413.16 572.675 411.869 565.98 411.518 559.2C409.528 519.195 439.978 482.835 473.073 464.159C495.124 451.716 516.984 445.341 542.249 444.215Z")

    /// Absolute M, L, H, V, C and Z commands only, which is all the artwork uses.
    private static func svgPath(_ data: String) -> Path {
        var path = Path()
        var command: Character = "M"
        var point = CGPoint.zero
        let scanner = Scanner(string: data)
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: " ,\n")
        func number() -> CGFloat? { scanner.scanDouble().map { CGFloat($0) } }
        while !scanner.isAtEnd {
            for letter in scanner.scanCharacters(from: .letters) ?? "" {
                if letter == "Z" { path.closeSubpath() } else { command = letter }
            }
            switch command {
            case "M", "L":
                guard let x = number(), let y = number() else { return path }
                point = CGPoint(x: x, y: y)
                if command == "M" { path.move(to: point); command = "L" } else { path.addLine(to: point) }
            case "H":
                guard let x = number() else { return path }
                point.x = x; path.addLine(to: point)
            case "V":
                guard let y = number() else { return path }
                point.y = y; path.addLine(to: point)
            case "C":
                guard let x1 = number(), let y1 = number(), let x2 = number(), let y2 = number(), let x = number(), let y = number() else { return path }
                point = CGPoint(x: x, y: y)
                path.addCurve(to: point, control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
            default: return path
            }
        }
        return path
    }
}

/// The logo on a rounded tile, coloured by the active palette.
struct BrandLogo: View {
    let size: CGFloat
    @Environment(\.portTheme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
        let scale = CGAffineTransform(scaleX: size / 1024, y: size / 1024)
        ZStack {
            shape.fill(theme.logoTile)
            // The line's own loop fills solid, so the yolk has to be painted over it.
            BrandAssets.logoOutline.applying(scale).fill(theme.logoInk)
            BrandAssets.logoYolk.applying(scale).fill(theme.logoYolk)
        }
        .frame(width: size, height: size)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}
