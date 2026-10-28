import SwiftUI
import Combine

// MARK: - Haptic

func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
    UIImpactFeedbackGenerator(style: style).impactOccurred()
}

// MARK: - Chord Maps
//
// Finger bitmasks: Index=1  Middle=2  Ring=4  Pinky=8
//
// All 15 finger combinations map to letters — zero collisions with specials.
// Specials are triggered by holding the THUMB BUTTON while tapping fingers:
//
//   Thumb held + index          → space
//   Thumb held + middle         → backspace
//   Thumb held + ring           → newline
//   Thumb held + pinky          → delete word
//   Thumb held + index+middle   → space  (easy two-finger hit)
//   Thumb tap  (no fingers)     → toggle layer
//   Thumb hold (no fingers)     → space

let layer1: [Int: String] = [
    1:       "E",
    2:       "T",
    4:       "A",
    8:       "I",
    1+2:     "N",
    1+4:     "S",
    1+8:     "R",
    2+4:     "H",
    2+8:     "L",
    4+8:     "D",
    1+2+4:   "C",
    1+2+8:   "U",
    1+4+8:   "O",
    2+4+8:   "M",
    1+2+4+8: "F",
]

let layer2: [Int: String] = [
    1:       "P",
    2:       "W",
    4:       "B",
    8:       "G",
    1+2:     "V",
    1+4:     "K",
    1+8:     "Y",
    2+4:     "J",
    2+8:     "X",
    4+8:     "Q",
    1+2+4:   "Z",
    1+2+8:   ".",
    1+4+8:   ",",
    2+4+8:   "?",
    1+2+4+8: "!",
]

// Thumb-modified chords — only fire when thumbHeld == true
let thumbChords: [Int: String] = [
    1:   "space",
    2:   "backspace",
    4:   "newline",
    8:   "deleteword",
    1+2: "space",   // index+middle alternative
]

// MARK: - Chord Engine

class ChordEngine: NSObject, ObservableObject {
    @Published var activeMask: Int = 0
    @Published var layer2Active: Bool = false
    @Published var flashKey: String? = nil

    // True while thumb button is physically pressed.
    // ChordTracker finger commits check this to route letter vs special.
    var thumbHeld: Bool = false

    var previewLabel: String {
        guard activeMask != 0 else { return "" }
        if thumbHeld, let s = thumbChords[activeMask] { return specialDisplay(s) }
        if let ch = (layer2Active ? layer2 : layer1)[activeMask] { return ch }
        var parts: [String] = []
        if activeMask & 1 != 0 { parts.append("I") }
        if activeMask & 2 != 0 { parts.append("M") }
        if activeMask & 4 != 0 { parts.append("R") }
        if activeMask & 8 != 0 { parts.append("P") }
        return parts.joined(separator: "+")
    }

    func updateMask(_ mask: Int) { activeMask = mask }

    func commit(mask: Int, session: SessionManager) {
        guard mask != 0 else { return }

        if thumbHeld, let special = thumbChords[mask] {
            dispatch(special, display: specialDisplay(special), session: session)
            return
        }

        if let ch = (layer2Active ? layer2 : layer1)[mask] {
            dispatch("char:\(ch)", display: ch, session: session)
        } else {
            haptic(.rigid)
            flash("?")
        }
    }

    // Thumb tap alone → toggle layer
    func toggleLayer() {
        layer2Active.toggle()
        haptic(.rigid)
        flash(layer2Active ? "L2" : "L1")
    }

    // Thumb hold alone → space
    func thumbSpaceAlone(session: SessionManager) {
        dispatch("space", display: "⎵", session: session)
    }

    private func dispatch(_ command: String, display: String, session: SessionManager) {
        session.send(command)
        haptic((command == "backspace" || command == "deleteword") ? .medium : .light)
        flash(display)
    }

    private func flash(_ text: String) {
        withAnimation(.easeOut(duration: 0.06)) { flashKey = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            withAnimation { self.flashKey = nil }
        }
    }

