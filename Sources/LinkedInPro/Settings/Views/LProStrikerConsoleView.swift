import SwiftUI
import LinkedInProC

// Live view of what a remote viewer sends the Striker console over the loopback
// socket and the output it got back. Striker records each command/response pair
// in its own ring (StrikerConsoleSnapshot); this polls that ring and refreshes
// only when the sequence counter changes, so an idle console costs nothing.
//
// It shows traffic regardless of the DevKit toggle's current state - if the
// listener is off, the ring simply stops gaining entries and the last session's
// transcript stays visible until cleared.
struct LProStrikerConsoleView: View {
    @State private var text = ""
    @State private var seq: UInt = 0
    @State private var running = LProDevKit.isRunning
    private let timer = Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(text.isEmpty ? placeholder : text)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
                Color.clear.frame(height: 1).id("console-end")
            }
            .onReceive(timer) { _ in refresh(proxy) }
            .onAppear { refresh(proxy) }
        }
        .navigationTitle("Striker console")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") {
                    StrikerConsoleReset()
                    text = ""
                    seq = UInt(StrikerConsoleSeq())
                }
            }
        }
        .safeAreaInset(edge: .top) {
            HStack(spacing: 6) {
                Circle().fill(running ? Color.green : Color.secondary).frame(width: 8, height: 8)
                Text(running ? "Listening on 127.0.0.1:\(LProDevKit.port)" : "Listener off")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.bar)
        }
    }

    private var placeholder: String {
        "No commands received yet.\n\nBridge over USB with\n  iproxy \(LProDevKit.port) \(LProDevKit.port)\nthen send a command with the Striker driver. Each command and its output appears here as it arrives."
    }

    private func refresh(_ proxy: ScrollViewProxy) {
        running = LProDevKit.isRunning
        let current = UInt(StrikerConsoleSeq())
        guard current != seq else { return }
        seq = current
        if let c = StrikerConsoleSnapshot(400) {
            text = String(cString: c)
            StrikerFree(c)
        }
        proxy.scrollTo("console-end", anchor: .bottom)
    }
}
