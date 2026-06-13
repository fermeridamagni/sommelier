import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Supporting Types

/// Represents each screen in the onboarding wizard, ordered sequentially.
enum OnboardingStep: Int, CaseIterable, Comparable {
    case welcome
    case systemCheck
    case rosetta
    case gptk
    case cliTools
    case apiKeys
    case complete

    static func < (lhs: OnboardingStep, rhs: OnboardingStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Human-readable title for each onboarding step.
    var title: String {
        switch self {
        case .welcome: "Welcome to Sommelier"
        case .systemCheck: "System Check"
        case .rosetta: "Rosetta 2"
        case .gptk: "Game Porting Toolkit"
        case .cliTools: "CLI Tools"
        case .apiKeys: "API Keys"
        case .complete: "All Set!"
        }
    }

    /// Descriptive subtitle explaining what this step does.
    var subtitle: String {
        switch self {
        case .welcome:
            "Your premium macOS game library manager. Let's get everything set up."
        case .systemCheck:
            "Checking your system capabilities and architecture."
        case .rosetta:
            "Rosetta 2 translates x86 applications to run on Apple Silicon."
        case .gptk:
            "Apple's Game Porting Toolkit enables Windows games on macOS."
        case .cliTools:
            "Install the CLI tools needed to manage your game libraries."
        case .apiKeys:
            "Optional API keys for enhanced artwork and metadata."
        case .complete:
            "Everything is configured. You're ready to start playing."
        }
    }

    /// SF Symbol name for the step's hero icon.
    var systemImage: String {
        switch self {
        case .welcome: "wineglass"
        case .systemCheck: "cpu"
        case .rosetta: "arrow.triangle.2.circlepath"
        case .gptk: "gamecontroller"
        case .cliTools: "terminal"
        case .apiKeys: "key.horizontal"
        case .complete: "checkmark.seal"
        }
    }
}

/// Tracks the state of the GPTK installation pipeline.
enum GPTKInstallState: Equatable {
    /// GPTK is fully installed.
    case installed

    /// Phase 1: Downloading the base Wine translation environment from GitHub.
    case downloadingBase(progress: Double)

    /// Phase 1: Extracting the base Wine environment.
    case extractingBase

    /// Phase 2: Waiting for the user to drag-and-drop the Apple DMG.
    case waitingForDMG

    /// Phase 2: Validating that the dropped file is a real GPTK DMG.
    case validating

    /// Phase 2: Mounting the DMG via `hdiutil attach -nobrowse`.
    case mounting

    /// Phase 2: Injecting D3DMetal libraries into the base Wine installation.
    case injectingMetal

    /// Phase 2: Cleaning up: detaching the DMG volume.
    case detaching

    /// Installation completed successfully.
    case success

    /// An error occurred at some stage.
    case error(String)

    /// Human-readable label for UI display.
    var label: String {
        switch self {
        case .installed: "Installed ✓"
        case .downloadingBase(let p): "Downloading base engine (\(Int(p * 100))%)…"
        case .extractingBase: "Extracting base engine…"
        case .waitingForDMG: "Waiting for DMG…"
        case .validating: "Validating file…"
        case .mounting: "Mounting disk image…"
        case .injectingMetal: "Injecting Metal libraries…"
        case .detaching: "Cleaning up…"
        case .success: "Installed successfully ✓"
        case .error(let msg): "Error: \(msg)"
        }
    }

    /// Whether the pipeline is actively working (shows a spinner).
    var isProcessing: Bool {
        switch self {
        case .downloadingBase, .extractingBase, .validating, .mounting, .injectingMetal, .detaching: true
        default: false
        }
    }

