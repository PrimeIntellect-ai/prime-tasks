#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import re
import secrets
import shutil
import subprocess
import tempfile
import time

import cv2
import numpy as np


def expected_sanitized(data):
    def valid_line(line):
        text = line[:-1] if line.endswith("\n") else line
        if text.endswith("\r"):
            text = text[:-1]
        stack = []
        i = 0
        while i < len(text):
            if text[i] == ">":
                return False
            if text[i] != "<":
                i += 1
                continue
            end = text.find(">", i + 1)
            if end < 0:
                return False
            tag = text[i:end + 1]
            if tag in ("<b>", "<i>"):
                stack.append(tag[1])
            elif re.fullmatch(r"<color=#[0-9A-Fa-f]{6}>", tag):
                stack.append("color")
            elif tag in ("</b>", "</i>", "</color>"):
                name = tag[2:-1]
                if not stack or stack.pop() != name:
                    return False
            else:
                return False
            i = end + 1
        return not stack

    return "".join(line for line in data.splitlines(keepends=True) if valid_line(line))


def run_sanitizer(input_text, input_name="input.txt"):
    script_path = "/home/user/sanitize.py"
    with tempfile.TemporaryDirectory() as tmpdir:
        in_path = os.path.join(tmpdir, input_name)
        out_path = os.path.join(tmpdir, "output.txt")
        with open(in_path, "w", newline="") as f:
            f.write(input_text)
        result = subprocess.run(
            ["python3", script_path, in_path, out_path],
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, result.stderr
        assert os.path.isfile(out_path), "Sanitizer did not create its output file."
        with open(out_path, "r", newline="") as f:
            return f.read()


def count_black_frames(path):
    cap = cv2.VideoCapture(path)
    assert cap.isOpened(), f"Could not open video {path}"
    count = 0
    frames = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frames += 1
        if np.all(frame == 0):
            count += 1
    cap.release()
    assert frames > 0, "Video contained no decodable frames."
    return count


def test_card_count():
    card_count_path = "/home/user/card_count.txt"
    assert os.path.isfile(card_count_path), f"File {card_count_path} does not exist."
    with open(card_count_path, "r") as f:
        content = f.read().strip()
    assert content == "7", f"Expected card count to be 7, but got '{content}'."


def test_sanitize_script_adversarial_corpus():
    script_path = "/home/user/sanitize.py"
    assert os.path.isfile(script_path), f"Sanitize script {script_path} does not exist."

    clean_dir = "/app/corpora/clean"
    evil_dir = "/app/corpora/evil"
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir)
                   if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir)
                  if os.path.isfile(os.path.join(evil_dir, f))]

    clean_bypassed = []
    evil_bypassed = []
    with tempfile.TemporaryDirectory() as tmpdir:
        for c_file in clean_files:
            out_file = os.path.join(tmpdir, os.path.basename(c_file) + "_out")
            subprocess.run(["python3", script_path, c_file, out_file], check=False)
            if not os.path.isfile(out_file):
                clean_bypassed.append(os.path.basename(c_file))
                continue
            with open(c_file, "r") as f1, open(out_file, "r") as f2:
                if f1.read() != f2.read():
                    clean_bypassed.append(os.path.basename(c_file))

        for e_file in evil_files:
            out_file = os.path.join(tmpdir, os.path.basename(e_file) + "_out")
            subprocess.run(["python3", script_path, e_file, out_file], check=False)
            if os.path.isfile(out_file):
                with open(out_file, "r") as f:
                    if f.read().strip() != "":
                        evil_bypassed.append(os.path.basename(e_file))

    errors = []
    if clean_bypassed:
        errors.append(f"{len(clean_bypassed)} of {len(clean_files)} clean modified: {', '.join(clean_bypassed)}")
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    assert not errors, "Adversarial corpus validation failed: " + "; ".join(errors)


def test_sanitizer_generated_inputs():
    nonce = secrets.token_hex(10)
    color = secrets.token_hex(3).upper()
    cases = [
        f"Plain translation {nonce}",
        f"<b>Bold {nonce}</b>",
        f"<i><color=#{color}>Nested {nonce}</color></i>",
        f"Start <b>bold <i>{nonce}</i></b> end",
        f"<color=#a1B2c3>{nonce}</color>",
        f"<script>{nonce}</script>",
        f"<b>{nonce}</i>",
        f"<color=#{color}>{nonce}</b></color>",
        f"<color=red>{nonce}</color>",
        f"<color=#{color} onclick=x>{nonce}</color>",
        f"<B>{nonce}</B>",
        f"<b class=x>{nonce}</b>",
        f"<img src=x>{nonce}",
        f"<b>{nonce}",
        f"{nonce}</b>",
        f"Malformed <b {nonce}>",
        f"Malformed {nonce} <tag",
        f"Malformed {nonce} > tag",
    ]
    # Randomize order and filename so corpus-specific behavior cannot pass.
    rng = np.random.default_rng(int.from_bytes(secrets.token_bytes(8), "big"))
    rng.shuffle(cases)
    data = "\n".join(cases) + "\n"
    actual = run_sanitizer(data, f"generated-{secrets.token_hex(8)}.txt")
    assert actual == expected_sanitized(data), "Sanitizer failed generated tag-validation cases."


