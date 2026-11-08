#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
from pathlib import Path


def natural_key(path):
    return [int(x) if x.isdigit() else x.lower() for x in re.split(r"(\d+)", os.path.basename(path))]


def decode_rgb(path):
    result = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-frames:v", "1", "-pix_fmt", "rgb24", "-f", "rawvideo", "-"],
        capture_output=True,
        timeout=20,
    )
    assert result.returncode == 0, f"Could not decode frame {path}: {result.stderr.decode(errors='replace')}"
    assert result.stdout, f"Decoded frame {path} is empty"
    return result.stdout


def test_video_anomaly_detection():
    timestamps_file = "/home/user/red_alert_timestamps.txt"
    assert os.path.exists(timestamps_file), f"Missing {timestamps_file}"

    with open(timestamps_file, "r") as f:
        content = f.read().strip()

    lines = [line.strip() for line in content.splitlines() if line.strip()]
    expected = ["14", "15", "16", "42", "43"]

    assert set(lines) == set(expected), f"Expected timestamps {expected}, but got {lines}"

    frames_dir = "/home/user/frames"
    assert os.path.isdir(frames_dir), f"Missing extracted frames directory {frames_dir}"

    with tempfile.TemporaryDirectory() as reference_dir:
        reference_pattern = os.path.join(reference_dir, "frame_%06d.png")
        extraction = subprocess.run(
            ["ffmpeg", "-v", "error", "-y", "-i", "/app/rack_monitor.mp4", "-vf", "fps=1", "-start_number", "1", reference_pattern],
            capture_output=True,
            timeout=120,
        )
        assert extraction.returncode == 0, extraction.stderr.decode(errors="replace")

        reference_frames = sorted(
            [str(p) for p in Path(reference_dir).iterdir() if p.is_file()], key=natural_key
        )
        submitted_candidates = sorted(
            [str(p) for p in Path(frames_dir).iterdir() if p.is_file()], key=natural_key
        )
        submitted_frames = []
        for candidate in submitted_candidates:
            probe = subprocess.run(
                ["ffmpeg", "-v", "error", "-i", candidate, "-frames:v", "1", "-f", "null", "-"],
                capture_output=True,
                timeout=20,
            )
            if probe.returncode == 0:
                submitted_frames.append(candidate)

        assert reference_frames, "Reference 1-fps extraction produced no frames"
        assert len(submitted_frames) == len(reference_frames), (
            f"Expected {len(reference_frames)} extracted 1-fps frames, got {len(submitted_frames)}"
        )

        derived_alerts = []
        for frame_number, (submitted, reference) in enumerate(zip(submitted_frames, reference_frames), start=1):
            submitted_rgb = decode_rgb(submitted)
            reference_rgb = decode_rgb(reference)
            assert len(submitted_rgb) == len(reference_rgb), f"Frame {submitted} has incorrect dimensions"
            mean_difference = sum(abs(a - b) for a, b in zip(submitted_rgb, reference_rgb)) / len(reference_rgb)
            assert mean_difference < 10.0, f"Frame {submitted} does not match the corresponding source-video frame"

            red_pixels = sum(
                1
                for i in range(0, len(submitted_rgb), 3)
                if submitted_rgb[i] > 200 and submitted_rgb[i + 1] < 50 and submitted_rgb[i + 2] < 50
            )
            pixel_count = len(submitted_rgb) // 3
            if red_pixels >= max(1, pixel_count // 100):
                derived_alerts.append(str(frame_number))

        assert lines == derived_alerts, f"Timestamps {lines} do not match red pixels in extracted frames {derived_alerts}"

    excluded = {
        "/home/user/alert_filter",
        "/home/user/alert_filter.cpp",
        "/home/user/vault.img",
        "/home/user/red_alert_timestamps.txt",
        "/home/user/vault_fstab",
    }
    analyzer_found = False
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if os.path.join(root, d) not in {frames_dir, "/home/user/proxy_cache", "/home/user/vault_mount"}]
        for name in files:
            path = os.path.join(root, name)
            if path in excluded or os.path.islink(path):
                continue
            suffix = Path(path).suffix.lower()
            if suffix in {".sh", ".bash"}:
                check = subprocess.run(["bash", "-n", path], capture_output=True)
                if check.returncode == 0:
                    analyzer_found = True
            elif suffix in {".cpp", ".cc", ".cxx"}:
                with tempfile.NamedTemporaryFile() as output:
                    check = subprocess.run(["g++", "-std=c++17", path, "-o", output.name], capture_output=True, timeout=60)
                if check.returncode == 0:
                    analyzer_found = True
            elif os.path.isfile(path) and os.access(path, os.X_OK):
                analyzer_found = True
    assert analyzer_found, "No valid bash script or compiled/compilable C++ frame analyzer was found"


def test_webhook_sanitizer_binary_exists():
    source_path = "/home/user/alert_filter.cpp"
    binary_path = "/home/user/alert_filter"
    assert os.path.isfile(source_path), f"Source {source_path} does not exist"
    assert os.path.exists(binary_path), f"Binary {binary_path} does not exist"
    assert os.access(binary_path, os.X_OK), f"Binary {binary_path} is not executable"


