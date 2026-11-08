#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import os
import re
import secrets
import shutil
import struct
import subprocess
from pathlib import Path

import pytest

ARCHIVE_PATH = "/home/user/incremental.archive"
RAW_LOGS_DIR = "/home/user/raw_logs"
LAST_RUN_FILE = "/home/user/last_run.txt"
ARCHIVER_DIR = Path("/home/user/archiver")
RUN_SCRIPT = Path("/home/user/run_backup.sh")
MARKER = Path("/tmp/archiver_tool_marker")


def get_expected_data():
    if not os.path.exists(LAST_RUN_FILE):
        pytest.fail(f"Missing {LAST_RUN_FILE}")

    with open(LAST_RUN_FILE, "r") as f:
        try:
            last_run_time = int(f.read().strip())
        except ValueError:
            pytest.fail(f"Invalid timestamp in {LAST_RUN_FILE}")

    if not os.path.exists(RAW_LOGS_DIR):
        pytest.fail(f"Missing {RAW_LOGS_DIR}")

    expected_data = {}
    for filename in os.listdir(RAW_LOGS_DIR):
        if not filename.endswith(".log"):
            continue

        filepath = os.path.join(RAW_LOGS_DIR, filename)
        mtime = os.stat(filepath).st_mtime

        if mtime > last_run_time:
            with open(filepath, "r") as f:
                lines = f.readlines()

            critical_lines = [line for line in lines if "CRITICAL" in line]
            if critical_lines:
                expected_data[filename] = "".join(critical_lines).encode("utf-8")
            else:
                expected_data[filename] = b""

    return expected_data


