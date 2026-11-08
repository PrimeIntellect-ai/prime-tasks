#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import re
import secrets
import string
import subprocess
import tempfile

import pytest

RL_PATH = "/home/user/rate_limiter/rl_check"
VALIDATOR = "/home/user/validate_job.sh"
MASTER_JOB = "/app/master_job.json"
OUTPUT_FRAME = "/home/user/output_frame.jpg"
BENCHMARK = "/home/user/benchmark.txt"


def run(cmd, **kwargs):
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    kwargs.setdefault("timeout", 15)
    return subprocess.run(cmd, **kwargs)


def test_rl_check_compiled_and_executable():
    assert os.path.isfile(RL_PATH), f"Compiled executable {RL_PATH} is missing."
    assert os.access(RL_PATH, os.X_OK), f"File {RL_PATH} is not executable."


def test_rate_limiter_sources_build_and_behavior():
    build = run(["make", "-B"], cwd="/home/user/rate_limiter", timeout=30)
    assert build.returncode == 0, f"make failed:\n{build.stdout}\n{build.stderr}"
    assert os.path.isfile(RL_PATH)
    assert os.access(RL_PATH, os.X_OK)

    alphabet = string.ascii_letters + string.digits
    valid_tokens = [
        "".join(secrets.choice(alphabet) for _ in range(10))
        for _ in range(8)
    ]
    valid_tokens += ["0000000000", "Z9a8B7c6D5"]
    for token in valid_tokens:
        result = run([RL_PATH, token])
        assert result.returncode == 0, f"rl_check rejected valid token {token!r}"

    invalid_tokens = [
        "", "A1B2C3D4E", "A1B2C3D4E5F", "A1B2-3D4E5",
        "A1B2_3D4E5", "A1B2 C3D4E", "!!!!!!!!!!", "abc$def123",
    ]
    for token in invalid_tokens:
        result = run([RL_PATH, token])
        assert result.returncode != 0, f"rl_check accepted invalid token {token!r}"

    no_argument = run([RL_PATH])
    assert no_argument.returncode != 0, "rl_check must safely reject a missing token"


def test_validate_job_sh_exists_and_executable():
    assert os.path.isfile(VALIDATOR), f"Script {VALIDATOR} is missing."
    assert os.access(VALIDATOR, os.X_OK), f"Script {VALIDATOR} is not executable."


def invoke_payload(payload=None, raw=None):
    fd, path = tempfile.mkstemp(prefix="job_", suffix=".data", dir="/tmp")
    try:
        with os.fdopen(fd, "w") as f:
            if raw is not None:
                f.write(raw)
            else:
                json.dump(payload, f)
        return run([VALIDATOR, path])
    finally:
        os.unlink(path)


def random_token():
    chars = string.ascii_letters + string.digits
    return "".join(secrets.choice(chars) for _ in range(10))


def test_validator_generated_clean_and_malicious_inputs():
    # These files and values are created only during verification, so validation
    # cannot be implemented by recognizing the shipped corpus or its pathnames.
    valid_payloads = []
    for _ in range(10):
        stem = "v_" + secrets.token_hex(5)
        valid_payloads.append({
            "video": stem + ".mp4",
            "timestamp": f"{secrets.randbelow(100):02d}:{secrets.randbelow(100):02d}:{secrets.randbelow(100):02d}",
            "filters": secrets.choice(["vflip", "scale=123x77", "abc=12,XYZ", "a1,b2=C3"]),
            "token": random_token(),
        })

    for payload in valid_payloads:
        result = invoke_payload(payload)
        assert result.returncode == 0, (
            f"validator rejected generated valid payload {payload!r}: {result.stderr}"
        )

    base = {
        "video": "safe_42.mp4",
        "timestamp": "07:08:09",
        "filters": "scale=320x240,vflip",
        "token": random_token(),
    }
    invalid_variants = []
    mutations = {
        "video": [
            "../safe.mp4", "dir/safe.mp4", "/tmp/safe.mp4", "safe..mp4",
            "safe-name.mp4", "safe.mp4.jpg", ".mp4", "safe.MP4", "safe mp4",
        ],
        "timestamp": [
            "7:08:09", "07:8:09", "07:08:9", "007:08:09", "07-08-09",
            "07:08:09Z", "07:08:09\n", "now", "$(id)",
        ],
        "filters": [
            "vflip;id", "vflip|cat", "scale=1:1", "$(id)", "a b", "a/b",
            "vflip\nscale=2", "a&b", "a>b", "a'b", 'a"b',
        ],
        "token": [
            "short", "ABCDEFGHIJK", "ABC_DEF123", "ABC-DEF123", "ABC$DEF123",
            "123456789!",
        ],
    }
    for field, bad_values in mutations.items():
        for value in bad_values:
            candidate = dict(base)
            candidate[field] = value
            invalid_variants.append(candidate)

    for field in base:
        candidate = dict(base)
        del candidate[field]
        invalid_variants.append(candidate)

    for field, bad_value in [
        ("video", 12), ("timestamp", None), ("filters", ["vflip"]),
        ("token", True),
    ]:
        candidate = dict(base)
        candidate[field] = bad_value
        invalid_variants.append(candidate)

    for payload in invalid_variants:
        result = invoke_payload(payload)
        assert result.returncode != 0, f"validator accepted invalid payload {payload!r}"

    malformed = ["", "not json", "{", '{"video":"safe.mp4",}', "[]", "null"]
    for raw in malformed:
        result = invoke_payload(raw=raw)
        assert result.returncode != 0, f"validator accepted malformed JSON {raw!r}"

    assert run([VALIDATOR]).returncode != 0, "validator accepted a missing pathname"
    nonexistent = "/tmp/absent_job_" + secrets.token_hex(10)
    assert run([VALIDATOR, nonexistent]).returncode != 0, "validator accepted a missing file"
    assert run([VALIDATOR, MASTER_JOB]).returncode == 0, "master_job.json should validate"


