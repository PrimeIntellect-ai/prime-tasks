#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import atexit
import csv
import glob
import hashlib
import math
import os
import random
import re
import shutil
import subprocess
import tempfile
import wave

ORACLE = "/app/oracle_projector"
AGENT = "/home/user/project_features"
SOURCE = "/home/user/project_features.c"
EXPECTED_WORDS = ["turn", "on", "the", "living", "room"]

# Derive all fuzz answers from the real oracle before making it unavailable to
# submitted programs. This prevents project_features from delegating to it.
random.seed(42)
FUZZ_CASES = []
for i in range(100):
    values = [random.uniform(-100.0, 100.0) for _ in range(5)]
    input_str = " ".join(f"{x:.6f}" for x in values) + "\n"
    proc = subprocess.run([ORACLE], input=input_str, text=True,
                          capture_output=True, timeout=2)
    assert proc.returncode == 0, f"Oracle failed on fuzz case {i + 1}: {proc.stderr}"
    FUZZ_CASES.append((input_str, proc.stdout.strip()))

if os.path.isfile(AGENT):
    with open(ORACLE, "rb") as f:
        oracle_hash = hashlib.sha256(f.read()).digest()
    with open(AGENT, "rb") as f:
        agent_hash = hashlib.sha256(f.read()).digest()
    assert agent_hash != oracle_hash, "project_features must not be a byte-for-byte copy of the oracle"

_hidden_dir = tempfile.mkdtemp(prefix="verifier-oracle-")
_hidden_oracle = os.path.join(_hidden_dir, "reference")
os.replace(ORACLE, _hidden_oracle)

def _restore_oracle():
    try:
        if os.path.exists(_hidden_oracle) and not os.path.exists(ORACLE):
            os.replace(_hidden_oracle, ORACLE)
        shutil.rmtree(_hidden_dir, ignore_errors=True)
    except Exception:
        pass

atexit.register(_restore_oracle)


def _norm_word(value):
    words = re.findall(r"[A-Za-z]+(?:'[A-Za-z]+)?", value.lower())
    return words[0] if len(words) == 1 else ""


def _timestamp_ms(value):
    h, m, rest = value.split(":")
    return (int(h) * 3600 + int(m) * 60 + float(rest)) * 1000.0


def _run_whisper_and_get_words():
    root = "/home/user/whisper.cpp"
    assert os.path.isdir(root), f"Missing whisper.cpp clone at {root}"
    assert os.path.isdir(os.path.join(root, ".git")), f"{root} is not a git clone"

    models = glob.glob(os.path.join(root, "**", "ggml-tiny.en.bin"), recursive=True)
    assert models, "Missing downloaded tiny.en model (ggml-tiny.en.bin)"
    model = max(models, key=os.path.getsize)
    assert os.path.getsize(model) > 10_000_000, "tiny.en model file is implausibly small"

    candidates = [
        os.path.join(root, "build", "bin", "whisper-cli"),
        os.path.join(root, "main"),
        os.path.join(root, "build", "bin", "main"),
    ]
    cli = next((p for p in candidates if os.path.isfile(p) and os.access(p, os.X_OK)), None)
    assert cli is not None, "Missing compiled whisper.cpp CLI executable"

    proc = subprocess.run(
        [cli, "-m", model, "-f", "/app/command.wav", "-ml", "1"],
        text=True, capture_output=True, timeout=180
    )
    combined = proc.stdout + "\n" + proc.stderr
    assert proc.returncode == 0, f"whisper.cpp inference failed:\n{combined[-2000:]}"

    entries = []
    pattern = re.compile(
        r"\[(\d{2}:\d{2}:\d{2}(?:\.\d+)?)\s*-->\s*"
        r"(\d{2}:\d{2}:\d{2}(?:\.\d+)?)\]\s*(.*)"
    )
    for line in combined.splitlines():
        match = pattern.search(line)
        if not match:
            continue
        start = _timestamp_ms(match.group(1))
        end = _timestamp_ms(match.group(2))
        for word in re.findall(r"[A-Za-z]+(?:'[A-Za-z]+)?", match.group(3).lower()):
            entries.append((word, start, end))

    words = [x[0] for x in entries]
    start_index = next(
        (i for i in range(len(words) - 4) if words[i:i + 5] == EXPECTED_WORDS),
        None
    )
    assert start_index is not None, (
        "Fresh whisper.cpp inference did not produce the expected first five spoken words; "
        f"parsed words were: {words[:20]}"
    )
    return entries[start_index:start_index + 5]


