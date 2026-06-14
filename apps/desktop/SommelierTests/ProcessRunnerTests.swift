import Testing
import Foundation
@testable import Sommelier

/// Tests for `ProcessRunner` subprocess execution.
@Suite("ProcessRunner Tests")
struct ProcessRunnerTests {

    @Test("Echo command captures stdout")
    func echoCapture() async throws {
        let runner = ProcessRunner()
        let result = try await runner.run(
            executablePath: "/bin/echo",
            arguments: ["hello world"]
        )
        #expect(result.exitCode == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "hello world")
    }

    @Test("Non-existent executable throws notFound")
    func notFoundThrows() async {
        let runner = ProcessRunner()
        do {
            _ = try await runner.run(
                executablePath: "/nonexistent/binary"
            )
            #expect(Bool(false), "Should have thrown")
        } catch let error as ProcessError {
            switch error {
            case .notFound:
                // Expected
                break
            default:
                #expect(Bool(false), "Expected notFound, got \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }

    @Test("Stderr is captured separately")
    func stderrCapture() async throws {
        let runner = ProcessRunner()
        let result = try await runner.run(
            executablePath: "/bin/zsh",
            arguments: ["-c", "echo error_output >&2"]
        )
        #expect(result.stderr.contains("error_output"))
    }

    @Test("Non-zero exit code is captured")
    func nonZeroExit() async throws {
        let runner = ProcessRunner()
        let result = try await runner.run(
            executablePath: "/bin/zsh",
            arguments: ["-c", "exit 42"]
        )
        #expect(result.exitCode == 42)
    }
}
