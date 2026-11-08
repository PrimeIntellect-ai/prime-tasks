#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import re
import secrets
import subprocess
import time

import pytest
import requests

BASE_URL = "http://127.0.0.1:9090"
DATASTORE_DIR = "/home/user/datastore"
PROJECT_DIR = "/home/user/frame_etl"
VIDEO = "/app/video_feed.mp4"
FFMPEG_LOG = "/tmp/verifier_ffmpeg_calls.log"
REAL_FFMPEG = os.environ["REAL_FFMPEG"]


def request_json(sec: int):
    url = f"{BASE_URL}/process?sec={sec}"
    try:
        response = requests.get(url, timeout=8)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service at {url}: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert isinstance(data, dict), "JSON response must be an object"
    assert set(data) == {"second", "size", "classification"}, "JSON response has missing or extra fields"
    assert data["second"] == sec, f"Expected second {sec}, got {data['second']}"
    assert isinstance(data["size"], int) and not isinstance(data["size"], bool), "size must be an integer"
    assert data["classification"] in ("Complex", "Simple")
    return response, data


def verify_process_endpoint(sec: int):
    _, data = request_json(sec)
    frame_path = os.path.join(DATASTORE_DIR, f"frame_{sec}.jpg")
    assert os.path.exists(frame_path), f"Frame image {frame_path} was not created."

    actual_size = os.path.getsize(frame_path)
    assert data["size"] == actual_size, f"JSON size {data['size']} does not match actual file size {actual_size}"
    expected_classification = "Complex" if actual_size > 40000 else "Simple"
    assert data["classification"] == expected_classification, \
        f"Expected classification '{expected_classification}', got '{data['classification']}'"
    return frame_path


def ffmpeg_calls():
    if not os.path.exists(FFMPEG_LOG):
        return []
    with open(FFMPEG_LOG, "r", encoding="utf-8", errors="replace") as f:
        return [line.rstrip("\n").split("\x1f")[:-1] for line in f if line.strip()]


def decode_rgb(path):
    result = subprocess.run(
        [REAL_FFMPEG, "-v", "error", "-i", path, "-frames:v", "1",
         "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15,
    )
    assert result.returncode == 0, f"Invalid JPEG {path}: {result.stderr.decode(errors='replace')}"
    assert len(result.stdout) == 640 * 480 * 3, f"Unexpected decoded frame dimensions for {path}"
    return result.stdout


def make_expected(sec, path):
    subprocess.run(
        [REAL_FFMPEG, "-hide_banner", "-loglevel", "error", "-y",
         "-ss", str(sec), "-i", VIDEO, "-frames:v", "1", "-q:v", "2", path],
        check=True, timeout=20,
    )


def test_datastore_directory_exists():
    assert os.path.exists(DATASTORE_DIR), f"Directory {DATASTORE_DIR} does not exist."
    assert os.path.isdir(DATASTORE_DIR), f"Path {DATASTORE_DIR} is not a directory."


def test_rust_project_and_running_binary():
    manifest = os.path.join(PROJECT_DIR, "Cargo.toml")
    assert os.path.isfile(manifest), "Rust project is missing Cargo.toml"
    sources = glob.glob(os.path.join(PROJECT_DIR, "**", "*.rs"), recursive=True)
    assert sources, "Rust project contains no .rs source files"
    source_text = "\n".join(open(p, encoding="utf-8", errors="replace").read() for p in sources)
    assert "ffmpeg" in source_text, "Rust source does not invoke ffmpeg"
    assert "Command" in source_text, "Rust source does not use a subprocess Command"

    metadata = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1", "--manifest-path", manifest],
        check=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20,
    )
    cargo_data = json.loads(metadata.stdout)
    bin_names = {t["name"] for p in cargo_data["packages"] for t in p["targets"] if "bin" in t["kind"]}
    assert bin_names, "Cargo project has no binary target"

    socket_inodes = set()
    with open("/proc/net/tcp", encoding="ascii") as f:
        for line in f.readlines()[1:]:
            fields = line.split()
            if fields[1] == "0100007F:2382" and fields[3] == "0A":
                socket_inodes.add(fields[9])
    assert socket_inodes, "No service is listening specifically on 127.0.0.1:9090"

    matching_exes = []
    for proc in glob.glob("/proc/[0-9]*"):
        for fd in glob.glob(os.path.join(proc, "fd", "*")):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in socket_inodes:
                try:
                    exe = os.readlink(os.path.join(proc, "exe"))
                    with open(os.path.join(proc, "exe"), "rb") as ef:
                        is_elf = ef.read(4) == b"\x7fELF"
                    if is_elf and os.path.basename(exe).replace(" (deleted)", "") in bin_names:
                        matching_exes.append(exe)
                except OSError:
                    pass
    assert matching_exes, "The listener is not an ELF binary matching a Cargo binary target"