    func specialDisplay(_ s: String) -> String {
        switch s {
        case "space":      return "⎵"
        case "backspace":  return "⌫"
        case "newline":    return "↵"
        case "deleteword": return "⌫⌫"
        default:           return s
        }
    }
}

// MARK: - Multi-Touch Tracker UIView
//
// TWO PATHS depending on whether more than one finger ever lands:
//
//  SINGLE-FINGER (fast path)
//    40 ms release debounce only — feels instant.
//
//  MULTI-FINGER (chord path)
//    110 ms release debounce to absorb staggered lifts.
//    Commits the PEAK MASK (highest simultaneous finger count), not an
//    OR-accumulation — ignores grazes on the way in/out.
//
//  NEW-FINGER DURING RELEASE
//    Cancels the pending commit; new touch joins the gesture.

class ChordTracker: UIView {
    var onMaskChange: ((Int) -> Void)?
    var onCommit:     ((Int) -> Void)?
    var fingerRects: [Int: CGRect] = [:]

    private var activeTouches: [UITouch: Int] = [:]
    private var peakMask:  Int  = 0
    private var everMulti: Bool = false

    private let singleRelease: TimeInterval = 0.040
    private let multiRelease:  TimeInterval = 0.110
    private var releaseTimer: Timer?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        releaseTimer?.invalidate()
        releaseTimer = nil
        for t in touches {
            if let z = hitZone(t.location(in: self)) { activeTouches[t] = z }
        }
        let current = currentMask()
        if current.nonzeroBitCount > 1 { everMulti = true }
        if current.nonzeroBitCount > peakMask.nonzeroBitCount { peakMask = current }
        onMaskChange?(current)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        var changed = false
        for t in touches {
            if let z = hitZone(t.location(in: self)) {
                let old = activeTouches[t] ?? 0
                if old != z { activeTouches[t] = z; changed = true }
            }
        }
        if changed {
            let current = currentMask()
            if current.nonzeroBitCount > 1 { everMulti = true }
            if current.nonzeroBitCount > peakMask.nonzeroBitCount { peakMask = current }
            onMaskChange?(current)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { activeTouches.removeValue(forKey: t) }
        onMaskChange?(currentMask())
        scheduleCommitIfAllLifted()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        resetGesture(); onMaskChange?(0)
    }

    private func scheduleCommitIfAllLifted() {
        guard activeTouches.isEmpty else { return }
        let debounce = everMulti ? multiRelease : singleRelease
        releaseTimer?.invalidate()
        releaseTimer = Timer.scheduledTimer(withTimeInterval: debounce, repeats: false) { [weak self] _ in
            guard let self, self.activeTouches.isEmpty else { return }
            let mask = self.peakMask
            self.resetGesture()
            if mask != 0 { self.onCommit?(mask) }
        }
    }

    private func resetGesture() {
        activeTouches.removeAll()
        peakMask = 0; everMulti = false
        releaseTimer?.invalidate(); releaseTimer = nil
    }

    private func hitZone(_ pt: CGPoint) -> Int? {
        for (mask, rect) in fingerRects { if rect.contains(pt) { return mask } }
        return nil
    }

    private func currentMask() -> Int { activeTouches.values.reduce(0, |) }
    override var isMultipleTouchEnabled: Bool { get { true } set {} }
}

// MARK: - SwiftUI wrapper

struct ChordSurface: UIViewRepresentable {
    var fingerRects: [Int: CGRect]
    var onMaskChange: (Int) -> Void
    var onCommit:     (Int) -> Void

    func makeUIView(context: Context) -> ChordTracker {
        let v = ChordTracker()
        v.isMultipleTouchEnabled = true
        v.backgroundColor = .clear
        return v
    }
    func updateUIView(_ v: ChordTracker, context: Context) {
        v.fingerRects  = fingerRects
        v.onMaskChange = onMaskChange
        v.onCommit     = onCommit
    }
}

// MARK: - Models

struct FingerZone: Identifiable {
    let id: Int
    let name: String
    let color: Color
}

