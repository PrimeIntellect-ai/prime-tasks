#!/bin/bash
set +e
mkdir -p /logs/verifier

# Recreate the originally promised corpus after the agent has finished, and make
# it non-writable so it cannot be populated or altered by the submission.
rm -rf /app/corpora/evil /app/corpora/clean
mkdir -p /app/corpora/evil /app/corpora/clean
python3 - <<'PY'
import io
import tarfile

def make(path, name):
    with tarfile.open(path, "w") as tf:
        info = tarfile.TarInfo(name)
        data = b"sample\n"
        info.size = len(data)
        tf.addfile(info, io.BytesIO(data))

make('/app/corpora/clean/basic.tar', 'docs/example.gcode')
make('/app/corpora/evil/absolute.tar', '/tmp/tar-slip-verifier')
make('/app/corpora/evil/traversal.tar', '../../tmp/tar-slip-verifier')
PY
chmod 755 /app /app/corpora /app/corpora/evil /app/corpora/clean
chmod 644 /app/corpora/evil/*.tar /app/corpora/clean/*.tar

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import io
import os
import random
import secrets
import shutil
import stat
import subprocess
import tarfile
import tempfile

SCRIPT_PATH = "/home/user/check_tar.sh"
THUMBNAIL_PATH = "/home/user/thumbnail.jpg"
EVIL_CORPUS_DIR = "/app/corpora/evil/"
CLEAN_CORPUS_DIR = "/app/corpora/clean/"


def run_script(path, cwd=None):
    return subprocess.run(
        [SCRIPT_PATH, path],
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=10,
    )


def write_tar(path, members):
    with tarfile.open(path, "w") as tf:
        for member in members:
            info = tarfile.TarInfo(member)
            data = b"verification data\n"
            info.size = len(data)
            tf.addfile(info, io.BytesIO(data))


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"


def test_exactly_one_argument_required():
    no_args = subprocess.run([SCRIPT_PATH], capture_output=True, text=True, timeout=10)
    two_args = subprocess.run(
        [SCRIPT_PATH, "/dev/null", "/dev/null"],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert no_args.returncode != 0, "Script accepted zero arguments"
    assert two_args.returncode != 0, "Script accepted more than one argument"


def test_adversarial_corpus():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"

    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.tar"))
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.tar"))

    assert len(evil_files) > 0, "No evil corpus files found to test against."
    assert len(clean_files) > 0, "No clean corpus files found to test against."

    evil_bypassed = []
    for evil_file in evil_files:
        result = subprocess.run(["bash", SCRIPT_PATH, evil_file], capture_output=True, text=True)
        stdout = result.stdout.strip()
        if result.returncode != 1 or stdout != "REJECT":
            evil_bypassed.append(os.path.basename(evil_file))

    clean_modified = []
    for clean_file in clean_files:
        result = subprocess.run(["bash", SCRIPT_PATH, clean_file], capture_output=True, text=True)
        stdout = result.stdout.strip()
        if result.returncode != 0 or stdout != "ACCEPT":
            clean_modified.append(os.path.basename(clean_file))

    error_msg = []
    if evil_bypassed:
        error_msg.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msg.append(f"{len(clean_modified)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_modified)}")

    assert not evil_bypassed and not clean_modified, " | ".join(error_msg)


def test_randomized_mixed_archives_without_extraction():
    # Clean and malicious archives share one directory and have random names, so
    # their expected result cannot be inferred from their path.
    with tempfile.TemporaryDirectory(prefix="tar-cases-") as case_dir, \
         tempfile.TemporaryDirectory(prefix="tar-cwd-") as work_dir:
        token = secrets.token_hex(12)
        cases = [
            ([f"docs/{token}/readme.txt", f"models/{token}.gcode"], 0, "ACCEPT"),
            ([f"./docs/{token}/notes.txt", f"name..part/{token}"], 0, "ACCEPT"),
            ([f"safe/.../{token}/file.txt"], 0, "ACCEPT"),
            ([f"/{token}/absolute.gcode"], 1, "REJECT"),
            ([f"../{token}/escape.txt"], 1, "REJECT"),
            ([f"safe/../{token}/escape.txt"], 1, "REJECT"),
            ([f"safe/sub/../../{token}/escape.txt"], 1, "REJECT"),
            ([f"safe/{token}/.."], 1, "REJECT"),
        ]
        random.SystemRandom().shuffle(cases)

        archives = []
        for members, code, output in cases:
            path = os.path.join(case_dir, secrets.token_hex(16) + ".tar")
            write_tar(path, members)
            archives.append((path, code, output))

        random.SystemRandom().shuffle(archives)
        for path, expected_code, expected_output in archives:
            before = set(os.listdir(work_dir))
            result = run_script(path, cwd=work_dir)
            assert result.returncode == expected_code, (
                f"Wrong exit status for randomized archive: {result.returncode}; "
                f"stderr={result.stderr!r}"
            )
            assert result.stdout.strip() == expected_output, (
                f"Wrong stdout for randomized archive: {result.stdout!r}"
            )
            assert set(os.listdir(work_dir)) == before, "Archive contents were extracted while checking"


def decode_rgb(path):
    result = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-frames:v", "1",
         "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
        capture_output=True,
        timeout=30,
    )
    assert result.returncode == 0, f"ffmpeg could not decode {path}: {result.stderr.decode(errors='replace')}"
    return result.stdout


def test_thumbnail_extracted():
    assert os.path.isfile(THUMBNAIL_PATH), f"Thumbnail not found at {THUMBNAIL_PATH}"
    mode = os.lstat(THUMBNAIL_PATH).st_mode
    assert stat.S_ISREG(mode) and not os.path.islink(THUMBNAIL_PATH), "Thumbnail must be a regular file"

    # Preserve the original validity checks.
    with open(THUMBNAIL_PATH, "rb") as f:
        header = f.read(3)
        assert header == b'\xff\xd8\xff', f"File at {THUMBNAIL_PATH} is not a valid JPEG"

    size = os.path.getsize(THUMBNAIL_PATH)
    assert size > 1000, f"Thumbnail size ({size} bytes) is suspiciously small"

    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height", "-of", "csv=p=0:s=x", THUMBNAIL_PATH],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert probe.returncode == 0 and probe.stdout.strip() == "1280x720", (
        f"Thumbnail has the wrong dimensions: {probe.stdout.strip()!r}"
    )

    # Recreate the setup video independently, then compare the submitted image
    # with frames around two seconds. The closest frame must be frame 60 (2.0s).
    with tempfile.TemporaryDirectory(prefix="thumb-reference-") as td:
        reference_video = os.path.join(td, "reference.mp4")
        made = subprocess.run(
            ["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
             "testsrc=duration=5:size=1280x720:rate=30", "-c:v", "libx264", reference_video],
            capture_output=True,
            timeout=60,
        )
        assert made.returncode == 0, made.stderr.decode(errors="replace")

        refs = subprocess.run(
            ["ffmpeg", "-v", "error", "-i", reference_video,
             "-vf", "select=between(n\\,55\\,65)", "-vsync", "0",
             "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
            capture_output=True,
            timeout=60,
        )
        assert refs.returncode == 0, refs.stderr.decode(errors="replace")

        submitted = decode_rgb(THUMBNAIL_PATH)
        frame_size = 1280 * 720 * 3
        assert len(submitted) == frame_size, "Thumbnail did not decode to one complete 1280x720 frame"
        assert len(refs.stdout) == 11 * frame_size, "Could not derive reference frames"

        # Sample every eighth pixel, retaining all three color channels.
        positions = []
        for p in range(0, frame_size, 24):
            positions.extend((p, p + 1, p + 2))

        distances = []
        for offset in range(11):
            frame = memoryview(refs.stdout)[offset * frame_size:(offset + 1) * frame_size]
            total = sum(abs(submitted[p] - frame[p]) for p in positions)
            distances.append(total / len(positions))

        best_frame = 55 + min(range(len(distances)), key=distances.__getitem__)
        assert best_frame == 60, (
            f"Thumbnail is closest to source frame {best_frame}, not the frame at exactly 2 seconds"
        )
        assert distances[5] < 15.0, (
            f"Thumbnail does not visually match the source video at 2 seconds (MAE {distances[5]:.2f})"
        )
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
