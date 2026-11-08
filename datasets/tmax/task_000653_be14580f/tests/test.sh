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

cat <<'PY_EOF' > /tmp/verify_task.py
import io
import json
import math
import os
import secrets
import shutil
import subprocess
import tarfile
import tempfile
import time
from pathlib import Path

import requests
from PIL import Image

URL = "http://127.0.0.1:8080/result.json"
WEB_RESULT = Path("/home/user/web/result.json")
EXTRACTED = Path("/home/user/extracted")
TAR_PATH = Path("/home/user/dataset/job.tar")
VIDEO_PATH = Path("/app/print_video.mp4")


def get_json(url):
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as exc:
        raise AssertionError(f"Failed to connect to the HTTP server at {url}: {exc}")
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    try:
        return response.json()
    except ValueError:
        raise AssertionError(f"Response from {url} is not valid JSON: {response.text}")


def assert_result(data, extrusion, status, flashes):
    assert "total_extrusion" in data, "Missing 'total_extrusion' in JSON response"
    assert "final_status" in data, "Missing 'final_status' in JSON response"
    assert "flash_frames" in data, "Missing 'flash_frames' in JSON response"
    assert isinstance(data["total_extrusion"], (int, float)) and not isinstance(data["total_extrusion"], bool)
    assert math.isclose(data["total_extrusion"], extrusion, rel_tol=1e-5, abs_tol=1e-5), \
        f"Expected total_extrusion to be {extrusion}, got {data['total_extrusion']}"
    assert data["final_status"] == status, \
        f"Expected final_status to be {status!r}, got {data['final_status']!r}"
    assert data["flash_frames"] == flashes, \
        f"Expected flash_frames to be {flashes}, got {data['flash_frames']}"


# Preserve the original checks against the supplied fixture and the agent's server.
original = get_json(URL)
assert_result(original, 4.0, "Finished", 3)
assert not os.path.exists("/home/user/malicious_file.txt"), \
    "Malicious file was extracted to /home/user/malicious_file.txt! Archive integrity verification failed."

# A C source artifact must exist and be compilable.
sources = []
for root in (Path("/home/user"), Path("/app")):
    for source in root.rglob("*.c"):
        if "/extracted/" not in str(source) and "/web/" not in str(source):
            sources.append(source)
assert sources, "No C source file was found"
sources = sources[:20]

build_dir = Path(tempfile.mkdtemp(prefix="verifier_build_"))
compile_sets = []
analyze_sources = [p for p in sources if p.name == "analyze.c"]
compile_sets.extend([[p] for p in analyze_sources])
compile_sets.extend([[p] for p in sources if p not in analyze_sources])
if len(sources) > 1:
    compile_sets.append(sources)

binaries = []
for index, source_set in enumerate(compile_sets):
    binary = build_dir / f"submission_{index}"
    command = ["gcc", "-std=c11", "-O2", "-o", str(binary)] + [str(p) for p in source_set] + ["-lm"]
    completed = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if completed.returncode == 0:
        binaries.append(binary)
assert binaries, "The submitted C source could not be compiled"

# Replace all three inputs with an unpredictable fixture so a constant result cannot pass.
token = secrets.token_hex(6)
values = [1.125, 2.25, 0.625, (secrets.randbelow(500) + 1) / 1000.0]
expected_extrusion = sum(values)
expected_status = "Verified-" + token

gcode = (
    f"G1 X1 Y1 E{values[0]}\n"
    "G0 X9 Y9 E9999\n"
    f"G1 X2 Y2 E{values[1]}\n"
    "; G1 E8888\n"
    f"G1 X3 Y3 E{values[2]}\n"
    f"G1 X4 Y4 E{values[3]}\n"
)
machine_log = (
    "[first]\nStatus:\nWarming\n"
    "Status: this text is not followed in the required form\n"
    "[last]\nStatus:\n" + expected_status + "\n"
)
escape_name = "verifier_escape_" + token + ".txt"
escape_path = Path("/home/user") / escape_name

with tarfile.open(TAR_PATH, "w") as archive:
    for name, content in (("print.gcode", gcode), ("machine.log", machine_log)):
        raw = content.encode()
        info = tarfile.TarInfo(name)
        info.size = len(raw)
        archive.addfile(info, io.BytesIO(raw))
    malicious = b"directory traversal succeeded"
    info = tarfile.TarInfo("../" + escape_name)
    info.size = len(malicious)
    archive.addfile(info, io.BytesIO(malicious))

frame_source = Path(tempfile.mkdtemp(prefix="verifier_frames_"))
frame_count = 13
white_indices = set(secrets.SystemRandom().sample(range(1, frame_count + 1), 4))
for index in range(1, frame_count + 1):
    level = 255 if index in white_indices else 12
    Image.new("RGB", (64, 64), (level, level, level)).save(frame_source / f"frame_{index:03d}.png")
subprocess.run([
    "ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-framerate", "10",
    "-i", str(frame_source / "frame_%03d.png"), "-c:v", "libx264", "-pix_fmt", "yuv420p",
    str(VIDEO_PATH)
], check=True)

# Independently derive the flash count from the encoded video, not from the generation list.
decoded = Path(tempfile.mkdtemp(prefix="verifier_decoded_"))
subprocess.run([
    "ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(VIDEO_PATH),
    str(decoded / "decoded_%04d.png")
], check=True)
expected_flashes = 0
for frame in sorted(decoded.glob("decoded_*.png")):
    image = Image.open(frame).convert("L")
    average = sum(image.getdata()) / (image.width * image.height)
    if average > 200:
        expected_flashes += 1
assert expected_flashes > 0


def reset_outputs():
    shutil.rmtree(EXTRACTED, ignore_errors=True)
    EXTRACTED.mkdir(parents=True, exist_ok=True)
    WEB_RESULT.unlink(missing_ok=True)
    escape_path.unlink(missing_ok=True)
    shutil.rmtree("/tmp/frames", ignore_errors=True)
    Path("/tmp/frames").mkdir(parents=True, exist_ok=True)


def run_candidate(binary):
    reset_outputs()
    process = subprocess.Popen(
        [str(binary)], cwd="/home/user", stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, start_new_session=True
    )
    deadline = time.time() + 35
    data = None
    try:
        while time.time() < deadline:
            if WEB_RESULT.is_file():
                try:
                    data = json.loads(WEB_RESULT.read_text())
                    break
                except (OSError, ValueError):
                    pass
            if process.poll() is not None and not WEB_RESULT.exists():
                break
            time.sleep(0.2)
    finally:
        if process.poll() is None:
            try:
                os.killpg(process.pid, 15)
                process.wait(timeout=3)
            except Exception:
                try:
                    os.killpg(process.pid, 9)
                except Exception:
                    pass
    if data is None:
        return False
    try:
        assert_result(data, expected_extrusion, expected_status, expected_flashes)
        assert not escape_path.exists(), f"Traversal entry was extracted to {escape_path}"
        assert (EXTRACTED / "print.gcode").read_text() == gcode, "Safe print.gcode was not extracted correctly"
        assert (EXTRACTED / "machine.log").read_text() == machine_log, "Safe machine.log was not extracted correctly"
        # The already-running HTTP service must serve the newly produced file, not a fixed response.
        served = get_json(URL + "?nonce=" + token)
        assert_result(served, expected_extrusion, expected_status, expected_flashes)
        return True
    except (AssertionError, OSError, ValueError):
        return False


assert any(run_candidate(binary) for binary in binaries), \
    "No compiled C submission safely processed the randomized archive/video and updated the served result"
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
