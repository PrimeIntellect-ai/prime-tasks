#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import shutil
import subprocess
import tempfile
import uuid
from pathlib import Path

BINARY = Path("/home/user/edge_filter/target/release/edge_filter")
DEPLOY = Path("/home/user/deploy.sh")
VIDEO = Path("/app/signal_test.mp4")
DROPOUTS = Path("/home/user/dropouts.txt")
EXPECTED_ORIGINAL = ["42", "43", "44", "89"]


def run_binary(path):
    return subprocess.run([str(BINARY), str(path)], capture_output=True, timeout=30)


def read_dropouts():
    assert DROPOUTS.is_file(), f"Expected output file {DROPOUTS} does not exist."
    return [line.strip() for line in DROPOUTS.read_text().splitlines() if line.strip()]


def run_deploy():
    return subprocess.run(
        ["bash", str(DEPLOY)], capture_output=True, text=True, timeout=240
    )


def make_video(path, black_frames):
    width, height, count = 320, 240, 150
    black = bytes([0, 0, 0]) * (width * height)
    normal = bytes([100, 120, 140]) * (width * height)
    raw = b"".join(black if index in black_frames else normal for index in range(count))
    result = subprocess.run(
        [
            "ffmpeg", "-y", "-loglevel", "error",
            "-f", "rawvideo", "-pix_fmt", "rgb24",
            "-s", f"{width}x{height}", "-r", "30", "-i", "pipe:0",
            "-frames:v", str(count), "-c:v", "libx264", "-qp", "0",
            "-pix_fmt", "yuv420p", str(path),
        ],
        input=raw,
        capture_output=True,
        timeout=120,
    )
    assert result.returncode == 0, result.stderr.decode(errors="replace")


def test_video_analyzer_output():
    """Test that the video signal analyzer correctly identified the black frames."""
    output_file = Path("/home/user/dropouts.txt")
    assert output_file.is_file(), f"Expected output file {output_file} does not exist."

    with open(output_file, "r") as f:
        lines = f.read().splitlines()

    lines = [line.strip() for line in lines if line.strip()]
    expected_frames = ["42", "43", "44", "89"]
    assert lines == expected_frames, f"Expected frames {expected_frames}, but got {lines}."


def test_adversarial_corpus():
    """Test that the Rust binary correctly accepts clean payloads and rejects evil payloads."""
    binary_path = Path("/home/user/edge_filter/target/release/edge_filter")
    assert binary_path.is_file(), f"Rust binary not found at {binary_path}."
    assert os.access(binary_path, os.X_OK), f"Rust binary at {binary_path} is not executable."

    clean_dir = Path("/app/corpora/clean")
    evil_dir = Path("/app/corpora/evil")
    assert clean_dir.is_dir(), f"Clean corpus directory missing: {clean_dir}"
    assert evil_dir.is_dir(), f"Evil corpus directory missing: {evil_dir}"

    clean_files = list(clean_dir.glob("*.json"))
    evil_files = list(evil_dir.glob("*.json"))
    assert len(clean_files) > 0, "No clean files found."
    assert len(evil_files) > 0, "No evil files found."

    clean_failed = []
    for clean_file in clean_files:
        result = subprocess.run([str(binary_path), str(clean_file)], capture_output=True)
        if result.returncode != 0:
            clean_failed.append(clean_file.name)

    evil_bypassed = []
    for evil_file in evil_files:
        result = subprocess.run([str(binary_path), str(evil_file)], capture_output=True)
        if result.returncode == 0:
            evil_bypassed.append(evil_file.name)

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_failed)}")
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed (accepted): {', '.join(evil_bypassed)}")
    assert not errors, "Adversarial corpus verification failed: " + "; ".join(errors)


