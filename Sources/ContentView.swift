import SwiftUI

struct ContentView: View {
    @StateObject private var vm = ChatViewModel()
    @State private var showHistory = false
    @State private var showSettings = false
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var inputFocused: Bool

    private let suggestions = [
        "Explain how airplanes stay in the air",
        "Give me a 3-day itinerary for Lisbon",
        "Help me write a polite email declining an invitation",
        "Quiz me on basic Spanish phrases"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if case .unavailable(let title, let detail) = vm.engine.status {
                    UnavailableBanner(title: title, detail: detail) { vm.engine.refreshAvailability() }
                }
                messageList
                InputBar(text: $vm.input, isGenerating: vm.isGenerating, canSend: vm.engine.status.isReady,
                         focused: $inputFocused, send: { vm.send() }, stop: { vm.stop() })
            }
            .navigationTitle(vm.current.messages.isEmpty ? "Pocket Chat" : vm.current.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
                        .accessibilityLabel("Chat history")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { vm.newChat() } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("New chat")
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showHistory) { HistoryView(vm: vm, isPresented: $showHistory) }
            .sheet(isPresented: $showSettings) { SettingsView(vm: vm, settings: vm.settings, isPresented: $showSettings) }
        }
        .onAppear {
            vm.prewarm()
            if let i = CommandLine.arguments.firstIndex(of: "-autoprompt"), i + 1 < CommandLine.arguments.count {
                let p = CommandLine.arguments[i + 1]                  // test hook: send a prompt at launch
                Task { try? await Task.sleep(nanoseconds: 800_000_000); vm.send(p) }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { vm.engine.refreshAvailability() }   // the user may have just enabled Apple Intelligence
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if vm.current.messages.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(vm.current.messages) { m in
                            MessageRow(message: m, isStreaming: vm.streamingID == m.id,
                                       isLast: m.id == vm.current.messages.last?.id,
                                       canRegenerate: !vm.isGenerating && vm.engine.status.isReady,
                                       regenerate: { vm.regenerate() })
                                .id(m.id)
                        }
                        Color.clear.frame(height: 4).id("bottom")
                    }
                    .padding(.horizontal, 12).padding(.top, 8)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: vm.current.messages.last?.text) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: vm.current.messages.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: vm.currentID) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "sparkles")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [.indigo, .blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(.top, 56)
            Text("Ask anything").font(.title.bold())
            Label("Runs on this iPhone with Apple Intelligence. Nothing leaves your device.", systemImage: "lock.shield")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 28)
            VStack(spacing: 10) {
                ForEach(suggestions, id: \.self) { s in
                    Button { vm.send(s) } label: {
                        Text(s).font(.subheadline).multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(!vm.engine.status.isReady)
                }
            }
            .padding(.horizontal, 16).padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }
}

struct UnavailableBanner: View {
    let title: String
    let detail: String
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "exclamationmark.triangle.fill").font(.subheadline.bold()).foregroundStyle(.orange)
            Text(detail).font(.footnote).foregroundStyle(.secondary)
            Button("Check again", action: retry).font(.footnote.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .accessibilityElement(children: .combine)
    }
}

struct MessageRow: View {
    let message: ChatMessage
    let isStreaming: Bool
    let isLast: Bool
    let canRegenerate: Bool
    let regenerate: () -> Void

    private var isUser: Bool { message.role == .user }

    private var rendered: AttributedString {
        (try? AttributedString(markdown: message.text,
                               options: .init(allowsExtendedAttributes: true, interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(message.text)
    }

    var body: some View {
        HStack(alignment: .bottom) {
            if isUser { Spacer(minLength: 44) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                bubble
                if isLast && !isUser && !isStreaming && canRegenerate {
                    Button(action: regenerate) {
                        Label(message.isError ? "Try again" : "Regenerate", systemImage: "arrow.clockwise").font(.caption.bold())
                    }
                    .buttonStyle(.bordered).controlSize(.mini)
                }
            }
            if !isUser { Spacer(minLength: 44) }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var bubble: some View {
        if message.text.isEmpty && isStreaming {
            TypingDots().padding(.horizontal, 16).padding(.vertical, 14)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityLabel("Thinking")
        } else {
            Text(rendered)
                .font(.body)
                .textSelection(.enabled)
                .foregroundStyle(isUser ? Color.white : (message.isError ? Color.red : Color.primary))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contextMenu {
                    Button { UIPasteboard.general.string = message.text } label: { Label("Copy", systemImage: "doc.on.doc") }
                    ShareLink(item: message.text) { Label("Share", systemImage: "square.and.arrow.up") }
                }
                .accessibilityLabel((isUser ? "You: " : "Assistant: ") + message.text)
        }
    }

    private var background: AnyShapeStyle {
        if isUser { return AnyShapeStyle(LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)) }
        if message.isError { return AnyShapeStyle(Color.red.opacity(0.12)) }
        return AnyShapeStyle(Color(.secondarySystemBackground))
    }
}

struct TypingDots: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(Color.secondary).frame(width: 8, height: 8).opacity(phase == i ? 1 : 0.3)
            }
        }
        .onReceive(timer) { _ in withAnimation(.easeInOut(duration: 0.2)) { phase = (phase + 1) % 3 } }
    }
}

