#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import posixpath
import subprocess
import tempfile
import uuid

import pytest

SUMMARY = "/home/user/project_summary.log"
SOURCE = "/home/user/sanitizer.cpp"
EXECUTABLE = "/home/user/sanitizer"


def count_green_frames():
    video = "/app/file_events.mp4"
    assert os.path.isfile(video), f"Missing video: {video}"

    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height", "-of", "json", video],
        capture_output=True, text=True, check=True,
    )
    stream = json.loads(probe.stdout)["streams"][0]
    width, height = int(stream["width"]), int(stream["height"])
    assert width >= 10 and height >= 10

    decoded = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", video, "-f", "rawvideo",
         "-pix_fmt", "rgb24", "-"],
        capture_output=True, check=True,
    ).stdout
    frame_size = width * height * 3
    assert frame_size and len(decoded) % frame_size == 0

    green_frames = 0
    for offset in range(0, len(decoded), frame_size):
        frame = decoded[offset:offset + frame_size]
        green = 0
        for y in range(10):
            for x in range(10):
                p = (y * width + x) * 3
                r, g, b = frame[p:p + 3]
                if r <= 20 and g >= 235 and b <= 20:
                    green += 1
        if green >= 60:
            green_frames += 1
    return green_frames


def test_project_summary_log():
    assert os.path.isfile(SUMMARY), f"Missing {SUMMARY}"
    with open(SUMMARY, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 2, f"Expected at least 2 lines in {SUMMARY}, found {len(lines)}"
    assert lines[0] == "42", f"Expected first line of {SUMMARY} to be '42', got '{lines[0]}'"
    recovered = count_green_frames()
    assert recovered == 42, f"Verifier decoded {recovered} green frames, expected 42"
    assert int(lines[0]) == recovered, "Summary frame count does not match the decoded video"
    assert lines[1] == EXECUTABLE, f"Expected second line of {SUMMARY} to be '{EXECUTABLE}', got '{lines[1]}'"


@pytest.fixture(scope="session")
def sanitizer_binaries():
    assert os.path.isfile(SOURCE), f"Missing C++ source: {SOURCE}"
    assert os.path.getsize(SOURCE) > 0, f"Empty C++ source: {SOURCE}"
    assert os.path.isfile(EXECUTABLE), f"Missing executable: {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE} is not a compiled ELF executable"

    rebuilt = os.path.join(tempfile.mkdtemp(prefix="rebuilt_sanitizer_"), "sanitizer")
    result = subprocess.run(
        ["g++", "-std=c++17", "-O2", SOURCE, "-o", rebuilt],
        capture_output=True, text=True,
    )
    assert result.returncode == 0, f"sanitizer.cpp does not compile:\n{result.stdout}\n{result.stderr}"
    return [EXECUTABLE, rebuilt]


def run_and_check(binary, config, expected_code, expected_text, cwd=None):
    result = subprocess.run(
        [binary, config], cwd=cwd, capture_output=True, text=True, timeout=5
    )
    assert result.returncode == expected_code, (
        f"{binary} returned {result.returncode} for {config}; expected {expected_code}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert result.stdout.strip() == expected_text, (
        f"{binary} printed {result.stdout!r} for {config}; expected {expected_text!r}"
    )


def test_sanitizer_adversarial_corpus(sanitizer_binaries):
    clean_dir = "/app/corpora/clean/"
    evil_dir = "/app/corpora/evil/"
    assert os.path.isdir(clean_dir), f"Missing clean corpus directory: {clean_dir}"
    assert os.path.isdir(evil_dir), f"Missing evil corpus directory: {evil_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir)
                   if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir)
                  if os.path.isfile(os.path.join(evil_dir, f))]
    assert clean_files, "Clean corpus is empty"
    assert evil_files, "Evil corpus is empty"

    for binary in sanitizer_binaries:
        for config in clean_files:
            run_and_check(binary, config, 0, "ACCEPTED")
        for config in evil_files:
            run_and_check(binary, config, 1, "REJECTED")


def emit(node):
    kind = node[0]
    if kind == "file":
        return "file(" + json.dumps(node[1]) + ")"
    if kind == "concat":
        return "concat(" + emit(node[1]) + ", " + emit(node[2]) + ")"
    if kind == "parent":
        return "parent(" + emit(node[1]) + ")"
    raise AssertionError(kind)


def evaluate(node):
    kind = node[0]
    if kind == "file":
        return node[1]
    if kind == "concat":
        return evaluate(node[1]) + evaluate(node[2])
    if kind == "parent":
        return posixpath.dirname(evaluate(node[1]))
    raise AssertionError(kind)


def is_malicious(path):
    normalized = posixpath.normpath(path)
    return posixpath.isabs(path) or normalized == ".." or normalized.startswith("../")


def test_generated_expression_evaluation(sanitizer_binaries):
    token = "p" + uuid.uuid4().hex
    secret = "s" + uuid.uuid4().hex
    F = lambda value: ("file", value)
    C = lambda left, right: ("concat", left, right)
    P = lambda value: ("parent", value)

    cases = [
        F(token + "/docs/readme.md"),
        C(P(F(token + "/config.json")), F("/settings.json")),
        P(F(token + "/nested/item.txt")),
        C(F(token + "/sub/../"), F("safe.txt")),
        C(F(token + "/.."), F("/safe.txt")),
        C(P(F(token + "/a/file")), C(F("/b/../"), F("result"))),
        F(token + '/quo"ted.txt'),
        F("../" + secret),
        C(F(".."), C(F("/"), F(secret))),
        C(F("/"), F("etc/" + secret)),
        C(P(F(token + "/config")), C(F("/../../"), F(secret))),
        P(P(F("../" + secret + "/item"))),
        C(F(token), C(F("/../../../"), F(secret))),
    ]

    workdir = tempfile.mkdtemp(prefix="sanitizer_runtime_")
    for index, expression in enumerate(cases):
        evaluated = evaluate(expression)
        malicious = is_malicious(evaluated)
        config = os.path.join(workdir, f"case_{index}_{uuid.uuid4().hex}.json")
        document = {
            "description": "untrusted configuration " + uuid.uuid4().hex,
            "depends_on": emit(expression),
            "unrelated": {"depends_on_text": "../this-is-only-a-decoy"},
        }
        with open(config, "w", encoding="utf-8") as f:
            json.dump(document, f, indent=2)

        expected_code = 1 if malicious else 0
        expected_text = "REJECTED" if malicious else "ACCEPTED"
        for binary in sanitizer_binaries:
            run_and_check(binary, config, expected_code, expected_text, cwd=workdir)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
