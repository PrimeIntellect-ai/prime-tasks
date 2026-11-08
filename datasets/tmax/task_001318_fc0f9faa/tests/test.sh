#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import uuid
from pathlib import Path

BASE = Path("/home/user/debug_env")
SCRIPT = BASE / "process_logs.sh"
ENV_FILE = BASE / ".env"
TRACE = BASE / "logs/network_trace.txt"


def run_script():
    return subprocess.run(
        ["bash", str(SCRIPT)],
        cwd=str(BASE),
        capture_output=True,
        text=True,
    )


def test_resolution_txt():
    res_path = "/home/user/resolution.txt"
    assert os.path.isfile(res_path), f"File {res_path} does not exist."

    with open(res_path, "r") as f:
        content = f.read().strip()

    expected = "Crash Reason: OOMKilled_Memory_Limit_Exceeded\nAttacker IP: 10.45.99.12"
    assert content == expected, f"Content of {res_path} does not match the expected format and values. Found:\n{content}"


def test_process_logs_script_fixed():
    script_path = "/home/user/debug_env/process_logs.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."

    with open(script_path, "r") as f:
        content = f.read()

    assert "$(ls logs/*.log)" not in content, "The script still contains the buggy '$(ls logs/*.log)' construct which breaks on spaces."


def test_script_execution_and_combined_output():
    result = run_script()
    assert result.returncode == 0, f"Script execution failed with exit code {result.returncode}.\nStderr: {result.stderr}"

    combined_path = "/home/user/debug_env/combined.txt"
    assert os.path.isfile(combined_path), f"File {combined_path} was not created after script execution."

    with open(combined_path, "r") as f:
        combined_content = f.read()

    assert "OOMKilled_Memory_Limit_Exceeded" in combined_content, "combined.txt does not contain the crash reason. The script might not be processing files with spaces correctly."
    assert "High latency detected." in combined_content, "combined.txt does not contain the performance monitor log."


def test_env_fixed():
    env_path = "/home/user/debug_env/.env"
    assert os.path.isfile(env_path), f"Environment file {env_path} does not exist."

    with open(env_path, "r") as f:
        content = f.read()

    assert "--invalid-flag-MALICIOUS" not in content, ".env file still contains the invalid flag."

    malicious_packets_path = "/home/user/debug_env/malicious_packets.txt"
    assert os.path.isfile(malicious_packets_path), f"File {malicious_packets_path} was not created."

    with open(malicious_packets_path, "r") as f:
        malicious_content = f.read()

    assert "MALICIOUS_PAYLOAD" in malicious_content, "malicious_packets.txt does not contain the expected malicious payload. The PCAP_FILTER_TERM in .env might still be incorrect."


def test_script_processes_unseen_spaced_logs_and_uses_filter_variable():
    token = "FILTER_" + uuid.uuid4().hex
    log_token_a = "DYNAMIC_LOG_A_" + uuid.uuid4().hex
    log_token_b = "DYNAMIC_LOG_B_" + uuid.uuid4().hex
    name_token = uuid.uuid4().hex
    dynamic_logs = [
        BASE / "logs" / f"dynamic report {name_token}.log",
        BASE / "logs" / f"second spaced file {name_token}.log",
    ]

    original_env = ENV_FILE.read_bytes()
    original_trace = TRACE.read_bytes()
    matching_lines = [
        f"12:00:01 IP 203.0.113.17.4321 > 10.0.0.1.80: payload {token} alpha",
        f"12:00:03 IP 198.51.100.24.9876 > 10.0.0.1.80: payload {token} omega",
    ]
    trace_lines = [
        "12:00:00 IP 192.0.2.10.1111 > 10.0.0.1.80: MALICIOUS distractor",
        matching_lines[0],
        "12:00:02 IP 192.0.2.11.2222 > 10.0.0.1.80: harmless distractor",
        matching_lines[1],
    ]

    try:
        dynamic_logs[0].write_text(log_token_a + "\n", encoding="utf-8")
        dynamic_logs[1].write_text(log_token_b + "\n", encoding="utf-8")
        ENV_FILE.write_text(f'PCAP_FILTER_TERM="{token}"\n', encoding="utf-8")
        TRACE.write_text("\n".join(trace_lines) + "\n", encoding="utf-8")

        for output in (BASE / "combined.txt", BASE / "malicious_packets.txt"):
            if output.exists():
                output.unlink()

        result = run_script()
        assert result.returncode == 0, (
            f"Script failed on dynamically generated inputs with exit code {result.returncode}.\n"
            f"Stdout: {result.stdout}\nStderr: {result.stderr}"
        )
        assert "No such file or directory" not in result.stderr, (
            f"Script emitted a filename handling error: {result.stderr}"
        )

        combined_path = BASE / "combined.txt"
        assert combined_path.is_file(), "combined.txt was not generated for dynamic logs."
        combined = combined_path.read_text(encoding="utf-8")
        assert log_token_a in combined, "A dynamically named log file containing spaces was not processed."
        assert log_token_b in combined, "A second dynamically named log file containing spaces was not processed."

        malicious_path = BASE / "malicious_packets.txt"
        assert malicious_path.is_file(), "malicious_packets.txt was not generated for the dynamic trace."
        actual_lines = malicious_path.read_text(encoding="utf-8").splitlines()
        assert actual_lines == matching_lines, (
            "malicious_packets.txt was not produced by filtering network_trace.txt with "
            "the current PCAP_FILTER_TERM. "
            f"Expected {matching_lines!r}, found {actual_lines!r}."
        )
    finally:
        ENV_FILE.write_bytes(original_env)
        TRACE.write_bytes(original_trace)
        for path in dynamic_logs:
            if path.exists():
                path.unlink()

        cleanup_result = run_script()
        assert cleanup_result.returncode == 0, (
            "Script no longer executes successfully after restoring the task inputs. "
            f"Stderr: {cleanup_result.stderr}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
