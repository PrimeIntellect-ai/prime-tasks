#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import glob
import os
import secrets
import subprocess

SERVICE = "/home/user/service"
SOURCE = os.path.join(SERVICE, "processor.go")
BINARY = os.path.join(SERVICE, "processor")
LOG = os.path.join(SERVICE, "processed.log")
REPORT = "/home/user/report.txt"
PAYLOAD_GLOB = "/home/user/payloads/*.dat"


def expected_payloads():
    return sorted(os.path.abspath(path) for path in glob.glob(PAYLOAD_GLOB))


def run_processor():
    if os.path.exists(LOG):
        os.remove(LOG)
    result = subprocess.run(
        ["./processor"],
        cwd=SERVICE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Compiled processor exited with status {result.returncode}. "
        f"stderr: {result.stderr}"
    )
    assert os.path.isfile(LOG), f"Processor did not create {LOG}."
    with open(LOG, "r") as f:
        return [line.strip() for line in f if line.strip()]


def assert_exact_log(lines, expected):
    assert len(lines) == len(expected), (
        f"Expected {len(expected)} logged payload paths, got {len(lines)}."
    )
    assert collections.Counter(lines) == collections.Counter(expected), (
        "processed.log must contain every current payload path exactly once, "
        "with no missing, duplicate, or fabricated entries."
    )


def test_final_state_and_processor_behavior():
    assert os.path.isfile(SOURCE), f"Go source file {SOURCE} is missing."
    with open(SOURCE, "r") as f:
        content = f.read()
    assert "package main" in content, "Go source does not contain 'package main'."
    assert "func processPayload" in content, "Go source does not contain processPayload function."

    build = subprocess.run(
        ["go", "build", "-o", "processor", "processor.go"],
        cwd=SERVICE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert build.returncode == 0, f"go build failed: {build.stderr}"
    assert os.path.isfile(BINARY), "go build did not produce the processor binary."
    assert os.access(BINARY, os.X_OK), "The rebuilt processor is not executable."

    baseline = expected_payloads()
    assert len(baseline) == 100, f"Expected 100 payload files, found {len(baseline)}."
    lines = run_processor()
    assert_exact_log(lines, baseline)
    poison_pill_entry = "/home/user/payloads/042.dat"
    assert poison_pill_entry in lines, (
        f"Log file does not contain {poison_pill_entry}. The processor may have skipped it."
    )

    # Exercise the rebuilt artifact with an unpredictable additional short payload,
    # so a fixed, prewritten list of the original 100 paths cannot pass.
    probe = f"/home/user/payloads/verifier_{secrets.token_hex(12)}.dat"
    try:
        with open(probe, "wb") as f:
            f.write(os.urandom(13))
        expected_with_probe = expected_payloads()
        probe_lines = run_processor()
        assert_exact_log(probe_lines, expected_with_probe)
        assert probe in probe_lines, "Processor did not process the newly added payload."
    finally:
        if os.path.exists(probe):
            os.remove(probe)

    # Leave and verify the required final state after removing the verifier probe.
    final_expected = expected_payloads()
    final_lines = run_processor()
    assert len(final_lines) == 100, (
        f"Expected 100 lines in {LOG}, got {len(final_lines)}."
    )
    assert_exact_log(final_lines, final_expected)
    assert poison_pill_entry in final_lines

    assert os.path.isfile(REPORT), f"Report file {REPORT} is missing."
    with open(REPORT, "r") as f:
        report_lines = f.read().splitlines()
    assert len(report_lines) == 2, f"Report file {REPORT} must contain exactly two lines."
    assert report_lines[0] == "042.dat", (
        f"Line 1 of report.txt should be '042.dat', got '{report_lines[0]}'."
    )
    assert report_lines[1] == "100", (
        f"Line 2 of report.txt should be '100', got '{report_lines[1]}'."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
