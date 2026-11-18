#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shlex
import shutil
import subprocess
import tempfile
import time


def test_makefile_uses_required_flags():
    project = "/app/edge-aggregator-1.0"
    makefile = os.path.join(project, "Makefile")
    assert os.path.isfile(makefile), f"File {makefile} does not exist."

    result = subprocess.run(
        ["make", "-Bn"], cwd=project, capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, f"Makefile dry run failed:\n{result.stderr}"

    compile_lines = [
        line for line in result.stdout.splitlines()
        if "main.cpp" in line and re.search(r"(?:^|\s)-o\s+/home/user/edge-aggregator(?:\s|$)", line)
    ]
    assert compile_lines, "Makefile does not compile main.cpp to /home/user/edge-aggregator."
    assert any(
        re.search(r"(?:^|\s)-std=c\+\+17(?:\s|$)", line)
        and re.search(r"(?:^|\s)-O3(?:\s|$)", line)
        for line in compile_lines
    ), "The aggregator compile command must use both -std=c++17 and -O3."


def test_fstab_configured():
    path = "/home/user/ota_payload/etc/fstab"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()

    # Preserve the original required-entry assertion.
    pattern = re.compile(r"^/dev/mmcblk0p3\s+/var/spool/iot_data\s+ext4\s+.*usrquota.*", re.MULTILINE)
    assert pattern.search(content), "fstab does not contain the required mount entry for /dev/mmcblk0p3 to /var/spool/iot_data with ext4 and usrquota options."

    valid_entry = False
    for raw_line in content.splitlines():
        line = raw_line.split("#", 1)[0].strip()
        if not line:
            continue
        fields = line.split()
        if len(fields) < 4:
            continue
        if fields[0:3] != ["/dev/mmcblk0p3", "/var/spool/iot_data", "ext4"]:
            continue
        options = set(fields[3].split(","))
        if {"defaults", "usrquota"}.issubset(options):
            valid_entry = True
            break
    assert valid_entry, "fstab needs an active ext4 entry with both defaults and usrquota mount options."


def test_iptables_rules():
    path = "/home/user/ota_payload/etc/iptables.rules"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()

    # Preserve the original component assertions.
    assert "-t nat" in content, "iptables rule must specify the 'nat' table."
    assert "PREROUTING" in content, "iptables rule must append or insert to the 'PREROUTING' chain."
    assert "-p tcp" in content, "iptables rule must specify the TCP protocol."
    assert "--dport 80" in content, "iptables rule must specify destination port 80."
    assert "-j REDIRECT" in content, "iptables rule must use the REDIRECT target."
    assert "--to-port 8080" in content, "iptables rule must redirect to port 8080."

    def has_pair(tokens, flag, value):
        return any(tokens[i] == flag and tokens[i + 1] == value for i in range(len(tokens) - 1))

    valid_rule = False
    for raw_line in content.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        try:
            tokens = shlex.split(line, comments=True)
        except ValueError:
            continue
        if not tokens or os.path.basename(tokens[0]) != "iptables":
            continue
        if (has_pair(tokens, "-t", "nat")
                and has_pair(tokens, "-A", "PREROUTING")
                and has_pair(tokens, "-p", "tcp")
                and has_pair(tokens, "--dport", "80")
                and has_pair(tokens, "-j", "REDIRECT")
                and has_pair(tokens, "--to-port", "8080")):
            valid_rule = True
            break
    assert valid_rule, "No active iptables command contains the complete required append rule."


def test_metric_correctness_on_hidden_input():
    executable = "/home/user/edge-aggregator"
    assert os.path.isfile(executable), f"Executable {executable} does not exist."
    assert os.access(executable, os.X_OK), f"File {executable} is not executable."
    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", "edge-aggregator must be a compiled ELF executable."

    workdir = tempfile.mkdtemp(prefix="aggregator-check-")
    try:
        input_path = os.path.join(workdir, secrets.token_hex(8) + ".csv")
        output_path = os.path.join(workdir, secrets.token_hex(8) + ".bin")
        expected = 0
        with open(input_path, "w") as f:
            for i in range(137 + secrets.randbelow(73)):
                if secrets.randbelow(5) == 0:
                    f.write("\n")
                else:
                    f.write(f"sensor_{secrets.token_hex(4)},{secrets.randbelow(10000) / 10},170000{i:04d}\n")
                    expected += 1

        result = subprocess.run(
            [executable, input_path, output_path], capture_output=True, timeout=10
        )
        assert result.returncode == 0, f"Execution failed with return code {result.returncode}:\n{result.stderr.decode(errors='replace')}"
        assert os.path.isfile(output_path), "Aggregator did not create its requested output file."
        with open(output_path, "r") as f:
            output = f.read().strip()
        assert output == str(expected), f"Incorrect aggregate: expected {expected}, got {output!r}."
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


def test_sample_was_verified():
    output_path = "/home/user/ota_payload/test_output.bin"
    assert os.path.isfile(output_path), "The aggregator was not run to create test_output.bin."
    with open(output_path, "r") as f:
        assert f.read().strip() == "4", "test_output.bin does not contain the correct sample aggregate."


def test_metric_execution_time():
    executable = "/home/user/edge-aggregator"
    assert os.path.isfile(executable), f"Executable {executable} does not exist."
    assert os.access(executable, os.X_OK), f"File {executable} is not executable."

    workdir = tempfile.mkdtemp(prefix="aggregator-perf-")
    test_csv = os.path.join(workdir, secrets.token_hex(8) + ".csv")
    output_path = os.path.join(workdir, secrets.token_hex(8) + ".bin")
    expected = 20_000_000
    try:
        chunk = b"1672531200,sensor_1,25.4\n" * 100000
        with open(test_csv, "wb") as f:
            for _ in range(200):
                f.write(chunk)

        start_time = time.perf_counter()
        result = subprocess.run(
            [executable, test_csv, output_path], capture_output=True, timeout=10
        )
        end_time = time.perf_counter()

        assert result.returncode == 0, f"Execution failed with return code {result.returncode}:\n{result.stderr.decode(errors='replace')}"
        assert os.path.isfile(output_path), "Aggregator did not create an output for the performance input."
        with open(output_path, "r") as f:
            output = f.read().strip()
        assert output == str(expected), f"Incorrect aggregate for performance input: expected {expected}, got {output!r}."

        runtime = end_time - start_time
        assert runtime <= 1.5, f"Execution runtime {runtime:.4f}s exceeds the threshold of 1.5s. Ensure the code is compiled with -O3."
    finally:
        shutil.rmtree(workdir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