let fingerZones: [FingerZone] = [
    FingerZone(id: 1, name: "Index",  color: Color(red: 0.94, green: 0.72, blue: 0.18)),
    FingerZone(id: 2, name: "Middle", color: Color(red: 0.11, green: 0.72, blue: 0.50)),
    FingerZone(id: 4, name: "Ring",   color: Color(red: 0.22, green: 0.54, blue: 0.87)),
    FingerZone(id: 8, name: "Pinky",  color: Color(red: 0.55, green: 0.45, blue: 0.90)),
]

// MARK: - Selective corner rounding

struct RoundedCornerShape: InsettableShape {
    var corners: UIRectCorner
    var radius: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        return Path(UIBezierPath(
            roundedRect: r, byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        ).cgPath)
    }
    func inset(by amount: CGFloat) -> RoundedCornerShape {
        var s = self; s.insetAmount += amount; return s
    }
}

// MARK: - Finger Zone View

struct FingerZoneView: View {
    let zone: FingerZone
    let isActive: Bool
    let roundedCorners: UIRectCorner

    var body: some View {
        ZStack {
            RoundedCornerShape(corners: roundedCorners, radius: 16)
                .fill(isActive ? zone.color.opacity(0.25) : zone.color.opacity(0.07))
            RoundedCornerShape(corners: roundedCorners, radius: 16)
                .strokeBorder(zone.color.opacity(isActive ? 0.80 : 0.18),
                              lineWidth: isActive ? 1.5 : 0.5)
            Text(zone.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(zone.color.opacity(isActive ? 1.0 : 0.28))
                .tracking(0.6)
        }
        .scaleEffect(isActive ? 0.97 : 1.0)
        .animation(.easeInOut(duration: 0.04), value: isActive)
    }
}

// MARK: - Thumb Button
//
// Three interactions:
//   Press + release quickly (no fingers) → toggleLayer
//   Press + hold  (no fingers)           → space
//   Press + hold while tapping fingers   → finger commits read thumbHeld=true → specials
//
// thumbHeld is set on the engine immediately on press and cleared on release,
// so finger ChordTracker commits that arrive while the thumb is down will see it.

struct ThumbButton: View {
    @ObservedObject var engine: ChordEngine
    let session: SessionManager
    let color = Color(red: 0.85, green: 0.38, blue: 0.22)

    @State private var holdTimer: Timer?
    @State private var holdFired = false
    @State private var isPressed = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(isPressed ? color.opacity(0.28) : color.opacity(0.08))
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(color.opacity(isPressed ? 0.75 : 0.20),
                              lineWidth: isPressed ? 1.5 : 0.5)
            VStack(spacing: 3) {
                Text("Thumb")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(color.opacity(isPressed ? 1.0 : 0.55))
                Text(engine.thumbHeld
                     ? "I=spc  M=⌫  R=↵  P=⌫⌫"
                     : "tap=layer  ·  hold=spc")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundColor(color.opacity(engine.thumbHeld ? 0.70 : 0.30))
                    .animation(.none, value: engine.thumbHeld)
            }
        }
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(.easeInOut(duration: 0.05), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    isPressed = true
                    holdFired = false
                    engine.thumbHeld = true   // immediately visible to ChordTracker commits
                    haptic(.medium)
                    holdTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in
                        holdFired = true
                        engine.thumbSpaceAlone(session: session)
                        haptic(.heavy)
                    }
                }
                .onEnded { _ in
                    isPressed = false
                    engine.thumbHeld = false
                    holdTimer?.invalidate(); holdTimer = nil
                    if !holdFired { engine.toggleLayer() }
                    holdFired = false
                }
        )
    }
}

// MARK: - ContentView

struct IOSContentView: View {
    @StateObject var session = SessionManager()
    @StateObject var engine  = ChordEngine()

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.08).ignoresSafeArea()
            ChordLayout(session: session, engine: engine)
        }
        .preferredColorScheme(.dark)
        .onAppear { AppDelegate.lockLandscape() }
    }
}

// MARK: - Chord Layout

struct ChordLayout: View {
    @ObservedObject var session: SessionManager
    @ObservedObject var engine:  ChordEngine

    @State private var fingerRects: [Int: CGRect] = [:]

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height