    /// Color for the status indicator dot.
    var color: Color {
        switch self {
        case .installed, .success: .green
        case .waitingForDMG: .orange
        case .downloadingBase, .extractingBase, .validating, .mounting, .injectingMetal, .detaching: .blue
        case .error: .red
        }
    }
}

// MARK: - OnboardingViewModel

/// Drives the multi-step onboarding wizard, checking and installing
/// system dependencies required to run Windows games via GPTK/Wine.
///
/// The GPTK step uses a Homebrew-free installation flow:
/// the user downloads Apple's official DMG from the Developer portal,
/// drags it onto a drop zone, and the VM silently mounts the image,
/// extracts `bin/` and `lib/` into the app's internal directory, then
/// detaches the volume. No terminal interaction is ever needed.
@MainActor
@Observable
final class OnboardingViewModel {

    // MARK: Navigation

    /// The currently displayed onboarding step.
    var currentStep: OnboardingStep = .welcome

    // MARK: System Info

    /// Whether the Mac has Apple Silicon (required for Rosetta / GPTK).
    var isAppleSilicon: Bool = false

    /// macOS version string for display.
    var macOSVersion: String = ""

    /// Mac model name for display.
    var macModel: String = ""

    // MARK: Dependency Statuses

    /// Rosetta 2 translation layer status.
    var rosettaStatus: DependencyStatus = .checking

    /// Apple Game Porting Toolkit installation state.
    var gptkState: GPTKInstallState = .waitingForDMG

    /// Legendary CLI (Epic Games) status.
    var legendaryStatus: DependencyStatus = .checking

    /// SteamCMD status.
    var steamcmdStatus: DependencyStatus = .checking

    /// Nile CLI (Amazon Games) status.
    var nileStatus: DependencyStatus = .checking

    // MARK: Installation

    /// Real-time log output displayed during installations.
    var installationLog: String = ""

    // MARK: API Keys

    /// SteamGridDB API key for fetching game artwork.
    var steamGridDBKey: String = ""

    /// Steam Web API key for library sync.
    var steamWebAPIKey: String = ""

    // MARK: GPTK DMG Processing

    /// Whether the drop zone is currently highlighted by a drag hover.
    var isDragTargeted: Bool = false

    /// The path to the mounted DMG volume (used for cleanup on error).
    private var mountedVolumePath: String?

    /// Internal GPTK directory inside the app's Application Support folder.
    ///
    /// Structure after install:
    /// ```
    /// ~/Library/Application Support/Sommelier/GPTK/
    /// ├── bin/
    /// │   └── wine64 (and other binaries)
    /// └── lib/
    ///     └── (Wine/D3DMetal libraries)
    /// ```
    static let gptkDirectory: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("Sommelier", isDirectory: true)
            .appendingPathComponent("GPTK", isDirectory: true)
    }()

    /// URL to Apple's developer downloads portal for GPTK.
    static let appleDownloadURL = URL(
        string: "https://developer.apple.com/download/all/?q=game%20porting%20toolkit"
    )!

    /// The expected volume name prefix when the official Apple DMG is mounted.
    /// Apple's GPTK 3.0 DMG mounts as "Evaluation environment for Windows games 3.0"
    /// or similar. We check for a partial match to be resilient across minor versions.
    private static let expectedVolumePrefix = "Evaluation environment"

    /// The process runner used for `hdiutil` subprocess invocations.
    private let processRunner = ProcessRunner.shared

    // MARK: - Computed Properties

    /// Whether the "Continue" button should be enabled for the current step.
    var canAdvance: Bool {
        switch currentStep {
        case .welcome:
            return true
        case .systemCheck:
            return true // informational only
        case .rosetta:
            return rosettaStatus == .installed || !isAppleSilicon
        case .gptk:
            // Allow advancing if GPTK is installed or successfully extracted,
            // but also allow skipping (it's technically optional for native games).
            return true
        case .cliTools:
            return true // optional
        case .apiKeys:
            return true // optional
        case .complete:
            return true
        }
    }

    /// Whether the "Back" button should be visible.
    var canGoBack: Bool {
        currentStep != .welcome
    }

    /// Whether GPTK is installed in the internal bodega directory.
    var isGPTKInstalled: Bool {
        let wine64 = Self.gptkDirectory
            .appendingPathComponent("bin")
            .appendingPathComponent("wine64")
        return FileManager.default.fileExists(atPath: wine64.path)
    }

    // MARK: - Methods

