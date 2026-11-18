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
import os
import random
import re
import shutil
import signal
import subprocess
import time

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
VIDEO = "/app/microarray_timelapse.mp4"
BACKUP = "/tmp/original_microarray_timelapse.mp4"
FRAMES = "/home/user/frames"
RUN_ANALYSIS = "/home/user/run_analysis.sh"
SERVER = "/home/user/server.sh"
LOG = "/home/user/analysis.log"


def read_pgm(path):
    data = open(path, "rb").read()
    pos = 0

    def token():
        nonlocal pos
        while True:
            while pos < len(data) and data[pos] in b" \t\r\n":
                pos += 1
            if pos < len(data) and data[pos] == 35:
                while pos < len(data) and data[pos] not in b"\r\n":
                    pos += 1
                continue
            break
        start = pos
        while pos < len(data) and data[pos] not in b" \t\r\n#":
            pos += 1
        if start == pos:
            raise ValueError(f"Invalid PGM header in {path}")
        return data[start:pos]

    magic = token()
    width = int(token())
    height = int(token())
    maxval = int(token())
    count = width * height

    if magic == b"P2":
        pixels = [int(token()) for _ in range(count)]
    elif magic == b"P5":
        if pos >= len(data) or data[pos] not in b" \t\r\n":
            raise ValueError(f"Missing PGM raster separator in {path}")
        if data[pos] == 13 and pos + 1 < len(data) and data[pos + 1] == 10:
            pos += 2
        else:
            pos += 1
        if maxval < 256:
            pixels = list(data[pos:pos + count])
        else:
            raw = data[pos:pos + count * 2]
            pixels = [int.from_bytes(raw[i:i + 2], "big") for i in range(0, len(raw), 2)]
    else:
        raise ValueError(f"{path} is not a P2/P5 PGM file")

    if len(pixels) != count:
        raise ValueError(f"Incorrect pixel count in {path}")
    return width, height, maxval, pixels


def quadrant_means(path):
    width, height, _, pixels = read_pgm(path)
    assert width % 2 == 0 and height % 2 == 0, "Frames must split into four equal quadrants"
    hw, hh = width // 2, height // 2
    sums = [0.0, 0.0, 0.0, 0.0]
    for y in range(height):
        for x in range(width):
            q = (2 if y >= hh else 0) + (1 if x >= hw else 0)
            sums[q] += pixels[y * width + x]
    n = hw * hh
    return width, height, tuple(v / n for v in sums)


def extract_reference(video, destination):
    shutil.rmtree(destination, ignore_errors=True)
    os.makedirs(destination)
    subprocess.run([
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", video,
        "-vf", "fps=1", "-pix_fmt", "gray", os.path.join(destination, "%06d.pgm")
    ], check=True, timeout=30)
    paths = sorted(glob.glob(os.path.join(destination, "*.pgm")))
    assert paths, "Reference extraction produced no frames"
    return [quadrant_means(p) for p in paths]


def expected_result(frames):
    values = [f[2] for f in frames]
    for i in range(1, len(values)):
        if all(abs(values[i][q] - values[i - 1][q]) < 2.0 for q in range(4)):
            return i + 1, values[i]
    pytest.fail("Probe unexpectedly has no convergence point")


