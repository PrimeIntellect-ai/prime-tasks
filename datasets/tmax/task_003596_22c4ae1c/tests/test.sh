#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import pytest

SCRIPT_PATH = "/home/user/log_processor.sh"
ORIGINAL_PATH = "/home/user/log_processor.sh.orig"
PATCH_PATH = "/home/user/processor.patch"
PAYLOAD_PATH = "/home/user/leaked_payload.txt"
EXPECTED_PAYLOAD = "[SESSION_4815] {{DATA_FRAG_992_UNMATCHED"

ORIGINAL_SCRIPT = '''#!/bin/bash
declare -a STATE_HISTORY

parse_message() {
    local msg="$1"
    if [[ "$msg" == *"{{"* ]]; then
        if [[ "$msg" == *"}}"* ]]; then
            # Valid message, extract data
            extracted="${msg#*\\{\\{}"
            extracted="${extracted%%\\}\\}*}"
            echo "Processed: $extracted"
        else
            # BUG: Infinite recursion on malformed input
            STATE_HISTORY+=("$msg")
            parse_message "$msg"
        fi
    else
        echo "Ignored: $msg"
    fi
}

# Entry point
parse_message "$1"
'''


def run_script(message, timeout=1):
    try:
        return subprocess.run(
            ["bash", SCRIPT_PATH, message],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Fail: log_processor.sh hangs on malformed input")


def apply_unified_diff(original, patch_text):
    """Apply a single-file unified diff and return the resulting text."""
    patch_lines = patch_text.splitlines(keepends=True)
    old_lines = original.splitlines(keepends=True)

    header = None
    for i in range(len(patch_lines) - 1):
        if patch_lines[i].startswith("--- ") and patch_lines[i + 1].startswith("+++ "):
            header = i
            break
    assert header is not None, "Fail: patch lacks unified diff file headers"

    i = header + 2
    old_pos = 0
    result = []
    saw_hunk = False
    hunk_re = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")

    while i < len(patch_lines):
        line = patch_lines[i]
        if not line.startswith("@@ "):
            assert not line.strip(), f"Fail: unexpected patch content: {line!r}"
            i += 1
            continue

        match = hunk_re.match(line)
        assert match, f"Fail: malformed unified diff hunk header: {line!r}"
        saw_hunk = True
        old_start = int(match.group(1))
        expected_old_count = int(match.group(2) or 1)
        expected_new_count = int(match.group(4) or 1)
        target = 0 if old_start == 0 else old_start - 1
        assert target >= old_pos, "Fail: overlapping or out-of-order patch hunks"
        result.extend(old_lines[old_pos:target])
        old_pos = target
        i += 1
        old_count = 0
        new_count = 0

        while i < len(patch_lines) and not patch_lines[i].startswith("@@ "):
            body = patch_lines[i]
            if body.startswith("\\ No newline at end of file"):
                i += 1
                continue
            assert body and body[0] in " +-", f"Fail: invalid unified diff line: {body!r}"
            prefix, text = body[0], body[1:]
            if prefix in " -":
                assert old_pos < len(old_lines), "Fail: patch reads past original file"
                assert old_lines[old_pos] == text, "Fail: patch does not apply to the original script"
                old_pos += 1
                old_count += 1
            if prefix in " +":
                result.append(text)
                new_count += 1
            i += 1

        assert old_count == expected_old_count, "Fail: incorrect old-line count in patch hunk"
        assert new_count == expected_new_count, "Fail: incorrect new-line count in patch hunk"

    assert saw_hunk, "Fail: patch contains no changes"
    result.extend(old_lines[old_pos:])
    return "".join(result)


def test_leaked_payload_extracted():
    assert os.path.exists(PAYLOAD_PATH), f"Fail: {PAYLOAD_PATH} not found"
    with open(PAYLOAD_PATH, "r") as f:
        raw = f.read()
    assert raw == EXPECTED_PAYLOAD + "\n", "Fail: leaked payload must be the exact string on one line"


def test_log_processor_fixed_for_leaked_payload():
    assert os.path.isfile(SCRIPT_PATH), f"Fail: {SCRIPT_PATH} not found or not a regular file"
    result = run_script(EXPECTED_PAYLOAD)
    assert result.returncode == 1, f"Fail: expected exit code 1, got {result.returncode}"
    assert "Malformed message" in result.stdout, "Fail: script did not echo 'Malformed message'"


def test_log_processor_general_behavior():
    # Unpredictable values prevent a solution hardcoded only for the known leaked payload.
    token = secrets.token_hex(12)
    malformed_messages = [
        f"[SESSION_{token}] {{{{DATA_{token}",
        f"prefix-{token} {{{{unterminated",
        f"{{{{{token}}}",
        f"noise {{{{ inner {{{{ {token}",
    ]
    for message in malformed_messages:
        result = run_script(message)
        assert result.returncode == 1, f"Fail: malformed input returned {result.returncode}: {message!r}"
        assert result.stdout == "Malformed message\n", f"Fail: wrong output for malformed input: {message!r}"

    valid_data = secrets.token_hex(10)
    valid = f"[SESSION_{token}] {{{{{valid_data}}}}} trailing"
    result = run_script(valid)
    assert result.returncode == 0, "Fail: valid messages must still succeed"
    assert result.stdout == f"Processed: {valid_data}\n", "Fail: valid message processing was changed"

    ignored = f"ordinary-message-{secrets.token_hex(10)}"
    result = run_script(ignored)
    assert result.returncode == 0, "Fail: messages without an opening tag must still succeed"
    assert result.stdout == f"Ignored: {ignored}\n", "Fail: ignored-message behavior was changed"


def test_malformed_path_does_not_accumulate_state_and_returns():
    message = f"[SESSION_{secrets.token_hex(8)}] {{{{BROKEN"
    probe = r'''
source "$1" "$2"
rc=$?
printf '__RETURN__=%s\n' "$rc"
printf '__STATE_COUNT__=%s\n' "${#STATE_HISTORY[@]}"
'''
    try:
        result = subprocess.run(
            ["bash", "-c", probe, "probe", SCRIPT_PATH, message],
            capture_output=True,
            text=True,
            timeout=1,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Fail: malformed-message function recurses or hangs")
    assert "Malformed message\n" in result.stdout
    assert "__RETURN__=1\n" in result.stdout, "Fail: malformed-message function must return 1"
    assert "__STATE_COUNT__=0\n" in result.stdout, "Fail: malformed input was accumulated in global state"


def test_processor_patch_exists_and_valid():
    assert os.path.exists(PATCH_PATH), f"Fail: {PATCH_PATH} does not exist"
    assert os.path.getsize(PATCH_PATH) > 0, f"Fail: {PATCH_PATH} is empty"
    with open(PATCH_PATH, "r") as f:
        patch_content = f.read()
    assert "---" in patch_content and "+++" in patch_content, f"Fail: {PATCH_PATH} does not look like a unified diff"

    assert os.path.isfile(ORIGINAL_PATH), f"Fail: {ORIGINAL_PATH} is missing"
    with open(ORIGINAL_PATH, "r") as f:
        saved_original = f.read()
    assert saved_original == ORIGINAL_SCRIPT, "Fail: the saved original buggy script was modified"

    with open(SCRIPT_PATH, "r") as f:
        fixed_script = f.read()
    patched_result = apply_unified_diff(ORIGINAL_SCRIPT, patch_content)
    assert patched_result == fixed_script, "Fail: processor.patch does not transform the original script into the submitted fixed script"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
