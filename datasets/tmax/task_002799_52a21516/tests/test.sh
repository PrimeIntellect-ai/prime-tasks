#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import functools
import ipaddress
import os
import random
import re
import secrets
import shutil
import ssl
import subprocess
import tempfile
import urllib.request

import pytest


@functools.lru_cache(maxsize=1)
def derived_red_frame_count():
    """Decode the mounted video and derive the number of uniformly red frames."""
    video = "/mnt/evidence/network_status.mp4"
    assert os.path.isfile(video), f"{video} does not exist."

    probe = subprocess.run(
        [
            "ffprobe", "-v", "error", "-select_streams", "v:0",
            "-show_entries", "stream=width,height", "-of", "csv=p=0:s=x", video,
        ],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert probe.returncode == 0, f"ffprobe failed: {probe.stderr}"
    match = re.fullmatch(r"(\d+)x(\d+)", probe.stdout.strip())
    assert match, f"Could not determine video dimensions: {probe.stdout!r}"
    width, height = map(int, match.groups())

    decoded = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", video, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
        capture_output=True,
        timeout=30,
    )
    assert decoded.returncode == 0, f"ffmpeg failed: {decoded.stderr.decode(errors='replace')}"

    frame_size = width * height * 3
    assert frame_size > 0 and len(decoded.stdout) % frame_size == 0, "Decoded video contains incomplete frames."

    count = 0
    for offset in range(0, len(decoded.stdout), frame_size):
        frame = decoded.stdout[offset:offset + frame_size]
        # The supplied MP4 uses chroma-subsampled lossy encoding, so decoded
        # pure-red source pixels can differ by a few levels from (255, 0, 0).
        if (all(value >= 250 for value in frame[0::3]) and
                all(value <= 5 for value in frame[1::3]) and
                all(value <= 5 for value in frame[2::3])):
            count += 1
    return count


def test_mount_and_fstab():
    """Verify that the image is mounted and fstab is updated."""
    mount_point = "/mnt/evidence"
    assert os.path.ismount(mount_point), f"{mount_point} is not a mount point."

    with open("/etc/fstab", "r") as f:
        fstab_content = f.read()

    fstab_regex = re.compile(r"^/app/evidence\.img\s+/mnt/evidence\s+ext4", re.MULTILINE)
    assert fstab_regex.search(fstab_content), "fstab does not contain the correct entry for /app/evidence.img."


def test_drop_count():
    """Verify the drop count file against a fresh analysis of the video."""
    drop_count_file = "/home/user/drop_count.txt"
    assert os.path.isfile(drop_count_file), f"{drop_count_file} does not exist."

    with open(drop_count_file, "r") as f:
        content = f.read().strip()

    expected = str(derived_red_frame_count())
    assert content == expected, f"Expected drop count to be {expected!r}, but got {content!r}."


def classifier_path():
    candidates = ["/home/user/classify_logs.py", "/home/user/classify_logs.sh"]
    for path in candidates:
        if os.path.isfile(path) and os.access(path, os.X_OK):
            return path
    pytest.fail("Executable classify_logs script not found at /home/user/classify_logs.py or .sh")


def run_classifier(script_path, filepath):
    try:
        result = subprocess.run(
            [script_path, filepath], capture_output=True, text=True, timeout=5
        )
    except Exception as exc:
        pytest.fail(f"Classifier could not process {filepath}: {exc}")
    assert result.returncode == 0, (
        f"Classifier exited with status {result.returncode} for {filepath}: {result.stderr}"
    )
    return result.stdout.strip()