def kill_port_8080():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if fields[1].split(":")[-1].upper() == "1F90" and fields[3] == "0A":
                inodes.add(fields[9])
    if not inodes:
        return
    for proc in glob.glob("/proc/[0-9]*"):
        pid = int(proc.rsplit("/", 1)[1])
        try:
            for fd in os.listdir(proc + "/fd"):
                try:
                    target = os.readlink(proc + "/fd/" + fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    try:
                        os.kill(pid, signal.SIGTERM)
                    except ProcessLookupError:
                        pass
                    break
        except (FileNotFoundError, PermissionError):
            pass
    time.sleep(0.5)


def run_pipeline():
    shutil.rmtree(FRAMES, ignore_errors=True)
    os.makedirs(FRAMES)
    try:
        os.remove(LOG)
    except FileNotFoundError:
        pass
    subprocess.run([RUN_ANALYSIS], cwd="/home/user", check=True, timeout=60)
    assert os.path.isfile(LOG), "run_analysis.sh did not create /home/user/analysis.log"


def start_server():
    kill_port_8080()
    subprocess.Popen([SERVER], cwd="/home/user", stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)
    deadline = time.time() + 8
    last_error = None
    while time.time() < deadline:
        try:
            response = requests.get(BASE_URL + "/convergence", timeout=1)
            if response.status_code == 200:
                return
        except requests.exceptions.RequestException as exc:
            last_error = exc
        time.sleep(0.15)
    pytest.fail(f"server.sh did not start on port 8080: {last_error}")


def assert_log_details(expected_frames):
    lines = open(LOG, errors="replace").read().splitlines()
    numeric_lines = []
    number = re.compile(r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)")
    for line in lines:
        vals = [float(x) for x in number.findall(line)]
        if vals:
            numeric_lines.append(vals)

    unused = set(range(len(numeric_lines)))
    for frame_number, (_, _, expected) in enumerate(expected_frames, 1):
        found = None
        for line_index in unused:
            vals = numeric_lines[line_index]
            for start in range(max(0, len(vals) - 3)):
                candidate = vals[start:start + 4]
                if len(candidate) == 4 and all(abs(candidate[q] - expected[q]) <= 1.0 for q in range(4)):
                    found = line_index
                    break
            if found is not None:
                break
        assert found is not None, f"analysis.log lacks quadrant intensities for frame {frame_number}"
        unused.remove(found)


def assert_frames_match(reference):
    submitted = sorted(glob.glob(os.path.join(FRAMES, "*.pgm")))
    assert len(submitted) == len(reference), (
        f"Expected exactly {len(reference)} one-frame-per-second PGM files, found {len(submitted)}"
    )
    for index, (path, expected) in enumerate(zip(submitted, reference), 1):
        actual = quadrant_means(path)
        assert actual[:2] == expected[:2], f"Frame {index} has incorrect dimensions"
        assert all(abs(actual[2][q] - expected[2][q]) <= 1.0 for q in range(4)), (
            f"Frame {index} does not match independent extraction from the video"
        )


def assert_dynamic_endpoints(convergence, intensities):
    response = requests.get(BASE_URL + "/convergence", timeout=5)
    assert response.status_code == 200
    assert response.text.strip() == str(convergence)

    response = requests.get(BASE_URL + "/intensities", timeout=5)
    assert response.status_code == 200
    body = response.text.strip()
    match = re.fullmatch(r"TL=([0-9]+\.[0-9]{2}),TR=([0-9]+\.[0-9]{2}),BL=([0-9]+\.[0-9]{2}),BR=([0-9]+\.[0-9]{2})", body)
    assert match is not None, f"Incorrect intensities format: {body!r}"
    actual = tuple(map(float, match.groups()))
    assert all(abs(actual[q] - intensities[q]) <= 1.0 for q in range(4))


def test_00_artifacts_and_pipeline_on_derived_probe():
    assert os.path.isfile(RUN_ANALYSIS), "Missing /home/user/run_analysis.sh"
    assert os.access(RUN_ANALYSIS, os.X_OK), "run_analysis.sh is not executable"
    assert os.path.isfile(SERVER), "Missing /home/user/server.sh"
    assert os.access(SERVER, os.X_OK), "server.sh is not executable"

    server_text = open(SERVER, errors="replace").read()
    first_line = server_text.splitlines()[0] if server_text.splitlines() else ""
    assert re.search(r"(?:/|env\s+)bash\b", first_line), "server.sh must be a Bash script"
    assert re.search(r"\b(?:nc|socat)\b", server_text), "server.sh must use nc or socat"
    assert re.search(r"\b(?:while|until|for)\b", server_text), "server.sh must serve in a loop"

    shutil.copy2(VIDEO, BACKUP)
    restored = False
    try:
        source = "/tmp/probe_source"
        shutil.rmtree(source, ignore_errors=True)
        os.makedirs(source)
        rng = random.SystemRandom()
        values = []
        previous = None
        for _ in range(6):
            while True:
                candidate = tuple(rng.randint(20, 235) for _ in range(4))
                if previous is None or all(abs(candidate[q] - previous[q]) >= 20 for q in range(4)):
                    break
            values.append(candidate)
            previous = candidate
        values.append(values[-1])

        for i, quadrants in enumerate(values, 1):
            path = os.path.join(source, f"frame_{i:03d}.pgm")
            with open(path, "w") as f:
                f.write("P2\n100 100\n255\n")
                for y in range(100):
                    row = []
                    for x in range(100):
                        q = (2 if y >= 50 else 0) + (1 if x >= 50 else 0)
                        row.append(str(quadrants[q]))
                    f.write(" ".join(row) + "\n")

        subprocess.run([
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-framerate", "1",
            "-i", os.path.join(source, "frame_%03d.pgm"), "-c:v", "libx264",
            "-pix_fmt", "yuv420p", VIDEO
        ], check=True, timeout=30)

        reference = extract_reference(VIDEO, "/tmp/reference_probe_frames")
        convergence, intensities = expected_result(reference)
        run_pipeline()
        assert_frames_match(reference)
        assert_log_details(reference)
        start_server()
        assert_dynamic_endpoints(convergence, intensities)

        kill_port_8080()
        shutil.copy2(BACKUP, VIDEO)
        restored = True
        original_reference = extract_reference(VIDEO, "/tmp/reference_original_frames")
        run_pipeline()
        assert_frames_match(original_reference)
        assert_log_details(original_reference)
        start_server()
    finally:
        if not restored:
            kill_port_8080()
            shutil.copy2(BACKUP, VIDEO)


def test_convergence_endpoint():
    """Test the /convergence endpoint returns the correct frame number."""
    try:
        response = requests.get(f"{BASE_URL}/convergence", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {BASE_URL}/convergence: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    body = response.text.strip()
    assert body == "7", f"Expected convergence frame '7', got '{body}'"


def test_intensities_endpoint():
    """Test the /intensities endpoint returns the correct format and values within tolerance."""
    try:
        response = requests.get(f"{BASE_URL}/intensities", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {BASE_URL}/intensities: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    body = response.text.strip()
    pattern = r"^TL=([0-9.]+),TR=([0-9.]+),BL=([0-9.]+),BR=([0-9.]+)$"
    match = re.match(pattern, body)
    assert match is not None, f"Response body '{body}' does not match expected format 'TL=<val>,TR=<val>,BL=<val>,BR=<val>'"

    tl, tr, bl, br = map(float, match.groups())
    expected_tl = 120.50
    expected_tr = 49.00
    expected_bl = 81.50
    expected_br = 199.00
    tolerance = 1.0
    assert abs(tl - expected_tl) <= tolerance, f"TL value {tl} is outside tolerance of {expected_tl}"
    assert abs(tr - expected_tr) <= tolerance, f"TR value {tr} is outside tolerance of {expected_tr}"
    assert abs(bl - expected_bl) <= tolerance, f"BL value {bl} is outside tolerance of {expected_bl}"
    assert abs(br - expected_br) <= tolerance, f"BR value {br} is outside tolerance of {expected_br}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
