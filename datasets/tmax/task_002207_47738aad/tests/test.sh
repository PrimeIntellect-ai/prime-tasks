#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import re
import shlex
import stat
import subprocess
import tempfile
from pathlib import Path

BASE = Path("/home/user/pentest_audit")


def derive_pin_from_service(tmpdir):
    harness = Path(tmpdir) / "derive_pin.cpp"
    binary = Path(tmpdir) / "derive_pin"
    harness.write_text(r'''
#define main vulnerable_service_main
#include "/home/user/pentest_audit/vuln_auth.cpp"
#undef main
#include <iomanip>
#include <iostream>
int main() {
    for (int pin = 0; pin <= 9999; ++pin) {
        if (custom_hash(pin) == ADMIN_HASH) {
            std::cout << std::setw(4) << std::setfill('0') << pin << "\n";
            return 0;
        }
    }
    return 1;
}
''')
    result = subprocess.run(
        ["g++", "-std=c++17", str(harness), "-o", str(binary)],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Could not compile PIN derivation harness: {result.stderr}"
    result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, "No 4-digit PIN in vuln_auth.cpp matches ADMIN_HASH."
    pin = result.stdout.strip()
    assert re.fullmatch(r"\d{4}", pin), f"Derived PIN has invalid format: {pin!r}"
    return pin


def test_cwe_report():
    file_path = BASE / "cwe_report.txt"
    assert file_path.is_file(), f"File {file_path} is missing."
    content = file_path.read_text().strip()
    assert content.upper() == "CWE-798", f"Expected CWE-798 in {file_path}, but found: {content}"


def test_cracked_pin():
    file_path = BASE / "cracked_pin.txt"
    source_path = BASE / "cracker.cpp"
    assert file_path.is_file(), f"File {file_path} is missing."
    assert source_path.is_file(), f"File {source_path} is missing."

    content = file_path.read_text().strip()
    assert content == "4829", f"Expected cracked PIN to be 4829 in {file_path}, but found: {content}"

    source = source_path.read_text(errors="replace")
    code = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    code = re.sub(r"//[^\n]*", "", code)
    assert re.search(r"\b(for|while|do)\b", code), "cracker.cpp does not contain a brute-force iteration."
    assert re.search(r"\b(9999|10000)\b", code), "cracker.cpp does not iterate over the 4-digit PIN range."
    assert "0x5a5a" in code.lower() and re.search(r"\b99991\b", code), \
        "cracker.cpp does not implement the service's custom hash."

    with tempfile.TemporaryDirectory() as tmpdir:
        expected_pin = derive_pin_from_service(tmpdir)
        assert expected_pin == "4829", f"Expected service PIN 4829, derived {expected_pin}."

        binary = Path(tmpdir) / "cracker"
        result = subprocess.run(
            ["g++", "-std=c++17", "-O0", str(source_path), "-o", str(binary)],
            cwd=BASE,
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"cracker.cpp failed to compile: {result.stderr}"

        original = file_path.read_bytes()
        original_mode = stat.S_IMODE(file_path.stat().st_mode)
        generated = None
        try:
            file_path.unlink()
            result = subprocess.run(
                [str(binary)],
                cwd=BASE,
                capture_output=True,
                text=True,
                timeout=15,
            )
            if file_path.is_file():
                generated = file_path.read_text().strip()
        finally:
            file_path.write_bytes(original)
            os.chmod(file_path, original_mode)

        assert result.returncode == 0, f"Compiled cracker exited with status {result.returncode}: {result.stderr}"
        output = result.stdout + "\n" + result.stderr
        reported = re.search(rf"(?<!\d){re.escape(expected_pin)}(?!\d)", output) is not None
        assert reported or generated == expected_pin, \
            "Running cracker.cpp did not report or save the PIN derived from vuln_auth.cpp."


def test_redacted_logs():
    file_path = BASE / "redacted_logs.txt"
    assert file_path.is_file(), f"File {file_path} is missing."

    expected_logs = [
        "[INFO] 192.168.1.50 Attempted login user=guest PIN=XXXX",
        "[INFO] 10.0.0.5 Attempted login user=admin PIN=XXXX",
        "[INFO] 10.0.0.5 Attempted login user=admin PIN=XXXX",
        "[INFO] 10.0.0.5 Attempted login user=admin PIN=XXXX",
        "[INFO] 10.0.0.5 Attempted login user=admin PIN=XXXX",
        "[INFO] 192.168.1.100 Attempted login user=admin PIN=XXXX",
        "[INFO] 172.16.0.4 Attempted login user=guest PIN=XXXX"
    ]

    lines = [line.strip() for line in file_path.read_text().splitlines() if line.strip()]
    assert len(lines) == len(expected_logs), f"Expected {len(expected_logs)} lines in {file_path}, but found {len(lines)}."
    for i, (actual, expected) in enumerate(zip(lines, expected_logs)):
        assert actual == expected, \
            f"Line {i+1} in {file_path} does not match expected redacted format. Expected: '{expected}', Actual: '{actual}'"

    original = (BASE / "network_logs.txt").read_text()
    derived = re.sub(r"(?<=PIN=)\d{4}", "XXXX", original)
    assert file_path.read_text().splitlines() == derived.splitlines(), \
        "redacted_logs.txt is not the complete PIN-redacted form of network_logs.txt."
    assert not re.search(r"PIN=\d{4}", file_path.read_text()), "An unredacted PIN remains in redacted_logs.txt."


def test_firewall_rule():
    file_path = BASE / "firewall_rule.sh"
    assert file_path.is_file(), f"File {file_path} is missing."

    st = os.stat(file_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {file_path} is not executable."

    content = file_path.read_text().strip()
    commands = [line.strip() for line in content.split('\n') if line.strip() and not line.startswith('#')]
    assert len(commands) >= 1, f"No valid commands found in {file_path}"
    cmd = commands[-1]

    assert "iptables" in cmd, f"iptables command missing in {file_path}"
    assert "-A INPUT" in cmd or "--append INPUT" in cmd, f"Missing append to INPUT chain in {file_path}"
    assert "-s 10.0.0.5" in cmd or "--source 10.0.0.5" in cmd, f"Missing source IP 10.0.0.5 in {file_path}"
    assert "-j DROP" in cmd or "--jump DROP" in cmd, f"Missing jump DROP in {file_path}"

    meaningful = [line.strip() for line in content.splitlines()
                  if line.strip() and not line.lstrip().startswith('#')]
    assert len(meaningful) == 1, f"{file_path} must contain exactly one non-comment command."

    syntax = subprocess.run(["bash", "-n", str(file_path)], capture_output=True, text=True)
    assert syntax.returncode == 0, f"Invalid bash syntax in {file_path}: {syntax.stderr}"

    try:
        tokens = shlex.split(meaningful[0], posix=True)
    except ValueError as exc:
        raise AssertionError(f"Invalid shell command in {file_path}: {exc}")
    assert tokens and os.path.basename(tokens[0]) == "iptables", "The sole command must invoke iptables directly."
    assert len(tokens) == 7, "The iptables command must contain only append, source, and DROP-jump arguments."

    args = tokens[1:]
    parsed = {}
    allowed = {"-A": "append", "--append": "append", "-s": "source", "--source": "source",
               "-j": "jump", "--jump": "jump"}
    for i in range(0, len(args), 2):
        option, value = args[i], args[i + 1]
        assert option in allowed, f"Unexpected iptables argument: {option}"
        key = allowed[option]
        assert key not in parsed, f"Duplicate iptables {key} argument."
        parsed[key] = value

    counts = collections.Counter()
    for line in (BASE / "network_logs.txt").read_text().splitlines():
        match = re.search(r"\b(?:\d{1,3}\.){3}\d{1,3}\b", line)
        if match:
            counts[match.group(0)] += 1
    offenders = [ip for ip, count in counts.items() if count > 3]
    assert len(offenders) == 1, f"Expected one source with more than 3 failed attempts, found {offenders}."
    assert parsed == {"append": "INPUT", "source": offenders[0], "jump": "DROP"}, \
        f"Firewall command does not exactly drop all INPUT traffic from {offenders[0]}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