def _read_features():
    path = "/home/user/features.csv"
    assert os.path.isfile(path), f"Missing {path}"
    with open(path, newline="") as f:
        reader = csv.reader(f)
        headers = next(reader, None)
        assert headers is not None, f"File {path} is empty"
        expected_headers = ["word", "start_time_ms", "end_time_ms", "duration_ms", "char_count"]
        headers_clean = [h.strip().lower() for h in headers]
        assert headers_clean == expected_headers, (
            f"Headers mismatch in {path}. Expected {expected_headers}, got {headers_clean}"
        )
        rows = list(reader)
    assert len(rows) >= 5, f"Expected at least 5 rows of features in {path}, got {len(rows)}"
    return rows[:5]


def test_features_csv_exists_format_and_matches_audio():
    rows = _read_features()
    reference = _run_whisper_and_get_words()

    with wave.open("/app/command.wav", "rb") as wav:
        audio_ms = wav.getnframes() * 1000.0 / wav.getframerate()

    previous_start = -1.0
    boundaries = set()
    for i, (row, expected_word, ref) in enumerate(zip(rows, EXPECTED_WORDS, reference), 1):
        assert len(row) == 5, f"Feature row {i} must contain exactly 5 columns: {row}"
        word = _norm_word(row[0].strip())
        assert word == expected_word, f"Row {i} word should be '{expected_word}', got '{row[0]}'"
        try:
            start, end, duration = map(float, row[1:4])
            char_count = float(row[4])
        except ValueError:
            assert False, f"Row {i} contains non-numeric feature values: {row}"
        assert all(math.isfinite(x) for x in (start, end, duration, char_count)), f"Non-finite value in row {i}"
        assert 0 <= start < end <= audio_ms + 250, f"Invalid timestamps in row {i}: {start}, {end}"
        assert start >= previous_start, f"Word timestamps are not ordered at row {i}"
        assert abs(duration - (end - start)) <= 1.0, f"duration_ms is inconsistent in row {i}"
        assert char_count == len(expected_word), f"Incorrect char_count in row {i}"
        ref_word, ref_start, ref_end = ref
        assert ref_word == expected_word
        assert abs(start - ref_start) <= 500, f"Row {i} start time does not match fresh audio inference"
        assert abs(end - ref_end) <= 500, f"Row {i} end time does not match fresh audio inference"
        previous_start = start
        boundaries.add((round(start), round(end)))
    assert len(boundaries) >= 4, "Word-level timestamps were not extracted for the five words"


def test_final_activations_txt():
    path = "/home/user/final_activations.txt"
    assert os.path.isfile(path), f"Missing {path}"
    with open(path, "r") as f:
        content = f.read()

    stripped = content.strip()
    parts = stripped.split()
    assert len(parts) == 3, f"Expected exactly 3 space-separated numbers in {path}, got {len(parts)}: {stripped}"
    assert re.fullmatch(r"-?\d+\.\d{4} -?\d+\.\d{4} -?\d+\.\d{4}\n?", content), (
        "final_activations.txt must contain the projector's exact three-value, four-decimal output"
    )
    for p in parts:
        float(p)

    rows = _read_features()
    first = rows[0]
    for value in first[1:5]:
        float(value)
    input_str = " ".join(first[1:5] + ["1.0"]) + "\n"
    proc = subprocess.run([AGENT], input=input_str, text=True,
                          capture_output=True, timeout=2)
    assert proc.returncode == 0, f"project_features failed on the first CSV row: {proc.stderr}"
    assert content == proc.stdout, (
        "final_activations.txt is not the exact output of project_features for "
        "start_time_ms, end_time_ms, duration_ms, char_count, and 1.0 from the first CSV row"
    )


def test_fuzz_equivalence_project_features():
    assert os.path.isfile(AGENT), f"Missing compiled binary {AGENT}"
    assert os.access(AGENT, os.X_OK), f"Binary {AGENT} is not executable"
    assert os.path.isfile(SOURCE), f"Missing C source {SOURCE}"

    rebuilt = os.path.join(tempfile.mkdtemp(prefix="rebuild-"), "project_features")
    compile_proc = subprocess.run(
        ["gcc", "-O2", SOURCE, "-o", rebuilt], text=True, capture_output=True, timeout=30
    )
    assert compile_proc.returncode == 0, f"Could not compile project_features.c:\n{compile_proc.stderr}"

    for binary in (AGENT, rebuilt):
        for i, (input_str, oracle_out) in enumerate(FUZZ_CASES):
            proc = subprocess.run([binary], input=input_str, text=True,
                                  capture_output=True, timeout=2)
            assert proc.returncode == 0, (
                f"{binary} failed on fuzz iteration {i + 1}/100: {proc.stderr}"
            )
            agent_out = proc.stdout.strip()
            assert oracle_out == agent_out, (
                f"Mismatch for {binary} on fuzz iteration {i + 1}/100.\n"
                f"Input: {input_str.strip()}\n"
                f"Oracle output: '{oracle_out}'\n"
                f"Agent output:  '{agent_out}'"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
