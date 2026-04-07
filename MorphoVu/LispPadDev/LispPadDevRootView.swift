//
//  LispPadDevRootView.swift
//  LispPadDev
//
//  Created by Codex on 3/21/26.
//

import SwiftUI
import LispPadCore

struct LispPadDevRootView: View {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var interpreter = Interpreter()
    @StateObject private var history = HistoryManager()

    @State private var splitViewMode: SideBySideMode = .normal
    @State private var masterWidthFraction: CGFloat = 0.32
    @State private var commandText = ""
    @State private var didLoadSCMUtils = false

    private var supportsSplit: Bool {
        #if os(iOS)
        horizontalSizeClass == .regular
        #else
        true
        #endif
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.11, blue: 0.16),
                    Color(red: 0.04, green: 0.06, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            SideBySide(
                mode: $splitViewMode,
                fraction: $masterWidthFraction,
                leftMinFraction: 0.24,
                rightMinFraction: 0.38,
                dragToHide: supportsSplit,
                visibleThickness: 1,
                invisibleThickness: 24
            ) {
                SidebarPanel(
                    supportsSplit: supportsSplit,
                    mode: $splitViewMode,
                    fraction: $masterWidthFraction,
                    interpreter: interpreter,
                    libraryManager: interpreter.libManager,
                    environmentManager: interpreter.envManager,
                    history: history,
                    commandText: $commandText,
                    loadCommand: loadCommand(_:),
                    runSample: runSample(_:)
                )
            } right: {
                SessionPanel(
                    supportsSplit: supportsSplit,
                    mode: $splitViewMode,
                    fraction: $masterWidthFraction,
                    interpreter: interpreter,
                    console: interpreter.console,
                    scmutilsIsAvailable: SCMUtilsSupport.isAvailable,
                    scmutilsIsAutoLoaded: didLoadSCMUtils,
                    commandText: $commandText,
                    runCommand: runCurrentCommand,
                    stageSCMUtils: stageSCMUtils,
                    resetSession: resetSession,
                    clearTranscript: clearTranscript
                )
            }
            .padding(supportsSplit ? 16 : 0)
        }
        .task {
            normalizeSplitMode(isRegularWidth: supportsSplit)
            if commandText.isEmpty {
                commandText = initialCommandText()
            }
        }
        .onChange(of: supportsSplit) { _, isRegularWidth in
            normalizeSplitMode(isRegularWidth: isRegularWidth)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                history.saveCommandHistory()
                history.saveSearchHistory()
                history.saveFilesHistory()
                history.saveFavorites()
            }
        }
    }

    private func normalizeSplitMode(isRegularWidth: Bool) {
        if isRegularWidth {
            if !splitViewMode.isSideBySide {
                splitViewMode.makeSideBySide()
            }
        } else if splitViewMode.isSideBySide {
            splitViewMode = .leftOnLeft
        }
    }

    private func loadCommand(_ command: String) {
        commandText = command
    }

    private func runSample(_ sample: BootstrapCommand) {
        commandText = sample.code
        runCurrentCommand()
    }

    private func stageSCMUtils() {
        guard SCMUtilsSupport.isAvailable else {
            interpreter.console.append(output: .info(SCMUtilsSupport.unavailableSummary))
            return
        }
        guard !didLoadSCMUtils else {
            interpreter.console.append(output: .info("SCMUtils is already loaded for this session. Use Reset for a fresh session before loading it again."))
            return
        }
        commandText = SCMUtilsSupport.stagedLoadCommand
        interpreter.console.append(output: .info(SCMUtilsSupport.consoleSummary))
    }

    private func runCurrentCommand() {
        var submitted = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        let includesSCMUtilsBootstrap = SCMUtilsSupport.strippingDuplicateBootstrap(from: submitted) != submitted
        if didLoadSCMUtils {
            let stripped = SCMUtilsSupport.strippingDuplicateBootstrap(from: submitted)
            if stripped != submitted {
                interpreter.console.append(output: .info("Skipping duplicate SCMUtils bootstrap because this session already loaded it."))
                submitted = stripped
            }
        }
        guard !submitted.isEmpty else {
            commandText = ""
            return
        }
        if didLoadSCMUtils || includesSCMUtilsBootstrap {
            interpreter.setReplEnvironment(named: "user-generic-environment")
        } else {
            interpreter.setReplEnvironment(named: nil)
        }
        if includesSCMUtilsBootstrap {
            didLoadSCMUtils = true
        }
        _ = history.addCommandEntry(submitted)
        history.saveCommandHistory()
        interpreter.evaluate(submitted)
        commandText = ""
    }

    private func resetSession() {
        if interpreter.reset() {
            didLoadSCMUtils = false
            interpreter.setReplEnvironment(named: nil)
            commandText = initialCommandText()
        }
    }

    private func initialCommandText() -> String {
        let candidate = history.commandHistory.first ?? BootstrapCommand.samples[0].code
        let stripped = SCMUtilsSupport.strippingDuplicateBootstrap(from: candidate)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? BootstrapCommand.samples[0].code : stripped
    }

    private func clearTranscript() {
        interpreter.clearConsole()
    }
}

