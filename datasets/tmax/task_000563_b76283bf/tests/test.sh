#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import ipaddress
import os
import random
import re
import subprocess
import tarfile
import tempfile
import pytest


def run_checked(command, **kwargs):
    result = subprocess.run(command, capture_output=True, text=True, timeout=10, **kwargs)
    assert result.returncode == 0, (
        f"Command failed: {command}\nstdout: {result.stdout}\nstderr: {result.stderr}"
    )
    return result


def assert_elf_executable(path):
    assert os.path.isfile(path), f"Required binary not found at {path}"
    assert os.access(path, os.X_OK), f"Binary is not executable: {path}"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Expected a compiled ELF executable at {path}"


def test_netlogger_compiled():
    """Verify that the netlogger binary is compiled and runs successfully."""
    binary_path = "/home/user/netlogger/netlogger"
    assert os.path.isfile(binary_path), f"netlogger binary not found at {binary_path}"

    try:
        result = subprocess.run([binary_path, "--version"], capture_output=True, text=True, timeout=5)
        assert result.returncode == 0, f"netlogger failed to execute properly. Return code: {result.returncode}, Stderr: {result.stderr}"
    except Exception as e:
        pytest.fail(f"Failed to run netlogger: {e}")


def test_netlogger_was_extracted_and_builds_with_cxx17():
    root = "/home/user/netlogger"
    source = os.path.join(root, "src/main.cpp")
    makefile = os.path.join(root, "Makefile")
    assert os.path.isdir(root), "Extracted netlogger directory is missing"
    assert os.path.isfile(source), "Extracted src/main.cpp is missing"
    assert os.path.isfile(makefile), "Corrected Makefile is missing"

    with tarfile.open("/app/vendor/netlogger-1.2.tar.gz", "r:gz") as archive:
        members = [m for m in archive.getmembers() if m.name.endswith("/src/main.cpp")]
        assert len(members) == 1, "Vendored archive has an unexpected source layout"
        archived_source = archive.extractfile(members[0]).read()
    with open(source, "rb") as f:
        assert f.read() == archived_source, "Extracted netlogger source does not match the vendored package"

    dry_run = run_checked(["make", "-n", "-B", "netlogger"], cwd=root)
    build_commands = dry_run.stdout + dry_run.stderr
    assert re.search(r"(?:g\+\+|c\+\+|clang\+\+)", build_commands), "Makefile does not compile C++"
    assert re.search(r"-std=(?:c\+\+|gnu\+\+)17(?:\s|$)", build_commands), "Makefile does not select C++17"
    assert "src/main.cpp" in build_commands, "Makefile does not compile the extracted source"

    run_checked(["make", "-B", "netlogger"], cwd=root)
    binary = os.path.join(root, "netlogger")
    assert_elf_executable(binary)
    result = run_checked([binary, "--version"])
    assert result.stdout == "Netlogger 1.2\n", f"Unexpected netlogger output: {result.stdout!r}"


def test_log_sanitiser_clean_corpus():
    """Verify that the log sanitiser preserves all lines in the clean corpus."""
    sanitiser_path = "/home/user/log_sanitiser"
    assert os.path.isfile(sanitiser_path), f"log_sanitiser binary not found at {sanitiser_path}"

    clean_files = glob.glob("/app/corpus/clean/*.log")
    assert len(clean_files) > 0, "No clean corpus files found."

    failed_files = []

    for file_path in clean_files:
        with open(file_path, 'r') as f:
            original_lines = f.read().splitlines()

        try:
            result = subprocess.run([sanitiser_path, file_path], capture_output=True, text=True, timeout=5)
            output_lines = result.stdout.splitlines()

            if original_lines != output_lines:
                failed_files.append(os.path.basename(file_path))
        except Exception as e:
            pytest.fail(f"Failed to run sanitiser on {file_path}: {e}")

    assert not failed_files, f"{len(failed_files)} of {len(clean_files)} clean modified: {', '.join(failed_files)}"


