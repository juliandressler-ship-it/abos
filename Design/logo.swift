import AppKit

// Abos-Logo: ein Abreißkalender-Blatt (die Signatur der App) mit Euro-Zeichen
let groesse: CGFloat = 1024
let bild = NSImage(size: NSSize(width: groesse, height: groesse))
bild.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

func farbe(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

// Grundform nach macOS-Raster: 824 × 824, Rand 100
let flaeche = CGRect(x: 100, y: 100, width: 824, height: 824)
let grund = CGPath(roundedRect: flaeche, cornerWidth: 186, cornerHeight: 186, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: farbe(0, 0, 0, 0.28))
ctx.addPath(grund); ctx.setFillColor(farbe(31, 41, 66)); ctx.fillPath()
ctx.restoreGState()

// Ton-in-Ton-Verlauf innerhalb eines Tintenblaus
ctx.saveGState()
ctx.addPath(grund); ctx.clip()
let verlauf = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                         colors: [farbe(46, 61, 97), farbe(27, 35, 58)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(verlauf, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
ctx.restoreGState()

// Kalenderblatt
let blatt = CGRect(x: 262, y: 236, width: 500, height: 540)
let blattPfad = CGPath(roundedRect: blatt, cornerWidth: 64, cornerHeight: 64, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: farbe(0, 0, 0, 0.35))
ctx.addPath(blattPfad); ctx.setFillColor(farbe(250, 249, 246)); ctx.fillPath()
ctx.restoreGState()

// Kopfleiste in der Akzentfarbe der App
ctx.saveGState()
ctx.addPath(blattPfad); ctx.clip()
let kopf = CGRect(x: blatt.minX, y: blatt.maxY - 150, width: blatt.width, height: 150)
ctx.setFillColor(farbe(69, 120, 214)); ctx.fill(kopf)
ctx.setFillColor(farbe(0, 0, 0, 0.10)); ctx.fill(CGRect(x: blatt.minX, y: kopf.minY, width: blatt.width, height: 6))
ctx.restoreGState()

// Zwei Ringe der Bindung
for x in [blatt.minX + 140, blatt.maxX - 140] {
    let loch = CGRect(x: x - 22, y: kopf.midY - 4, width: 44, height: 44)
    ctx.setFillColor(farbe(27, 35, 58, 0.55)); ctx.fillEllipse(in: loch)
    let ring = CGPath(roundedRect: CGRect(x: x - 14, y: kopf.midY + 12, width: 28, height: 110),
                      cornerWidth: 14, cornerHeight: 14, transform: nil)
    ctx.addPath(ring); ctx.setFillColor(farbe(214, 219, 230)); ctx.fillPath()
}

// Euro-Zeichen im Blatt
let schrift = NSFont.systemFont(ofSize: 210, weight: .medium)
let text = NSAttributedString(string: "€", attributes: [
    .font: schrift,
    .foregroundColor: NSColor(srgbRed: 31 / 255, green: 41 / 255, blue: 66 / 255, alpha: 1),
])
let tg = text.size()
let koerper = CGRect(x: blatt.minX, y: blatt.minY, width: blatt.width, height: blatt.height - 150)
text.draw(at: NSPoint(x: koerper.midX - tg.width / 2, y: koerper.midY - tg.height / 2 + 6))

// Verlängerungspfeil: ein offener Kreis um das Euro-Zeichen
let mitte = CGPoint(x: koerper.midX, y: koerper.midY)
let radius: CGFloat = 150
let start: CGFloat = .pi * 0.62, ende: CGFloat = .pi * 0.62 - .pi * 1.62
ctx.setStrokeColor(farbe(69, 120, 214))
ctx.setLineWidth(30)
ctx.setLineCap(.round)
ctx.addArc(center: mitte, radius: radius, startAngle: start, endAngle: ende, clockwise: true)
ctx.strokePath()
// Pfeilspitze am Ende des Bogens, in Laufrichtung
let spitze = CGPoint(x: mitte.x + radius * cos(ende), y: mitte.y + radius * sin(ende))
let richtung = ende - .pi / 2   // Tangente im Uhrzeigersinn
let laenge: CGFloat = 70, breite: CGFloat = 0.55
let vorne = CGPoint(x: spitze.x + 26 * cos(richtung), y: spitze.y + 26 * sin(richtung))
let l = CGPoint(x: vorne.x - laenge * cos(richtung - breite), y: vorne.y - laenge * sin(richtung - breite))
let r = CGPoint(x: vorne.x - laenge * cos(richtung + breite), y: vorne.y - laenge * sin(richtung + breite))
ctx.move(to: vorne); ctx.addLine(to: l); ctx.addLine(to: r); ctx.closePath()
ctx.setFillColor(farbe(69, 120, 214)); ctx.setLineJoin(.round); ctx.setLineWidth(10)
ctx.drawPath(using: .fillStroke)

bild.unlockFocus()
let rep = NSBitmapImageRep(data: bild.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