def test_pipeline_script_and_cron():
    pipeline_script = "/home/user/run_pipeline.sh"
    assert os.path.isfile(pipeline_script), f"Pipeline script {pipeline_script} does not exist."
    assert os.access(pipeline_script, os.X_OK), f"Pipeline script {pipeline_script} is not executable."

    result = subprocess.run(["crontab", "-u", "user", "-l"], capture_output=True, text=True)
    assert result.returncode == 0, "The user account has no readable crontab."
    active = [line.strip() for line in result.stdout.splitlines()
              if line.strip() and not line.lstrip().startswith("#")]
    assert any(re.match(r"^\*/5\s+\*\s+\*\s+\*\s+\*\s+.*(?:^|/)run_pipeline\.sh(?:\s|$)", line)
               for line in active), "Cron job for user with schedule */5 * * * * was not found."


def parse_timestamp(value):
    value = value.strip()
    try:
        return float(value)
    except ValueError:
        pass
    try:
        return datetime.datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    except ValueError:
        pass
    result = subprocess.run(["date", "-d", value, "+%s"], capture_output=True, text=True)
    assert result.returncode == 0, f"pipeline.log does not contain a recognizable timestamp: {value!r}"
    return float(result.stdout.strip())


def test_pipeline_execution():
    pipeline_script = "/home/user/run_pipeline.sh"
    files_to_check = [
        "/home/user/pipeline.log",
        "/home/user/card_count.txt",
        "/home/user/final_translations.txt",
    ]

    with tempfile.TemporaryDirectory() as tmpdir:
        trailer_backup = os.path.join(tmpdir, "trailer.mp4")
        staging_backup = os.path.join(tmpdir, "staging.txt")
        shutil.copy2("/app/trailer.mp4", trailer_backup)
        shutil.copy2("/app/staging.txt", staging_backup)
        try:
            nonce = secrets.token_hex(12)
            black_wanted = secrets.randbelow(8) + 2
            total_frames = 19
            black_positions = set(secrets.SystemRandom().sample(range(total_frames), black_wanted))
            writer = cv2.VideoWriter(
                "/app/trailer.mp4", cv2.VideoWriter_fourcc(*"mp4v"), 30, (96, 64)
            )
            assert writer.isOpened(), "Could not create verifier video."
            for i in range(total_frames):
                if i in black_positions:
                    frame = np.zeros((64, 96, 3), dtype=np.uint8)
                else:
                    level = 80 + (i * 7 % 150)
                    frame = np.full((64, 96, 3), level, dtype=np.uint8)
                writer.write(frame)
            writer.release()
            expected_count = count_black_frames("/app/trailer.mp4")
            assert expected_count == black_wanted

            staging = "\n".join([
                f"<b>Pipeline {nonce}</b>",
                f"<color=#12aBcD><i>Nested {nonce}</i></color>",
                f"<script>{nonce}</script>",
                f"<b>Mismatched {nonce}</i>",
                f"Plain {nonce}",
            ]) + "\n"
            with open("/app/staging.txt", "w") as f:
                f.write(staging)

            for path in files_to_check:
                if os.path.exists(path):
                    os.remove(path)

            started = time.time()
            result = subprocess.run(["bash", pipeline_script], capture_output=True, text=True, timeout=60)
            finished = time.time()
            assert result.returncode == 0, f"Pipeline script execution failed with output: {result.stderr}"

            for path in files_to_check:
                assert os.path.isfile(path), f"Expected file {path} was not created by the pipeline script."
                assert os.path.getsize(path) > 0, f"File {path} is empty."

            with open("/home/user/card_count.txt") as f:
                actual_count = f.read().strip()
            assert actual_count == str(expected_count), "Pipeline did not analyze the current trailer video."

            with open("/home/user/final_translations.txt", newline="") as f:
                actual_translations = f.read()
            assert actual_translations == expected_sanitized(staging), "Pipeline did not correctly sanitize the current staging file."

            with open("/home/user/pipeline.log") as f:
                timestamp = parse_timestamp(f.read())
            assert started - 120 <= timestamp <= finished + 120, "pipeline.log timestamp is not current."
        finally:
            shutil.copy2(trailer_backup, "/app/trailer.mp4")
            shutil.copy2(staging_backup, "/app/staging.txt")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