struct InputBar: View {
    @Binding var text: String
    let isGenerating: Bool
    let canSend: Bool
    var focused: FocusState<Bool>.Binding
    let send: () -> Void
    let stop: () -> Void

    private var hasText: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message", text: $text, axis: .vertical)
                .lineLimit(1...6)
                .focused(focused)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .submitLabel(.send)
                .onSubmit { if hasText { send() } }
                .disabled(!canSend)
            Button(action: isGenerating ? stop : send) {
                Image(systemName: isGenerating ? "stop.fill" : "arrow.up")
                    .font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(isGenerating || (hasText && canSend) ? Color.blue : Color.gray.opacity(0.5), in: Circle())
            }
            .disabled(!isGenerating && !(hasText && canSend))
            .accessibilityLabel(isGenerating ? "Stop generating" : "Send")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.bar)
    }
}

struct HistoryView: View {
    @ObservedObject var vm: ChatViewModel
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List {
                if vm.sortedConversations.filter({ !$0.messages.isEmpty }).isEmpty {
                    ContentUnavailableView("No saved chats yet", systemImage: "bubble.left.and.bubble.right",
                                           description: Text("Your conversations appear here and stay on this iPhone."))
                }
                ForEach(vm.sortedConversations.filter { !$0.messages.isEmpty }) { c in
                    Button { vm.select(c.id); isPresented = false } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(c.title).font(.headline).lineLimit(1)
                                if c.id == vm.currentID { Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue) }
                            }
                            Text(c.messages.last?.text ?? "").font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            Text(c.updatedAt, style: .relative).font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                    .swipeActions { Button("Delete", role: .destructive) { vm.delete(c.id) } }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("New chat") { vm.newChat(); isPresented = false } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { isPresented = false } }
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var vm: ChatViewModel
    @ObservedObject var settings: SettingsStore
    @Binding var isPresented: Bool
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Persona", selection: $settings.persona) {
                        ForEach(Persona.allCases) { Text($0.name).tag($0) }
                    }
                    if settings.persona == .custom {
                        TextField("Describe how the assistant should behave", text: $settings.custom, axis: .vertical).lineLimit(2...6)
                    }
                    Picker("Response length", selection: $settings.length) {
                        ForEach(ResponseLength.allCases) { Text($0.name).tag($0) }
                    }
                    VStack(alignment: .leading) {
                        HStack { Text("Creativity"); Spacer(); Text(String(format: "%.0f%%", settings.creativity * 100)).foregroundStyle(.secondary) }
                        Slider(value: $settings.creativity, in: 0...1)
                    }
                } header: { Text("Assistant") } footer: {
                    Text("Changes apply to your next message. Lower creativity gives steadier answers; higher gives more varied ones.")
                }
                Section("Feedback") { Toggle("Haptics", isOn: $settings.haptics) }
                Section {
                    switch vm.engine.status {
                    case .ready: Label("Apple Intelligence model ready", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    case .unavailable(let t, let d): VStack(alignment: .leading, spacing: 4) { Label(t, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange); Text(d).font(.footnote).foregroundStyle(.secondary) }
                    }
                } header: { Text("On-device model") } footer: {
                    Text("Pocket Chat uses the language model built into this iPhone through Apple's Foundation Models framework. Prompts and replies are processed on the device and are not sent to any server. The model has a small memory, so very long chats are condensed automatically.")
                }
                Section {
                    Button("Delete all chats", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { isPresented = false } } }
            .confirmationDialog("Delete every saved chat?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete all", role: .destructive) { vm.deleteAll(); isPresented = false }
            }
            .onAppear { vm.engine.refreshAvailability() }
            .onChange(of: settings.persona) { _, _ in vm.engine.invalidate() }
            .onChange(of: settings.custom) { _, _ in vm.engine.invalidate() }
            .onChange(of: settings.length) { _, _ in vm.engine.invalidate() }
        }
    }
}