def test_log_sanitiser_evil_corpus():
    """Verify that the log sanitiser rejects all invalid lines in the evil corpus."""
    sanitiser_path = "/home/user/log_sanitiser"
    assert os.path.isfile(sanitiser_path), f"log_sanitiser binary not found at {sanitiser_path}"

    evil_files = glob.glob("/app/corpus/evil/*.log")
    assert len(evil_files) > 0, "No evil corpus files found."

    failed_files = []

    for file_path in evil_files:
        try:
            result = subprocess.run([sanitiser_path, file_path], capture_output=True, text=True, timeout=5)
            output_lines = [line for line in result.stdout.splitlines() if line.strip()]

            if len(output_lines) > 0:
                failed_files.append(os.path.basename(file_path))
        except Exception as e:
            pytest.fail(f"Failed to run sanitiser on {file_path}: {e}")

    assert not failed_files, f"{len(failed_files)} of {len(evil_files)} evil bypassed: {', '.join(failed_files)}"


def expected_clean(ip_text, port, message):
    ip = ipaddress.ip_address(ip_text)
    private_10 = ip in ipaddress.ip_network("10.0.0.0/8")
    private_192 = ip in ipaddress.ip_network("192.168.0.0/16")
    return (private_10 or private_192) and port >= 1024 and "SPOOF" not in message and "MALFORMED" not in message


def test_log_sanitiser_generated_unseen_inputs():
    source = "/home/user/log_sanitiser.cpp"
    submitted = "/home/user/log_sanitiser"
    assert os.path.isfile(source), "log_sanitiser.cpp is missing"
    assert_elf_executable(submitted)

    fd, rebuilt = tempfile.mkstemp(prefix="rebuilt-sanitiser-")
    os.close(fd)
    os.unlink(rebuilt)
    log_path = None
    try:
        compile_result = subprocess.run(
            ["g++", "-O2", "-std=c++17", source, "-o", rebuilt],
            capture_output=True, text=True, timeout=30
        )
        assert compile_result.returncode == 0, (
            f"log_sanitiser.cpp does not compile with the required command: {compile_result.stderr}"
        )
        assert_elf_executable(rebuilt)

        records = [
            ("10.0.0.0", 1024, "CONNECT boundary accepted"),
            ("10.255.255.255", 65535, "DATA upper boundary"),
            ("192.168.0.0", 1024, "CONNECT private boundary"),
            ("192.168.255.255", 8080, "DATA private upper boundary"),
            ("9.255.255.255", 8080, "CONNECT external"),
            ("11.0.0.0", 8080, "CONNECT external"),
            ("192.167.255.255", 8080, "DATA external"),
            ("192.169.0.0", 8080, "DATA external"),
            ("10.4.5.6", 1023, "CONNECT privileged"),
            ("192.168.4.5", 1, "DATA privileged"),
            ("10.7.8.9", 9000, "CONNECT XSPOOFY marker"),
            ("192.168.7.8", 9000, "DATA MALFORMED packet"),
            ("10.8.9.10", 9000, "DATA spoof lowercase is ordinary"),
            ("192.168.9.10", 9000, "DATA malformed lowercase is ordinary"),
        ]

        rng = random.SystemRandom()
        messages = ["CONNECT generated traffic", "DATA payload received", "CONNECT SPOOF generated", "DATA xMALFORMEDx"]
        for _ in range(80):
            ip_text = ".".join(str(rng.randrange(0, 256)) for _ in range(4))
            port = rng.randrange(1, 65536)
            message = rng.choice(messages)
            records.append((ip_text, port, message))

        nonce = rng.randrange(10**8, 10**9)
        lines = []
        expected = []
        for index, (ip_text, port, message) in enumerate(records):
            line = f"[2099-12-31T23:{index % 60:02d}:{(index * 7) % 60:02d}Z] {ip_text}:{port} STATUS{nonce} {message}"
            lines.append(line)
            if expected_clean(ip_text, port, message):
                expected.append(line)

        fd, log_path = tempfile.mkstemp(prefix=f"sanitiser-unseen-{nonce}-", suffix=".log")
        with os.fdopen(fd, "w") as f:
            f.write("\n".join(lines) + "\n")

        for executable in (submitted, rebuilt):
            result = subprocess.run([executable, log_path], capture_output=True, text=True, timeout=10)
            assert result.returncode == 0, f"Sanitiser failed on generated input: {result.stderr}"
            assert result.stdout.splitlines() == expected, (
                f"Sanitiser produced incorrect output for generated mixed log using {executable}"
            )
    finally:
        if log_path and os.path.exists(log_path):
            os.unlink(log_path)
        if os.path.exists(rebuilt):
            os.unlink(rebuilt)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