    /// Checks system architecture and gathers basic system information.
    func runSystemChecks() {
        // Detect Apple Silicon
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
        isAppleSilicon = machine.hasPrefix("arm64")

        // Get macOS version
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        macOSVersion = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
        macModel = machine

        appendLog("System: \(machine), macOS \(macOSVersion)")
        appendLog("Apple Silicon: \(isAppleSilicon ? "Yes" : "No")")

        // Check dependency statuses
        checkRosetta()
        checkGPTK()
        checkCLITools()
    }

    /// Attempts to install Rosetta 2 via softwareupdate.
    func installRosetta() {
        guard isAppleSilicon else { return }
        rosettaStatus = .installing
        appendLog("Installing Rosetta 2…")

        Task {
            do {
                let result = try await processRunner.run(
                    executablePath: "/usr/sbin/softwareupdate",
                    arguments: ["--install-rosetta", "--agree-to-license"]
                )
                rosettaStatus = result.exitCode == 0 ? .installed : .error("Exit code \(result.exitCode)")
                appendLog(result.exitCode == 0 ? "Rosetta 2 installed successfully." : "Rosetta 2 installation failed.")
            } catch {
                rosettaStatus = .error(error.localizedDescription)
                appendLog("Rosetta 2 installation error: \(error.localizedDescription)")
            }
        }
    }

    /// Opens Apple's Developer portal in the default browser so the user
    /// can download the official GPTK 3.0 DMG.
    func openAppleDeveloperPortal() {
        NSWorkspace.shared.open(Self.appleDownloadURL)
        appendLog("Opened Apple Developer portal for GPTK download.")
    }

    /// Advances to the next onboarding step if possible.
    func nextStep() {
        guard let nextIndex = OnboardingStep(rawValue: currentStep.rawValue + 1) else { return }
        currentStep = nextIndex
    }

    /// Returns to the previous onboarding step.
    func previousStep() {
        guard let prevIndex = OnboardingStep(rawValue: currentStep.rawValue - 1) else { return }
        currentStep = prevIndex
    }

    // MARK: - GPTK Base Download Pipeline

    /// Phase 1: Downloads the base Wine environment (wine-staging) from GitHub
    /// and extracts it to the internal GPTK directory.
    func downloadAndInstallBaseWine() {
        guard !gptkState.isProcessing else { return }

        Task {
            do {
                gptkState = .downloadingBase(progress: 0.0)
                appendLog("Fetching latest base Wine release from Gcenx/macOS_Wine_builds…")

                // Find the latest tarball URL
                let url = try await fetchLatestBaseWineURL()
                appendLog("Downloading base from: \(url.absoluteString)")

                // Download with progress
                let tempZip = try await downloadFile(from: url) { [weak self] progress in
                    Task { @MainActor in
                        self?.gptkState = .downloadingBase(progress: progress)
                    }
                }

                gptkState = .extractingBase
                appendLog("Extracting base engine…")
                try await extractBaseWine(from: tempZip)

                appendLog("Base engine installed successfully. Waiting for Metal DMG.")
                gptkState = .waitingForDMG

            } catch {
                gptkState = .error(error.localizedDescription)
                appendLog("Failed to install base engine: \(error.localizedDescription)")
            }
        }
    }

