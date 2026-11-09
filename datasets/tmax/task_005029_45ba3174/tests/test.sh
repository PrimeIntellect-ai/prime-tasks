#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import shutil
import subprocess
import tarfile
import tempfile
from pathlib import Path

import pytest

SCRIPT_PATH = "/home/user/filter.sh"


def run_filter(package, timeout=30):
    tmpdir = Path(tempfile.mkdtemp(prefix="filter-runtime-"))
    before = set(os.listdir("/tmp"))
    env = os.environ.copy()
    env["TMPDIR"] = str(tmpdir)
    try:
        result = subprocess.run(
            [SCRIPT_PATH, str(package)],
            capture_output=True,
            env=env,
            timeout=timeout,
        )
        leftovers = list(tmpdir.iterdir()) if tmpdir.exists() else []
        after = set(os.listdir("/tmp"))
        unrelated_new = after - before - {tmpdir.name}
        assert not leftovers, f"Temporary files were not cleaned up: {leftovers}"
        assert not unrelated_new, f"Files were left behind in /tmp: {sorted(unrelated_new)}"
        return result
    except subprocess.TimeoutExpired:
        pytest.fail(f"Filter hung while processing {package}")
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)


def test_filter_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"


def test_adversarial_corpus():
    evil_base = "/app/corpora/evil"
    clean_base = "/app/corpora/clean"
    evil_bypassed = []
    clean_rejected = []

    if os.path.isdir(evil_base):
        for item in sorted(os.listdir(evil_base)):
            item_path = os.path.join(evil_base, item)
            if not os.path.isdir(item_path):
                continue
            if run_filter(item_path).returncode == 0:
                evil_bypassed.append(item)

    if os.path.isdir(clean_base):
        for item in sorted(os.listdir(clean_base)):
            item_path = os.path.join(clean_base, item)
            if not os.path.isdir(item_path):
                continue
            if run_filter(item_path).returncode != 0:
                clean_rejected.append(item)

    error_messages = []
    if evil_bypassed:
        error_messages.append(
            f"{len(evil_bypassed)} evil items bypassed (should have been rejected): "
            + ", ".join(evil_bypassed)
        )
    if clean_rejected:
        error_messages.append(
            f"{len(clean_rejected)} clean items rejected (should have been accepted): "
            + ", ".join(clean_rejected)
        )
    assert not evil_bypassed and not clean_rejected, " | ".join(error_messages)


def frame_count(video):
    result = subprocess.run(
        [
            "ffprobe", "-v", "error", "-select_streams", "v:0",
            "-count_frames", "-show_entries", "stream=nb_read_frames",
            "-of", "default=noprint_wrappers=1:nokey=1", str(video),
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    return int(result.stdout.strip())


def make_video(path, frames, color):
    subprocess.run(
        [
            "ffmpeg", "-v", "error", "-f", "lavfi", "-i",
            f"color=c={color}:s=176x144:r=25", "-frames:v", str(frames),
            "-c:v", "mpeg4", "-y", str(path),
        ],
        check=True,
    )


def make_tar(tar_path, video_path):
    with tarfile.open(tar_path, "w") as archive:
        archive.add(video_path, arcname=f"clip_{secrets.token_hex(5)}.mp4")


def test_randomized_content_based_validation():
    reference = Path("/app/reference_feed.mp4")
    assert reference.is_file()
    reference_frames = frame_count(reference)
    assert reference_frames > 0

    with tempfile.TemporaryDirectory(prefix="ingestion-check-") as root_name:
        root = Path(root_name)
        package = root / f"package_{secrets.token_hex(8)}"
        valid_video = root / f"source_{secrets.token_hex(6)}.mp4"
        valid_frames = 17 if reference_frames != 17 else 19
        make_video(valid_video, valid_frames, "green")
        assert frame_count(valid_video) == valid_frames

        def reset_package():
            shutil.rmtree(package, ignore_errors=True)
            package.mkdir()

        def valid_case():
            reset_package()
            make_tar(package / "payload.tar", valid_video)

        def loop_case():
            valid_case()
            left = f"node_{secrets.token_hex(4)}"
            right = f"node_{secrets.token_hex(4)}"
            os.symlink(right, package / left)
            os.symlink(left, package / right)

        def missing_case():
            reset_package()

        def corrupt_tar_case():
            reset_package()
            (package / "payload.tar").write_bytes(os.urandom(257))

        def fake_video_case():
            reset_package()
            fake = root / f"fake_{secrets.token_hex(5)}.mp4"
            fake.write_bytes(b"not an mp4 and not a JPEG frame\n" + os.urandom(31))
            make_tar(package / "payload.tar", fake)
            fake.unlink()

        def reference_frame_case():
            reset_package()
            make_tar(package / "payload.tar", reference)

        cases = [
            ("valid video", valid_case, True),
            ("symlink loop", loop_case, False),
            ("missing archive", missing_case, False),
            ("corrupt archive", corrupt_tar_case, False),
            ("fake video", fake_video_case, False),
            ("reference frame count", reference_frame_case, False),
        ]
        random.SystemRandom().shuffle(cases)

        for label, prepare, should_accept in cases:
            prepare()
            result = run_filter(package)
            if should_accept:
                assert result.returncode == 0, (
                    f"Randomly located valid package was rejected ({label}); "
                    f"stderr={result.stderr!r}"
                )
            else:
                assert result.returncode != 0, (
                    f"Randomly located invalid package was accepted ({label})"
                )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
