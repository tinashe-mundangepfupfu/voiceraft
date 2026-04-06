import AppKit

enum VoiceRaftStatusItemIcon {
    static let splitVGlyphName = "voiceraft.splitv"

    static func makeImage(named glyphName: String, size: CGFloat = 18, color: NSColor = .white) -> NSImage? {
        switch glyphName {
        case splitVGlyphName:
            return makeSplitVImage(size: size, color: color)
        default:
            return nil
        }
    }

    private static func makeSplitVImage(size: CGFloat, color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            color.setStroke()

            let leftStroke = NSBezierPath()
            leftStroke.lineWidth = rect.width * 0.18
            leftStroke.lineCapStyle = .round
            leftStroke.move(to: NSPoint(x: rect.minX + rect.width * 0.24, y: rect.minY + rect.height * 0.76))
            leftStroke.line(to: NSPoint(x: rect.midX - rect.width * 0.06, y: rect.minY + rect.height * 0.22))
            leftStroke.stroke()

            let rightStroke = NSBezierPath()
            rightStroke.lineWidth = rect.width * 0.18
            rightStroke.lineCapStyle = .round
            rightStroke.move(to: NSPoint(x: rect.maxX - rect.width * 0.24, y: rect.minY + rect.height * 0.76))
            rightStroke.line(to: NSPoint(x: rect.midX + rect.width * 0.09, y: rect.minY + rect.height * 0.22))
            rightStroke.stroke()

            let notch = NSBezierPath()
            notch.lineWidth = rect.width * 0.10
            notch.lineCapStyle = .round
            notch.move(to: NSPoint(x: rect.midX + rect.width * 0.01, y: rect.minY + rect.height * 0.67))
            notch.line(to: NSPoint(x: rect.midX + rect.width * 0.15, y: rect.minY + rect.height * 0.47))
            notch.stroke()

            return true
        }
        return image
    }
}