private struct SidebarPanel: View {
    let supportsSplit: Bool
    @Binding var mode: SideBySideMode
    @Binding var fraction: CGFloat
    @ObservedObject var interpreter: Interpreter
    @ObservedObject var libraryManager: LibraryManager
    @ObservedObject var environmentManager: EnvironmentManager
    @ObservedObject var history: HistoryManager
    @Binding var commandText: String
    let loadCommand: (String) -> Void
    let runSample: (BootstrapCommand) -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("LispPadDev")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Shared LispPadCore runtime shell")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))

                    Text(LispPadCoreStatus.bootstrapSummary)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                SideBySideNavigator(
                    leftSide: true,
                    allowSplit: supportsSplit,
                    mode: $mode,
                    fraction: $fraction
                )
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    StatusBadge(
                        title: interpreter.isReady ? "Ready" : "Booting",
                        tint: interpreter.isReady ? Color(red: 0.48, green: 0.83, blue: 0.63) : Color(red: 0.95, green: 0.68, blue: 0.31)
                    )

                    Text("\(LispPadCoreStatus.bootstrapFileCount) shared files")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))

                    Spacer()
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    MetricCard(title: "Outputs", value: "\(interpreter.console.content.count)")
                    MetricCard(title: "Libraries", value: "\(libraryManager.loadedLibraryCount)/\(libraryManager.libraries.count)")
                    MetricCard(title: "Bindings", value: "\(environmentManager.bindingCount)")
                    MetricCard(title: "History", value: "\(history.commandHistory.count)")
                }
            }
            .padding(16)
            .background(panelBackground)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sidebarSection(title: "Quick Start") {
                        ForEach(BootstrapCommand.samples) { sample in
                            SidebarCommandButton(
                                title: sample.title,
                                summary: sample.summary,
                                tag: sample.tag,
                                primaryTitle: "Load",
                                secondaryTitle: "Run",
                                primaryAction: { loadCommand(sample.code) },
                                secondaryAction: { runSample(sample) }
                            )
                        }
                    }

                    sidebarSection(title: "Recent Commands") {
                        if history.commandHistory.isEmpty {
                            EmptySidebarState(text: "Run a few forms and they’ll show up here.")
                        } else {
                            ForEach(Array(history.commandHistory.prefix(6)), id: \.self) { entry in
                                SidebarPill(text: entry) {
                                    loadCommand(entry)
                                }
                            }
                        }
                    }

                    sidebarSection(title: "Libraries") {
                        if libraryManager.libraries.isEmpty {
                            EmptySidebarState(text: "Scanning LispKit libraries...")
                        } else {
                            ForEach(Array(libraryManager.libraries.prefix(14))) { library in
                                LibraryRow(name: library.name, state: library.state) {
                                    loadCommand("(import \(library.name))")
                                }
                            }
                        }
                    }

                    sidebarSection(title: "Environment") {
                        if environmentManager.bindingNames.isEmpty {
                            EmptySidebarState(text: "Bindings will appear after the session finishes bootstrapping.")
                        } else {
                            ForEach(Array(environmentManager.bindingNames.prefix(18)), id: \.self) { binding in
                                SidebarPill(text: binding) {
                                    loadCommand(binding)
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var panelBackground: some ShapeStyle {
        .linearGradient(
            colors: [
                Color.white.opacity(0.12),
                Color.white.opacity(0.06)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private func sidebarSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.48))

            content()
        }
    }
}

private struct SessionPanel: View {
    let supportsSplit: Bool
    @Binding var mode: SideBySideMode
    @Binding var fraction: CGFloat
    @ObservedObject var interpreter: Interpreter
    @ObservedObject var console: Console
    let scmutilsIsAvailable: Bool
    let scmutilsIsAutoLoaded: Bool
    @Binding var commandText: String
    let runCommand: () -> Void
    let stageSCMUtils: () -> Void
    let resetSession: () -> Void
    let clearTranscript: () -> Void

    private var trimmedCommand: String {
        commandText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Session")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("This transcript is backed by the shared `LispPadCore` interpreter, so the same service graph can feed future iPadOS, macOS, and visionOS shells.")
                        .font(LispPadUI.bodyFont)
                        .foregroundStyle(.white.opacity(0.72))
                }

                Spacer()

                HStack(spacing: 10) {
                    StatusBadge(
                        title: interpreter.isReady ? "Accepting Input" : "Evaluating",
                        tint: interpreter.isReady ? Color(red: 0.48, green: 0.83, blue: 0.63) : Color(red: 0.95, green: 0.68, blue: 0.31)
                    )

                    Button("Clear", action: clearTranscript)
                        .buttonStyle(SessionButtonStyle())

                    Button("Reset", action: resetSession)
                        .buttonStyle(SessionButtonStyle())

                    Button(SCMUtilsSupport.buttonTitle(isAvailable: scmutilsIsAvailable, isLoaded: scmutilsIsAutoLoaded), action: stageSCMUtils)
                        .buttonStyle(SessionButtonStyle())
                        .disabled(scmutilsIsAutoLoaded || !scmutilsIsAvailable || !interpreter.isReady)

                    SideBySideNavigator(
                        leftSide: false,
                        allowSplit: supportsSplit,
                        mode: $mode,
                        fraction: $fraction
                    )
                }
            }

            HStack(spacing: 10) {
                Text("LispKit runtime")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.91, green: 0.95, blue: 1.0))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.1))
                    )

                Text("Libraries \(interpreter.loadedLibraryCount)/\(interpreter.libraryCount)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.91, green: 0.95, blue: 1.0))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.1))
                    )

                Text("Bindings \(interpreter.bindingCount)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.91, green: 0.95, blue: 1.0))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.1))
                    )

                Spacer()
            }

            TranscriptView(console: console)

            VStack(alignment: .leading, spacing: 12) {
                Text("Command")
                    .font(LispPadUI.headerFont)
                    .foregroundStyle(.white.opacity(0.92))

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.black.opacity(0.26))

                    if trimmedCommand.isEmpty {
                        Text("Type Scheme here, or tap a quick-start command on the left.")
                            .font(LispPadUI.bodyFont)
                            .foregroundStyle(.white.opacity(0.28))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                    }

                    TextEditor(text: $commandText)
                        .font(LispPadUI.monoFont)
                        .foregroundStyle(Color(red: 0.90, green: 0.96, blue: 1.0))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(minHeight: 122)
                }

                HStack(alignment: .center, spacing: 12) {
                    Text("Shared core: `Interpreter`, `Console`, `LibraryManager`, `EnvironmentManager`, `HistoryManager`")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))

                    Spacer()

                    Button(action: runCommand) {
                        Label(interpreter.isReady ? "Run" : "Queue Input", systemImage: "play.fill")
                    }
                    .buttonStyle(RunButtonStyle())
                    .disabled(trimmedCommand.isEmpty)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var cardBackground: some ShapeStyle {
        .linearGradient(
            colors: [
                Color(red: 0.11, green: 0.14, blue: 0.22),
                Color(red: 0.07, green: 0.09, blue: 0.15)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct TranscriptView: View {
    @ObservedObject var console: Console

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(console.content) { entry in
                        TranscriptRow(entry: entry)
                            .id(entry.id)
                    }
                }
                .padding(18)
            }
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.black.opacity(0.26))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white.opacity(0.05), lineWidth: 1)
            )
            .onChange(of: console.lastOutputID) { _, newID in
                guard let newID else {
                    return
                }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(newID, anchor: .bottom)
                }
            }
        }
    }
}

