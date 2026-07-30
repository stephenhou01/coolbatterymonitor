import AppKit

func makeIcon(file: String, topC: NSColor, botC: NSColor, symbolColor: NSColor,
              symScale: CGFloat, glow: Bool) {
    let size: CGFloat = 1024
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let radius: CGFloat = size * 0.2237
    let bg = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    bg.addClip()

    let grad = NSGradient(starting: topC, ending: botC)!
    grad.draw(in: rect, angle: -90)

    // 左上柔和高光
    let hi = NSGradient(colors: [NSColor(white: 1, alpha: 0.18), NSColor(white: 1, alpha: 0)])!
    hi.draw(in: rect, relativeCenterPosition: NSPoint(x: -0.4, y: 0.4))

    let cfg = NSImage.SymbolConfiguration(pointSize: size * symScale, weight: .bold)
    if let base = NSImage(systemSymbolName: "battery.100.bolt", accessibilityDescription: nil),
       let sym = base.withSymbolConfiguration(cfg) {
        let s = sym.size
        let tinted = NSImage(size: s)
        tinted.lockFocus()
        let r = NSRect(origin: .zero, size: s)
        sym.draw(in: r)
        symbolColor.set()
        r.fill(using: .sourceAtop)
        tinted.unlockFocus()

        let x = (size - s.width) / 2
        let y = (size - s.height) / 2
        let shadow = NSShadow()
        if glow {
            shadow.shadowColor = NSColor(red: 0.3, green: 0.85, blue: 1, alpha: 0.9)
            shadow.shadowBlurRadius = size * 0.05
            shadow.shadowOffset = .zero
        } else {
            shadow.shadowColor = NSColor(white: 0, alpha: 0.28)
            shadow.shadowBlurRadius = size * 0.022
            shadow.shadowOffset = NSSize(width: 0, height: -size * 0.008)
        }
        shadow.set()
        tinted.draw(in: NSRect(x: x, y: y, width: s.width, height: s.height))
    }
    img.unlockFocus()

    if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try! png.write(to: URL(fileURLWithPath: file))
        print("wrote \(file)")
    }
}

// V2 浓郁蓝→青，符号更大
makeIcon(file: "icon_v2.png",
         topC: NSColor(red: 0.16, green: 0.50, blue: 1.0, alpha: 1),
         botC: NSColor(red: 0.10, green: 0.80, blue: 0.78, alpha: 1),
         symbolColor: .white, symScale: 0.36, glow: false)

// V3 深色专业风，发光电池
makeIcon(file: "icon_v3.png",
         topC: NSColor(red: 0.10, green: 0.12, blue: 0.20, alpha: 1),
         botC: NSColor(red: 0.05, green: 0.06, blue: 0.10, alpha: 1),
         symbolColor: NSColor(red: 0.35, green: 0.92, blue: 0.95, alpha: 1),
         symScale: 0.34, glow: true)
