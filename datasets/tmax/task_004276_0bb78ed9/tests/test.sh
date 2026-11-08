#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pathlib
import subprocess
import tempfile
import uuid

from PIL import Image


def test_event_indices():
    indices_file = "/home/user/event_indices.txt"
    assert os.path.isfile(indices_file), f"Missing {indices_file}"

    with open(indices_file, "r") as f:
        content = f.read().strip().split()

    # Preserve the original assertion.
    expected_indices = ["5", "12", "19", "34", "51"]
    assert content == expected_indices, f"Expected indices {expected_indices}, but got {content}"

    # Independently decode the supplied video and derive the event indices.
    with tempfile.TemporaryDirectory(prefix="decoded-audit-") as frame_dir:
        pattern = os.path.join(frame_dir, "frame_%06d.png")
        subprocess.run(
            ["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", "/app/audit_log.mp4",
             "-vf", "fps=1", pattern],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
        frame_paths = sorted(pathlib.Path(frame_dir).glob("frame_*.png"))
        assert frame_paths, "ffmpeg extracted no audit frames"
        derived = []
        for index, frame_path in enumerate(frame_paths):
            with Image.open(frame_path) as image:
                rgb = image.convert("RGB")
                pixels = [rgb.getpixel((x, y)) for y in range(10) for x in range(10)]
                # The source was encoded with lossy H.264, so decoded white pixels
                # may differ slightly from 255 while remaining clearly white.
                if all(min(pixel) >= 245 for pixel in pixels):
                    derived.append(str(index))

    assert content == derived, f"Indices do not match events decoded from the video: {derived}"
    assert pathlib.Path(indices_file).read_text().splitlines() == derived, \
        "event_indices.txt must contain exactly one index per line"


def test_final_configuration_from_template():
    dag = pathlib.Path("/app/config_dag.tsv")
    template = pathlib.Path("/app/template.conf")
    output = pathlib.Path("/home/user/final_config.conf")
    assert dag.is_file(), f"Missing DAG input {dag}"
    assert template.is_file(), f"Missing template input {template}"
    assert output.is_file(), f"Missing generated configuration {output}"

    # This fixture's template has no placeholders, so correct template processing
    # must preserve its bytes in the generated configuration.
    assert output.read_bytes() == template.read_bytes(), \
        "final_config.conf was not generated correctly from template.conf"


def test_config_sanitizer_executable():
    executable = "/home/user/config_sanitizer"
    assert os.path.isfile(executable), f"Missing executable {executable}"
    assert os.access(executable, os.X_OK), f"{executable} is not executable"
    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", "config_sanitizer must be a compiled executable"


def test_config_sanitizer_clean_corpus():
    executable = "/home/user/config_sanitizer"
    clean_dir = "/app/corpus/clean"
    assert os.path.isdir(clean_dir), f"Missing clean corpus dir {clean_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir)
                   if os.path.isfile(os.path.join(clean_dir, f))]

    failed_files = []
    for filepath in clean_files:
        result = subprocess.run([executable, filepath], capture_output=True, text=True)
        if result.returncode != 0 or "ACCEPT" not in result.stdout:
            failed_files.append(os.path.basename(filepath))

    assert not failed_files, \
        f"{len(failed_files)} of {len(clean_files)} clean files modified/rejected: {failed_files}"


def test_config_sanitizer_evil_corpus():
    executable = "/home/user/config_sanitizer"
    evil_dir = "/app/corpus/evil"
    assert os.path.isdir(evil_dir), f"Missing evil corpus dir {evil_dir}"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir)
                  if os.path.isfile(os.path.join(evil_dir, f))]

    failed_files = []
    for filepath in evil_files:
        result = subprocess.run([executable, filepath], capture_output=True, text=True)
        if result.returncode != 1 or "REJECT" not in result.stdout:
            failed_files.append(os.path.basename(filepath))

    assert not failed_files, \
        f"{len(failed_files)} of {len(evil_files)} evil files bypassed: {failed_files}"


def test_config_sanitizer_generated_adversarial_cases():
    executable = "/home/user/config_sanitizer"
    cases = [
        ("ключ=значение\n日本語=安全\nemoji=✓\n", 0, "ACCEPT"),
        ('value="$HOME; `echo ok` | literal"\n', 0, "ACCEPT"),
        ("value='$HOME; `echo ok` | literal'\n", 0, "ACCEPT"),
        (r"escaped=\$HOME escaped2=\; escaped3=\| escaped4=\`" + "\n", 0, "ACCEPT"),
        ("before $HOME after\n", 1, "REJECT"),
        ("before `whoami` after\n", 1, "REJECT"),
        ("left | right\n", 1, "REJECT"),
        ("first; second\n", 1, "REJECT"),
        ('quoted="safe"; outside\n', 1, "REJECT"),
        ("unicode-prefix Привет \u202e suffix\n", 1, "REJECT"),
        ('inside-quote="\u202e"\n', 1, "REJECT"),
    ]

    # Names and directory do not reveal the expected classification.
    with tempfile.TemporaryDirectory(prefix="cfg-cases-") as case_dir:
        for content, expected_code, expected_word in cases:
            path = os.path.join(case_dir, uuid.uuid4().hex)
            pathlib.Path(path).write_text(content, encoding="utf-8")
            result = subprocess.run(
                [executable, path], capture_output=True, text=True, timeout=5
            )
            assert result.returncode == expected_code, \
                f"Wrong exit code for generated content {content!r}: {result.returncode}"
            assert result.stdout.strip() == expected_word, \
                f"Wrong classification for generated content {content!r}: {result.stdout!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