private struct TranscriptRow: View {
    let entry: ConsoleOutput

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.text.isEmpty && entry.kind == .result ? "()" : entry.text)
                .font(entry.kind == .command ? .system(size: 14, weight: .semibold, design: .monospaced) : LispPadUI.monoFont)
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            if let errorContext = entry.errorContext, !errorContext.description.isEmpty {
                Text(errorContext.description)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(backgroundColor)
        )
    }

    private var textColor: Color {
        switch entry.kind {
        case .command:
            return Color(red: 0.73, green: 0.93, blue: 0.78)
        case .info:
            return Color(red: 0.74, green: 0.87, blue: 1.0)
        case .error:
            return Color(red: 1.0, green: 0.80, blue: 0.72)
        case .output:
            return Color.white.opacity(0.72)
        default:
            return Color(red: 0.90, green: 0.96, blue: 1.0)
        }
    }

    private var backgroundColor: Color {
        switch entry.kind {
        case .command:
            return Color(red: 0.17, green: 0.28, blue: 0.20).opacity(0.75)
        case .info:
            return Color(red: 0.12, green: 0.22, blue: 0.31).opacity(0.75)
        case .error:
            return Color(red: 0.33, green: 0.13, blue: 0.12).opacity(0.78)
        default:
            return Color.white.opacity(0.05)
        }
    }
}

