#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest


def get_actual_bad_commit():
    repo = "/home/user/pipeline"
    cmd = ["git", "-C", repo, "log", "-S", "$(('", "--format=%H", "--reverse"]
    # Correct the search argument without embedding it ambiguously above.
    cmd[4] = "$(('"[:-1]
    try:
        out = subprocess.check_output(cmd, text=True).strip().splitlines()
        return out[0] if out else None
    except subprocess.CalledProcessError:
        return None


def test_bad_commit_logged():
    log_path = "/home/user/bad_commit.log"
    assert os.path.isfile(log_path), f"File {log_path} is missing."

    with open(log_path, "r") as f:
        student_commit = f.read().strip()

    actual_commit = get_actual_bad_commit()
    assert actual_commit is not None, "Could not determine the actual bad commit from the repository."
    assert re.fullmatch(r"[0-9a-f]{40}", student_commit), "bad_commit.log must contain a full 40-character SHA-1."
    assert student_commit == actual_commit, f"Expected bad commit {actual_commit}, but got {student_commit}."


def run_script(script, video):
    return subprocess.run(
        [script, video], text=True, capture_output=True, timeout=20, check=False
    )


def test_video_patch_and_analysis_log():
    script_path = "/home/user/pipeline/process_video.sh"
    log_path = "/home/user/video_analysis.log"
    video_path = "/app/incident_capture.mp4"

    assert os.path.isfile(script_path), f"Pipeline script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Pipeline script {script_path} is not executable."
    assert os.path.isfile(video_path), f"Video fixture {video_path} is missing."
    assert os.path.isfile(log_path), f"File {log_path} is missing."

    syntax = subprocess.run(["bash", "-n", script_path], capture_output=True, text=True)
    assert syntax.returncode == 0, f"process_video.sh has invalid Bash syntax: {syntax.stderr}"

    source = Path(script_path).read_text()
    non_comment_source = "\n".join(
        line for line in source.splitlines() if not line.lstrip().startswith("#")
    )
    assert re.search(r"\b(?:bc|awk)\b", non_comment_source), "The patch must use bc or awk for the large-integer calculation."
    assert not re.search(r"accumulator\s*=\s*\$\(\(", non_comment_source), "The accumulator still uses Bash arithmetic."

    result = run_script(script_path, video_path)
    assert result.returncode == 0, f"process_video.sh failed: {result.stderr}"

    content = Path(log_path).read_text()
    expected_val = str(9223372036854775800 + 15)
    assert expected_val in content, f"Expected final cumulative intensity diff {expected_val} not found in {log_path}."
    assert "-9223372036854775807" not in content, "Found overflowed negative value in the analysis log."
    assert content == result.stdout, "video_analysis.log is not the standard output produced by the current patched script."

    # Exercise the submitted calculation with fresh operands so a fixed output
    # or a prewritten log cannot substitute for repairing the arithmetic.
    left = 10**24 + secrets.randbelow(10**12)
    right = 10**20 + secrets.randbelow(10**10)
    mutated = source
    mutated, n1 = re.subn(r"(?m)^accumulator=\d+\s*$", f"accumulator={left}", mutated, count=1)
    mutated, n2 = re.subn(r"(?m)^frame_diff=\d+\s*$", f"frame_diff={right}", mutated, count=1)
    assert n1 == 1 and n2 == 1, "The required accumulator and frame_diff calculation was removed rather than repaired."

    with tempfile.TemporaryDirectory() as td:
        probe = os.path.join(td, "process_video.sh")
        Path(probe).write_text(mutated)
        os.chmod(probe, 0o755)
        probe_result = run_script(probe, video_path)

    assert probe_result.returncode == 0, f"Patched calculation failed on large operands: {probe_result.stderr}"
    assert f"Frame 144: {left + right}" in probe_result.stdout, "Patched script does not correctly calculate fresh arbitrarily large integer operands."


def invoke_sanitizer(script, path):
    return subprocess.run(
        ["bash", script, path], capture_output=True, text=True, timeout=10
    ).returncode


def test_adversarial_sanitizer():
    sanitizer_script = "/home/user/sanitizer.sh"
    assert os.path.isfile(sanitizer_script), f"Sanitizer script {sanitizer_script} is missing."

    syntax = subprocess.run(["bash", "-n", sanitizer_script], capture_output=True, text=True)
    assert syntax.returncode == 0, f"sanitizer.sh has invalid Bash syntax: {syntax.stderr}"

    evil_corpus_path = "/home/user/corpora/evil/"
    clean_corpus_path = "/home/user/corpora/clean/"
    evil_files = [os.path.join(evil_corpus_path, f) for f in os.listdir(evil_corpus_path) if os.path.isfile(os.path.join(evil_corpus_path, f))]
    clean_files = [os.path.join(clean_corpus_path, f) for f in os.listdir(clean_corpus_path) if os.path.isfile(os.path.join(clean_corpus_path, f))]

    evil_bypassed = [os.path.basename(f) for f in evil_files if invoke_sanitizer(sanitizer_script, f) != 1]
    clean_modified = [os.path.basename(f) for f in clean_files if invoke_sanitizer(sanitizer_script, f) != 0]

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msgs.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_modified)}")
    if error_msgs:
        pytest.fail(" | ".join(error_msgs))

    # Generate fresh hidden traces at verification time. Expected outcomes are
    # derived from strict monotonicity rather than copied from a visible corpus.
    base = 10**25 + secrets.randbelow(10**15)
    inc1 = 1 + secrets.randbelow(10**8)
    inc2 = 1 + secrets.randbelow(10**8)
    clean_texts = [
        f"Frame 1 {base}\nFrame 2 {base + inc1}\nFrame 3 {base + inc1 + inc2}\n",
        f"Frame 10 0\nFrame 11 {inc1}\nFrame 12 {inc1 + inc2}\n",
    ]
    evil_texts = [
        f"Frame 1 {base}\nFrame 2 {base + inc1}\nFrame 3 -{base}\n",
        f"Frame 1 {base}\nFrame 2 {base + inc1}\nFrame 3 {base - 1}\n",
        f"Frame 1 {base}\nFrame 2 {base + inc1}\nFrame 3 {base + inc1}\n",
    ]

    with tempfile.TemporaryDirectory() as td:
        cases = [(text, 0) for text in clean_texts] + [(text, 1) for text in evil_texts]
        secrets.SystemRandom().shuffle(cases)
        for text, expected in cases:
            path = os.path.join(td, secrets.token_hex(12))
            Path(path).write_text(text)
            actual = invoke_sanitizer(sanitizer_script, path)
            assert actual == expected, f"Sanitizer returned {actual}, expected {expected}, for trace:\n{text}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
