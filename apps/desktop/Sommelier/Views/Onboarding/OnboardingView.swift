import SwiftUI
import UniformTypeIdentifiers

/// Multi-step onboarding wizard that guides new users through
/// system dependency setup: Rosetta 2, GPTK, CLI tools, and API keys.
///
/// Uses a custom step-based layout with animated transitions between
/// each phase. Calls `onComplete` when the user finishes the wizard.
struct OnboardingView: View {

    /// Called when the user completes or dismisses the onboarding flow.
    let onComplete: () -> Void

    @State private var viewModel = OnboardingViewModel()

    /// Namespace for matched geometry transitions between steps.
    @Namespace private var stepAnimation

    var body: some View {
        ZStack {
            // Premium dark gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.06, blue: 0.10),
                    Color(red: 0.14, green: 0.10, blue: 0.16),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Step progress indicator
                stepProgressBar
                    .padding(.top, 32)
                    .padding(.bottom, 24)

                // Step content — centered card
                stepContent
                    .frame(maxWidth: 560, maxHeight: .infinity)

                // Navigation buttons
                navigationButtons
                    .padding(.bottom, 32)
            }
            .padding(.horizontal, 48)
        }
        .onAppear {
            viewModel.runSystemChecks()
        }
    }

    // MARK: - Step Progress Bar

    /// Horizontal dots showing progress through the onboarding steps.
    private var stepProgressBar: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                Circle()
                    .fill(step <= viewModel.currentStep ? Color.accentColor : Color.white.opacity(0.2))
                    .frame(width: step == viewModel.currentStep ? 10 : 7,
                           height: step == viewModel.currentStep ? 10 : 7)
                    .animation(.spring(response: 0.4), value: viewModel.currentStep)
            }
        }
    }

    // MARK: - Step Content

    /// The main content area that switches between onboarding steps.
    @ViewBuilder
    private var stepContent: some View {
        Group {
            switch viewModel.currentStep {
            case .welcome:
                welcomeStep
            case .systemCheck:
                systemCheckStep
            case .rosetta:
                rosettaStep
            case .gptk:
                gptkStep
            case .cliTools:
                cliToolsStep
            case .apiKeys:
                apiKeysStep
            case .complete:
                completeStep
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: viewModel.currentStep)
    }

    // MARK: - Individual Steps

    /// Welcome screen with app branding.
    private var welcomeStep: some View {
        stepCard {
            VStack(spacing: 20) {
                Image(systemName: "wineglass")
                    .font(.system(size: 64))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.6)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Text("Sommelier")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                Text("Your premium macOS game library manager.\nLet's get everything set up.")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
    }

    /// System check results showing architecture and macOS version.
    private var systemCheckStep: some View {
        stepCard {
            VStack(spacing: 24) {
                stepIcon("cpu")

                Text("System Check")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                Text("Checking your system capabilities.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.7))

                VStack(spacing: 12) {
                    infoRow(label: "Architecture", value: viewModel.isAppleSilicon ? "Apple Silicon" : "Intel")
                    infoRow(label: "macOS Version", value: viewModel.macOSVersion)
                    infoRow(label: "Machine", value: viewModel.macModel)
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    /// Rosetta 2 installation step.
    private var rosettaStep: some View {
        stepCard {
            VStack(spacing: 24) {
                stepIcon("arrow.triangle.2.circlepath")

                Text("Rosetta 2")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                Text("Rosetta 2 translates x86 applications to run on Apple Silicon.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)

                // Status
                HStack(spacing: 8) {
                    Circle()
                        .fill(viewModel.rosettaStatus.color)
                        .frame(width: 8, height: 8)
                    Text(viewModel.rosettaStatus.label)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }

                if viewModel.rosettaStatus == .installing {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(.white)
                }

                if viewModel.rosettaStatus == .notInstalled && viewModel.isAppleSilicon {
                    Button("Install Rosetta 2") {
                        viewModel.installRosetta()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accentColor)
                    .controlSize(.large)
                }

                if !viewModel.isAppleSilicon {
                    Text("Not required on Intel Macs.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }

    /// Game Porting Toolkit step with drag-and-drop DMG installation.
    ///
    /// Replaces the old Homebrew-based flow with a direct DMG extraction
    /// pipeline. The user downloads the official DMG from Apple's portal,
    /// then drags it onto the receptive drop zone.
    private var gptkStep: some View {
        stepCard {
            VStack(spacing: 20) {
                stepIcon("gamecontroller")

                Text("Game Porting Toolkit 3.0")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                Text("Download the official DMG from Apple Developer, then drag it here.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)

                // Status indicator
                HStack(spacing: 8) {
                    Circle()
                        .fill(viewModel.gptkState.color)
                        .frame(width: 8, height: 8)
                    Text(viewModel.gptkState.label)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }

                // Show different content based on the current GPTK state.
                switch viewModel.gptkState {
                case .installed, .success:
                    // Already installed — show confirmation.
                    gptkInstalledContent

                case .error:
                    // Error — show message and retry button.
                    gptkErrorContent

                default:
                    // Waiting, validating, mounting, copying, detaching —
                    // show the drop zone and download button.
                    gptkDropZoneContent
                }
            }
        }
    }

    /// Content shown when GPTK is already installed or just finished installing.
    private var gptkInstalledContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.green)

            Text("Wine engine is ready.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.vertical, 8)
    }

    /// Content shown when a GPTK installation error occurred.
    private var gptkErrorContent: some View {
        VStack(spacing: 12) {
            if case .error(let message) = viewModel.gptkState {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 8)
            }

            Button("Try Again") {
                viewModel.resetGPTKState()
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            .controlSize(.regular)
        }
        .padding(.vertical, 4)
    }

    /// The drag-and-drop zone, download button, and processing spinner.
    private var gptkDropZoneContent: some View {
        VStack(spacing: 16) {
            // Download button → opens Apple Developer portal.
            Button {
                viewModel.openAppleDeveloperPortal()
            } label: {
                Label("Download from Apple Developer", systemImage: "safari")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentColor)
            .controlSize(.regular)

            // Drag-and-drop zone.
            gptkDropZone

            // Processing spinner (shown during mount/copy/detach).
            if viewModel.gptkState.isProcessing {
                ProgressView()
                    .controlSize(.regular)
                    .tint(.white)
                    .padding(.top, 4)
            }
        }
    }

    /// The receptive drop zone where the user drags the Apple GPTK DMG.
    ///
    /// Uses `.onDrop(of:isTargeted:perform:)` to accept `.fileURL` types.
    /// Visual feedback is provided via border color and icon changes
    /// when a file is being hovered over the zone.
    private var gptkDropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: viewModel.isDragTargeted ? "arrow.down.circle.fill" : "arrow.down.doc")
                .font(.system(size: 28))
                .foregroundStyle(viewModel.isDragTargeted ? Color.accentColor : .white.opacity(0.4))
                .animation(.easeInOut(duration: 0.2), value: viewModel.isDragTargeted)

            Text(viewModel.gptkState.isProcessing
                ? viewModel.gptkState.label
                : "Drop GPTK .dmg here")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)

            Text("Evaluation environment for Windows games 3.0.dmg")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    viewModel.isDragTargeted ? Color.accentColor : .white.opacity(0.15),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
        )
        .onDrop(
            of: [.fileURL],
            isTargeted: $viewModel.isDragTargeted
        ) { providers in
            viewModel.handleDrop(providers: providers)
        }
        .animation(.easeInOut(duration: 0.15), value: viewModel.isDragTargeted)
        // Disable the drop zone while actively processing to prevent re-entry.
        .allowsHitTesting(!viewModel.gptkState.isProcessing)
    }

    /// CLI tools status step (legendary, steamcmd, nile).
    private var cliToolsStep: some View {
        stepCard {
            VStack(spacing: 24) {
                stepIcon("terminal")

                Text("CLI Tools")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                Text("These tools manage your game libraries from each platform.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)

                VStack(spacing: 10) {
                    dependencyRow(name: "Legendary", detail: "Epic Games", status: viewModel.legendaryStatus) {
                        viewModel.installLegendary()
                    }
                    dependencyRow(name: "SteamCMD", detail: "Steam", status: viewModel.steamcmdStatus) {
                        viewModel.installSteamCMD()
                    }
                    dependencyRow(name: "Nile", detail: "Amazon Games", status: viewModel.nileStatus) {
                        viewModel.installNile()
                    }
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    /// API key entry step.
    private var apiKeysStep: some View {
        stepCard {
            VStack(spacing: 24) {
                stepIcon("key.horizontal")

                Text("API Keys")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                Text("Optional keys for enhanced artwork and metadata.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SteamGridDB API Key")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                        SecureField("Enter your SteamGridDB key", text: $viewModel.steamGridDBKey)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Steam Web API Key")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                        SecureField("Enter your Steam Web API key", text: $viewModel.steamWebAPIKey)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))

                Text("You can add these later in Settings.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    /// Completion step with success message.
    private var completeStep: some View {
        stepCard {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 64))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .green.opacity(0.6)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Text("All Set!")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                Text("Everything is configured.\nYou're ready to start playing.")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
    }

    // MARK: - Navigation Buttons

    /// Bottom bar with Back / Continue (or Get Started) buttons.
    private var navigationButtons: some View {
        HStack {
            if viewModel.canGoBack {
                Button("Back") {
                    withAnimation {
                        viewModel.previousStep()
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.6))
                .controlSize(.large)
            }

            Spacer()

            if viewModel.currentStep == .complete {
                Button("Get Started") {
                    onComplete()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentColor)
                .controlSize(.large)
            } else {
                Button("Continue") {
                    withAnimation {
                        viewModel.nextStep()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentColor)
                .controlSize(.large)
                .disabled(!viewModel.canAdvance)
            }
        }
    }

    // MARK: - Reusable Components

    /// Wraps step content in a centered, glass-effect card.
    private func stepCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            Spacer()
            content()
                .padding(40)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            Spacer()
        }
    }

    /// Large gradient SF Symbol icon for a step header.
    private func stepIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 48))
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.accentColor, Color.accentColor.opacity(0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    /// Row showing a label-value pair.
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.white)
        }
    }

    /// Row showing a dependency's name, detail, and status indicator or an action button.
    private func dependencyRow(name: String, detail: String, status: DependencyStatus, action: (() -> Void)? = nil) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            
            if status == .installing {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                Text("Installing…")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.leading, 4)
            } else if (status == .notInstalled || (status.label.starts(with: "Error"))), let action = action {
                Button(action: action) {
                    Text(status == .notInstalled ? "Download" : "Try Again")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentColor)
                .controlSize(.small)
            } else {
                HStack(spacing: 6) {
                    Circle()
                        .fill(status.color)
                        .frame(width: 7, height: 7)
                    Text(status.label)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }
}

#Preview {
    OnboardingView(onComplete: {})
        .frame(width: 900, height: 600)
}