private struct StatusBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.16))
            )
    }
}

private struct MetricCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.44))

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.18))
        )
    }
}

private struct SidebarCommandButton: View {
    let title: String
    let summary: String
    let tag: String
    let primaryTitle: String
    let secondaryTitle: String
    let primaryAction: () -> Void
    let secondaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text(tag)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(.white.opacity(0.52))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
            }

            Text(summary)
                .font(LispPadUI.bodyFont)
                .foregroundStyle(.white.opacity(0.68))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(SidebarActionStyle())

                Button(secondaryTitle, action: secondaryAction)
                    .buttonStyle(SidebarActionStyle(filled: true))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct SidebarPill: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(red: 0.90, green: 0.96, blue: 1.0))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.18))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct LibraryRow: View {
    let name: String
    let state: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(red: 0.90, green: 0.96, blue: 1.0))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(state)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.44))
                }

                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .foregroundStyle(.white.opacity(0.28))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.18))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct EmptySidebarState: View {
    let text: String

    var body: some View {
        Text(text)
            .font(LispPadUI.bodyFont)
            .foregroundStyle(.white.opacity(0.52))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
    }
}

private struct SidebarActionStyle: ButtonStyle {
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(filled ? Color.black.opacity(0.82) : .white.opacity(0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(filled ? Color(red: 0.82, green: 0.93, blue: 0.98) : Color.white.opacity(configuration.isPressed ? 0.16 : 0.10))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

private struct SessionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.86))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.16 : 0.10))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

private struct RunButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(Color.black.opacity(0.82))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.72, green: 0.93, blue: 0.77),
                                Color(red: 0.62, green: 0.86, blue: 0.96)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

private struct BootstrapCommand: Identifiable {
    let id: String
    let title: String
    let summary: String
    let tag: String
    let code: String

    static let samples: [BootstrapCommand] = [
        BootstrapCommand(
            id: "math",
            title: "Warmup",
            summary: "Confirm the shared interpreter is live with a tiny arithmetic form.",
            tag: "REPL",
            code: "(+ 2 3)"
        ),
        BootstrapCommand(
            id: "map",
            title: "Map Squares",
            summary: "Exercise higher-order functions and list printing in the live session.",
            tag: "CORE",
            code: "(map (lambda (x) (* x x)) '(1 2 3 4 5))"
        ),
        BootstrapCommand(
            id: "features",
            title: "Feature List",
            summary: "Inspect the current LispKit feature set the shared session exposes.",
            tag: "RUNTIME",
            code: "(features)"
        ),
        BootstrapCommand(
            id: "bindings",
            title: "Environment Peek",
            summary: "Inspect a few bindings through Lisp rather than the side panel.",
            tag: "INTROSPECT",
            code: "(list *1 *2 *3)"
        )
    ]
}

private enum SCMUtilsSupport {
    private static let fileManager = FileManager.default
    private static let workspaceBundleRoot = preferredExistingPath(
        [
            "/Volumes/GitHubDeveloper/Packages/SCMUtilsBundle",
            "/Volumes/GitHubDeveloper/__Graveyard/SCMUtilsBundle"
        ],
        fallback: "/Volumes/GitHubDeveloper/Packages/SCMUtilsBundle"
    )
    private static let workspaceProbeScript = preferredExistingPath(
        [
            "/Volumes/GitHubDeveloper/Projects/MorphoVu/scripts/scmutils_compat_probe.py"
        ],
        fallback: "/Volumes/GitHubDeveloper/Projects/MorphoVu/scripts/scmutils_compat_probe.py"
    )
    private static let workspaceBootstrap = workspaceBundleRoot + "/Bootstrap/scmutils_lispkit_bootstrap.scm"

