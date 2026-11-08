#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import glob
import os
import re
import secrets
import subprocess
import sys

SCRIPT_PATH = "/home/user/parse_build.py"
MERGED_PATH = "/home/user/merged_build.log"
MISSING_PATH = "/home/user/missing_lib.txt"
LOG_GLOB = "/home/user/build_logs/worker_*.log"


def run_script():
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"parse_build.py exited with status {result.returncode}. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )


def test_00_script_generates_outputs_when_executed():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    for path in (MERGED_PATH, MISSING_PATH):
        if os.path.exists(path):
            os.remove(path)
    run_script()
    assert os.path.isfile(MERGED_PATH), "Executing parse_build.py did not create merged_build.log."
    assert os.path.isfile(MISSING_PATH), "Executing parse_build.py did not create missing_lib.txt."


def test_parse_build_script_exists():
    script_path = "/home/user/parse_build.py"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."


def test_missing_lib_extracted_correctly():
    missing_lib_path = "/home/user/missing_lib.txt"
    assert os.path.isfile(missing_lib_path), f"The file {missing_lib_path} does not exist."

    with open(missing_lib_path, "r") as f:
        content = f.read().strip()

    assert content == "TelemetryEngineX", f"Expected missing_lib.txt to contain 'TelemetryEngineX', but got '{content}'"


def test_merged_build_log():
    merged_log_path = "/home/user/merged_build.log"
    assert os.path.isfile(merged_log_path), f"The file {merged_log_path} does not exist."

    # Read all original logs to get the expected lines
    original_lines = []
    log_files = glob.glob("/home/user/build_logs/worker_*.log")
    for log_file in log_files:
        with open(log_file, "r") as f:
            original_lines.extend(f.read().splitlines())

    # Read the merged log
    with open(merged_log_path, "r") as f:
        merged_lines = f.read().splitlines()

    # Check that the number of lines matches
    assert len(merged_lines) == len(original_lines), f"Expected {len(original_lines)} lines in merged log, but got {len(merged_lines)}."

    # Check that the merged log contains all original lines
    assert sorted(merged_lines) == sorted(original_lines), "The merged log does not contain the exact same lines as the original logs."

    # Check that the merged log is sorted by timestamp
    # The timestamp is at the beginning of each line, so lexicographical sorting of lines
    # should match the chronological sorting since the format is [YYYY-MM-DDTHH:MM:SS.mmmZ]
    expected_sorted_lines = sorted(original_lines)
    assert merged_lines == expected_sorted_lines, "The merged log is not chronologically sorted."


def test_script_processes_fresh_logs_and_derives_library_name():
    original_logs = {}
    for path in glob.glob(LOG_GLOB):
        with open(path, "rb") as f:
            original_logs[path] = f.read()

    library_name = "VerifierLib_" + secrets.token_hex(8)
    dynamic_logs = {
        "/home/user/build_logs/worker_41.log": [
            "[2026-07-19T09:15:05.401Z] [Worker-41] Linking target randomized_app",
            "[2026-07-19T09:15:01.007Z] [Worker-41] Compiling alpha.cpp",
        ],
        "/home/user/build_logs/worker_7.log": [
            f"[2026-07-19T09:15:06.777Z] [Worker-7] ld: library not found for -l{library_name}",
            "[2026-07-19T09:15:02.215Z] [Worker-7] Resolving dependencies",
        ],
        "/home/user/build_logs/worker_103.log": [
            "[2026-07-19T09:15:04.099Z] [Worker-103] Normal flag mention: -lNotTheMissingLibrary",
            "[2026-07-19T09:15:03.808Z] [Worker-103] Compiling beta.cpp",
            "[2026-07-19T09:15:07.900Z] [Worker-103] Build failed.",
        ],
    }

    all_dynamic_lines = [line for lines in dynamic_logs.values() for line in lines]
    expected_merged = sorted(all_dynamic_lines, key=lambda line: line.split("]", 1)[0] + "]")
    linker_lines = [line for line in all_dynamic_lines if "ld: library not found for -l" in line]
    assert len(linker_lines) == 1
    match = re.search(r"ld: library not found for -l([^\s]+)", linker_lines[0])
    assert match is not None
    expected_library = match.group(1)

    try:
        for path in glob.glob(LOG_GLOB):
            os.remove(path)
        for path, lines in dynamic_logs.items():
            with open(path, "w") as f:
                f.write("\n".join(lines) + "\n")

        for path in (MERGED_PATH, MISSING_PATH):
            if os.path.exists(path):
                os.remove(path)

        run_script()

        with open(MERGED_PATH, "r") as f:
            actual_merged = f.read().splitlines()
        with open(MISSING_PATH, "r") as f:
            actual_library = f.read().strip()

        assert actual_merged == expected_merged, (
            "parse_build.py did not merge and chronologically sort the fresh worker logs correctly."
        )
        assert actual_library == expected_library, (
            f"Expected dynamically derived library {expected_library!r}, got {actual_library!r}."
        )
    finally:
        for path in glob.glob(LOG_GLOB):
            os.remove(path)
        for path, data in original_logs.items():
            with open(path, "wb") as f:
                f.write(data)
        # Restore outputs for the original task data when possible.
        if os.path.isfile(SCRIPT_PATH):
            subprocess.run(
                [sys.executable, SCRIPT_PATH],
                cwd="/home/user",
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=15,
                check=False,
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
