#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import stat
import subprocess
import tempfile
from datetime import datetime, timedelta, timezone
from fractions import Fraction
from zoneinfo import ZoneInfo


def decode_expected_timestamps():
    video_path = "/app/monitor_feed.mp4"
    assert os.path.isfile(video_path), f"Video {video_path} is missing."

    probe = subprocess.run(
        [
            "ffprobe", "-v", "error", "-select_streams", "v:0",
            "-show_entries", "stream=width,height,avg_frame_rate",
            "-of", "json", video_path,
        ],
        capture_output=True,
        check=True,
        text=True,
    )
    stream = json.loads(probe.stdout)["streams"][0]
    width = int(stream["width"])
    height = int(stream["height"])
    fps = Fraction(stream["avg_frame_rate"])
    assert width > 10 and height > 10 and fps > 0

    decoded = subprocess.run(
        [
            "ffmpeg", "-v", "error", "-i", video_path,
            "-f", "rawvideo", "-pix_fmt", "rgb24", "-",
        ],
        capture_output=True,
        check=True,
    ).stdout

    frame_size = width * height * 3
    assert frame_size > 0 and len(decoded) % frame_size == 0
    frame_count = len(decoded) // frame_size
    assert frame_count > 0

    start = datetime(2024, 3, 15, 14, 0, 0, tzinfo=timezone.utc)
    tokyo = ZoneInfo("Asia/Tokyo")
    expected = []
    pixel_offset = (10 * width + 10) * 3

    for frame_number in range(frame_count):
        offset = frame_number * frame_size + pixel_offset
        red, green, blue = decoded[offset:offset + 3]
        # The source indicator is pure red. The supplied MP4 uses lossy MPEG-4
        # encoding, so decode-time values are identified by strong red dominance.
        if red >= 40 and red >= green * 2 + 20 and red >= blue * 2 + 20:
            whole_seconds = (frame_number * fps.denominator) // fps.numerator
            timestamp = (start + timedelta(seconds=whole_seconds)).astimezone(tokyo)
            expected.append(timestamp.strftime("%Y-%m-%d %H:%M:%S JST"))

    assert expected, "No red alert frames were decoded from monitor_feed.mp4."
    return expected


def test_alert_timestamps():
    output_file = "/home/user/alert_timestamps.txt"
    assert os.path.isfile(output_file), f"Output file {output_file} is missing."

    with open(output_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    # Preserve the original ground-truth assertion.
    expected_timestamps = {
        "2024-03-15 23:00:01 JST",
        "2024-03-15 23:00:02 JST",
        "2024-03-15 23:00:05 JST",
        "2024-03-15 23:00:06 JST"
    }
    actual_timestamps = set(lines)
    missing = expected_timestamps - actual_timestamps
    unexpected = actual_timestamps - expected_timestamps
    assert not missing, f"Missing expected timestamps in output: {missing}"
    assert not unexpected, f"Found unexpected timestamps in output: {unexpected}"

    # Decode the actual artifact and require one chronologically ordered line for
    # every alert frame, including repeated whole-second timestamps.
    dynamically_expected = decode_expected_timestamps()
    assert lines == dynamically_expected, (
        f"Timestamp output does not match decoded alert frames: expected "
        f"{len(dynamically_expected)} lines, got {len(lines)}"
    )


def run_linter_with_python(script_path, config_path):
    return subprocess.run(
        ["python3", script_path, config_path],
        capture_output=True,
        text=True,
        timeout=10,
    )


def assert_classification(result, expected, description):
    expected_code = 1 if expected == "EVIL" else 0
    assert result.returncode == expected_code and result.stdout.strip() == expected, (
        f"Misclassified {description}: return code {result.returncode}, "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def test_ssh_config_linter_adversarial_corpus():
    script_path = "/home/user/check_ssh_config.py"
    assert os.path.isfile(script_path), f"Linter script {script_path} is missing."

    evil_corpus_path = "/app/hidden_corpus/evil/"
    clean_corpus_path = "/app/hidden_corpus/clean/"
    assert os.path.isdir(evil_corpus_path), f"Evil corpus directory {evil_corpus_path} is missing."
    assert os.path.isdir(clean_corpus_path), f"Clean corpus directory {clean_corpus_path} is missing."

    evil_files = [os.path.join(evil_corpus_path, f) for f in os.listdir(evil_corpus_path) if os.path.isfile(os.path.join(evil_corpus_path, f))]
    clean_files = [os.path.join(clean_corpus_path, f) for f in os.listdir(clean_corpus_path) if os.path.isfile(os.path.join(clean_corpus_path, f))]

    evil_bypassed = []
    clean_modified = []
    for evil_file in evil_files:
        result = run_linter_with_python(script_path, evil_file)
        if result.returncode != 1 or result.stdout.strip() != "EVIL":
            evil_bypassed.append(os.path.basename(evil_file))
    for clean_file in clean_files:
        result = run_linter_with_python(script_path, clean_file)
        if result.returncode != 0 or result.stdout.strip() != "CLEAN":
            clean_modified.append(os.path.basename(clean_file))

    error_messages = []
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_messages.append(f"{len(clean_modified)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_modified)}")
    assert not error_messages, " | ".join(error_messages)


def mixed_case(text):
    return "".join(c.upper() if random.choice((True, False)) else c.lower() for c in text)


def test_ssh_config_linter_generated_semantic_holdout():
    script_path = "/home/user/check_ssh_config.py"
    assert os.path.isfile(script_path), f"Linter script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Linter script {script_path} is not executable."

    pka = mixed_case("PubkeyAuthentication")
    akf = mixed_case("AuthorizedKeysFile")
    pkt = mixed_case("PubkeyAcceptedKeyTypes")
    am = mixed_case("AuthenticationMethods")
    marker = secrets.token_hex(12)

    cases = [
        ("EVIL", f"# generated {marker}\n\t{akf}\t/dev/null   # discard keys\n"),
        ("EVIL", f"Port 22\nMatch User deploy_{marker}\n    {akf}   /var/empty/%u\n"),
        ("EVIL", f"# unrelated\n{pkt}    NoNe\nPasswordAuthentication yes\n"),
        ("EVIL", f"{pka} yes\n  {am}\tpassword   # password only\n"),
        ("EVIL", f"PasswordAuthentication yes\n{pka}\tNo\n"),
        ("CLEAN", f"# {akf} /dev/null\n# {pkt} none\nPort 22\n"),
        ("CLEAN", f"{pka} YES\n{akf} .ssh/authorized_keys\n"),
        ("CLEAN", f"PasswordAuthentication no\n{am} publickey\n"),
        ("CLEAN", f"{am}\tpublickey,password\n{pka} yes\n"),
        ("CLEAN", f"# generated clean {marker}\nPort 2222\n"),
    ]
    random.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="ssh_holdout_") as directory:
        for index, (expected, content) in enumerate(cases):
            filename = os.path.join(directory, f"{secrets.token_hex(10)}_{index}.conf")
            with open(filename, "w") as config:
                config.write(content)

            result = run_linter_with_python(script_path, filename)
            assert_classification(result, expected, f"generated holdout case {index}")

            direct_result = subprocess.run(
                [script_path, filename],
                capture_output=True,
                text=True,
                timeout=10,
            )
            assert_classification(direct_result, expected, f"direct executable case {index}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
