import AppKit

enum MenuBarIcon {
    static func make() -> NSImage {
        // A vector silhouette of the app icon's two lanes. Template rendering
        // lets macOS choose the tint for the menu bar and highlighted state.
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            for destinationY: CGFloat in [4, 14] {
                let lane = NSBezierPath()
                lane.lineWidth = 3.2
                lane.lineCapStyle = .round
                lane.lineJoinStyle = .round
                lane.move(to: NSPoint(x: 2, y: 9))
                lane.line(to: NSPoint(x: 5, y: 9))
                lane.curve(to: NSPoint(x: 15.5, y: destinationY),
                           controlPoint1: NSPoint(x: 10, y: 9),
                           controlPoint2: NSPoint(x: 9.5, y: destinationY))
                lane.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Tabitat"
        return image
    }
}
