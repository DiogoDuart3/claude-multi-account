import Foundation
import AppKit

enum LoginRunnerError: Error {
    case binaryNotFound
    case launchFailed(String)
    case urlNotFound
    case failed(Int32)
}

class LoginRunner {
    static let shared = LoginRunner()
    
    private var process: Process?
    private var outputPipe: Pipe?
    
    func findClaudePath() -> String? {
        // Mimic shell behavior: Try 'which claude' first
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", "claude"]
        process.standardOutput = pipe
        
        try? process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            return path
        }

        // Fallback to common locations
        let possiblePaths = [
            "/opt/homebrew/bin/claude",
            "\(NSHomeDirectory())/.npm-global/bin/claude",
            "\(NSHomeDirectory())/.local/bin/claude",
            "/usr/local/bin/claude",
            "/usr/bin/claude"
        ]
        
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        return nil
    }
    
    func startLogin(onOutput: @escaping (String) -> Void) async throws {
        guard let claudePath = findClaudePath() else {
            throw LoginRunnerError.binaryNotFound
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["login"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        // Setup environment to encourage non-interactive simple output if supported
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color" // Some CLIs behave better if they think it's a TTY
        // env["NO_COLOR"] = "1" // Let's keep color for now, we can strip regex if needed, often URL changes with NO_COLOR
        process.environment = env
        
        self.process = process
        self.outputPipe = pipe
        
        return try await withCheckedThrowingContinuation { continuation in
            let outputHandle = pipe.fileHandleForReading
            var capturedOutput = ""
            var browserOpened = false
            
            outputHandle.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                
                capturedOutput += text
                onOutput(text) // For debugging log
                
                // Check for URL
                if !browserOpened {
                    if let url = self.extractUrl(from: text) {
                        print("Found Login URL: \(url)")
                        NSWorkspace.shared.open(url)
                        browserOpened = true
                    }
                }
                
                // Check for success
                if text.contains("Successfully logged in") || text.contains("Login successful") {
                    // Success!
                    // We can wait a moment and then terminate, or let it finish
                }
            }
            
            process.terminationHandler = { proc in
                outputHandle.readabilityHandler = nil
                
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    // If it was terminated by us (cancel), it might be 15 or 9
                    // But if it failed cleanly with non-zero
                    continuation.resume(throwing: LoginRunnerError.failed(proc.terminationStatus))
                }
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: LoginRunnerError.launchFailed(error.localizedDescription))
            }
        }
    }
    
    func cancel() {
        process?.terminate()
        process = nil
        outputPipe = nil
    }
    
    private func extractUrl(from text: String) -> URL? {
        // Regex to find https URL
        // Claude CLI usually outputs: "Visit the following URL to log in: https://..."
        
        // Clean ANSI codes first?
        let method1 = text // simplistic
        
        let types: NSTextCheckingResult.CheckingType = .link
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return nil }
        
        let matches = detector.matches(in: method1, options: [], range: NSRange(location: 0, length: method1.utf16.count))
        
        // Look for api.anthropic.com or similar
        for match in matches {
            if let url = match.url, url.absoluteString.contains("anthropic.com") {
                return url
            }
        }
        
        return nil
    }
}