def test_sanitizer_on_independent_payloads():
    """Exercise JSON parsing and every required target_path substring outside the fixed corpus paths."""
    assert BINARY.is_file() and os.access(BINARY, os.X_OK)

    with tempfile.TemporaryDirectory(prefix="validator-cases-") as directory:
        root = Path(directory)
        nonce = uuid.uuid4().hex
        cases = [
            ("safe", {"sync_interval": 7, "target_path": f"/srv/{nonce}/data", "device_id": "cam && ../ $( ` ||"}, 0),
            ("traversal", {"device_id": nonce, "target_path": "/srv/data/../secret", "sync_interval": 1}, 1),
            ("substitution", {"device_id": nonce, "target_path": "/srv/$(id)/data", "sync_interval": 1}, 1),
            ("backtick", {"device_id": nonce, "target_path": "/srv/`id`/data", "sync_interval": 1}, 1),
            ("and", {"device_id": nonce, "target_path": "/srv/data && id", "sync_interval": 1}, 1),
            ("or", {"device_id": nonce, "target_path": "/srv/data || id", "sync_interval": 1}, 1),
        ]
        for label, payload, expected in cases:
            path = root / f"{uuid.uuid4().hex}-{label}.json"
            path.write_text(json.dumps(payload))
            result = run_binary(path)
            assert result.returncode == expected, (
                f"{label} payload expected exit {expected}, got {result.returncode}; "
                f"stdout={result.stdout!r}, stderr={result.stderr!r}"
            )

        escaped = root / f"{uuid.uuid4().hex}-escaped.json"
        escaped.write_text(
            '{"sync_interval":1,"device_id":"cam","target_path":"/srv/\\u002e\\u002e/secret"}'
        )
        result = run_binary(escaped)
        assert result.returncode == 1, "Decoded dangerous substrings in JSON strings must be rejected."


def test_deploy_script_exists():
    """Test that the deployment script was created."""
    deploy_script = Path("/home/user/deploy.sh")
    assert deploy_script.is_file(), f"Deployment script not found at {deploy_script}."


def test_deploy_builds_checks_corpora_extracts_video_and_is_idempotent():
    assert DEPLOY.is_file()
    assert Path("/home/user/edge_filter/Cargo.toml").is_file()
    assert Path("/home/user/edge_filter/src/main.rs").is_file()

    clean_dir = Path("/app/corpora/clean")
    evil_dir = Path("/app/corpora/evil")
    token = uuid.uuid4().hex
    clean_extra = clean_dir / f"generated-{token}.json"
    evil_extra = evil_dir / f"generated-{token}.json"
    evil_should_fail = evil_dir / f"unexpected-clean-{token}.json"
    clean_should_fail = clean_dir / f"unexpected-evil-{token}.json"

    with tempfile.TemporaryDirectory(prefix="deploy-verification-") as directory:
        root = Path(directory)
        backup_video = root / "signal_test.original.mp4"
        generated_video = root / "signal_test.generated.mp4"
        shutil.copy2(VIDEO, backup_video)
        dynamic_frames = sorted(random.SystemRandom().sample(range(5, 145), 5))
        make_video(generated_video, set(dynamic_frames))

        try:
            clean_extra.write_text(json.dumps({
                "device_id": token,
                "target_path": f"/var/generated/{token}",
                "sync_interval": 17,
            }))
            evil_extra.write_text(json.dumps({
                "device_id": token,
                "target_path": f"/var/generated/{token} || false",
                "sync_interval": 17,
            }))
            shutil.copyfile(generated_video, VIDEO)

            if BINARY.exists():
                BINARY.unlink()
            if DROPOUTS.exists():
                DROPOUTS.unlink()

            first = run_deploy()
            assert first.returncode == 0, f"First deployment failed: stdout={first.stdout!r}, stderr={first.stderr!r}"
            assert BINARY.is_file() and os.access(BINARY, os.X_OK), "Deployment did not build the release binary."
            expected_dynamic = [str(index) for index in dynamic_frames]
            assert read_dropouts() == expected_dynamic, "Deployment did not analyze the current video fixture."

            second = run_deploy()
            assert second.returncode == 0, f"Idempotent deployment failed: stdout={second.stdout!r}, stderr={second.stderr!r}"
            assert read_dropouts() == expected_dynamic

            evil_should_fail.write_text(json.dumps({
                "device_id": token,
                "target_path": f"/completely/safe/{token}",
                "sync_interval": 9,
            }))
            bad_evil_result = run_deploy()
            assert bad_evil_result.returncode == 1, "Deployment must fail when an evil corpus file is accepted."
            evil_should_fail.unlink()

            clean_should_fail.write_text(json.dumps({
                "device_id": token,
                "target_path": f"/clean/{token}/../secret",
                "sync_interval": 9,
            }))
            bad_clean_result = run_deploy()
            assert bad_clean_result.returncode == 1, "Deployment must fail when a clean corpus file is rejected."
            clean_should_fail.unlink()
        finally:
            for path in (clean_extra, evil_extra, evil_should_fail, clean_should_fail):
                if path.exists():
                    path.unlink()
            shutil.copyfile(backup_video, VIDEO)

        restored = run_deploy()
        assert restored.returncode == 0, f"Deployment failed on restored fixtures: {restored.stderr!r}"
        assert read_dropouts() == EXPECTED_ORIGINAL
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
