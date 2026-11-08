#!/bin/bash
set -e
mkdir -p /logs/verifier

# Prevent the submitted checker, which is executed unprivileged below, from
# changing the policy inputs while it is being evaluated.
chmod 0755 /app 2>/dev/null || true
chmod 0444 /app/manifest.txt /app/breach_record.mp4 2>/dev/null || true
find /app/clean_corpus /app/evil_corpus -type d -exec chmod 0555 {} + 2>/dev/null || true
find /app/clean_corpus /app/evil_corpus -type f -exec chmod 0444 {} + 2>/dev/null || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import pwd
import py_compile
import random
import secrets
import shutil
import stat
import string
import subprocess
import tempfile
import uuid
from pathlib import Path

import cv2
import numpy as np
import pytest

SCRIPT_PATH = "/home/user/policy_checker.py"


def _drop_privileges():
    account = pwd.getpwnam("user")
    os.setgroups([])
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)


def run_checker(file_path):
    return subprocess.run(
        ["python3", SCRIPT_PATH, str(file_path)],
        capture_output=True,
        text=True,
        timeout=15,
        preexec_fn=_drop_privileges,
    )


def test_policy_checker_exists():
    script_path = "/home/user/policy_checker.py"
    assert os.path.isfile(script_path), f"Missing policy checker script at {script_path}"


def test_adversarial_corpus_evaluation():
    script_path = "/home/user/policy_checker.py"
    clean_corpus_path = "/app/clean_corpus"
    evil_corpus_path = "/app/evil_corpus"

    assert os.path.isdir(clean_corpus_path), f"Missing clean corpus directory at {clean_corpus_path}"
    assert os.path.isdir(evil_corpus_path), f"Missing evil corpus directory at {evil_corpus_path}"

    clean_files = sorted([os.path.join(clean_corpus_path, f) for f in os.listdir(clean_corpus_path) if f.endswith(".pyc")])
    evil_files = sorted([os.path.join(evil_corpus_path, f) for f in os.listdir(evil_corpus_path) if f.endswith(".pyc")])

    assert len(clean_files) > 0, "No .pyc files found in clean corpus."
    assert len(evil_files) > 0, "No .pyc files found in evil corpus."

    clean_failed = []
    evil_failed = []

    # Test clean corpus (expected exit code 0)
    for file_path in clean_files:
        result = run_checker(file_path)
        if result.returncode != 0:
            clean_failed.append(os.path.basename(file_path))

    # Test evil corpus (expected exit code 1)
    for file_path in evil_files:
        result = run_checker(file_path)
        if result.returncode != 1:
            evil_failed.append(os.path.basename(file_path))

    errors = []
    if evil_failed:
        errors.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_failed)}")

    if errors:
        pytest.fail(" | ".join(errors))


def _decode_video_signature(path):
    capture = cv2.VideoCapture(str(path))
    assert capture.isOpened(), f"Could not open video {path}"
    bits = []
    while True:
        ok, frame = capture.read()
        if not ok:
            break
        average = float(np.mean(frame))
        assert average != 128, "Ambiguous frame luminance"
        bits.append("1" if average > 128 else "0")
    capture.release()

    assert len(bits) == 64, f"Expected 64 frames, found {len(bits)}"
    return "".join(chr(int("".join(bits[i:i + 8]), 2)) for i in range(0, 64, 8))


def _write_video(path, signature):
    writer = cv2.VideoWriter(
        str(path), cv2.VideoWriter_fourcc(*"mp4v"), 10, (100, 100)
    )
    assert writer.isOpened(), "Could not create verification video"
    bits = "".join(format(ord(character), "08b") for character in signature)
    for bit in bits:
        value = 255 if bit == "1" else 0
        writer.write(np.full((100, 100, 3), value, dtype=np.uint8))
    writer.release()


def _compile_case(directory, source):
    token = uuid.uuid4().hex
    source_path = directory / f"{token}.py"
    pyc_path = directory / f"{uuid.uuid4().hex}.pyc"
    source_path.write_text(source, encoding="utf-8")
    py_compile.compile(str(source_path), cfile=str(pyc_path), doraise=True)
    source_path.unlink()
    os.chmod(pyc_path, 0o444)
    return pyc_path


def _sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def test_generated_policy_cases_with_rotated_video_and_manifest():
    manifest_path = Path("/app/manifest.txt")
    video_path = Path("/app/breach_record.mp4")
    assert manifest_path.is_file(), "Missing manifest"
    assert video_path.is_file(), "Missing breach video"

    original_manifest = manifest_path.read_bytes()
    original_video = video_path.read_bytes()
    manifest_mode = stat.S_IMODE(manifest_path.stat().st_mode)
    video_mode = stat.S_IMODE(video_path.stat().st_mode)

    work = Path(tempfile.mkdtemp(prefix="policy-verification-", dir="/tmp"))
    os.chmod(work, 0o755)
    replacement_video = Path("/app") / f".{uuid.uuid4().hex}.mp4"

    try:
        # Rotate the video to an unpredictable signature so a hard-coded answer
        # cannot pass. Expected payload bytes are independently decoded from it.
        requested_signature = "".join(
            secrets.choice(string.ascii_uppercase + string.digits) for _ in range(8)
        )
        _write_video(replacement_video, requested_signature)
        os.chmod(replacement_video, 0o444)
        os.replace(replacement_video, video_path)
        os.chmod(video_path, 0o444)
        signature = _decode_video_signature(video_path)
        assert signature == requested_signature

        harmless_one = uuid.uuid4().hex
        harmless_two = uuid.uuid4().hex
        clean_authorized = _compile_case(
            work, f"value = {harmless_one!r}\nprint(value)\n"
        )
        clean_unauthorized = _compile_case(
            work, f"value = {harmless_two!r}\nprint(value)\n"
        )
        malicious_whole = _compile_case(
            work, f"payload = {signature!r}\nprint(payload)\n"
        )
        split_at = secrets.randbelow(7) + 1
        malicious_split = _compile_case(
            work,
            f"left = {signature[:split_at]!r}\n"
            f"right = {signature[split_at:]!r}\n"
            "payload = left + right\nprint(payload)\n",
        )

        authorized = [clean_authorized, malicious_whole, malicious_split]
        manifest_entries = [_sha256(path) for path in authorized]
        manifest_entries.extend(secrets.token_hex(32) for _ in range(5))
        random.SystemRandom().shuffle(manifest_entries)
        manifest_path.write_text("\n".join(manifest_entries) + "\n", encoding="ascii")
        os.chmod(manifest_path, 0o444)
        os.chmod(work, 0o555)

        cases = [
            (clean_authorized, 0, "authorized clean bytecode was rejected"),
            (clean_unauthorized, 1, "unmanifested clean bytecode was accepted"),
            (malicious_whole, 1, "whole malware signature was accepted"),
            (malicious_split, 1, "split malware signature was accepted"),
        ]
        random.SystemRandom().shuffle(cases)

        failures = []
        for path, expected, description in cases:
            result = run_checker(path)
            if result.returncode != expected:
                failures.append(
                    f"{description}: expected {expected}, got {result.returncode}"
                )
        assert not failures, " | ".join(failures)
    finally:
        manifest_path.write_bytes(original_manifest)
        video_path.write_bytes(original_video)
        os.chmod(manifest_path, manifest_mode)
        os.chmod(video_path, video_mode)
        if replacement_video.exists():
            replacement_video.unlink()
        os.chmod(work, 0o755)
        shutil.rmtree(work, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
