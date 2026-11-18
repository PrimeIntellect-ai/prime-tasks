#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import hashlib
import secrets
import subprocess
import tempfile
import pytest

ORIGINAL_LOGD_C = """#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    FILE *fp = fopen("/home/user/web.log", "r");
    if (!fp) {
        perror("Failed to open log file");
        return 1;
    }

    char line[512];
    while (fgets(line, sizeof(line), fp)) {
        line[strcspn(line, "\\n")] = 0;

        // Only process ERROR logs
        if (strstr(line, "ERROR")) {
            char cmd[1024];
            // VULNERABILITY: Command Injection via unsanitized input
            sprintf(cmd, "echo '%s' >> /home/user/alerts.log", line);
            system(cmd);
        }
    }

    fclose(fp);
    return 0;
}
"""

def get_sha256(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()

def test_report_contents():
    report_path = "/home/user/report.txt"
    assert os.path.isfile(report_path), f"Report file {report_path} is missing."

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.read().strip().split('\n')]

    assert len(lines) == 3, f"Expected exactly 3 lines in report.txt, found {len(lines)}."

    assert lines[0] == "198.51.100.44", f"Line 1 of report.txt should be '198.51.100.44', got '{lines[0]}'."

    expected_original_sha256 = get_sha256(ORIGINAL_LOGD_C.encode('utf-8'))
    assert lines[1] == expected_original_sha256, "Line 2 of report.txt should be the SHA256 of the original logd.c."

    c_file_path = "/home/user/logd.c"
    assert os.path.isfile(c_file_path), f"Patched source file {c_file_path} is missing."
    with open(c_file_path, "rb") as f:
        current_c_content = f.read()
    expected_patched_sha256 = get_sha256(current_c_content)

    assert lines[2] == expected_patched_sha256, "Line 3 of report.txt should be the SHA256 of the patched logd.c."

def test_remediation_script():
    script_path = "/home/user/remediation.sh"
    assert os.path.isfile(script_path), f"Remediation script {script_path} is missing."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Remediation script {script_path} is not executable."

    with open(script_path, "r") as f:
        content = f.read().strip()

    lines = [line.strip() for line in content.split('\n') if line.strip() and not line.startswith('#')]
    assert len(lines) == 1, "remediation.sh should contain exactly one command line."

    expected_cmd = "iptables -A INPUT -s 198.51.100.44 -p tcp -j DROP"
    assert lines[0] == expected_cmd, f"remediation.sh does not contain the correct iptables command. Got: {lines[0]}"

def test_logd_c_patched():
    c_file_path = "/home/user/logd.c"
    assert os.path.isfile(c_file_path), f"Source file {c_file_path} is missing."

    with open(c_file_path, "r") as f:
        content = f.read()

    assert "system(" not in content, "logd.c still contains 'system(' calls."
    assert "popen(" not in content, "logd.c still contains 'popen(' calls."
    assert "fopen" in content or "open(" in content, "logd.c should use secure file I/O functions."

def test_logd_fixed_executable():
    bin_path = "/home/user/logd_fixed"
    assert os.path.isfile(bin_path), f"Compiled binary {bin_path} is missing."

    st = os.stat(bin_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Compiled binary {bin_path} is not executable."

    with open(bin_path, "rb") as f:
        magic = f.read(4)
    assert magic == b"\x7fELF", f"{bin_path} is not a valid ELF binary."

def test_source_compiles_and_both_artifacts_process_logs_safely():
    source_path = "/home/user/logd.c"
    submitted_binary = "/home/user/logd_fixed"

    fd, rebuilt_binary = tempfile.mkstemp(prefix="logd_rebuilt_", dir="/tmp")
    os.close(fd)
    os.unlink(rebuilt_binary)

    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-Wall", "-Wextra", source_path, "-o", rebuilt_binary],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        "Patched logd.c does not compile cleanly with gcc:\n"
        + compile_result.stdout + compile_result.stderr
    )

    web_path = "/home/user/web.log"
    alerts_path = "/home/user/alerts.log"
    old_web = open(web_path, "rb").read() if os.path.exists(web_path) else None
    old_alerts = open(alerts_path, "rb").read() if os.path.exists(alerts_path) else None

    token = secrets.token_hex(12)
    sentinel = f"/tmp/logd_command_injection_{token}"
    prefix = f"existing-alert-{token}\n".encode()
    input_lines = [
        f"[{token}] INFO: ordinary entry",
        f"[{token}] ERROR: first failure",
        f"[{token}] WARNING: ignored entry",
        f"[{token}] ERROR: probe'; /usr/bin/touch {sentinel}; echo '",
        f"[{token}] ERROR: final entry without input newline",
    ]
    web_data = ("\n".join(input_lines)).encode()
    expected = prefix + b"".join((line + "\n").encode() for line in input_lines if "ERROR" in line)

    try:
        for executable in (rebuilt_binary, submitted_binary):
            with open(web_path, "wb") as f:
                f.write(web_data)
            with open(alerts_path, "wb") as f:
                f.write(prefix)
            if os.path.exists(sentinel):
                os.unlink(sentinel)

            try:
                result = subprocess.run(
                    [executable],
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=10,
                )
            except subprocess.TimeoutExpired:
                pytest.fail(f"{executable} did not terminate while processing the test log")

            assert result.returncode == 0, (
                f"{executable} exited with status {result.returncode}. "
                f"stderr: {result.stderr.decode(errors='replace')}"
            )
            assert not os.path.exists(sentinel), f"{executable} executed shell content from a log entry"
            assert os.path.isfile(alerts_path), f"{executable} did not create or append to alerts.log"
            with open(alerts_path, "rb") as f:
                actual = f.read()
            assert actual == expected, (
                f"{executable} did not append exactly the ERROR entries with one newline each. "
                f"Expected {expected!r}, got {actual!r}"
            )
    finally:
        if old_web is None:
            if os.path.exists(web_path):
                os.unlink(web_path)
        else:
            with open(web_path, "wb") as f:
                f.write(old_web)

        if old_alerts is None:
            if os.path.exists(alerts_path):
                os.unlink(alerts_path)
        else:
            with open(alerts_path, "wb") as f:
                f.write(old_alerts)

        if os.path.exists(sentinel):
            os.unlink(sentinel)
        if os.path.exists(rebuilt_binary):
            os.unlink(rebuilt_binary)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