    private func fetchLatestBaseWineURL() async throws -> URL {
        let apiURL = URL(string: "https://api.github.com/repos/Gcenx/macOS_Wine_builds/releases/latest")!
        let (data, response) = try await URLSession.shared.data(from: apiURL)
        guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else {
            throw GPTKError.networkError("Failed to fetch GitHub API.")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = json["assets"] as? [[String: Any]] else {
            throw GPTKError.networkError("Invalid JSON from GitHub API.")
        }

        // Prefer wine-staging over wine-devel
        let tarballURLs = assets.compactMap { $0["browser_download_url"] as? String }
            .filter { $0.hasSuffix(".tar.xz") }
        
        let targetURLStr = tarballURLs.first { $0.contains("wine-staging") } ?? tarballURLs.first
        guard let targetURLStr, let url = URL(string: targetURLStr) else {
            throw GPTKError.networkError("No suitable tarball found in latest release.")
        }

        return url
    }

    private func downloadFile(from url: URL, progressHandler: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tar.xz")
        
        // We use curl because it's highly optimized, robust, and handles redirects automatically.
        // We parse its stderr progress output to update the UI.
        let result = try await processRunner.run(
            executablePath: "/usr/bin/curl",
            arguments: ["-L", "-#", url.absoluteString, "-o", tempURL.path],
            environment: nil,
            workingDirectory: nil,
            onStdout: nil,
            onStderr: { output in
                // curl -# outputs like "###       20.0%"
                let pattern = "([0-9]+\\.[0-9]+)%"
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)) {
                    if let range = Range(match.range(at: 1), in: output),
                       let percent = Double(String(output[range])) {
                        progressHandler(percent / 100.0)
                    }
                }
            }
        )
        
        guard result.exitCode == 0 else {
            throw GPTKError.networkError("Failed to download base Wine: \(result.stderr)")
        }
        
