#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT

cat > "$temporary_dir/Test.swift" <<'SWIFT'
import Foundation

enum CodexPaths {
    static let sessionsDir = URL(fileURLWithPath: "/tmp")
}

@main
struct TestRunner {
    static func main() {
        let prefix = """
        {"type":"session_meta","payload":{"id":"session-1","cwd":"/tmp/project"}}
        {"type":"event_msg","payload":{"type":"user_message"}}
        """

        let completed = CodexSessionRecovery.parseContent(
            prefix + "\n{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\"}}",
            transcriptPath: "/tmp/completed.jsonl"
        )
        precondition(completed?.status == "waiting_for_input")

        let aborted = CodexSessionRecovery.parseContent(
            prefix + "\n{\"type\":\"event_msg\",\"payload\":{\"type\":\"turn_aborted\"}}",
            transcriptPath: "/tmp/aborted.jsonl"
        )
        precondition(aborted?.status == "waiting_for_input")
    }
}
SWIFT

swiftc \
    "$repo_root/VibeHUD/Services/Session/CodexSessionRecovery.swift" \
    "$temporary_dir/Test.swift" \
    -o "$temporary_dir/test-codex-recovery"
"$temporary_dir/test-codex-recovery"