def test_00_build_and_run_backup_pipeline():
    assert ARCHIVER_DIR.is_dir(), "Missing Rust Cargo project /home/user/archiver"
    cargo_toml = ARCHIVER_DIR / "Cargo.toml"
    assert cargo_toml.is_file(), "Missing /home/user/archiver/Cargo.toml"

    rust_files = list(ARCHIVER_DIR.rglob("*.rs"))
    assert rust_files, "The archiver project contains no Rust source files"
    rust_source = "\n".join(p.read_text(errors="replace") for p in rust_files)
    command_pattern = re.compile(
        r"(?:std\s*::\s*process\s*::\s*)?Command\s*::\s*new\s*\(\s*\"[^\"]*(?:awk|sed)\"",
        re.DOTALL,
    )
    assert command_pattern.search(rust_source), (
        "Rust source must invoke awk or sed through std::process::Command"
    )

    assert RUN_SCRIPT.is_file(), "Missing /home/user/run_backup.sh"
    script_text = RUN_SCRIPT.read_text(errors="replace")
    active_script = "\n".join(
        line for line in script_text.splitlines() if not line.lstrip().startswith("#")
    )
    assert "|" in active_script, "run_backup.sh must pipeline file paths to the archiver"
    assert re.search(r"cargo|/home/user/archiver|target/", active_script), (
        "run_backup.sh does not invoke the Rust archiver project or its compiled binary"
    )

    build = subprocess.run(
        ["cargo", "build", "--quiet", "--manifest-path", str(cargo_toml)],
        cwd=str(ARCHIVER_DIR),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert build.returncode == 0, f"Rust archiver failed to build:\n{build.stderr}"

    # Replace the known setup data with unpredictable verification-time inputs so
    # a precomputed archive cannot pass. The boundary file checks strict mtime use.
    shutil.rmtree(RAW_LOGS_DIR, ignore_errors=True)
    os.makedirs(RAW_LOGS_DIR, mode=0o777)
    os.chmod(RAW_LOGS_DIR, 0o777)
    cutoff = 1800000000
    Path(LAST_RUN_FILE).write_text(f"{cutoff}\n")
    os.chmod(LAST_RUN_FILE, 0o666)

    token = secrets.token_hex(8)
    cases = [
        (f"service_{token}.log", cutoff + 11,
         "INFO: generated verification record\n"
         f"CRITICAL: dynamic failure {secrets.token_hex(12)}\n"
         "WARN: ignored record\n"
         f"CRITICAL: dynamic retry {secrets.token_hex(12)}\n"),
        (f"empty_{token}.log", cutoff + 17,
         "INFO: no matching payload here\ncritical: wrong case\n"),
        (f"boundary_{token}.log", cutoff,
         "CRITICAL: strict-boundary file must be excluded\n"),
        (f"old_{token}.log", cutoff - 1,
         "CRITICAL: old file must be excluded\n"),
        (f"wrong_extension_{token}.txt", cutoff + 20,
         "CRITICAL: non-log file must be excluded\n"),
    ]
    for name, mtime, contents in cases:
        path = Path(RAW_LOGS_DIR) / name
        path.write_text(contents)
        os.utime(path, (mtime, mtime))
        os.chmod(path, 0o666)

    if os.path.lexists(ARCHIVE_PATH):
        os.unlink(ARCHIVE_PATH)

    wrapper_dir = Path("/tmp/archiver-tool-wrappers")
    shutil.rmtree(wrapper_dir, ignore_errors=True)
    wrapper_dir.mkdir()
    for tool in ("awk", "sed"):
        wrapper = wrapper_dir / tool
        wrapper.write_text(
            "#!/bin/sh\n"
            f"printf '%s\\n' '{tool}' >> \"$ARCHIVER_TOOL_MARKER\"\n"
            f"exec /usr/bin/{tool} \"$@\"\n"
        )
        wrapper.chmod(0o755)
    MARKER.unlink(missing_ok=True)

    env = os.environ.copy()
    env["PATH"] = f"{wrapper_dir}:{env.get('PATH', '')}"
    env["ARCHIVER_TOOL_MARKER"] = str(MARKER)
    run = subprocess.run(
        ["bash", str(RUN_SCRIPT)],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert run.returncode == 0, (
        f"run_backup.sh failed with exit code {run.returncode}\n"
        f"stdout:\n{run.stdout}\nstderr:\n{run.stderr}"
    )
    assert MARKER.is_file(), "Executing the backup did not invoke awk or sed"
    invocations = [line for line in MARKER.read_text().splitlines() if line]
    assert len(invocations) >= 2, (
        "The archiver must execute awk or sed for each qualifying log file"
    )


def test_archive_exists():
    assert os.path.isfile(ARCHIVE_PATH), f"Archive file {ARCHIVE_PATH} does not exist."


def test_archive_contents():
    expected_data = get_expected_data()

    assert os.path.isfile(ARCHIVE_PATH), f"Archive file {ARCHIVE_PATH} does not exist."

    found_files = set()

    with open(ARCHIVE_PATH, "rb") as f:
        while True:
            len_bytes = f.read(2)
            if not len_bytes:
                break

            assert len(len_bytes) == 2, "Unexpected EOF while reading filename length."
            name_len = struct.unpack("<H", len_bytes)[0]

            filename_bytes = f.read(name_len)
            assert len(filename_bytes) == name_len, "Unexpected EOF while reading filename."
            filename = filename_bytes.decode("utf-8")

            size_bytes = f.read(4)
            assert len(size_bytes) == 4, "Unexpected EOF while reading compressed size."
            comp_size = struct.unpack("<I", size_bytes)[0]

            comp_data = f.read(comp_size)
            assert len(comp_data) == comp_size, "Unexpected EOF while reading compressed data."

            try:
                decompressed = gzip.decompress(comp_data)
            except gzip.BadGzipFile:
                pytest.fail(f"Data for {filename} is not valid Gzip.")

            assert filename in expected_data, f"Found unexpected file '{filename}' in archive."
            assert decompressed == expected_data[filename], f"Content mismatch for '{filename}'. Expected {expected_data[filename]}, got {decompressed}"

            found_files.add(filename)

    expected_files = set(expected_data.keys())
    missing_files = expected_files - found_files
    assert not missing_files, f"Archive is missing expected files: {missing_files}"

    extra_files = found_files - expected_files
    assert not extra_files, f"Archive contains extra files: {extra_files}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
