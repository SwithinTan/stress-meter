import SwiftUI
import StressCore

/// The animation clock only redraws this illustration; it never requests health data.
struct TabbyCatView: View {
    let mood: PetMood
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    private var animates: Bool {
        PetAnimationPolicy.allowsAnimation(
            isVisible: isVisible, isActive: scenePhase == .active,
            isLuminanceReduced: isLuminanceReduced, reduceMotion: reduceMotion, lowPower: lowPower)
    }

    var body: some View {
        Group {
            if animates {
                TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
                    TabbyCatPortrait(mood: mood, time: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {
                TabbyCatPortrait(mood: mood, time: 0)
            }
        }
        .onAppear {
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onScrollVisibilityChange(threshold: 0.1) { isVisible = $0 }
        .onDisappear { isVisible = false }
        .onChange(of: scenePhase) { _, _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .receive(on: DispatchQueue.main)) { _ in
                lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        .accessibilityHidden(true)
    }
}

/// A fixed-time portrait also gives Always On and Reduce Motion a meaningful pose.
struct TabbyCatPortrait: View {
    let mood: PetMood
    var time: TimeInterval = 0

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 200, size.height / 112)
            context.translateBy(x: (size.width - 200 * scale) / 2,
                                y: (size.height - 112 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            TabbyDrawing(mood: mood, time: time).draw(in: context)
        }
        .accessibilityHidden(true)
    }
}

private struct TabbyDrawing {
    let mood: PetMood
    let time: TimeInterval
    private let ink = Color(red: 0.18, green: 0.21, blue: 0.24)
    private let fur = Color(red: 0.64, green: 0.68, blue: 0.72)
    private let lightFur = Color(red: 0.81, green: 0.83, blue: 0.84)
    private let darkFur = Color(red: 0.39, green: 0.44, blue: 0.49)
    private let muzzle = Color(red: 0.87, green: 0.88, blue: 0.86)

    private var wave: Double { time == 0 ? 0 : sin(time * .pi * 2 / 4.5) }
    private var isRelaxed: Bool { mood == .relaxed }
    private var isTense: Bool { mood == .tense }
    private var tint: Color {
        switch mood {
        case .relaxed: Palette.mint
        case .balanced: Palette.lavender
        case .tense: Palette.amber
        case .waiting: .gray
        }
    }

    func draw(in context: GraphicsContext) {
        context.fill(Path(ellipseIn: CGRect(x: 40, y: 101, width: 119, height: 8)),
                     with: .color(tint.opacity(0.22)))
        drawTail(in: context)

        var body = context
        body.translateBy(x: 100, y: 100)
        body.scaleBy(x: 1 + wave * 0.006, y: 1 + wave * 0.018)
        body.translateBy(x: -100, y: -100)
        let bodyRect = isRelaxed ? CGRect(x: 65, y: 64, width: 82, height: 36)
            : CGRect(x: isTense ? 68 : 74, y: isTense ? 59 : 52,
                     width: isTense ? 68 : 55, height: isTense ? 43 : 50)
        body.fill(Path(ellipseIn: bodyRect), with: .linearGradient(
            Gradient(colors: [fur, darkFur]), startPoint: CGPoint(x: 85, y: 56), endPoint: CGPoint(x: 125, y: 105)))
        body.fill(Path(ellipseIn: CGRect(x: 83, y: 66, width: 33, height: 31)), with: .color(lightFur))
        for y in [76.0, 85.0] {
            stroke(in: body, from: CGPoint(x: bodyRect.maxX - 5, y: y),
                   to: CGPoint(x: bodyRect.maxX - 15, y: y + 5), width: 4, color: ink.opacity(0.6))
        }
        drawHead(in: body)
        for x in isRelaxed ? [72.0, 101.0] : (isTense ? [85.0, 104.0] : [82.0, 104.0]) {
            body.fill(Path(ellipseIn: CGRect(x: x, y: 92, width: isRelaxed ? 26 : 19, height: 11)),
                      with: .color(lightFur))
            for dx in [6.0, 11.0] {
                stroke(in: body, from: CGPoint(x: x + dx, y: 99), to: CGPoint(x: x + dx, y: 102),
                       width: 1, color: darkFur)
            }
        }
        if mood == .waiting {
            for x in [156.0, 165.0, 174.0] {
                context.fill(Path(ellipseIn: CGRect(x: x, y: 40, width: 4, height: 4)),
                             with: .color(Color.white.opacity(0.6)))
            }
        }
    }

    private func drawTail(in context: GraphicsContext) {
        var tail = Path()
        tail.move(to: CGPoint(x: 126, y: 91))
        if isTense {
            tail.addCurve(to: CGPoint(x: 119, y: 99), control1: CGPoint(x: 169, y: 93), control2: CGPoint(x: 151, y: 112))
        } else {
            let sway = wave * (isRelaxed ? 9 : 3)
            tail.addCurve(to: CGPoint(x: 158 + sway, y: isRelaxed ? 51 : 65),
                          control1: CGPoint(x: 174, y: 102), control2: CGPoint(x: 180 + sway, y: 61))
        }
        context.stroke(tail, with: .color(darkFur), style: StrokeStyle(lineWidth: 14, lineCap: .round))
        context.stroke(tail, with: .color(fur), style: StrokeStyle(lineWidth: 10, lineCap: .round))
        context.stroke(tail, with: .color(ink.opacity(0.6)),
                       style: StrokeStyle(lineWidth: 11, lineCap: .butt, dash: [3, 11], dashPhase: 4))
    }

    private func drawHead(in original: GraphicsContext) {
        var context = original
        context.translateBy(x: isRelaxed ? -10 : 0, y: isTense ? 9 : (isRelaxed ? 3 : 0))
        if mood == .waiting {
            context.translateBy(x: 96, y: 54)
            context.rotate(by: .degrees(-5))
            context.translateBy(x: -96, y: -54)
        }
        drawEar(in: context, right: false)
        drawEar(in: context, right: true)
        var head = Path()
        head.move(to: CGPoint(x: 95, y: 24))
        head.addCurve(to: CGPoint(x: 137, y: 54), control1: CGPoint(x: 120, y: 22), control2: CGPoint(x: 135, y: 32))
        head.addCurve(to: CGPoint(x: 96, y: 82), control1: CGPoint(x: 143, y: 75), control2: CGPoint(x: 115, y: 83))
        head.addCurve(to: CGPoint(x: 55, y: 55), control1: CGPoint(x: 74, y: 83), control2: CGPoint(x: 49, y: 74))
        head.addCurve(to: CGPoint(x: 95, y: 24), control1: CGPoint(x: 54, y: 34), control2: CGPoint(x: 72, y: 22))
        context.fill(head, with: .linearGradient(Gradient(colors: [lightFur, fur]),
                                               startPoint: CGPoint(x: 83, y: 24), endPoint: CGPoint(x: 110, y: 81)))
        // The forehead M, cheek marks and ringed tail distinguish a grey tabby.
        var forehead = Path()
        forehead.addLines([CGPoint(x: 83, y: 40), CGPoint(x: 87, y: 28), CGPoint(x: 95, y: 38),
                           CGPoint(x: 103, y: 28), CGPoint(x: 107, y: 40)])
        context.stroke(forehead, with: .color(darkFur), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
        for right in [false, true] {
            let sign = right ? 1.0 : -1.0
            for y in [48.0, 58.0] {
                stroke(in: context, from: CGPoint(x: 96 + sign * 37, y: y),
                       to: CGPoint(x: 96 + sign * 29, y: y + 3), width: 3.5, color: darkFur)
            }
        }
        context.fill(Path(ellipseIn: CGRect(x: 78, y: 60, width: 22, height: 15)), with: .color(muzzle))
        context.fill(Path(ellipseIn: CGRect(x: 93, y: 60, width: 22, height: 15)), with: .color(muzzle))
        drawEyes(in: context)
        var nose = Path()
        nose.move(to: CGPoint(x: 91, y: 63))
        nose.addQuadCurve(to: CGPoint(x: 101, y: 63), control: CGPoint(x: 96, y: 60))
        nose.addQuadCurve(to: CGPoint(x: 96, y: 68), control: CGPoint(x: 101, y: 66))
        nose.closeSubpath()
        context.fill(nose, with: .color(Color(red: 0.56, green: 0.38, blue: 0.4)))
        var mouth = Path()
        mouth.move(to: CGPoint(x: 96, y: 67))
        mouth.addQuadCurve(to: CGPoint(x: 89, y: 71), control: CGPoint(x: 96, y: 73))
        mouth.move(to: CGPoint(x: 96, y: 67))
        mouth.addQuadCurve(to: CGPoint(x: 103, y: 71), control: CGPoint(x: 96, y: 73))
        context.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
        for right in [false, true] {
            let sign = right ? 1.0 : -1.0
            for (y, dy) in [(65.0, -2.0), (70.0, 2.0)] {
                stroke(in: context, from: CGPoint(x: 96 + sign * 22, y: y),
                       to: CGPoint(x: 96 + sign * 41, y: y + dy), width: 1, color: muzzle.opacity(0.8))
            }
        }
    }

    private func drawEar(in context: GraphicsContext, right: Bool) {
        var ear = context
        let baseX = right ? 122.0 : 69.0
        ear.translateBy(x: baseX, y: 36)
        ear.rotate(by: .degrees(isTense ? (right ? 28 : -28) : (right ? 5 : -5)))
        ear.scaleBy(x: right ? -1 : 1, y: 1)
        var outline = Path()
        outline.move(to: CGPoint(x: -12, y: 8))
        outline.addQuadCurve(to: CGPoint(x: -9, y: -27), control: CGPoint(x: -18, y: -29))
        outline.addQuadCurve(to: CGPoint(x: 15, y: 1), control: CGPoint(x: 4, y: -23))
        outline.closeSubpath()
        ear.fill(outline, with: .color(darkFur))
        var inner = Path()
        inner.addLines([CGPoint(x: -8, y: -18), CGPoint(x: -7, y: 0), CGPoint(x: 7, y: -2)])
        inner.closeSubpath()
        ear.fill(inner, with: .color(Color(red: 0.69, green: 0.52, blue: 0.56)))
    }

    private func drawEyes(in context: GraphicsContext) {
        let blink = time != 0 && time.truncatingRemainder(dividingBy: 6.7) < 0.22
        for x in [80.0, 112.0] {
            if isRelaxed || blink {
                var eye = Path()
                eye.move(to: CGPoint(x: x - 6, y: 53))
                eye.addQuadCurve(to: CGPoint(x: x + 6, y: 53), control: CGPoint(x: x, y: 58))
                context.stroke(eye, with: .color(ink), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            } else {
                context.fill(Path(ellipseIn: CGRect(x: x - 5, y: 48, width: 10, height: isTense ? 10 : 12)),
                             with: .color(ink))
                context.fill(Path(ellipseIn: CGRect(x: x - 3.5, y: 50, width: 7, height: isTense ? 6 : 8)),
                             with: .color(Color(red: 0.72, green: 0.77, blue: 0.5)))
                context.fill(Path(ellipseIn: CGRect(x: x - 1.6, y: 49, width: 3.2, height: 9)), with: .color(ink))
                context.fill(Path(ellipseIn: CGRect(x: x - 2, y: 50, width: 2, height: 2)), with: .color(.white))
                if isTense {
                    stroke(in: context, from: CGPoint(x: x - 5, y: x < 96 ? 44 : 42),
                           to: CGPoint(x: x + 5, y: x < 96 ? 42 : 44), width: 2, color: darkFur)
                }
            }
        }
    }

    private func stroke(in context: GraphicsContext, from start: CGPoint, to end: CGPoint, width: CGFloat, color: Color) {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}

#Preview("灰狸花猫 · 三种状态与等待") {
    ScrollView {
        VStack {
            ForEach(PetMood.allCases, id: \.self) { mood in
                TabbyCatPortrait(mood: mood).frame(width: 160, height: 90)
            }
        }
    }
    .background(.black)
}
