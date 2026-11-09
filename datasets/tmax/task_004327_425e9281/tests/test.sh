#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile
import uuid
import pytest

SCRIPT_PATH = "/home/user/classifier.sh"
EVIL_CORPUS_DIR = "/app/corpus/evil"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
VIDEO_PATH = "/app/crash_capture.mp4"
DISK_PATH = "/app/system_disk.ext4"
ELF_PATH = "/app/log_formatter.elf"


def test_script_exists_and_executable():
    """Test that the classifier script exists and is executable."""
    assert os.path.isfile(SCRIPT_PATH), f"Classifier script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Classifier script at {SCRIPT_PATH} is not executable"


def test_adversarial_corpus():
    """Keep the original corpus checks."""
    if not os.path.isfile(SCRIPT_PATH) or not os.access(SCRIPT_PATH, os.X_OK):
        pytest.fail("Classifier script missing or not executable.")

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]

    assert len(evil_files) > 0, "Evil corpus is empty."
    assert len(clean_files) > 0, "Clean corpus is empty."

    evil_bypassed = []
    for evil_file in evil_files:
        result = subprocess.run([SCRIPT_PATH, evil_file], capture_output=True)
        if result.returncode != 1:
            evil_bypassed.append(os.path.basename(evil_file))

    clean_modified = []
    for clean_file in clean_files:
        result = subprocess.run([SCRIPT_PATH, clean_file], capture_output=True)
        if result.returncode != 0:
            clean_modified.append(os.path.basename(clean_file))

    error_messages = []
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed[:10])}{'...' if len(evil_bypassed) > 10 else ''}")
    if clean_modified:
        error_messages.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_modified[:10])}{'...' if len(clean_modified) > 10 else ''}")
    if error_messages:
        pytest.fail(" | ".join(error_messages))


def derive_exploit_string():
    """Independently derive the required string from the supplied artifacts."""
    with tempfile.TemporaryDirectory() as frame_dir:
        pattern = os.path.join(frame_dir, "frame_%04d.png")
        subprocess.run(
            ["ffmpeg", "-loglevel", "error", "-i", VIDEO_PATH, pattern],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            timeout=45,
        )

        error_code = None
        for name in sorted(os.listdir(frame_dir)):
            image = os.path.join(frame_dir, name)
            ocr = subprocess.run(
                ["tesseract", image, "stdout", "--psm", "6"],
                capture_output=True,
                text=True,
                timeout=10,
            )
            if ocr.returncode != 0:
                continue
            text = ocr.stdout.replace(" ", "")
            match = re.search(r"ERR[_-]?CODE:?\s*[0oO][xX]([0-9A-Fa-f]+)", text, re.I)
            if match:
                error_code = "0x" + match.group(1).upper()
                break

    assert error_code is not None, "Could not recover ERR_CODE from the video"

    with open(DISK_PATH, "rb") as f:
        disk_data = f.read()
    mappings = {
        code.decode("ascii").upper(): payload.decode("ascii")
        for code, payload in re.findall(
            rb"(0x[0-9A-Fa-f]+)\s*->\s*PAYLOAD_ID:\s*([0-9]+)", disk_data
        )
    }
    payload_id = mappings.get(error_code.upper())
    assert payload_id is not None, f"No recovered mapping for {error_code}"

    with open(ELF_PATH, "rb") as f:
        elf_data = f.read()
    templates = re.findall(rb"(\[CRITICAL_FAULT\][ -~]*?%s[ -~]*)\x00", elf_data)
    assert templates, "Could not recover formatter string from ELF"
    template = templates[0].decode("ascii")
    return template.replace("%s", payload_id)


def test_classifier_on_unlabelled_generated_files():
    """Exercise the classifier on fresh paths whose names do not reveal labels."""
    exploit = derive_exploit_string()
    near_id = re.sub(r"_ID_[0-9]+_", "_ID_10_", exploit)
    near_suffix = exploit.replace("_ABORTING", "_CONTINUING")
    split = exploit.replace("EXPLOIT_TRIGGERED", "EXPLOIT\n_TRIGGERED")

    cases = [
        (b"ordinary log line\n", 0),
        ((near_id + "\n").encode(), 0),
        ((near_suffix + "\n").encode(), 0),
        ((split + "\n").encode(), 0),
        ((exploit[1:] + "\n").encode(), 0),
        ((exploit + "\n").encode(), 1),
        (("prefix-data " + exploit + " trailing-data\n").encode(), 1),
        (("INFO\n" + exploit + "\nINFO\n").encode(), 1),
    ]

    with tempfile.TemporaryDirectory(prefix="classifier-inputs-") as test_dir:
        failures = []
        for contents, expected in cases:
            path = os.path.join(test_dir, uuid.uuid4().hex + ".dat")
            with open(path, "wb") as f:
                f.write(contents)
            result = subprocess.run([SCRIPT_PATH, path], capture_output=True, timeout=10)
            if result.returncode != expected:
                failures.append(
                    f"{os.path.basename(path)} expected exit {expected}, got {result.returncode}"
                )

        # A clean file whose filename itself contains the exploit-like marker
        # ensures classification is based on contents rather than the argument.
        misleading = os.path.join(test_dir, "CRITICAL_FAULT_EXPLOIT_TRIGGERED_WITH_ID_99_ABORTING.log")
        with open(misleading, "w", encoding="utf-8") as f:
            f.write("INFO: clean contents only\n")
        result = subprocess.run([SCRIPT_PATH, misleading], capture_output=True, timeout=10)
        if result.returncode != 0:
            failures.append(f"misleading clean filename expected exit 0, got {result.returncode}")

        assert not failures, " | ".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