def test_adversarial_corpus():
    """Verify the classifier on both any shipped corpus and fresh hidden cases."""
    script_path = classifier_path()

    evil_dir = "/app/corpus/evil/"
    clean_dir = "/app/corpus/clean/"

    evil_failures = []
    if os.path.isdir(evil_dir):
        for filename in os.listdir(evil_dir):
            filepath = os.path.join(evil_dir, filename)
            if os.path.isfile(filepath) and run_classifier(script_path, filepath) != "EVIL":
                evil_failures.append(filename)

    clean_failures = []
    if os.path.isdir(clean_dir):
        for filename in os.listdir(clean_dir):
            filepath = os.path.join(clean_dir, filename)
            if os.path.isfile(filepath) and run_classifier(script_path, filepath) != "CLEAN":
                clean_failures.append(filename)

    error_msg = ""
    if evil_failures:
        error_msg += f"{len(evil_failures)} evil bypassed: {', '.join(evil_failures)}. "
    if clean_failures:
        error_msg += f"{len(clean_failures)} clean modified/flagged: {', '.join(clean_failures)}."
    assert not evil_failures and not clean_failures, error_msg.strip()

    # Each tuple is (source IP, status code, field order). Labels are computed
    # from the task rule rather than supplied to the classifier.
    cases = [
        [],
        [("10.99.1.4", 499, 0), ("10.99.254.8", 499, 1)],
        [("10.99.2.1", 499, 0), ("10.99.2.2", 499, 1), ("10.99.2.3", 499, 0)],
        [("10.98.1.1", 499, 0), ("10.99.4.1", 500, 1), ("192.0.2.8", 499, 0),
         ("10.99.4.2", 200, 0)],
        [("10.99.7.1", 499, 1), ("203.0.113.9", 404, 0), ("10.99.7.2", 499, 0),
         ("10.99.7.3", 499, 1), ("10.99.7.4", 503, 0)],
        [("10.99.0.1", 499, 0), ("10.99.255.254", 499, 0), ("10.99.88.9", 499, 1),
         ("10.9.99.1", 499, 0)],
    ]
    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="classifier-corpus-") as corpus:
        for case_number, entries in enumerate(cases):
            lines = []
            matching = 0
            for ip_text, status, order in entries:
                ip = ipaddress.ip_address(ip_text)
                if ip.version == 4 and ip.packed[0] == 10 and ip.packed[1] == 99 and status == 499:
                    matching += 1
                token = secrets.token_hex(5)
                if order == 0:
                    lines.append(f"2026-09-11T12:00:00Z request={token} source_ip={ip_text} Status Code {status}")
                else:
                    lines.append(f"2026-09-11T12:00:00Z request={token} Status Code {status} originating_from={ip_text}")
            random.SystemRandom().shuffle(lines)
            path = os.path.join(corpus, f"case-{secrets.token_hex(8)}.log")
            with open(path, "w") as handle:
                handle.write("\n".join(lines) + ("\n" if lines else ""))
            expected = "EVIL" if matching >= 3 else "CLEAN"
            actual = run_classifier(script_path, path)
            assert actual == expected, (
                f"Classifier returned {actual!r}, expected {expected!r} for generated case {case_number}."
            )


def test_web_server():
    """Verify the web server is running in a container and serves derived content over HTTPS."""
    runtime_results = []
    found = False
    for runtime in ("docker", "podman"):
        executable = shutil.which(runtime)
        if not executable:
            continue
        result = subprocess.run(
            [executable, "ps", "--format", "{{.Names}}"], capture_output=True, text=True, timeout=10
        )
        runtime_results.append(f"{runtime}: rc={result.returncode}, stderr={result.stderr.strip()}")
        if result.returncode == 0 and "alert-web" in result.stdout.splitlines():
            found = True
            break
    assert found, "Container 'alert-web' is not running. " + "; ".join(runtime_results)

    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    try:
        req = urllib.request.Request("https://localhost:8443/")
        with urllib.request.urlopen(req, context=ctx, timeout=5) as response:
            content = response.read().decode("utf-8")
    except Exception as exc:
        pytest.fail(f"Failed to connect to https://localhost:8443/: {exc}")

    expected = f"CRITICAL_ALERT: {derived_red_frame_count()}"
    assert expected in content, f"Expected {expected!r} in web server response, but got: {content}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