    private static let bootstrapURL: URL? = {
        let candidatePaths = [
            Bundle.main.url(forResource: "scmutils_lispkit_bootstrap", withExtension: "scm", subdirectory: "Bootstrap"),
            Bundle.main.url(forResource: "scmutils_lispkit_bootstrap", withExtension: "scm", subdirectory: "SCMUtilsBundle/Bootstrap"),
            Bundle.main.resourceURL?.appendingPathComponent("Bootstrap/scmutils_lispkit_bootstrap.scm"),
            Bundle.main.resourceURL?.appendingPathComponent("SCMUtilsBundle/Bootstrap/scmutils_lispkit_bootstrap.scm"),
            URL(fileURLWithPath: workspaceBootstrap)
        ]

        for candidate in candidatePaths.compactMap({ $0 }) where fileManager.fileExists(atPath: candidate.path) {
            return candidate.resolvingSymlinksInPath()
        }
        return nil
    }()

    static let isAvailable = bootstrapURL != nil

    private static let bundleRoot = bootstrapURL?
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .path

    private static let upstreamRoot = bundleRoot.map { $0 + "/Upstream/scmutils-20230902" }
    private static let lispKitRoot = bundleRoot.map { $0 + "/LispKit/scmutils-20230902" }
    private static let installScript = upstreamRoot.map { $0 + "/install.sh" }
    private static let sourceLoader = upstreamRoot.map { $0 + "/load.scm" }
    private static let sourceLoaderReal = upstreamRoot.map { $0 + "/load-real.scm" }
    private static let probeScript = bundleRoot.map { _ in workspaceProbeScript }
    private static let buildScript = bundleRoot.map { $0 + "/scripts/build_scmutils_bundle.py" }
    private static let lispKitBootstrap = bootstrapURL?.path

    static let runtimeLoadCommand = bootstrapURL.map { """
    (load "\($0.path)")
    """ } ?? """
    (load "\(workspaceBootstrap)")
    """

    static let stagedLoadCommand = """
    ;; LispKit-oriented SCMUtils bundle bootstrap.
    ;; This loads the generated LispKit working copy from SCMUtilsBundle and
    ;; bypasses MIT Scheme's top-level loader wrappers.
    \(runtimeLoadCommand)
    """

    static func strippingDuplicateBootstrap(from text: String) -> String {
        let bootstrapLines = Set([
            ";; LispKit-oriented SCMUtils bundle bootstrap.",
            ";; This loads the generated LispKit working copy from SCMUtilsBundle and",
            ";; bypasses MIT Scheme's top-level loader wrappers.",
            runtimeLoadCommand,
            "(load \"\(workspaceBootstrap)\")"
        ].filter { !$0.isEmpty })

        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                !bootstrapLines.contains(line.trimmingCharacters(in: .whitespaces))
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static let consoleSummary: String = {
        guard
            let upstreamRoot,
            let lispKitRoot,
            let lispKitBootstrap,
            let sourceLoader,
            let sourceLoaderReal,
            let buildScript,
            let probeScript,
            let installScript
        else {
            return unavailableSummary
        }
        return """
        SCMUtils load form staged in the editor.
        Vendored upstream snapshot: \(upstreamRoot)
        Generated LispKit copy: \(lispKitRoot)
        LispKit bootstrap: \(lispKitBootstrap)
        Raw MIT loaders: \(sourceLoader), \(sourceLoaderReal)
        Bundle rebuild: python3 \(buildScript)
        Probe script: \(probeScript)
        Terminal: python3 \(probeScript) --runtime-check \(lispKitRoot)
        Vendored install chain source: \(installScript)
        MIT compiled artifacts (.bci, mechanics.com) are intentionally excluded from the bundle.
        """
    }()

    static let unavailableSummary = """
    SCMUtils bundle is not available on this device yet, so the shared session will stay in plain LispKit mode.
    The macOS dev shell can still use the workspace bundle when \(workspaceBundleRoot) is present.
    """

    static func buttonTitle(isAvailable: Bool, isLoaded: Bool) -> String {
        if isLoaded {
            return "SCMUtils Loaded"
        }
        return isAvailable ? "Load SCMUtils" : "SCMUtils Unavailable"
    }

    private static func preferredExistingPath(_ candidates: [String], fallback: String) -> String {
        for candidate in candidates where fileManager.fileExists(atPath: candidate) {
            return candidate
        }
        return fallback
    }
}

#Preview {
    LispPadDevRootView()
}
