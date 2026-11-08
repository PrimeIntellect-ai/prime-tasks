#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import secrets
import stat
import subprocess
import tempfile
from collections import Counter

PIPELINE = "/home/user/pipeline"
SCRIPT = os.path.join(PIPELINE, "run_pipeline_fixed.sh")
DATA = os.path.join(PIPELINE, "data")
PARSER = os.path.join(PIPELINE, "log_parser")
OUTPUT = os.path.join(PIPELINE, "output_final.txt")


def run_script(timeout=30):
    env = os.environ.copy()
    # A correct script must replace the inherited legacy setting with the modern path.
    env["LD_LIBRARY_PATH"] = os.path.join(PIPELINE, "lib_legacy")
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    return subprocess.run(
        [SCRIPT],
        cwd=PIPELINE,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def read_output():
    assert os.path.isfile(OUTPUT), f"The final output file {OUTPUT} does not exist."
    with open(OUTPUT, "r") as f:
        return f.read().splitlines()


def test_fixed_pipeline_end_to_end():
    # Preserve the original verifier's script assertions.
    assert os.path.isfile(SCRIPT), f"The fixed script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"The fixed script {SCRIPT} is not executable."
    assert not os.path.islink(SCRIPT), "The fixed pipeline must be an actual script, not a symlink."
    with open(SCRIPT, "r") as f:
        content = f.read()
    assert content.startswith("#!"), "The fixed pipeline is not a script with a shebang."
    assert "lib_modern" in content, "The fixed script does not appear to set LD_LIBRARY_PATH to the modern library directory."
    assert "lib_legacy" not in content, "The fixed script still references the legacy library directory."
    assert "FATAL_CORRUPTION" in content, "The fixed script does not contain the check for 'FATAL_CORRUPTION'."
    assert "Skipping corrupt file:" in content, "The fixed script does not print the required corrupt-file message."

    backup_root = tempfile.mkdtemp(prefix="pipeline-verifier-")
    backup_data = os.path.join(backup_root, "data")
    backup_parser = os.path.join(backup_root, "log_parser")
    shutil.copytree(DATA, backup_data)
    shutil.copy2(PARSER, backup_parser)
    baseline_output = None

    try:
        # Execute against the supplied fixtures, retaining all original output assertions.
        result = run_script()
        assert result.returncode == 0, f"Fixed script failed on supplied data. stdout={result.stdout!r} stderr={result.stderr!r}"
        assert "Skipping corrupt file:" in result.stdout and "file_6.log" in result.stdout, "The script did not report skipping file_6.log."
        lines = read_output()
        assert len(lines) == 10, f"Expected exactly 10 processed lines in {OUTPUT}, but found {len(lines)}."
        for line in lines:
            assert line.startswith("PROCESSED: Data line "), f"Unexpected line format in output: {line}"
            assert "FATAL_CORRUPTION" not in line, "Corrupted data was not filtered out of the final output."
        expected_original = {
            f"PROCESSED: Data line {letter} for file {i}"
            for i in range(1, 6)
            for letter in ("A", "B")
        }
        missing = expected_original - set(lines)
        assert not missing, f"Missing expected lines in the final output: {missing}"
        with open(OUTPUT, "rb") as f:
            baseline_output = f.read()

        # Replace the fixed fixtures with unpredictable inputs and an instrumented
        # parser whose split writes expose unsafe concurrent appends.
        shutil.rmtree(DATA)
        os.mkdir(DATA)
        token = secrets.token_hex(12)
        valid_files = []
        expected_dynamic = []
        for i in range(18):
            name = f"dynamic_{i}_{token}.log"
            valid_files.append(name)
            path = os.path.join(DATA, name)
            with open(path, "w") as f:
                for j in range(7):
                    value = f"{token}-file-{i}-line-{j}"
                    f.write(value + "\n")
                    expected_dynamic.append("PROCESSED: " + value)

        corrupt_name = f"corrupt_{token}.log"
        with open(os.path.join(DATA, corrupt_name), "w") as f:
            f.write(f"before-{token}\n")
            f.write("FATAL_CORRUPTION\n")
            f.write(f"after-{token}\n")

        invocation_log = os.path.join(backup_root, "parser-invocations")
        wrapper = f'''#!/usr/bin/env python3
import os
import sys
import time

path = os.environ.get("LD_LIBRARY_PATH", "")
if "/home/user/pipeline/lib_modern" not in path or "lib_legacy" in path:
    sys.stderr.write("wrong libutils environment\\n")
    sys.exit(91)
if len(sys.argv) != 2:
    sys.exit(2)
name = os.path.basename(sys.argv[1])
fd = os.open({invocation_log!r}, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
os.write(fd, (name + "\\n").encode())
os.close(fd)
with open(sys.argv[1], "r") as src:
    for raw in src:
        value = raw.rstrip("\\n")
        if "FATAL_CORRUPTION" in value:
            sys.stderr.write("Segmentation fault (core dumped)\\n")
            sys.exit(139)
        os.write(1, b"PROCESSED: ")
        time.sleep(0.01)
        os.write(1, (value + "\\n").encode())
'''
        with open(PARSER, "w") as f:
            f.write(wrapper)
        os.chmod(PARSER, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR | stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)

        result = run_script(timeout=45)
        assert result.returncode == 0, f"Fixed script failed dynamic execution. stdout={result.stdout!r} stderr={result.stderr!r}"
        assert "Skipping corrupt file:" in result.stdout and corrupt_name in result.stdout, "The dynamically generated corrupt file was not reported as skipped."
        assert "Segmentation fault" not in result.stderr, "The corrupt input reached log_parser instead of being validated first."

        dynamic_lines = read_output()
        assert Counter(dynamic_lines) == Counter(expected_dynamic), "Dynamic output is missing, duplicated, fabricated, or interleaved; concurrent parser output must be assembled safely."

        with open(invocation_log, "r") as f:
            invoked = [line.strip() for line in f if line.strip()]
        invoked_counts = Counter(invoked)
        assert corrupt_name not in invoked_counts, "The corrupt file was passed to log_parser; validation must happen before invocation."
        assert set(valid_files).issubset(invoked_counts), "The fixed script did not invoke log_parser for every valid dynamic input file."
    finally:
        if os.path.exists(DATA):
            shutil.rmtree(DATA)
        shutil.copytree(backup_data, DATA)
        shutil.copy2(backup_parser, PARSER)
        if baseline_output is not None:
            with open(OUTPUT, "wb") as f:
                f.write(baseline_output)
        shutil.rmtree(backup_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
