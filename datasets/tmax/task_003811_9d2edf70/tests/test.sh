#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile

BINARY_PATH = "/home/user/bin/data_ingester"
BACKLOG_PATH = "/home/user/data/backlog.enc"


def derive_expected_outputs():
    assert os.path.isfile(BINARY_PATH), f"Core binary {BINARY_PATH} is missing."
    assert os.access(BINARY_PATH, os.X_OK), f"Core binary {BINARY_PATH} is not executable."

    with open(BINARY_PATH, "rb") as f:
        binary = f.read()
    assert binary.startswith(b"\x7fELF"), f"{BINARY_PATH} is not an ELF executable."

    matches = re.findall(rb"XOR_KEY=([^\x00\s]{1,256})\x00", binary)
    assert len(matches) == 1, f"Expected exactly one embedded XOR_KEY string, found {len(matches)}."
    key_bytes = matches[0]
    key = key_bytes.decode("ascii")

    assert os.path.isfile(BACKLOG_PATH), f"Encrypted backlog {BACKLOG_PATH} is missing."
    with open(BACKLOG_PATH, "rb") as f:
        encrypted = f.read()
    assert encrypted, f"Encrypted backlog {BACKLOG_PATH} is empty."

    decrypted = bytes(value ^ key_bytes[i % len(key_bytes)] for i, value in enumerate(encrypted))
    message = decrypted.decode("ascii")
    return key, message


def test_start_script_fixed():
    """Verify that start.sh sets PROD, invokes data_ingester, logs it, and succeeds."""
    script_path = "/home/user/bin/start.sh"
    assert os.path.isfile(script_path), f"Start script {script_path} is missing."

    clean_env = os.environ.copy()
    clean_env.pop("PIPELINE_ENV", None)

    prod_env = clean_env.copy()
    prod_env["PIPELINE_ENV"] = "PROD"
    direct = subprocess.run(
        [BINARY_PATH], capture_output=True, text=True, env=prod_env, timeout=10
    )
    assert direct.returncode == 0, f"The core binary does not run successfully in PROD: {direct.stderr}"
    expected_log_output = direct.stdout + direct.stderr
    assert expected_log_output, "The core binary produced no service output in PROD."

    token = next(tempfile._get_candidate_names())
    original_binary = f"/tmp/data_ingester.original.{token}"
    probe_path = f"/tmp/data_ingester.probe.{token}"
    log_path = "/home/user/logs/ingester.log"
    saved_log = f"/tmp/ingester.log.saved.{token}"
    had_log = os.path.lexists(log_path)

    os.replace(BINARY_PATH, original_binary)
    if had_log:
        os.replace(log_path, saved_log)

    wrapper = f'''#!/bin/bash
printf '%s' "${{PIPELINE_ENV-}}" > {probe_path!r}
exec {original_binary!r} "$@"
'''
    try:
        with open(BINARY_PATH, "w") as f:
            f.write(wrapper)
        os.chmod(BINARY_PATH, 0o755)

        result = subprocess.run(
            [script_path], capture_output=True, text=True, env=clean_env, timeout=10
        )
        assert result.returncode == 0, (
            f"Running {script_path} failed with exit code {result.returncode}. "
            f"Output: {result.stderr}"
        )
        assert os.path.isfile(probe_path), (
            f"{script_path} did not invoke {BINARY_PATH}."
        )
        with open(probe_path, "r") as f:
            observed_env = f.read()
        assert observed_env == "PROD", (
            f"{script_path} invoked data_ingester with PIPELINE_ENV={observed_env!r}, not 'PROD'."
        )
        assert os.path.isfile(log_path), f"{script_path} did not create {log_path}."
        with open(log_path, "r", errors="replace") as f:
            new_log = f.read()
        assert expected_log_output in new_log, (
            f"{script_path} did not write the actual data_ingester output to {log_path}."
        )
    finally:
        if os.path.lexists(BINARY_PATH):
            os.unlink(BINARY_PATH)
        os.replace(original_binary, BINARY_PATH)
        if os.path.lexists(probe_path):
            os.unlink(probe_path)
        if os.path.lexists(log_path):
            os.unlink(log_path)
        if had_log and os.path.lexists(saved_log):
            os.replace(saved_log, log_path)


def test_processed_txt_contents():
    """Verify that processed.txt contains the message derived from the supplied artifacts."""
    _, expected_message = derive_expected_outputs()
    processed_path = "/home/user/data/processed.txt"
    assert os.path.isfile(processed_path), f"Decrypted output file {processed_path} is missing."

    with open(processed_path, "r") as f:
        content = f.read().strip()

    assert expected_message in content, f"{processed_path} does not contain the expected decrypted message."
    assert content == expected_message, f"{processed_path} must contain only the fully decrypted message."


def test_resolution_txt_contents():
    """Verify that resolution.txt contains exactly the derived key and message."""
    expected_key, expected_message = derive_expected_outputs()
    resolution_path = "/home/user/resolution.txt"
    assert os.path.isfile(resolution_path), f"Resolution file {resolution_path} is missing."

    with open(resolution_path, "r") as f:
        raw = f.read()
    lines = [line.strip() for line in raw.splitlines() if line.strip()]

    assert len(lines) == 2, f"{resolution_path} should contain exactly 2 non-empty lines, found {len(lines)}."
    assert lines[0] == expected_key, f"First line of {resolution_path} is incorrect. Expected '{expected_key}', got '{lines[0]}'."
    assert lines[1] == expected_message, f"Second line of {resolution_path} is incorrect. Expected '{expected_message}', got '{lines[1]}'."

    exact_lines = raw.splitlines()
    assert exact_lines == [expected_key, expected_message], (
        f"{resolution_path} must contain exactly two lines with no blank or extra lines."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
