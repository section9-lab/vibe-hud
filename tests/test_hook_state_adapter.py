import importlib.util
import io
import pathlib
import sys
import unittest
from types import SimpleNamespace
from unittest import mock


SCRIPT = pathlib.Path(__file__).parents[1] / "VibeHUD/Resources/vibe-hud-state.py"


def load_adapter():
    spec = importlib.util.spec_from_file_location("vibe_hud_state", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class HookStateAdapterTests(unittest.TestCase):
    def run_adapter(self, payload, *arguments):
        adapter = load_adapter()
        sent = []

        with mock.patch.object(sys, "argv", [str(SCRIPT), *arguments]), \
             mock.patch.object(sys, "stdin", io.StringIO(__import__("json").dumps(payload))), \
             mock.patch.object(adapter, "send_event", side_effect=lambda state: sent.append(state)), \
             mock.patch.object(adapter, "get_tty", return_value=None), \
             mock.patch.object(adapter, "find_agent_pid", return_value=123), \
             mock.patch.object(adapter, "find_terminal_pid", return_value=None):
            adapter.main()

        self.assertEqual(len(sent), 1)
        return sent[0]

    def test_copilot_camel_case_payload_uses_explicit_event(self):
        state = self.run_adapter(
            {
                "sessionId": "copilot-session",
                "cwd": "/tmp/project",
                "prompt": "Fix the bug",
            },
            "--source", "copilot",
            "--event", "userPromptSubmitted",
        )

        self.assertEqual(state["session_id"], "copilot-session")
        self.assertEqual(state["event"], "UserPromptSubmit")
        self.assertEqual(state["status"], "processing")
        self.assertEqual(state["source"], "copilot")

    def test_copilot_tool_payload_preserves_camel_case_fields(self):
        state = self.run_adapter(
            {
                "sessionId": "copilot-session",
                "cwd": "/tmp/project",
                "toolName": "shell",
                "toolArgs": {"command": "pwd"},
                "toolCallId": "call-1",
            },
            "--source", "copilot",
            "--event", "preToolUse",
        )

        self.assertEqual(state["event"], "PreToolUse")
        self.assertEqual(state["tool"], "shell")
        self.assertEqual(state["tool_input"], {"command": "pwd"})
        self.assertEqual(state["tool_use_id"], "call-1")

    def test_copilot_serialized_tool_arguments_are_decoded_for_swift(self):
        for event in ("preToolUse", "postToolUse"):
            with self.subTest(event=event):
                state = self.run_adapter(
                    {
                        "sessionId": "copilot-session",
                        "toolName": "view",
                        "toolArgs": '{"path":"/tmp/probe.txt"}',
                    },
                    "--source", "copilot", "--event", event,
                )

                self.assertEqual(state["tool_input"], {"path": "/tmp/probe.txt"})

    def test_invalid_tool_arguments_remain_a_json_object(self):
        for arguments in ("invalid json", "[]", "null"):
            with self.subTest(arguments=arguments):
                state = self.run_adapter(
                    {"sessionId": "copilot-session", "toolName": "view", "toolArgs": arguments},
                    "--source", "copilot", "--event", "preToolUse",
                )

                self.assertEqual(state["tool_input"], {})

    def test_cursor_compaction_event_enters_compacting_state(self):
        state = self.run_adapter(
            {"conversation_id": "cursor-session", "cwd": "/tmp/project"},
            "--source", "cursor",
            "--event", "preCompact",
        )

        self.assertEqual(state["event"], "PreCompact")
        self.assertEqual(state["status"], "compacting")

    def test_cursor_session_end_closes_session(self):
        state = self.run_adapter(
            {"conversation_id": "cursor-session", "cwd": "/tmp/project"},
            "--source", "cursor",
            "--event", "sessionEnd",
        )

        self.assertEqual(state["event"], "SessionEnd")
        self.assertEqual(state["status"], "ended")

    def test_claude_agent_needs_input_notification_waits_for_user(self):
        state = self.run_adapter(
            {
                "session_id": "claude-session",
                "cwd": "/tmp/project",
                "hook_event_name": "Notification",
                "notification_type": "agent_needs_input",
            },
            "--source", "claude",
        )

        self.assertEqual(state["status"], "waiting_for_input")

    def test_claude_elicitation_waits_for_user(self):
        state = self.run_adapter(
            {
                "session_id": "claude-session",
                "cwd": "/tmp/project",
                "hook_event_name": "Elicitation",
            },
            "--source", "claude",
        )

        self.assertEqual(state["status"], "waiting_for_input")

    def test_vscode_agent_is_namespaced_from_copilot_cli(self):
        state = self.run_adapter(
            {"session_id": "shared-session", "cwd": "/tmp/project"},
            "--source", "vscodeagent",
            "--event", "UserPromptSubmit",
        )

        self.assertEqual(state["source"], "vscodeagent")
        self.assertEqual(state["session_id"], "vscodeagent-shared-session")
        self.assertEqual(state["status"], "processing")

    def test_string_source_timestamp_is_normalized_for_swift_decoder(self):
        state = self.run_adapter(
            {
                "session_id": "claude-session",
                "cwd": "/tmp/project",
                "hook_event_name": "SessionStart",
                "timestamp": "2026-08-15T01:00:00Z",
            },
            "--source", "claude",
        )

        self.assertIsInstance(state["event_timestamp"], float)

    def test_copilot_millisecond_timestamps_are_converted_to_seconds(self):
        for timestamp in (1788434716013, 1788434716013.0):
            with self.subTest(timestamp=timestamp):
                state = self.run_adapter(
                    {"sessionId": "copilot-session", "timestamp": timestamp},
                    "--source", "copilot", "--event", "postToolUse",
                )

                self.assertEqual(state["event_timestamp"], 1788434716.013)

    def test_second_timestamps_keep_their_precision(self):
        state = self.run_adapter(
            {"session_id": "claude-session", "event_timestamp": 1788434716.013},
            "--source", "claude", "--event", "Stop",
        )

        self.assertEqual(state["event_timestamp"], 1788434716.013)

    def test_copilot_error_is_reported_as_failure(self):
        state = self.run_adapter(
            {
                "sessionId": "copilot-session",
                "cwd": "/tmp/project",
                "message": "Request failed",
            },
            "--source", "copilot",
            "--event", "errorOccurred",
        )

        self.assertEqual(state["event"], "StopFailure")
        self.assertEqual(state["status"], "failed")
        self.assertEqual(state["message"], "Request failed")

    def test_copilot_notification_camel_case_waits_for_user(self):
        state = self.run_adapter(
            {
                "sessionId": "copilot-session",
                "cwd": "/tmp/project",
                "notificationType": "agent_needs_input",
                "message": "Choose an option",
            },
            "--source", "copilot",
            "--event", "notification",
        )

        self.assertEqual(state["status"], "waiting_for_input")
        self.assertEqual(state["notification_type"], "agent_needs_input")

    def test_cursor_stop_error_is_reported_as_failure(self):
        state = self.run_adapter(
            {
                "conversation_id": "cursor-session",
                "cwd": "/tmp/project",
                "status": "error",
                "error": "Model request failed",
            },
            "--source", "cursor",
            "--event", "stop",
        )

        self.assertEqual(state["status"], "failed")
        self.assertEqual(state["message"], "Model request failed")

    def test_agent_pid_walks_past_transient_hook_shell(self):
        adapter = load_adapter()
        process_rows = [
            SimpleNamespace(stdout="41 /bin/sh -c python3 vibe-hud-state.py\n"),
            SimpleNamespace(stdout="1 /Applications/Codex.app/Contents/MacOS/codex\n"),
        ]

        with mock.patch.object(adapter.subprocess, "run", side_effect=process_rows):
            self.assertEqual(adapter.find_agent_pid("codex", 42), 41)

    def test_shared_copilot_hook_finds_vs_code_process(self):
        adapter = load_adapter()
        process_rows = [
            SimpleNamespace(stdout="41 /bin/sh -c python3 vibe-hud-state.py\n"),
            SimpleNamespace(stdout="1 /Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper (Plugin).app/Contents/MacOS/Code Helper (Plugin)\n"),
        ]

        with mock.patch.object(adapter.subprocess, "run", side_effect=process_rows):
            self.assertEqual(adapter.find_agent_pid("copilot", 42), 41)

    def test_workbuddy_hook_preserves_transcript_and_source(self):
        state = self.run_adapter(
            {
                "session_id": "workbuddy-session",
                "cwd": "/tmp/project",
                "transcript_path": "/Users/test/.workbuddy/projects/project/workbuddy-session.jsonl",
                "hook_event_name": "PreToolUse",
                "tool_name": "Bash",
                "tool_input": {"command": "pwd"},
            },
            "--source", "workbuddy",
        )

        self.assertEqual(state["source"], "workbuddy")
        self.assertEqual(state["status"], "running_tool")
        self.assertEqual(state["transcript_path"], "/Users/test/.workbuddy/projects/project/workbuddy-session.jsonl")


if __name__ == "__main__":
    unittest.main()