def test_adversarial_corpus_validation():
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"
    clean_files = glob.glob(os.path.join(clean_dir, "*.json"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.json"))

    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_failed = []
    for cf in clean_files:
        if run([VALIDATOR, cf]).returncode != 0:
            clean_failed.append(os.path.basename(cf))

    evil_bypassed = []
    for ef in evil_files:
        if run([VALIDATOR, ef]).returncode == 0:
            evil_bypassed.append(os.path.basename(ef))

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean rejected: " + ", ".join(clean_failed))
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: " + ", ".join(evil_bypassed))
    assert not errors, "Adversarial corpus validation failed:\n" + "\n".join(errors)


def probe_dimensions(path):
    result = run([
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "stream=width,height", "-of", "csv=s=x:p=0", path,
    ])
    assert result.returncode == 0, f"ffprobe failed to read {path}: {result.stderr}"
    return result.stdout.strip()


def test_output_frame_exists_and_valid():
    assert os.path.isfile(OUTPUT_FRAME), f"Output frame {OUTPUT_FRAME} is missing."
    dimensions = probe_dimensions(OUTPUT_FRAME)
    assert dimensions == "640x480", f"Expected frame dimensions 640x480, got {dimensions}."


def test_output_frame_matches_requested_timestamp_and_filter():
    with open(MASTER_JOB) as f:
        job = json.load(f)

    expected = "/tmp/expected_frame_" + secrets.token_hex(8) + ".jpg"
    try:
        result = run([
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
            "-ss", job["timestamp"], "-i", "/app/dashcam.mp4",
            "-vf", job["filters"], "-frames:v", "1", expected,
        ], timeout=30)
        assert result.returncode == 0, f"Could not derive expected frame: {result.stderr}"
        assert probe_dimensions(expected) == probe_dimensions(OUTPUT_FRAME)

        comparison = run([
            "ffmpeg", "-hide_banner", "-i", OUTPUT_FRAME, "-i", expected,
            "-lavfi", "[0:v][1:v]ssim", "-f", "null", "-",
        ], timeout=30)
        text = comparison.stdout + comparison.stderr
        match = re.search(r"All:([0-9.]+)", text)
        assert comparison.returncode == 0 and match, f"Could not compare output frame: {text}"
        score = float(match.group(1))
        assert score >= 0.99, (
            f"output_frame.jpg is not the requested filtered frame at {job['timestamp']} "
            f"(SSIM {score:.6f})"
        )
    finally:
        if os.path.exists(expected):
            os.unlink(expected)


def test_benchmark_txt_exists_and_valid():
    assert os.path.isfile(BENCHMARK), f"Benchmark file {BENCHMARK} is missing."
    with open(BENCHMARK, "r", errors="replace") as f:
        content = f.read()

    assert "User time" in content, (
        f"{BENCHMARK} does not contain expected '/usr/bin/time -v' output (missing 'User time')."
    )
    required_labels = [
        "Command being timed:", "User time (seconds):", "System time (seconds):",
        "Elapsed (wall clock) time", "Maximum resident set size", "Exit status:",
    ]
    for label in required_labels:
        assert label in content, f"benchmark is missing GNU time -v field {label!r}"

    exits = re.findall(r"Exit status:\s*(\d+)", content)
    assert exits and exits[-1] == "0", "benchmarked extraction did not exit successfully"

    with open(MASTER_JOB) as f:
        job = json.load(f)
    commands = re.findall(r'Command being timed:\s*"([^\n]*)"', content)
    assert commands, "benchmark does not identify the command that was timed"
    matching = [c for c in commands if all(piece in c for piece in [
        "ffmpeg", "/app/dashcam.mp4", job["timestamp"], job["filters"], OUTPUT_FRAME,
    ])]
    assert matching, (
        "GNU time output does not show the required ffmpeg input, timestamp, filter, "
        "and output path in the benchmarked command"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
