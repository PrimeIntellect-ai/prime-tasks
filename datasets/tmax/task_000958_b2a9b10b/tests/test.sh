#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import struct
import subprocess
import tempfile
import pytest

SOURCE = "/home/user/elf_audit.c"
PROGRAM = "/home/user/elf_audit"
SERVER_BIN = "/home/user/server_bin"
REPORT = "/home/user/audit_report.txt"


def test_elf_audit_c_exists():
    """Verify that the C source file exists and includes <elf.h>."""
    path = SOURCE
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()
    assert "<elf.h>" in content, f"{path} does not include <elf.h>."


def test_elf_audit_executable_exists():
    """Verify that the compiled elf_audit binary exists and is executable."""
    path = PROGRAM
    assert os.path.isfile(path), f"Executable {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def read_entry_from_elf(path):
    with open(path, "rb") as f:
        header = f.read(64)
    assert len(header) >= 64, f"{path} has a truncated ELF64 header."
    assert header[:4] == b"\x7fELF", f"{path} is not an ELF file."
    assert header[4] == 2, f"{path} is not a 64-bit ELF file."
    if header[5] == 1:
        return struct.unpack_from("<Q", header, 24)[0]
    if header[5] == 2:
        return struct.unpack_from(">Q", header, 24)[0]
    pytest.fail(f"{path} has an invalid ELF data encoding.")


def run_auditor(path, target):
    env = os.environ.copy()
    env["PATH"] = "/nonexistent"
    result = subprocess.run(
        [path, target],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
        env=env,
    )
    assert result.returncode == 0, (
        f"{path} failed on {target} with status {result.returncode}: {result.stderr}"
    )
    return result.stdout


def make_elf64(path, entry):
    ident = b"\x7fELF" + bytes([2, 1, 1, 0, 0]) + b"\x00" * 7
    header = struct.pack(
        "<16sHHIQQQIHHHHHH",
        ident, 2, 62, 1, entry, 64, 0, 0, 64, 56, 0, 64, 0, 0
    )
    with open(path, "wb") as f:
        f.write(header)


def test_submitted_source_and_executable_behavior():
    """Recompile the submitted source and exercise both binaries on derived inputs."""
    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "elf_audit_rebuilt")
        build = subprocess.run(
            ["gcc", SOURCE, "-o", rebuilt],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert build.returncode == 0, f"Submitted C source does not compile: {build.stderr}"

        for executable in (PROGRAM, rebuilt):
            with open(executable, "rb") as f:
                assert f.read(4) == b"\x7fELF", f"{executable} is not a compiled ELF executable."

        cases = [(SERVER_BIN, read_entry_from_elf(SERVER_BIN))]
        for i in range(4):
            entry = secrets.randbits(64)
            target = os.path.join(td, f"sample_{i}.elf")
            make_elf64(target, entry)
            cases.append((target, entry))

        for target, entry in cases:
            expected = f"Entry: 0x{entry:x}\n"
            assert run_auditor(PROGRAM, target) == expected, (
                f"Submitted executable produced incorrect output for {target}."
            )
            assert run_auditor(rebuilt, target) == expected, (
                f"Executable rebuilt from submitted source produced incorrect output for {target}."
            )

        server_output = run_auditor(PROGRAM, SERVER_BIN).rstrip("\n")
        assert os.path.isfile(REPORT), f"Report {REPORT} does not exist."
        with open(REPORT, "r") as f:
            report_lines = f.read().strip().splitlines()
        assert report_lines, "Audit report is empty."
        assert report_lines[0] == server_output, (
            "Report line 1 is not the output of /home/user/elf_audit on /home/user/server_bin."
        )


def test_audit_report():
    """Verify the contents of the audit report."""
    report_path = REPORT
    assert os.path.isfile(report_path), f"Report {report_path} does not exist."

    # Compute expected entry point using readelf
    server_bin = SERVER_BIN
    try:
        out = subprocess.check_output(["readelf", "-h", server_bin], universal_newlines=True)
        entry_point = None
        for line in out.splitlines():
            if "Entry point address:" in line:
                entry_point = line.split(":", 1)[1].strip()
                break
        assert entry_point is not None, "Could not determine entry point from server_bin."
    except Exception as e:
        pytest.fail(f"Failed to run readelf: {e}")

    # Compute expected expiry using openssl
    server_crt = "/home/user/server.crt"
    try:
        out = subprocess.check_output(["openssl", "x509", "-in", server_crt, "-noout", "-enddate"], universal_newlines=True)
        expiry = out.strip().split("=", 1)[1]
    except Exception as e:
        pytest.fail(f"Failed to run openssl: {e}")

    # Read and verify report
    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.read().strip().splitlines()]

    assert len(lines) == 2, f"Audit report should have exactly 2 lines, found {len(lines)}."

    expected_line1 = f"Entry: {entry_point}"
    expected_line2 = f"Expiry: {expiry}"

    assert lines[0] == expected_line1, f"Line 1 mismatch. Expected '{expected_line1}', got '{lines[0]}'."
    assert lines[1] == expected_line2, f"Line 2 mismatch. Expected '{expected_line2}', got '{lines[1]}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