def test_process_sec_2():
    frame_path = verify_process_endpoint(2)
    mtime_before = os.path.getmtime(frame_path)
    calls_before = len(ffmpeg_calls())
    time.sleep(1)
    response, _ = request_json(2)
    assert response.status_code == 200
    mtime_after = os.path.getmtime(frame_path)
    assert mtime_before == mtime_after, "File modification time changed, indicating the frame was not cached."
    assert len(ffmpeg_calls()) == calls_before, "ffmpeg was run again for an already cached frame"


def test_process_sec_15():
    verify_process_endpoint(15)


def test_random_uncached_frames_are_real_ffmpeg_extractions():
    secs = secrets.SystemRandom().sample([n for n in range(3, 28) if n != 15], 3)
    for sec in secs:
        frame_path = os.path.join(DATASTORE_DIR, f"frame_{sec}.jpg")
        expected_path = f"/tmp/expected_frame_{sec}.jpg"
        try:
            os.unlink(frame_path)
        except FileNotFoundError:
            pass
        make_expected(sec, expected_path)
        expected_rgb = decode_rgb(expected_path)

        before = len(ffmpeg_calls())
        verify_process_endpoint(sec)
        calls = ffmpeg_calls()
        assert len(calls) > before, f"No ffmpeg subprocess was observed for uncached second {sec}"
        new_calls = calls[before:]
        assert any(
            VIDEO in args
            and frame_path in args
            and any(args[i] == "-q:v" and i + 1 < len(args) and args[i + 1] == "2" for i in range(len(args)))
            for args in new_calls
        ), f"ffmpeg was not invoked with the source video, requested output, and -q:v 2 for second {sec}"

        actual_rgb = decode_rgb(frame_path)
        assert actual_rgb == expected_rgb, f"frame_{sec}.jpg is not the frame from the source video at second {sec}"


def test_large_cached_file_is_preserved_and_classified_complex():
    sec = 28
    frame_path = os.path.join(DATASTORE_DIR, f"frame_{sec}.jpg")
    payload = secrets.token_bytes(45001)
    with open(frame_path, "wb") as f:
        f.write(payload)
    mtime_before = os.stat(frame_path).st_mtime_ns
    calls_before = len(ffmpeg_calls())

    _, data = request_json(sec)
    assert data["size"] == len(payload)
    assert data["classification"] == "Complex"
    assert open(frame_path, "rb").read() == payload, "Existing cached file was overwritten"
    assert os.stat(frame_path).st_mtime_ns == mtime_before, "Existing cached file modification time changed"
    assert len(ffmpeg_calls()) == calls_before, "ffmpeg was invoked despite the frame already being cached"
TEST_EOF

FFMPEG_PATH="$(readlink -f "$(command -v ffmpeg)")"
REAL_FFMPEG="${FFMPEG_PATH}.verifier-real"
FFMPEG_LOG=/tmp/verifier_ffmpeg_calls.log
rm -f "$FFMPEG_LOG"
touch "$FFMPEG_LOG"
chmod 666 "$FFMPEG_LOG"
mv "$FFMPEG_PATH" "$REAL_FFMPEG"
cat > "$FFMPEG_PATH" <<'WRAPPER_EOF'
#!/bin/sh
{
  printf '%s\037' "$@"
  printf '\n'
} >> /tmp/verifier_ffmpeg_calls.log
exec "$(readlink -f "$0").verifier-real" "$@"
WRAPPER_EOF
chmod 755 "$FFMPEG_PATH"
export REAL_FFMPEG FFMPEG_LOG

restore_ffmpeg() {
    rm -f "$FFMPEG_PATH"
    if [ -e "$REAL_FFMPEG" ]; then
        mv "$REAL_FFMPEG" "$FFMPEG_PATH"
    fi
}
trap restore_ffmpeg EXIT

set +e
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
set -e

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
