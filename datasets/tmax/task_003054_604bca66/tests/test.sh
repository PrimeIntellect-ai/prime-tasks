#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import string
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/redact.sh"
AUDIT_TRAIL_PATH = "/home/user/audit_trail.txt"
VIDEO_PATH = "/app/admin_session.mp4"
EVIL_DIR = "/app/corpora/evil"
CLEAN_DIR = "/app/corpora/clean"


def python_redact(text):
    # Redact AWS Access Keys
    text = re.sub(r'AKIA[A-Z0-9]{16}', '[REDACTED_AWS]', text)
    # Redact URL Credentials
    text = re.sub(r'(https?://[^:\s@/]+:)([^:@\s/]+)(@)', r'\g<1>[REDACTED_CREDS]\3', text)
    return text


def run_script(file_path):
    result = subprocess.run(
        ["/bin/bash", SCRIPT_PATH, file_path],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Redaction script failed for {file_path}: {result.stderr}"
    return result.stdout


def video_ocr_text():
    with tempfile.TemporaryDirectory() as frame_dir:
        subprocess.run(
            [
                "ffmpeg", "-loglevel", "error", "-i", VIDEO_PATH,
                "-vf", "fps=1", os.path.join(frame_dir, "frame_%03d.png")
            ],
            check=True,
            capture_output=True,
            text=True
        )
        frames = sorted(
            os.path.join(frame_dir, name)
            for name in os.listdir(frame_dir)
            if name.endswith(".png")
        )
        assert len(frames) == 3, f"Expected 3 video frames, got {len(frames)}"

        text = ""
        for frame in frames:
            result = subprocess.run(
                ["tesseract", frame, "stdout"],
                check=True,
                capture_output=True,
                text=True
            )
            text += result.stdout
        return text


def normalize_whitespace(text):
    return re.sub(r'\s+', ' ', text).strip()


def test_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"Redaction script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"


def test_audit_trail_exists_and_redacted():
    assert os.path.exists(AUDIT_TRAIL_PATH), f"Audit trail not found at {AUDIT_TRAIL_PATH}"
    with open(AUDIT_TRAIL_PATH, "r") as f:
        content = f.read()

    assert "[REDACTED_CREDS]" in content, "Audit trail missing [REDACTED_CREDS]"
    assert "[REDACTED_AWS]" in content, "Audit trail missing [REDACTED_AWS]"
    assert "supersecret99" not in content, "Audit trail still contains the URL password"
    assert "AKIAIOSFODNN7EXAMPLE" not in content, "Audit trail still contains the AWS key"

    expected = python_redact(video_ocr_text())
    assert normalize_whitespace(content) == normalize_whitespace(expected), \
        "Audit trail does not match the redacted OCR text from the video"


def test_clean_corpus():
    if not os.path.exists(CLEAN_DIR):
        pytest.skip("Clean corpus dir missing")

    clean_files = [os.path.join(CLEAN_DIR, f) for f in os.listdir(CLEAN_DIR) if os.path.isfile(os.path.join(CLEAN_DIR, f))]
    modified_files = []

    for cf in clean_files:
        with open(cf, "r") as f:
            original = f.read()
        output = run_script(cf)
        if output != original:
            modified_files.append(os.path.basename(cf))

    assert not modified_files, f"{len(modified_files)} of {len(clean_files)} clean modified: {', '.join(modified_files)}"


def test_evil_corpus():
    if not os.path.exists(EVIL_DIR):
        pytest.skip("Evil corpus dir missing")

    evil_files = [os.path.join(EVIL_DIR, f) for f in os.listdir(EVIL_DIR) if os.path.isfile(os.path.join(EVIL_DIR, f))]
    bypassed_files = []

    for ef in evil_files:
        with open(ef, "r") as f:
            original = f.read()
        expected = python_redact(original)
        output = run_script(ef)

        # Require the complete transformed output, while retaining the explicit leak checks.
        if output != expected or re.search(r'AKIA[A-Z0-9]{16}', output) or re.search(r'https?://[^:\s@/]+:[^:@\s/]+@', output):
            bypassed_files.append(os.path.basename(ef))

    assert not bypassed_files, f"{len(bypassed_files)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_files)}"


def test_runtime_generated_input():
    alphabet = string.ascii_uppercase + string.digits
    aws_key = "AKIA" + "".join(secrets.choice(alphabet) for _ in range(16))
    username = "user" + secrets.token_hex(4)
    password = "pass" + secrets.token_hex(8)
    host = secrets.token_hex(5) + ".example.test"
    original = (
        "prefix text must remain unchanged\n"
        f"export TOKEN={aws_key}\n"
        f"curl https://{username}:{password}@{host}/v1/data\n"
        "suffix text and AKIA_TOO_SHORT must remain unchanged\n"
    )
    expected = python_redact(original)

    with tempfile.NamedTemporaryFile(mode="w", delete=False) as test_file:
        test_file.write(original)
        test_path = test_file.name

    try:
        assert run_script(test_path) == expected
    finally:
        os.unlink(test_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
