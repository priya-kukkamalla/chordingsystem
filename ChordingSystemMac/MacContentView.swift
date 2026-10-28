import SwiftUI
import AppKit

struct MacContentView: View {

    @StateObject var session = SessionManager()

    @State var typedText   = ""
    @State var lastChar    = ""
    @State var exportDone  = false

    var body: some View {
        HStack(spacing: 0) {

            // ── Left panel ──────────────────────────────────────────
            VStack(spacing: 0) {

                // Status
                HStack(spacing: 8) {
                    Circle()
                        .fill(session.connected ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                    Text(session.connected ? "Connected" : "Waiting for iPhone...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(session.connected ? .green : Color(white: 0.4))
                    Spacer()
                }
                .padding(.bottom, 20)

                // Last character — big display
                Text("LAST")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(white: 0.3))
                    .tracking(2)

                Text(lastChar.isEmpty ? "·" : lastChar == " " ? "⎵" : lastChar == "\n" ? "↵" : lastChar)
                    .font(.system(size: 110, weight: .black, design: .monospaced))
                    .foregroundColor(Color(red: 1.0, green: 0.82, blue: 0.20))
                    .frame(height: 120)
                    .animation(.easeOut(duration: 0.1), value: lastChar)

                Divider()
                    .background(Color(white: 0.15))
                    .padding(.vertical, 16)

                // Current word being built
                let currentWord = typedText
                    .components(separatedBy: .whitespacesAndNewlines).last ?? ""

                VStack(spacing: 4) {
                    Text("BUILDING")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(white: 0.3))
                        .tracking(2)

                    Text(currentWord.isEmpty ? "—" : currentWord)
                        .font(.system(size: 30, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(white: currentWord.isEmpty ? 0.2 : 0.75))
                        .lineLimit(1)
                        .truncationMode(.head)
                }

                Spacer()

                // Chord reference — compact
                VStack(alignment: .leading, spacing: 3) {
                    Text("QUICK REF")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(white: 0.25))
                        .tracking(2)
                        .padding(.bottom, 2)
                    ForEach([
                        ("T", "E"),  ("I", "T"), ("M", "A"), ("R", "O"), ("P", "I"),
                        ("T+I", "N"), ("T+M", "S"), ("T+R", "R"), ("I+M", "L"),
                        ("I+M+R+P", "SPACE"), ("T+I+M+R", "⌫"), ("T+M+R+P", "↵"),
                    ], id: \.0) { pair in
                        HStack(spacing: 0) {
                            Text(pair.0)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(Color(white: 0.35))
                                .frame(width: 70, alignment: .leading)
                            Text(pair.1)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(Color(white: 0.55))
                        }
                    }
                }
                .padding(.bottom, 8)
            }
            .frame(width: 260)
            .padding(20)
            .background(Color(red: 0.10, green: 0.10, blue: 0.13))

            // ── Right panel ─────────────────────────────────────────
            VStack(alignment: .leading, spacing: 0) {

                // Toolbar
                HStack(spacing: 10) {
                    Text("NOTES")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(white: 0.3))
                        .tracking(2)

                    Spacer()

                    let wc = typedText.split(separator: " ").count
                    let cc = typedText.count
                    Text("\(wc) words · \(cc) chars")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.28))

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(typedText, forType: .string)
                        exportDone = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { exportDone = false }
                    } label: {
                        Label(
                            exportDone ? "Copied!" : "Copy all",
                            systemImage: exportDone ? "checkmark.circle.fill" : "doc.on.clipboard"
                        )
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(exportDone ? .green : Color(white: 0.55))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(white: 0.14))
                        .cornerRadius(7)
                    }
                    .buttonStyle(.plain)

                    Button {
                        typedText = ""
                        lastChar  = ""
                    } label: {
                        Label("Clear", systemImage: "trash")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(red: 1.0, green: 0.38, blue: 0.38))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(white: 0.14))
                            .cornerRadius(7)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color(red: 0.09, green: 0.09, blue: 0.11))

                Divider().background(Color(white: 0.13))

                TextEditor(text: $typedText)
                    .font(.system(size: 22, design: .monospaced))
                    .foregroundColor(Color(white: 0.88))
                    .scrollContentBackground(.hidden)
                    .background(Color(red: 0.07, green: 0.07, blue: 0.09))
                    .padding(18)
            }
            .background(Color(red: 0.07, green: 0.07, blue: 0.09))
        }
        .frame(minWidth: 760, minHeight: 480)
        .preferredColorScheme(.dark)

        .onChange(of: session.receivedMessage) { _, newValue in
            // Strip timestamp suffix
            let command = newValue.components(separatedBy: "|").first ?? newValue
            handle(command)
        }
    }

    // MARK: - Command Handler

    func handle(_ command: String) {
        guard !command.isEmpty, command != "noop" else { return }

        if command.hasPrefix("char:") {
            let ch = String(command.dropFirst(5))
            typedText += ch
            lastChar   = ch
            return
        }

        switch command {
        case "space":
            typedText += " "
            lastChar   = " "
        case "newline":
            typedText += "\n"
            lastChar   = "↵"
        case "backspace":
            if !typedText.isEmpty {
                typedText.removeLast()
                lastChar = "⌫"
            }
        case "deleteword":
            deleteLastWord()
            lastChar = "⌫⌫"
        // Legacy T9 commands (kept for compatibility if you switch modes)
        case "group":
            break
        case "letter":
            break
        case "select":
            break
        default:
            break
        }
    }

    func deleteLastWord() {
        guard !typedText.isEmpty else { return }
        // Trim trailing spaces first
        while typedText.last == " " { typedText.removeLast() }
        // Then remove until next space or start
        while !typedText.isEmpty && typedText.last != " " { typedText.removeLast() }
    }
}