        return tempURL
    }

    private func extractBaseWine(from archiveURL: URL) async throws {
        let fm = FileManager.default
        let tempExtractDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempExtractDir, withIntermediateDirectories: true)
        
        defer {
            try? fm.removeItem(at: archiveURL)
            try? fm.removeItem(at: tempExtractDir)
        }

        // Use standard tar to extract
        let result = try await processRunner.run(
            executablePath: "/usr/bin/tar",
            arguments: ["-xf", archiveURL.path, "-C", tempExtractDir.path]
        )

        guard result.exitCode == 0 else {
            throw GPTKError.extractionFailed(result.stderr)
        }

        // The tarball extracts to "Wine Staging.app/Contents/Resources/wine"
        // Let's locate the 'wine' directory dynamically inside the temp dir.
        let enumerator = fm.enumerator(at: tempExtractDir, includingPropertiesForKeys: [.isDirectoryKey])
        var wineDir: URL?
        
        while let url = enumerator?.nextObject() as? URL {
            if url.lastPathComponent == "wine", url.hasDirectoryPath {
                let binDir = url.appendingPathComponent("bin")
                if fm.fileExists(atPath: binDir.path) {
                    wineDir = url
                    break
                }
            }
        }

        guard let sourceWineDir = wineDir else {
            throw GPTKError.extractionFailed("Could not find 'wine' directory in the extracted archive.")
        }

        let destinationURL = Self.gptkDirectory
        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }
        
        try fm.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: sourceWineDir, to: destinationURL)
    }

    // MARK: - GPTK DMG Pipeline

    /// Phase 2: Handles a file URL dropped onto the GPTK drag-and-drop zone.
    ///
    /// Orchestrates the full pipeline: validate → mount → copy → detach.
    /// All state changes are published to `gptkState` so the view updates
    /// in real time. On any failure, the DMG is detached (if mounted) and
    /// the state transitions to `.error(...)`.
    ///
    /// - Parameter url: The local file URL of the dropped DMG.
    func handleDroppedDMG(url: URL) {
        // Guard against re-entry while already processing.
        guard !gptkState.isProcessing else { return }

        Task {
            do {
                // Stage 1: Validate the file.
                gptkState = .validating
                appendLog("Validating dropped file: \(url.lastPathComponent)")
                try validateDMG(at: url)

                // Stage 2: Mount the DMG silently.
                gptkState = .mounting
                appendLog("Mounting disk image…")
                let volumePath = try await mountDMG(at: url)
                mountedVolumePath = volumePath
                appendLog("Mounted at: \(volumePath)")

                // Stage 3: Validate it's actually Apple's GPTK DMG.
                try validateGPTKVolume(at: volumePath)

                // Stage 4: Inject redist/lib into our base Wine installation.
                gptkState = .injectingMetal
                appendLog("Injecting Metal libraries into base Wine engine…")
                try await injectMetalLibraries(from: volumePath)
                appendLog("Injection complete.")

                // Stage 5: Detach the mounted volume.
                gptkState = .detaching
                appendLog("Detaching disk image…")
                try await detachVolume(at: volumePath)
                mountedVolumePath = nil
                appendLog("Disk image detached.")

                // Done!
                gptkState = .success
                appendLog("GPTK 3.0 installed successfully ✓")

            } catch {
                gptkState = .error(error.localizedDescription)
                appendLog("GPTK installation failed: \(error.localizedDescription)")

                // Cleanup: always try to detach if we mounted something.
                if let mountPath = mountedVolumePath {
                    try? await detachVolume(at: mountPath)
                    mountedVolumePath = nil
                    appendLog("Cleaned up mounted volume after error.")
                }
            }
        }
    }

    /// Handles `NSItemProvider` objects from a SwiftUI `.onDrop` modifier.
    ///
    /// Extracts the file URL from the provider and delegates to `handleDroppedDMG(url:)`.
    /// Returns `true` if the drop was accepted for processing.
    ///
    /// - Parameter providers: The item providers from the drop event.
    /// - Returns: `true` if a valid file URL was extracted and processing began.
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        // Try to load as a file URL (the expected type for drag-and-drop from Finder).
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { [weak self] data, _ in
                guard let data = data as? Data,
                      let urlString = String(data: data, encoding: .utf8),
                      let url = URL(string: urlString)
                else { return }

                Task { @MainActor in
                    self?.handleDroppedDMG(url: url)
                }
            }
            return true
        }

        return false
    }

    /// Resets the GPTK state to allow the user to retry after an error.
    func resetGPTKState() {
        if isGPTKBaseInstalled {
            gptkState = .waitingForDMG
        } else {
            downloadAndInstallBaseWine()
        }
        appendLog("Reset GPTK installation state — ready for retry.")
    }
    
    /// Checks if the base wine engine is already installed.
    private var isGPTKBaseInstalled: Bool {
        let wine64 = Self.gptkDirectory
            .appendingPathComponent("bin")
            .appendingPathComponent("wine64")
        return FileManager.default.fileExists(atPath: wine64.path)
    }

    // MARK: - Private: DMG Pipeline Stages

    /// Validates that the file at the given URL is a `.dmg` disk image.
    ///
    /// - Parameter url: The file URL to validate.
    /// - Throws: A descriptive error if the file isn't a DMG or doesn't exist.
    private func validateDMG(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw GPTKError.fileNotFound(url.lastPathComponent)
        }

        guard url.pathExtension.lowercased() == "dmg" else {
            throw GPTKError.invalidFileType(url.pathExtension)
        }
    }

    /// Validates that the mounted volume actually contains Apple's GPTK content.
    ///
    /// Checks for the existence of `bin/wine64` and `lib/` inside the volume,
    /// and that the volume name matches the expected Apple naming pattern.
    ///
    /// - Parameter volumePath: The `/Volumes/...` path of the mounted DMG.
    /// - Throws: `GPTKError.invalidDMGContent` if the volume doesn't contain GPTK files.
    private func validateGPTKVolume(at volumePath: String) throws {
        let volumeURL = URL(fileURLWithPath: volumePath)
        let fm = FileManager.default

        // Check the volume name matches Apple's naming convention.
        let volumeName = volumeURL.lastPathComponent
        guard volumeName.hasPrefix(Self.expectedVolumePrefix) else {
            throw GPTKError.invalidDMGContent(
                "This doesn't appear to be Apple's GPTK DMG. "
                + "Expected volume name starting with \"\(Self.expectedVolumePrefix)\", "
                + "got \"\(volumeName)\"."
            )
        }

        // Verify critical directory exists inside the volume.
        let libPath = volumeURL.appendingPathComponent("redist").appendingPathComponent("lib").path
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: libPath, isDirectory: &isDir), isDir.boolValue else {
            throw GPTKError.invalidDMGContent(
                "Missing required directory 'redist/lib' in the mounted volume. "
                + "Make sure you downloaded the correct GPTK 3.0 DMG from Apple."
            )
        }
    }

    /// Mounts a DMG disk image silently using `hdiutil attach`.
    ///
    /// The `-nobrowse` flag prevents Finder from opening a window for the
    /// mounted volume. The `-plist` flag returns machine-readable output
    /// so we can reliably extract the mount point.
    ///
    /// - Parameter url: The local file URL of the DMG.
    /// - Returns: The filesystem path where the volume was mounted (e.g. `/Volumes/...`).
    /// - Throws: `GPTKError.mountFailed` if `hdiutil` returns non-zero or
    ///   we can't parse the mount point from its output.
    private func mountDMG(at url: URL) async throws -> String {
        // We use `sh -c "yes | ..."` to automatically accept the Software License Agreement
        // that Apple includes in the GPTK 3.0 DMG, otherwise hdiutil will hang indefinitely.
        let result = try await processRunner.run(
            executablePath: "/bin/sh",
            arguments: ["-c", "yes | /usr/bin/hdiutil attach -nobrowse -plist '\(url.path)'"]
        )

        guard result.exitCode == 0 else {
            throw GPTKError.mountFailed(
                result.stderr.isEmpty
                    ? "hdiutil returned exit code \(result.exitCode)"
                    : result.stderr
            )
        }

        // Parse the plist output to find the mount point.
        // hdiutil -plist returns an XML property list with a "system-entities"
        // array, each entry having "mount-point" for mounted partitions.
        // Wait, since we piped `yes`, stdout might contain `y\ny\ny\n` mixed with the plist!
        // Actually, `yes` pipes to stdin, hdiutil writes the plist to stdout.
        guard let plistData = result.stdout.data(using: .utf8) else {
            throw GPTKError.mountFailed("Could not read hdiutil output.")
        }

        guard let plist = try? PropertyListSerialization.propertyList(
            from: plistData,
            options: [],
            format: nil
        ) as? [String: Any] else {
            // Fallback: If `yes` polluted stdout, try to extract just the XML part
            if let xmlStart = result.stdout.range(of: "<?xml"),
               let xmlData = String(result.stdout[xmlStart.lowerBound...]).data(using: .utf8),
               let parsed = try? PropertyListSerialization.propertyList(from: xmlData, options: [], format: nil) as? [String: Any] {
                // Successfully extracted XML from polluted stdout
                let entities = parsed["system-entities"] as? [[String: Any]] ?? []
                for entity in entities {
                    if let mountPoint = entity["mount-point"] as? String, !mountPoint.isEmpty {
                        return mountPoint
                    }
                }
            }
            
            throw GPTKError.mountFailed("Could not parse hdiutil plist output.")
        }

        guard let entities = plist["system-entities"] as? [[String: Any]] else {
            throw GPTKError.mountFailed("No system-entities found in hdiutil output.")
        }

        // Find the entity with a mount-point (skip EFI/Apple_Free partitions).
        for entity in entities {
            if let mountPoint = entity["mount-point"] as? String, !mountPoint.isEmpty {
                return mountPoint
            }
        }

        throw GPTKError.mountFailed("No mount point found in hdiutil output.")
    }

    /// Injects the `redist/lib/` contents from the DMG into our internal
    /// `Sommelier/GPTK/lib/` directory, following Apple's patching instructions.
    ///
    /// - Parameter volumePath: The mounted volume path (e.g. `/Volumes/Evaluation...`).
    /// - Throws: File system errors.
    private func injectMetalLibraries(from volumePath: String) async throws {
        let fm = FileManager.default
        let redistLibURL = URL(fileURLWithPath: volumePath)
            .appendingPathComponent("redist")
            .appendingPathComponent("lib")
        
        let destinationLibURL = Self.gptkDirectory.appendingPathComponent("lib")

        guard fm.fileExists(atPath: destinationLibURL.path) else {
            throw GPTKError.copyFailed("Base Wine installation is missing the 'lib' directory.")
        }

        // Apple's instructions:
        // mv external external.old; mv wine wine.old
        // ditto redist/lib .

        // 1. Move old directories out of the way
        for dirName in ["external", "wine"] {
            let targetDir = destinationLibURL.appendingPathComponent(dirName)
            let oldDir = destinationLibURL.appendingPathComponent("\(dirName).old")
            
            if fm.fileExists(atPath: targetDir.path) {
                if fm.fileExists(atPath: oldDir.path) {
                    try fm.removeItem(at: oldDir)
                }
                try fm.moveItem(at: targetDir, to: oldDir)
            }
        }

        // 2. Perform a "ditto" style copy. We use a Process call to `/usr/bin/ditto`
        // because it handles directory merging flawlessly compared to FileManager.copyItem.
        let result = try await processRunner.run(
            executablePath: "/usr/bin/ditto",
            arguments: [redistLibURL.path, destinationLibURL.path]
        )

        guard result.exitCode == 0 else {
            throw GPTKError.copyFailed("Failed to ditto libraries: \(result.stderr)")
        }

        // Verify injection succeeded. D3DMetal.framework is inside `external/`
        let d3dMetalPath = destinationLibURL
            .appendingPathComponent("external")
            .appendingPathComponent("D3DMetal.framework")
            .path
        
        guard fm.fileExists(atPath: d3dMetalPath) else {
            throw GPTKError.copyFailed("D3DMetal.framework not found after injection.")
        }
    }

    /// Detaches (ejects) a mounted DMG volume using `hdiutil detach`.
    ///
    /// Called both on success and in error cleanup. Uses `-force` to ensure
    /// the volume is unmounted even if files are open.
    ///
    /// - Parameter volumePath: The mount point path to detach.
    /// - Throws: `GPTKError.detachFailed` if `hdiutil` reports an error.
    private func detachVolume(at volumePath: String) async throws {
        let result = try await processRunner.run(
            executablePath: "/usr/bin/hdiutil",
            arguments: ["detach", volumePath, "-force"]
        )

        // We intentionally don't throw on non-zero exit during cleanup —
        // the volume might already be detached if the mount partially failed.
        if result.exitCode != 0 {
            appendLog("Warning: hdiutil detach returned code \(result.exitCode): \(result.stderr)")
        }
    }

    // MARK: - Private: Dependency Checks

    /// Checks whether Rosetta 2 is installed on Apple Silicon.
    private func checkRosetta() {
        if !isAppleSilicon {
            rosettaStatus = .notInstalled
            appendLog("Rosetta 2: Not applicable (Intel Mac)")
            return
        }

        // Check for Rosetta by looking for the translation binary
        let rosettaPath = "/Library/Apple/usr/share/rosetta/rosetta"
        if FileManager.default.fileExists(atPath: rosettaPath) {
            rosettaStatus = .installed
            appendLog("Rosetta 2: Installed ✓")
        } else {
            rosettaStatus = .notInstalled
            appendLog("Rosetta 2: Not installed")
        }
    }

    /// Checks whether GPTK is installed in the internal Sommelier directory.
    ///
    /// No longer checks Homebrew paths — the app manages its own GPTK copy
    /// extracted from Apple's official DMG.
    private func checkGPTK() {
        if isGPTKInstalled {
            // Check if it's just the base or fully injected.
            let d3dMetalPath = Self.gptkDirectory
                .appendingPathComponent("lib")
                .appendingPathComponent("D3DMetal.framework")
                .path
            
            if FileManager.default.fileExists(atPath: d3dMetalPath) {
                gptkState = .installed
                appendLog("Game Porting Toolkit: Installed ✓ (fully injected)")
            } else {
                gptkState = .waitingForDMG
                appendLog("Game Porting Toolkit: Base installed — awaiting Metal DMG")
            }
        } else {
            // Trigger phase 1 automatically.
            appendLog("Game Porting Toolkit: Base not found — starting download.")
            downloadAndInstallBaseWine()
        }
    }

    /// Checks availability of CLI tools: legendary, steamcmd, nile.
    private func checkCLITools() {
        Task { @MainActor in
            let sys = SystemInfoService.shared
            legendaryStatus = await sys.checkDependency("legendary")
            steamcmdStatus = await sys.checkDependency("steamcmd")
            nileStatus = await sys.checkDependency("nile")
            
            appendLog("Legendary: \(legendaryStatus.label)")
            appendLog("SteamCMD: \(steamcmdStatus.label)")
            appendLog("Nile: \(nileStatus.label)")
        }
    }

    // MARK: - CLI Tool Installation

    func installLegendary() {
        guard legendaryStatus != .installing && legendaryStatus != .installed else { return }
        legendaryStatus = .installing
        appendLog("Downloading Legendary (Epic Games)...")
        Task {
            do {
                try await CLIDownloadManager.shared.downloadLegendary { progress in
                    // In a more complex app, we might want to show this progress percentage
                }
                await MainActor.run {
                    legendaryStatus = .installed
                    appendLog("Legendary installed successfully ✓")
                }
            } catch {
                await MainActor.run {
                    legendaryStatus = .error(error.localizedDescription)
                    appendLog("Legendary installation failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func installSteamCMD() {
        guard steamcmdStatus != .installing && steamcmdStatus != .installed else { return }
        steamcmdStatus = .installing
        appendLog("Downloading SteamCMD...")
        Task {
            do {
                try await CLIDownloadManager.shared.downloadSteamCMD { progress in }
                await MainActor.run {
                    steamcmdStatus = .installed
                    appendLog("SteamCMD installed successfully ✓")
                }
            } catch {
                await MainActor.run {
                    steamcmdStatus = .error(error.localizedDescription)
                    appendLog("SteamCMD installation failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func installNile() {
        guard nileStatus != .installing && nileStatus != .installed else { return }
        nileStatus = .installing
        appendLog("Downloading Nile (Amazon Games)...")
        Task {
            do {
                try await CLIDownloadManager.shared.downloadNile { progress in }
                await MainActor.run {
                    nileStatus = .installed
                    appendLog("Nile installed successfully ✓")
                }
            } catch {
                await MainActor.run {
                    nileStatus = .error(error.localizedDescription)
                    appendLog("Nile installation failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Appends a timestamped line to the installation log.
    private func appendLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(
            from: Date(),
            dateStyle: .none,
            timeStyle: .medium
        )
        installationLog += "[\(timestamp)] \(message)\n"
    }
}

// MARK: - GPTKError

/// Errors specific to the GPTK DMG installation pipeline.
///
/// Each case maps to a distinct failure mode in the mount → validate → copy
/// → detach flow, with user-facing descriptions that help diagnose the issue.
enum GPTKError: Error, LocalizedError {
    /// Failed to download or fetch API data.
    case networkError(String)

    /// Failed to extract tarball.
    case extractionFailed(String)

    /// The dropped file doesn't exist at the expected path.
    case fileNotFound(String)

    /// The dropped file isn't a `.dmg` disk image.
    case invalidFileType(String)

    /// The DMG mounted but doesn't contain the expected GPTK content.
    case invalidDMGContent(String)

    /// `hdiutil attach` failed to mount the DMG.
    case mountFailed(String)

    /// File copy from the mounted volume to the internal directory failed.
    case copyFailed(String)

    /// `hdiutil detach` failed to unmount the volume.
    case detachFailed(String)

    var errorDescription: String? {
        switch self {
        case .networkError(let detail):
            "Network error: \(detail)"
        case .extractionFailed(let detail):
            "Failed to extract base Wine package: \(detail)"
        case .fileNotFound(let name):
            "File not found: \"\(name)\". Make sure the DMG is still in your Downloads folder."
        case .invalidFileType(let ext):
            "Expected a .dmg file, but received a .\(ext) file. Please drag the GPTK disk image."
        case .invalidDMGContent(let detail):
            detail
        case .mountFailed(let detail):
            "Failed to mount the disk image: \(detail)"
        case .copyFailed(let detail):
            "Failed to copy GPTK files: \(detail)"
        case .detachFailed(let detail):
            "Failed to eject the disk image: \(detail)"
        }
    }
}
