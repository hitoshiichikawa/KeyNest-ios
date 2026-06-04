import Foundation

/// Wipes the vault and inserts a small, realistic credential set for App Store
/// screenshots. Invoked only when the host app passes `--seed-demo` on the
/// command line or sets `KN_SEED_DEMO=1` — never reachable from a normal launch.
public enum DemoSeeder {
    public static func isRequested(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        if arguments.contains("--seed-demo") { return true }
        if environment["KN_SEED_DEMO"] == "1" { return true }
        return false
    }

    public static func seed(services: ServiceLocator) async throws {
        try await services.credentialRepository.clearAll()

        let entries: [(label: String, domain: String, user: String, pass: String, fields: [CustomField])] = [
            ("GitHub",     "github.com",        "octocat",            "p@ssw0rd-Github!2026",   []),
            ("Apple ID",   "appleid.apple.com", "hitoshi@example.com","S3cure-Apple#2026",      []),
            ("Amazon",     "amazon.com",        "hitoshi.i",          "Sh0pping*Amazon!42",     []),
            ("Slack",      "slack.com",         "hitoshi",            "Slack&Team#2026",        [CustomField(fieldKey: "Workspace", value: "keynest-dev")]),
            ("Netflix",    "netflix.com",       "hitoshi.family",     "Stream*Movies!2026",     [CustomField(fieldKey: "Profile", value: "Hitoshi")]),
            ("Bank Demo",  "demo-bank.example", "100-2034-5678",      "Bank!Login#2026",        [CustomField(fieldKey: "Branch", value: "001"), CustomField(fieldKey: "PIN hint", value: "year+month")])
        ]

        for entry in entries {
            _ = try await services.saveCredential(
                NewCredentialInput(
                    serviceIdentifier: entry.domain,
                    username: entry.user,
                    password: Array(entry.pass.utf8),
                    label: entry.label,
                    customFields: entry.fields
                )
            )
        }
    }
}
