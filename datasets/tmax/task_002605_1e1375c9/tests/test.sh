#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import base64
import copy
import secrets
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/traffic_sanitizer.py"
EVIL_CORPUS_DIR = "/app/corpora/evil"
CLEAN_CORPUS_DIR = "/app/corpora/clean"

def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"

def test_evil_corpus_redacted():
    """Assert that the agent's script correctly redacts all evil payloads."""
    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.json')]
    assert len(evil_files) > 0, "No evil corpus files found."

    failed_files = []

    with tempfile.TemporaryDirectory() as tmpdir:
        for filename in evil_files:
            input_path = os.path.join(EVIL_CORPUS_DIR, filename)
            output_path = os.path.join(tmpdir, filename)

            result = subprocess.run([SCRIPT_PATH, input_path, output_path], capture_output=True, text=True)
            if result.returncode != 0:
                failed_files.append((filename, f"Script crashed with return code {result.returncode}"))
                continue

            if not os.path.exists(output_path):
                failed_files.append((filename, "Output file not created"))
                continue

            try:
                with open(output_path, 'r') as f:
                    out_data = json.load(f)

                header_val = out_data.get("headers", {}).get("X-Diagnostic-Dump")
                if header_val != "[REDACTED_ELF]":
                    failed_files.append((filename, f"Header not redacted. Got: {header_val}"))
            except Exception as e:
                failed_files.append((filename, f"Failed to parse output JSON: {e}"))

    if failed_files:
        error_msg = f"{len(failed_files)} of {len(evil_files)} evil bypassed.\n"
        error_msg += "\n".join([f"{f}: {reason}" for f, reason in failed_files[:10]])
        if len(failed_files) > 10:
            error_msg += f"\n... and {len(failed_files) - 10} more."
        pytest.fail(error_msg)

def test_clean_corpus_preserved():
    """Assert that the agent's script preserves all clean payloads without modification."""
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.json')]
    assert len(clean_files) > 0, "No clean corpus files found."

    failed_files = []

    with tempfile.TemporaryDirectory() as tmpdir:
        for filename in clean_files:
            input_path = os.path.join(CLEAN_CORPUS_DIR, filename)
            output_path = os.path.join(tmpdir, filename)

            result = subprocess.run([SCRIPT_PATH, input_path, output_path], capture_output=True, text=True)
            if result.returncode != 0:
                failed_files.append((filename, f"Script crashed with return code {result.returncode}"))
                continue

            if not os.path.exists(output_path):
                failed_files.append((filename, "Output file not created"))
                continue

            try:
                with open(input_path, 'r') as f:
                    in_data = json.load(f)
                with open(output_path, 'r') as f:
                    out_data = json.load(f)

                if in_data != out_data:
                    failed_files.append((filename, "Output JSON does not match input JSON semantically"))
            except Exception as e:
                failed_files.append((filename, f"Failed to parse JSON: {e}"))

    if failed_files:
        error_msg = f"{len(failed_files)} of {len(clean_files)} clean modified.\n"
        error_msg += "\n".join([f"{f}: {reason}" for f, reason in failed_files[:10]])
        if len(failed_files) > 10:
            error_msg += f"\n... and {len(failed_files) - 10} more."
        pytest.fail(error_msg)

def test_generated_varied_requests():
    """Exercise generated inputs outside the visible corpus and verify the full document."""
    cases = []
    for i in range(32):
        mode = i % 8
        request = {
            "method": ["GET", "POST", "PUT", "PATCH"][i % 4],
            "url": f"/generated/{secrets.token_hex(5)}/{i}",
            "headers": {
                "Host": f"host-{secrets.token_hex(4)}.example",
                "X-Trace-Id": secrets.token_hex(12),
                "Accept": "application/json",
            },
            "body": secrets.token_hex(i % 11),
            "metadata": {
                "sequence": i,
                "flags": [bool(i % 2), None, secrets.token_hex(3)],
            },
        }
        should_redact = False

        if mode in (0, 1):
            payload = b"\x7fELF" + os.urandom(i + 1)
            request["headers"]["X-Diagnostic-Dump"] = base64.b64encode(payload).decode("ascii")
            should_redact = True
        elif mode == 2:
            payload = b"ordinary benign payload:" + os.urandom(i + 1)
            request["headers"]["X-Diagnostic-Dump"] = base64.b64encode(payload).decode("ascii")
        elif mode == 3:
            request["headers"]["X-Diagnostic-Dump"] = "%%%not-valid-base64-" + secrets.token_hex(4)
        elif mode == 4:
            # This resembles an encoded ELF prefix but is malformed due to missing padding.
            request["headers"]["X-Diagnostic-Dump"] = "f0VMRg"
        elif mode == 5:
            payload = [b"\x7f", b"\x7fE", b"\x7fEL"][i % 3]
            request["headers"]["X-Diagnostic-Dump"] = base64.b64encode(payload).decode("ascii")
        elif mode == 6:
            payload = b"prefix-data\x7fELF" + os.urandom(i + 1)
            request["headers"]["X-Diagnostic-Dump"] = base64.b64encode(payload).decode("ascii")
        else:
            request["headers"]["X-Unrelated-Dump"] = base64.b64encode(
                b"\x7fELF" + os.urandom(i + 1)
            ).decode("ascii")

        expected = copy.deepcopy(request)
        if should_redact:
            expected["headers"]["X-Diagnostic-Dump"] = "[REDACTED_ELF]"
        cases.append((request, expected))

    with tempfile.TemporaryDirectory(prefix="traffic-check-") as tmpdir:
        for index, (request, expected) in enumerate(cases):
            input_path = os.path.join(tmpdir, secrets.token_hex(10) + ".json")
            output_path = os.path.join(tmpdir, secrets.token_hex(10) + ".out")

            with open(input_path, "w") as f:
                if index % 3 == 0:
                    json.dump(request, f, indent=2)
                elif index % 3 == 1:
                    json.dump(request, f, separators=(",", ":"))
                else:
                    json.dump(request, f)

            result = subprocess.run(
                [SCRIPT_PATH, input_path, output_path],
                capture_output=True,
                text=True,
                timeout=10,
            )
            assert result.returncode == 0, (
                f"Generated case {index} exited with {result.returncode}: {result.stderr}"
            )
            assert os.path.isfile(output_path), f"Generated case {index} did not create output"

            with open(output_path, "r") as f:
                actual = json.load(f)
            assert actual == expected, (
                f"Generated case {index} produced the wrong document. "
                f"Expected {expected!r}, got {actual!r}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
