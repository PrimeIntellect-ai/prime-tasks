#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import pytest

PROJECT = "/home/user/uptime_project"
SOURCE = os.path.join(PROJECT, "src/uptime_monitor.c")
BINARY = os.path.join(PROJECT, "uptime_monitor")
SOURCE_BINARY = "/tmp/uptime_monitor_from_source"


def run_monitor(path, uptime, total, maintenance):
    result = subprocess.run(
        [path, str(uptime), str(total), str(maintenance)],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, (
        f"Execution of {path} failed with status {result.returncode}: "
        f"{result.stderr}"
    )
    output = result.stdout.strip()
    assert re.fullmatch(r"-?[0-9]+\.[0-9]{2}", output), (
        f"Unexpected output from {path}: {output!r}"
    )
    return output


def test_crashing_host_extracted():
    filepath = "/home/user/crashing_host.txt"
    assert os.path.isfile(filepath), f"File {filepath} is missing. Task 1 not completed."
    with open(filepath, "r") as f:
        content = f.read().strip()
    assert content == "srv-092.prod.internal", f"Expected hostname 'srv-092.prod.internal', but found '{content}' in {filepath}."


def test_makefile_dependency_conflict_resolved():
    filepath = os.path.join(PROJECT, "Makefile")
    assert os.path.isfile(filepath), f"File {filepath} is missing."
    with open(filepath, "r") as f:
        content = f.read()
    assert "-I./modern_headers" in content, "Makefile does not contain the modern headers include path (-I./modern_headers). Task 2 not completed."
    assert "-I./legacy_headers" not in content, "Makefile still contains the legacy headers include path (-I./legacy_headers)."


def test_binary_compiled_and_executable():
    assert os.path.isfile(BINARY), f"Compiled binary {BINARY} is missing. Task 4 not completed."
    assert os.access(BINARY, os.X_OK), f"File {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not a compiled ELF executable."


@pytest.fixture(scope="session")
def rebuilt_binaries():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing."

    # Compile the submitted source independently. This directly verifies that the
    # requested correction exists in src/uptime_monitor.c rather than only in a
    # replacement executable.
    direct = subprocess.run(
        ["gcc", "-Wall", "-I./modern_headers", "-o", SOURCE_BINARY,
         "src/uptime_monitor.c"],
        cwd=PROJECT,
        capture_output=True,
        text=True,
    )
    assert direct.returncode == 0, (
        f"Submitted source did not compile with the modern headers: {direct.stderr}"
    )

    # Remove the existing artifact and force Make to recreate it, then test that
    # newly built artifact. This prevents a preinstalled script or stale binary
    # from satisfying the behavioral checks.
    if os.path.lexists(BINARY):
        os.unlink(BINARY)
    built = subprocess.run(
        ["make", "-B", "uptime_monitor"],
        cwd=PROJECT,
        capture_output=True,
        text=True,
    )
    assert built.returncode == 0, f"make failed: {built.stdout}\n{built.stderr}"
    assert os.path.isfile(BINARY), "make did not produce uptime_monitor."
    assert os.access(BINARY, os.X_OK), "The rebuilt uptime_monitor is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The rebuilt uptime_monitor is not an ELF binary."

    return SOURCE_BINARY, BINARY


def test_sla_calculation_fixed(rebuilt_binaries):
    source_binary, make_binary = rebuilt_binaries

    # Preserve the original fixed assertions.
    for path in rebuilt_binaries:
        assert run_monitor(path, 99, 100, 0) == "99.00", (
            f"Expected output '99.00' from {path}. The integer division bug may remain."
        )
        assert run_monitor(path, 45, 50, 0) == "90.00", (
            f"Expected output '90.00' for inputs 45 50 0 from {path}."
        )

    # Exercise both the independently compiled source and the Make-built binary
    # on unpredictable inputs whose expected values are derived by the verifier.
    cases = []
    for _ in range(24):
        scale = 1 + secrets.randbelow(10000)
        percentage = 1 + secrets.randbelow(99)
        denominator = 100 * scale
        uptime = percentage * scale
        maintenance = secrets.randbelow(10000)
        total = denominator + maintenance
        cases.append((uptime, total, maintenance, f"{percentage:.2f}"))

    for path in rebuilt_binaries:
        for uptime, total, maintenance, expected in cases:
            actual = run_monitor(path, uptime, total, maintenance)
            assert actual == expected, (
                f"For inputs {uptime} {total} {maintenance}, expected {expected} "
                f"from {path}, but got {actual}."
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
