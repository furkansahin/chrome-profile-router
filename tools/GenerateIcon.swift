import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let dimension = CGFloat(pixels)
        let inset = dimension * 0.07
        let rect = NSRect(x: inset, y: inset, width: dimension - inset * 2, height: dimension - inset * 2)
        let shape = NSBezierPath(roundedRect: rect, xRadius: dimension * 0.21, yRadius: dimension * 0.21)
        NSGradient(starting: NSColor(red: 0.36, green: 0.37, blue: 0.90, alpha: 1), ending: NSColor(red: 0.19, green: 0.20, blue: 0.63, alpha: 1))?.draw(in: shape, angle: -65)
        if let symbol = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: dimension * 0.48, weight: .medium)) {
            let symbolSize = symbol.size
            let symbolRect = NSRect(x: (dimension - symbolSize.width) / 2, y: (dimension - symbolSize.height) / 2, width: symbolSize.width, height: symbolSize.height)
            let tinted = NSImage(size: symbolSize)
            tinted.lockFocus()
            symbol.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
            NSColor.white.setFill()
            NSRect(origin: .zero, size: symbolSize).fill(using: .sourceAtop)
            tinted.unlockFocus()
            tinted.draw(in: symbolRect)
        }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let data = bitmap.representation(using: .png, properties: [:])!
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