def test_webhook_sanitizer_adversarial_corpus():
    binary_path = "/home/user/alert_filter"
    evil_corpus = "/app/corpus/evil"
    clean_corpus = "/app/corpus/clean"

    evil_files = [os.path.join(evil_corpus, f) for f in os.listdir(evil_corpus) if os.path.isfile(os.path.join(evil_corpus, f))]
    evil_failures = []
    for f in evil_files:
        result = subprocess.run([binary_path, f], capture_output=True)
        if result.returncode == 0:
            evil_failures.append(os.path.basename(f))

    clean_files = [os.path.join(clean_corpus, f) for f in os.listdir(clean_corpus) if os.path.isfile(os.path.join(clean_corpus, f))]
    clean_failures = []
    for f in clean_files:
        result = subprocess.run([binary_path, f], capture_output=True)
        if result.returncode != 0:
            clean_failures.append(os.path.basename(f))

    error_msg = []
    if evil_failures:
        error_msg.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        error_msg.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failures)}")

    assert not error_msg, " | ".join(error_msg)


def test_webhook_sanitizer_generated_inputs_and_source():
    source_path = "/home/user/alert_filter.cpp"
    installed_binary = "/home/user/alert_filter"
    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt_binary = os.path.join(tmpdir, "rebuilt_filter")
        build = subprocess.run(
            ["g++", "-std=c++17", source_path, "-o", rebuilt_binary],
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert build.returncode == 0, f"alert_filter.cpp does not compile: {build.stderr}"

        marker = secrets.token_hex(18)
        cases = [
            (f'{{"status":"ok","message":"{marker}"}}'.encode(), 0),
            (f'{{"path":"reports/2026/{marker}.json"}}'.encode(), 0),
            ((f'{{"data":"' + "A" * 1000 + '"}}').encode(), 0),
            (f'{{"path":"prefix/{marker}/../secret"}}'.encode(), 1),
            (f'{{"path":"prefix/{marker}/..%2Fsecret"}}'.encode(), 1),
            ((f'{{"data":"' + marker + "B" * 1001 + '"}}').encode(), 1),
            (b'{"path":"safe/' + marker.encode() + b'\x00hidden"}', 1),
        ]

        for payload, expected_code in cases:
            path = os.path.join(tmpdir, secrets.token_hex(16))
            with open(path, "wb") as payload_file:
                payload_file.write(payload)
            for binary in (installed_binary, rebuilt_binary):
                result = subprocess.run([binary, path], capture_output=True, timeout=10)
                assert result.returncode == expected_code, (
                    f"{binary} returned {result.returncode}, expected {expected_code}, for generated payload {payload[:80]!r}"
                )


def test_filesystem_and_vault_setup():
    img_path = "/home/user/vault.img"
    mount_point = "/home/user/vault_mount"
    proxy_cache = "/home/user/proxy_cache"
    alerts_symlink = os.path.join(proxy_cache, "alerts")
    metrics_dir = os.path.join(proxy_cache, "metrics")
    logs_dir = os.path.join(proxy_cache, "logs")
    fstab_file = "/home/user/vault_fstab"

    assert os.path.exists(img_path), f"Missing {img_path}"
    assert os.path.isfile(img_path), f"{img_path} is not a regular file"
    assert os.path.getsize(img_path) == 50 * 1024 * 1024, f"{img_path} is not exactly 50MB"

    result = subprocess.run(["blkid", "-o", "value", "-s", "TYPE", img_path], capture_output=True, text=True)
    assert result.stdout.strip() == "ext4", f"{img_path} is not formatted as ext4"

    assert os.path.isdir(mount_point), f"Missing mount point {mount_point}"
    assert os.path.isdir(metrics_dir), f"Missing metrics dir {metrics_dir}"
    assert os.path.isdir(logs_dir), f"Missing logs dir {logs_dir}"

    assert os.path.islink(alerts_symlink), f"{alerts_symlink} is not a symlink"
    target = os.readlink(alerts_symlink)
    assert target == "/home/user/vault_mount/alerts", f"Symlink target is {target}, expected /home/user/vault_mount/alerts"

    assert os.path.exists(fstab_file), f"Missing {fstab_file}"
    with open(fstab_file, "r") as f:
        raw_fstab = f.read()
    physical_lines = raw_fstab.splitlines()
    assert len(physical_lines) == 1 and physical_lines[0].strip(), "vault_fstab must contain only one non-empty line"
    fstab_content = raw_fstab.strip().split()

    assert len(fstab_content) >= 6, "fstab line format is incorrect"
    assert fstab_content[0] == "/home/user/vault.img", f"Incorrect fstab device: {fstab_content[0]}"
    assert fstab_content[1] == "/home/user/vault_mount", f"Incorrect fstab mount point: {fstab_content[1]}"
    assert fstab_content[2] == "ext4", f"Incorrect fstab fs type: {fstab_content[2]}"
    assert "loop" in fstab_content[3].split(","), f"Missing loop option in fstab: {fstab_content[3]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
