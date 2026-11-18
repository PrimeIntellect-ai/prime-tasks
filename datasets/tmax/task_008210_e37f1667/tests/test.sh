#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import tempfile

import pytest

SCANNER_DIR = "/home/user/scanner"
SOURCE_PATH = os.path.join(SCANNER_DIR, "src/main.rs")
EXE_PATH = os.path.join(SCANNER_DIR, "target/release/scanner")
CONFIG_PATH = "/home/user/backup_config.conf"
OUTPUT_PATH = "/home/user/final_sizes.txt"


def compute_dir_size_like_rust(path):
    total_size = 0
    try:
        for entry in os.scandir(path):
            entry_stat = entry.stat(follow_symlinks=False)
            if stat.S_ISDIR(entry_stat.st_mode):
                total_size += compute_dir_size_like_rust(entry.path)
            else:
                total_size += entry_stat.st_size
    except Exception:
        pass
    return total_size


def configured_dirs():
    expected_dirs = []
    if os.path.isfile(CONFIG_PATH):
        with open(CONFIG_PATH, "r") as config:
            for line in config:
                line = line.strip()
                if line.startswith("SCAN_DIR="):
                    expected_dirs.append(line.split("=", 1)[1])
    return expected_dirs


def expected_stdout(paths):
    return "".join(
        f"{path} - Total size: {compute_dir_size_like_rust(path)} bytes\n"
        for path in paths
    )


def run_scanner(paths, timeout=5):
    return subprocess.run(
        [EXE_PATH, *paths],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
        check=False,
    )


def assert_scanner_handles_symlinks():
    with tempfile.TemporaryDirectory(prefix="scanner-verifier-") as root:
        first = os.path.join(root, "first")
        second = os.path.join(root, "second")
        nested = os.path.join(first, "nested")
        os.makedirs(nested)
        os.makedirs(second)

        with open(os.path.join(first, "alpha.bin"), "wb") as output:
            output.write(b"A" * 1237)
        with open(os.path.join(nested, "beta.bin"), "wb") as output:
            output.write(b"B" * 4099)
        with open(os.path.join(second, "gamma.bin"), "wb") as output:
            output.write(b"C" * 811)

        # Include a directory cycle, a link outside its containing tree, and a
        # broken link. Each link itself must be counted, but none followed.
        os.symlink(first, os.path.join(nested, "back_to_first"))
        os.symlink(second, os.path.join(first, "link_to_second"))
        os.symlink("missing-target", os.path.join(second, "broken_link"))

        paths = [first, second]
        expected = expected_stdout(paths)
        try:
            result = run_scanner(paths)
        except subprocess.TimeoutExpired:
            pytest.fail("scanner timed out while scanning a symlink loop")

        assert result.returncode == 0, (
            f"scanner exited with {result.returncode}; stderr:\n{result.stderr}"
        )
        assert result.stdout == expected, (
            "scanner produced incorrect output for verifier-created directories. "
            f"Expected:\n{expected}Actual:\n{result.stdout}"
        )


def test_rust_code_fixed():
    assert os.path.isfile(SOURCE_PATH), f"Rust source file missing: {SOURCE_PATH}"
    with open(SOURCE_PATH, "r") as source:
        assert source.read().strip(), "Rust source file is empty"


def test_executable_built():
    assert os.path.isfile(EXE_PATH), (
        f"Compiled executable missing: {EXE_PATH}. Did you run 'cargo build --release'?"
    )
    assert os.access(EXE_PATH, os.X_OK), f"The file {EXE_PATH} is not executable."
    with open(EXE_PATH, "rb") as executable:
        assert executable.read(4) == b"\x7fELF", (
            f"{EXE_PATH} is not a compiled Linux executable"
        )


def test_final_sizes_output():
    assert os.path.isfile(OUTPUT_PATH), f"Output file missing: {OUTPUT_PATH}"

    with open(OUTPUT_PATH, "r") as output:
        raw_content = output.read()
    content = raw_content.strip()
    lines = [line.strip() for line in content.split("\n") if line.strip()]

    expected_dirs = configured_dirs()
    assert expected_dirs, "Could not find any SCAN_DIR entries in the config file."

    expected_results = {
        directory: compute_dir_size_like_rust(directory)
        for directory in expected_dirs
    }
    for directory, expected_size in expected_results.items():
        expected_line = f"{directory} - Total size: {expected_size} bytes"
        assert expected_line in lines, (
            f"Expected output line not found: '{expected_line}'. "
            f"Actual output:\n{content}"
        )

    assert len(lines) == len(expected_dirs), (
        f"Output file has {len(lines)} lines, but expected {len(expected_dirs)}."
    )

    try:
        result = run_scanner(expected_dirs)
    except subprocess.TimeoutExpired:
        pytest.fail("built scanner timed out on the configured directories")
    assert result.returncode == 0, (
        f"built scanner exited with {result.returncode}; stderr:\n{result.stderr}"
    )
    assert result.stdout == expected_stdout(expected_dirs), (
        "built scanner does not produce the required configured-directory output"
    )
    assert raw_content == result.stdout, (
        "final_sizes.txt is not the exact standard output produced by the scanner "
        "for all configured directories"
    )


def test_existing_executable_ignores_symlink_directories():
    assert_scanner_handles_symlinks()


def test_rust_source_rebuilds_to_working_scanner():
    # Force Cargo to compile the submitted source, then exercise that resulting
    # binary so a separately fabricated release-path executable is insufficient.
    subprocess.run(
        ["cargo", "clean"],
        cwd=SCANNER_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
        timeout=30,
    )
    build = subprocess.run(
        ["cargo", "build", "--release"],
        cwd=SCANNER_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
        timeout=120,
    )
    assert build.returncode == 0, (
        "submitted Rust source failed to build with cargo build --release:\n"
        f"{build.stdout}{build.stderr}"
    )
    assert os.path.isfile(EXE_PATH) and os.access(EXE_PATH, os.X_OK), (
        "cargo build --release did not produce an executable scanner"
    )
    assert_scanner_handles_symlinks()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
