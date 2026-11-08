#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import re
import secrets
import shutil
import subprocess
import tempfile
from decimal import Decimal, ROUND_HALF_UP

import pytest

SCRIPT = "/home/user/validate_subs.sh"
RAW = "/home/user/raw_translations.jsonl"
VIDEO = "/app/reference_ui.mp4"
SRT = "/home/user/final_subtitles.srt"


def run_validator(path):
    return subprocess.run([SCRIPT, path], capture_output=True, text=True, timeout=15)


def test_adversarial_corpus():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."

    clean_dir = "/app/corpora/clean"
    evil_dir = "/app/corpora/evil"
    clean_files = glob.glob(os.path.join(clean_dir, "*.jsonl"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.jsonl"))
    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_failed = []
    for cf in clean_files:
        with open(cf) as f:
            expected_output = f.read().strip()
        result = run_validator(cf)
        if result.returncode != 0 or result.stdout.strip() != expected_output:
            clean_failed.append(os.path.basename(cf))

    evil_failed = []
    for ef in evil_files:
        result = run_validator(ef)
        # Preserve the original bypass assertion and additionally require failure status.
        if result.returncode == 0 and result.stdout.strip() != "":
            evil_failed.append(os.path.basename(ef))
        assert result.returncode != 0, f"Evil file {os.path.basename(ef)} exited successfully"
        assert result.stdout.strip() == "", f"Evil file {os.path.basename(ef)} produced output"

    error_msg = []
    if clean_failed:
        error_msg.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")
    if evil_failed:
        error_msg.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")
    assert not error_msg, " | ".join(error_msg)


def test_generated_validator_cases(tmp_path):
    token = secrets.token_hex(12)
    valid = [
        json.dumps({"seq": 7, "text": f"plain {token}"}, ensure_ascii=True),
        '{"seq":2,"text":"BMP \\u2713 ' + token + '"}',
        '{"seq":3,"text":"pair \\uD83D\\uDE03 ' + token + '"}',
        '{"seq":4,"text":"literal slash \\\\uD800 ' + token + '"}',
        json.dumps({"seq": 1, "text": f"literal café {token}"}, ensure_ascii=False),
    ]
    invalid = [
        '{"seq":5,"text":"lone high \\uD800 ' + token + '"}',
        '{"seq":5,"text":"high then BMP \\uD800\\u2713 ' + token + '"}',
        '{"seq":5,"text":"lone low \\uDC00 ' + token + '"}',
        '{"seq":5,"text":"bad hex \\u12G4 ' + token + '"}',
        '{"seq":5,"text":"short \\u12"}',
        '{"seq":0,"text":"zero ' + token + '"}',
        '{"seq":-3,"text":"negative ' + token + '"}',
        '{"seq":1.5,"text":"fraction ' + token + '"}',
        '{"seq":"8","text":"string sequence ' + token + '"}',
        '{"text":"missing sequence ' + token + '"}',
        '{"seq":8}',
        '{"seq":8,"text":123}',
        'not-json-' + token,
    ]

    clean = tmp_path / f"clean-{token}.jsonl"
    clean.write_text("\n".join(valid) + "\n", encoding="utf-8")
    result = run_validator(str(clean))
    assert result.returncode == 0
    assert result.stdout == "\n".join(valid) + "\n"

    for i, line in enumerate(invalid):
        evil = tmp_path / f"evil-{token}-{i}.jsonl"
        evil.write_text(line + "\n", encoding="utf-8")
        result = run_validator(str(evil))
        assert result.returncode != 0, f"Invalid case {i} exited successfully: {line}"
        assert result.stdout == "", f"Invalid case {i} was emitted: {line}"

    mixed_lines = valid[:2] + invalid[:4] + valid[2:]
    random.SystemRandom().shuffle(mixed_lines)
    mixed = tmp_path / f"mixed-{token}.jsonl"
    mixed.write_text("\n".join(mixed_lines) + "\n", encoding="utf-8")
    expected = "".join(line + "\n" for line in mixed_lines if line in valid)
    result = run_validator(str(mixed))
    assert result.returncode != 0, "A mixed file containing invalid lines must fail"
    assert result.stdout == expected, "Mixed-file valid lines were not preserved exactly"


def detect_scene_times(video):
    command = [
        "ffmpeg", "-hide_banner", "-i", video,
        "-vf", "select='gt(scene,0.3)',showinfo",
        "-an", "-f", "null", "-"
    ]
    result = subprocess.run(command, capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stderr
    changes = [Decimal(x) for x in re.findall(r"showinfo[^\n]*?pts_time:([0-9]+(?:\.[0-9]+)?)", result.stderr)]
    assert changes, "ffmpeg did not detect any scene changes"
    duration_result = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", video],
        capture_output=True, text=True, timeout=20, check=True
    )
    return [Decimal("0")] + changes, Decimal(duration_result.stdout.strip())


def fmt_time(value):
    millis = int((value * 1000).quantize(Decimal("1"), rounding=ROUND_HALF_UP))
    hours, millis = divmod(millis, 3600000)
    minutes, millis = divmod(millis, 60000)
    seconds, millis = divmod(millis, 1000)
    return f"{hours:02d}:{minutes:02d}:{seconds:02d},{millis:03d}"


def valid_raw_translations(path):
    translations = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            try:
                item = json.loads(line)
            except (json.JSONDecodeError, UnicodeDecodeError):
                continue
            if (isinstance(item, dict) and type(item.get("seq")) is int and item["seq"] > 0
                    and isinstance(item.get("text"), str)):
                translations.append((item["seq"], item["text"]))
    return [text for _, text in sorted(translations)]


def expected_blocks(video, raw):
    starts, duration = detect_scene_times(video)
    texts = valid_raw_translations(raw)
    assert len(starts) >= len(texts), "Fewer scenes than valid translations"
    blocks = []
    for i, text in enumerate(texts):
        start = starts[i]
        natural_end = starts[i + 1] if i + 1 < len(starts) else duration
        end = min(natural_end, start + Decimal("5.0"))
        blocks.append((fmt_time(start), fmt_time(end), text))
    return blocks


def parse_srt(path):
    with open(path, encoding="utf-8") as f:
        content = f.read().replace("\r\n", "\n").strip()
    chunks = re.split(r"\n{2,}", content) if content else []
    parsed = []
    for expected_index, chunk in enumerate(chunks, 1):
        lines = chunk.split("\n")
        assert len(lines) >= 3, f"Malformed SRT block {expected_index}"
        assert lines[0].strip() == str(expected_index), f"Bad SRT index in block {expected_index}"
        match = re.fullmatch(r"(\d{2}:\d{2}:\d{2},\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2},\d{3})", lines[1].strip())
        assert match, f"Malformed timestamp in block {expected_index}"
        parsed.append((match.group(1), match.group(2), "\n".join(lines[2:])))
    return parsed, content


def test_srt_output():
    assert os.path.isfile(SRT), f"SRT file {SRT} does not exist."
    parsed, content = parse_srt(SRT)

    # Preserve the original fixed assertions.
    expected_timestamps = [
        ("00:00:00,000", "00:00:03,500"),
        ("00:00:03,500", "00:00:07,200"),
        ("00:00:07,200", "00:00:12,200"),
        ("00:00:14,100", "00:00:15,000"),
    ]
    timestamps = re.findall(r"(\d{2}:\d{2}:\d{2},\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2},\d{3})", content)
    assert len(timestamps) == len(expected_timestamps), f"Expected {len(expected_timestamps)} subtitle blocks, found {len(timestamps)}."
    for i, (expected_start, expected_end) in enumerate(expected_timestamps):
        actual_start, actual_end = timestamps[i]
        assert actual_start == expected_start, f"Block {i+1} start time mismatch. Expected {expected_start}, got {actual_start}."
        assert actual_end == expected_end, f"Block {i+1} end time mismatch. Expected {expected_end}, got {actual_end}."
    assert "Slide 1: Introduction" in content
    assert "Slide 2: Analytics" in content
    assert "Slide 3: Deep Dive" in content
    assert "Slide 4: Conclusion" in content

    # Also derive every timestamp and block association from the actual inputs.
    assert parsed == expected_blocks(VIDEO, RAW)

    raw_result = run_validator(RAW)
    assert raw_result.returncode != 0, "The supplied raw file contains an invalid line and must yield nonzero status"
    emitted = [json.loads(line) for line in raw_result.stdout.splitlines()]
    assert [x["text"] for x in sorted(emitted, key=lambda x: x["seq"])] == valid_raw_translations(RAW)


def make_video(path, durations):
    colors = ["red", "blue", "green", "yellow"]
    command = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y"]
    for color, duration in zip(colors, durations):
        command += ["-f", "lavfi", "-i", f"color=c={color}:s=320x240:r=25:d={duration}"]
    command += [
        "-filter_complex", "[0:v][1:v][2:v][3:v]concat=n=4:v=1:a=0[outv]",
        "-map", "[outv]", "-c:v", "libx264", "-preset", "ultrafast", path
    ]
    subprocess.run(command, capture_output=True, text=True, timeout=60, check=True)


def test_reproducible_pipeline_with_unseen_inputs():
    candidates = [p for p in glob.glob("/home/user/*.sh") if os.path.realpath(p) != os.path.realpath(SCRIPT)]
    assert candidates, "No subtitle synchronization shell script was provided"

    token = secrets.token_hex(10)
    durations = [Decimal("1.6"), Decimal("5.8"), Decimal("2.4"), Decimal("1.2")]
    shuffled = [
        {"seq": 3, "text": f"third-{token}"},
        {"seq": 1, "text": f"first-{token}"},
        {"seq": 4, "text": f"fourth-{token}"},
        {"seq": 2, "text": f"second-{token}"},
    ]

    with tempfile.TemporaryDirectory() as backup_dir:
        raw_backup = os.path.join(backup_dir, "raw.jsonl")
        video_backup = os.path.join(backup_dir, "video.mp4")
        srt_backup = os.path.join(backup_dir, "final.srt")
        shutil.copy2(RAW, raw_backup)
        shutil.copy2(VIDEO, video_backup)
        had_srt = os.path.exists(SRT)
        if had_srt:
            shutil.copy2(SRT, srt_backup)

        try:
            with open(RAW, "w", encoding="utf-8") as f:
                for item in shuffled:
                    f.write(json.dumps(item) + "\n")
                f.write('{"seq":999,"text":"bad-' + token + '-\\uD800"}\n')
            make_video(VIDEO, durations)
            wanted = expected_blocks(VIDEO, RAW)

            succeeded = False
            errors = []
            for candidate in candidates:
                if os.path.exists(SRT):
                    os.remove(SRT)
                try:
                    result = subprocess.run(["/bin/bash", candidate], cwd="/home/user", capture_output=True, text=True, timeout=90)
                except subprocess.TimeoutExpired:
                    errors.append(f"{candidate}: timed out")
                    continue
                if result.returncode != 0 or not os.path.isfile(SRT):
                    errors.append(f"{candidate}: exit {result.returncode}, did not generate SRT")
                    continue
                try:
                    actual, _ = parse_srt(SRT)
                except AssertionError as exc:
                    errors.append(f"{candidate}: {exc}")
                    continue
                if actual == wanted:
                    succeeded = True
                    break
                errors.append(f"{candidate}: generated incorrect blocks")
            assert succeeded, "No provided synchronization script reproduced the pipeline on unseen inputs: " + "; ".join(errors)
        finally:
            shutil.copy2(raw_backup, RAW)
            shutil.copy2(video_backup, VIDEO)
            if had_srt:
                shutil.copy2(srt_backup, SRT)
            elif os.path.exists(SRT):
                os.remove(SRT)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