            let stripLeft:   CGFloat = W * 0.28
            let stripTop:    CGFloat = H * 0.04
            let stripWidth:  CGFloat = W - stripLeft - 12
            let stripHeight: CGFloat = H * 0.58
            let zoneW = stripWidth / CGFloat(fingerZones.count)

            let thumbW: CGFloat = W * 0.26
            let thumbH: CGFloat = H * 0.30
            let thumbLeft: CGFloat = 12
            let thumbTop:  CGFloat = H - thumbH - 12

            ZStack(alignment: .topLeading) {

                // ── Full-screen multitouch surface ────────────────────────
                ChordSurface(
                    fingerRects: fingerRects,
                    onMaskChange: { engine.updateMask($0) },
                    onCommit:    { engine.commit(mask: $0, session: session) }
                )
                .frame(width: W, height: H)
                .ignoresSafeArea()

                // ── Status bar ────────────────────────────────────────────
                HStack(spacing: 8) {
                    Circle()
                        .fill(session.connected ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                    Text(session.connected ? "Connected" : "Disconnected")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(session.connected ? Color.green.opacity(0.7) : Color(white: 0.28))
                    Spacer()
                    Text(engine.layer2Active ? "L2" : "L1")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(engine.layer2Active
                            ? Color(red: 0.94, green: 0.72, blue: 0.18)
                            : Color(white: 0.25))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color(white: 0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text(engine.previewLabel)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(white: 0.32))
                        .frame(minWidth: 36, alignment: .trailing)
                }
                .padding(.horizontal, 14).padding(.top, 8)
                .frame(width: W, height: 34)
                .allowsHitTesting(false)

                // ── Finger zones ──────────────────────────────────────────
                ForEach(Array(fingerZones.enumerated()), id: \.element.id) { idx, zone in
                    let x = stripLeft + CGFloat(idx) * zoneW
                    let isFirst = idx == 0
                    let isLast  = idx == fingerZones.count - 1
                    let corners: UIRectCorner = {
                        if isFirst { return [.topLeft, .bottomLeft] }
                        if isLast  { return [.topRight, .bottomRight] }
                        return []
                    }()

                    FingerZoneView(
                        zone: zone,
                        isActive: engine.activeMask & zone.id != 0,
                        roundedCorners: corners
                    )
                    .frame(width: zoneW, height: stripHeight)
                    .offset(x: x, y: stripTop)
                    .background(
                        GeometryReader { zg in
                            Color.clear.preference(
                                key: FingerRectsKey.self,
                                value: [zone.id: zg.frame(in: .global)]
                            )
                        }
                        .frame(width: zoneW, height: stripHeight)
                        .offset(x: x, y: stripTop)
                    )
                    .allowsHitTesting(false)
                }

                // ── Thumb button ──────────────────────────────────────────
                ThumbButton(engine: engine, session: session)
                    .frame(width: thumbW, height: thumbH)
                    .offset(x: thumbLeft, y: thumbTop)

                // ── Flash overlay ─────────────────────────────────────────
                if let flash = engine.flashKey {
                    Text(flash)
                        .font(.system(
                            size: flash.count > 2 ? 48 : 96,
                            weight: .black, design: .monospaced))
                        .foregroundColor(.white).opacity(0.75)
                        .transition(.opacity.combined(with: .scale(scale: 1.08)))
                        .allowsHitTesting(false)
                        .frame(width: W, height: H)
                        .multilineTextAlignment(.center)
                }
            }
            .onPreferenceChange(FingerRectsKey.self) { globalRects in
                let origin = geo.frame(in: .global).origin
                fingerRects = globalRects.mapValues {
                    CGRect(x: $0.minX - origin.x, y: $0.minY - origin.y,
                           width: $0.width, height: $0.height)
                }
            }
        }
        .disabled(!session.connected)
        .opacity(session.connected ? 1.0 : 0.25)
    }
}

// MARK: - Preference key

struct FingerRectsKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - Lock to landscape

class AppDelegate: NSObject, UIApplicationDelegate {
    static func lockLandscape() {
        if #available(iOS 16.0, *) {
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }.first
            scene?.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
        }
    }
}
