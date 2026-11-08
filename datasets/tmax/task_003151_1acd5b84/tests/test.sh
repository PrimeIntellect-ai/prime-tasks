#!/bin/bash
set -u
mkdir -p /logs/verifier
reward=0
trap 'echo "$reward" > /logs/verifier/reward.txt' EXIT

# Restore the original payload set so deleting the triggering input cannot make a
# hardcoded fallback answer pass.
mkdir -p /home/user/suspicious_data
find /home/user/suspicious_data -mindepth 1 -maxdepth 1 -delete
for i in $(seq -w 1 50); do
    printf 'VALID_DATA_%s\n' "$i" > "/home/user/suspicious_data/payload_${i}.dat"
done
printf 'DEADBEEF\n' > /home/user/suspicious_data/payload_37.dat

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import glob
import json
import os
import secrets
import stat
import subprocess

import pytest


def get_expected_crashing_file() -> str:
    """Derive the answer from an actually present payload; there is no fallback."""
    data_dir = "/home/user/suspicious_data"
    assert os.path.isdir(data_dir), f"Payload directory {data_dir} is missing."

    matches = []
    for filepath in glob.glob(os.path.join(data_dir, "*.dat")):
        if filepath.endswith("_extracted.dat"):
            continue
        try:
            with open(filepath, "rb") as f:
                if f.read(4) == b"DEAD":
                    matches.append(os.path.abspath(filepath))
        except OSError:
            continue

    assert len(matches) == 1, (
        "Expected exactly one present payload containing the panic-triggering "
        f"magic bytes, found {matches!r}."
    )
    return matches[0]


def test_crashing_file_identified_correctly():
    result_file = "/home/user/crashing_file.txt"
    assert os.path.isfile(result_file), f"The result file {result_file} does not exist."

    with open(result_file, "r") as f:
        student_answer = f.read().strip()

    expected_file = get_expected_crashing_file()
    assert student_answer == expected_file, (
        f"Incorrect crashing file identified.\n"
        f"Expected: {expected_file}\n"
        f"Found: {student_answer}"
    )


def test_analyze_fixed_script_exists_and_executable():
    script_path = "/home/user/analyze_fixed.sh"
    assert os.path.isfile(script_path), f"The fixed script {script_path} does not exist."

    st = os.stat(script_path)
    is_executable = bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH))
    assert is_executable, f"The fixed script {script_path} is not executable."


def test_analyze_fixed_script_execution_and_termination():
    script_path = "/home/user/analyze_fixed.sh"
    data_dir = "/home/user/suspicious_data"
    extractor_path = "/home/user/bin/data_extractor"

    if not os.access(script_path, os.X_OK):
        pytest.fail(f"Cannot execute {script_path} because it lacks execute permissions.")

    # Use fresh, unpredictable payload names and an instrumented extractor. This
    # verifies that the wrapper really invokes data_extractor exactly once for
    # every original input, continues after a panic, and never feeds generated or
    # pre-existing *_extracted.dat files back into the extractor.
    token = secrets.token_hex(8)
    call_log = f"/tmp/extractor_calls_{token}.jsonl"

    for entry in os.scandir(data_dir):
        if entry.is_dir(follow_symlinks=False):
            subprocess.run(["rm", "-rf", entry.path], check=True)
        else:
            os.unlink(entry.path)

    originals = []
    crashing = None
    for index in range(8):
        path = os.path.join(data_dir, f"case_{token}_{index:02d}.dat")
        if index == 3:
            contents = b"DEAD malformed test payload\n"
            crashing = path
        else:
            contents = f"VALID_{token}_{index}\n".encode()
        with open(path, "wb") as f:
            f.write(contents)
        originals.append(path)

    decoy = os.path.join(data_dir, f"decoy_{token}_extracted.dat")
    with open(decoy, "wb") as f:
        f.write(b"preexisting-decoy\n")

    spy = f'''#!/usr/bin/env python3
import json
import os
import sys

if len(sys.argv) < 2:
    sys.exit(1)
path = os.path.abspath(sys.argv[1])
with open({call_log!r}, "a", encoding="utf-8") as log:
    log.write(json.dumps(path) + "\\n")
try:
    with open(path, "rb") as source:
        prefix = source.read(4)
except OSError:
    sys.exit(1)
if prefix == b"DEAD":
    print("thread 'main' panicked at simulated ParseError", file=sys.stderr)
    os.abort()
with open(path + ".out", "w", encoding="utf-8") as output:
    output.write("verified:" + os.path.basename(path) + "\\n")
sys.exit(0)
'''
    with open(extractor_path, "w", encoding="utf-8") as f:
        f.write(spy)
    os.chmod(extractor_path, 0o755)

    try:
        proc = subprocess.run(
            [script_path],
            cwd="/home/user",
            timeout=10,
            capture_output=True,
            text=True,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(
            f"Execution of {script_path} timed out after 10 seconds. "
            "The infinite loop bug is likely still present."
        )

    assert proc.returncode == 0, (
        f"{script_path} did not terminate cleanly (exit {proc.returncode}).\n"
        f"stdout: {proc.stdout}\nstderr: {proc.stderr}"
    )

    assert os.path.isfile(call_log), "The fixed script never invoked data_extractor."
    with open(call_log, "r", encoding="utf-8") as f:
        calls = [json.loads(line) for line in f if line.strip()]

    expected_counts = collections.Counter(map(os.path.abspath, originals))
    actual_counts = collections.Counter(calls)
    assert actual_counts == expected_counts, (
        "The fixed script must invoke data_extractor exactly once for every "
        f"original payload and for no generated files. Expected {expected_counts}, "
        f"found {actual_counts}."
    )

    valid_originals = [path for path in originals if path != crashing]
    for path in valid_originals:
        extracted = path + "_extracted.dat"
        assert os.path.isfile(extracted), f"Missing extracted output for {path}."
        with open(extracted, "r", encoding="utf-8") as f:
            assert f.read() == "verified:" + os.path.basename(path) + "\n"
        assert not os.path.exists(path), f"Processed original was not removed: {path}"

    # Preserve the original verifier's assertion that extraction produced files.
    extracted_files = glob.glob(os.path.join(data_dir, "*_extracted.dat"))
    assert len(extracted_files) > 0, (
        f"The script {script_path} completed, but no *_extracted.dat files were found."
    )

    assert crashing is not None and os.path.isfile(crashing), (
        "The malformed input should remain because the extractor produced no output."
    )
    assert not os.path.exists(crashing + "_extracted.dat")
    with open(decoy, "rb") as f:
        assert f.read() == b"preexisting-decoy\n", (
            "A pre-existing _extracted.dat file was modified or processed."
        )


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    reward=1
fi
exit 0
