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
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import math
import os
import re
import subprocess

import pytest
import requests

URL = "http://127.0.0.1:8080/posterior"


def independently_expected_posterior():
    """Extract all fixture frames and derive the posterior moments independently."""
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height,nb_frames",
         "-of", "json", "/app/fluor_seq.mp4"],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    stream = json.loads(probe.stdout)["streams"][0]
    width, height = int(stream["width"]), int(stream["height"])

    decoded = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", "/app/fluor_seq.mp4",
         "-f", "rawvideo", "-pix_fmt", "gray", "-"],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    ).stdout
    frame_size = width * height
    assert frame_size > 0 and len(decoded) % frame_size == 0
    frames = len(decoded) // frame_size
    assert frames == 50, f"Fixture should decode to 50 frames, got {frames}"

    positions = []
    for i in range(frames):
        frame = decoded[i * frame_size:(i + 1) * frame_size]
        brightest = max(range(frame_size), key=frame.__getitem__)
        positions.append((brightest % width, brightest // width))

    squared_sum = sum(
        (positions[i][0] - positions[i - 1][0]) ** 2
        + (positions[i][1] - positions[i - 1][1]) ** 2
        for i in range(1, frames)
    )
    n = frames - 1
    beta = squared_sum / 4.0

    # D^{-n} exp(-beta/D) is inverse-gamma with alpha=n-1. The fixture's
    # posterior is far from the prior bounds, so truncation at .1 and 100 has
    # negligible effect on its first two moments.
    alpha = n - 1
    expected_mean = beta / (alpha - 1)
    expected_std = beta / ((alpha - 1) * math.sqrt(alpha - 2))
    return expected_mean, expected_std


def listening_server_pid():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local, state = fields[1], fields[3]
            if local.upper().endswith(":1F90") and state == "0A":
                inodes.add(fields[9])

    for procdir in glob.glob("/proc/[0-9]*"):
        pid = int(procdir.rsplit("/", 1)[1])
        for fd in glob.glob(procdir + "/fd/*"):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            match = re.fullmatch(r"socket:\[(\d+)\]", target)
            if match and match.group(1) in inodes:
                return pid
    return None


def submitted_c_sources():
    result = []
    for root in ("/app", "/home/user", "/tmp"):
        for path, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in {".cache", ".git", "node_modules"}]
            for name in files:
                if name.lower().endswith(".c"):
                    result.append(os.path.join(path, name))
    return result


def has_extracted_frame_set():
    extensions = {".pgm", ".ppm", ".png", ".jpg", ".jpeg", ".bmp", ".raw", ".gray"}
    by_dir = {}
    for root in ("/app", "/home/user", "/tmp"):
        for path, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in {".cache", ".git", "node_modules"}]
            candidates = [
                os.path.join(path, f) for f in files
                if os.path.splitext(f)[1].lower() in extensions
                and os.path.getsize(os.path.join(path, f)) > 0
            ]
            if candidates:
                by_dir[path] = candidates
    return any(len(files) == 50 for files in by_dir.values())


def test_analysis_artifacts_and_c_server():
    assert os.path.isfile("/app/fluor_seq.mp4"), "Video fixture is missing"
    assert has_extracted_frame_set(), "No directory containing exactly 50 extracted frame files was found"

    sources = submitted_c_sources()
    assert sources, "No submitted C source file was found"
    source = "\n".join(open(p, errors="ignore").read() for p in sources)
    lower = source.lower()

    assert re.search(r"(?:100000|100\s*\*\s*1000|1(?:\.0)?e\+?5)", source, re.I), \
        "C source does not specify 100,000 MCMC iterations"
    assert re.search(r"(?:10000|10\s*\*\s*1000|1(?:\.0)?e\+?4)", source, re.I), \
        "C source does not specify the 10,000-iteration burn-in"
    assert re.search(r"\bexp\s*\(", source), "C source does not implement the exponential likelihood"
    assert "/posterior" in source, "C source does not implement GET /posterior"
    for api in ("socket", "bind", "listen", "accept"):
        assert re.search(r"\b" + api + r"\s*\(", source), f"C source does not call {api}()"
    assert ("bright" in lower or re.search(r"\bmax(?:imum)?\b", lower)), \
        "C source lacks brightest-pixel processing"
    assert "frame" in lower, "C source lacks frame processing"
    assert ("mean" in lower and ("std" in lower or "sqrt" in lower)), \
        "C source lacks posterior mean/standard-deviation calculation"

    pid = listening_server_pid()
    assert pid is not None, "No process is listening on TCP port 8080"
    exe = f"/proc/{pid}/exe"
    with open(exe, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The listening HTTP server is not a compiled native executable"


def test_server_response_and_recomputed_posterior():
    try:
        response = requests.get(URL, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the server at {URL}: {exc}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    assert re.fullmatch(
        r'\{"mean_D": -?\d+\.\d{2}, "std_D": \d+\.\d{2}\}',
        response.text.strip()
    ), f"Response does not have the required two-decimal JSON format: {response.text!r}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert "mean_D" in data, "JSON response missing 'mean_D'"
    assert "std_D" in data, "JSON response missing 'std_D'"
    assert set(data) == {"mean_D", "std_D"}, "JSON response contains unexpected fields"

    mean_d = data["mean_D"]
    std_d = data["std_D"]
    assert isinstance(mean_d, (int, float)) and not isinstance(mean_d, bool), "'mean_D' must be a number"
    assert isinstance(std_d, (int, float)) and not isinstance(std_d, bool), "'std_D' must be a number"

    # Preserve the original sanity assertions.
    assert 5.0 <= mean_d <= 25.0, f"mean_D {mean_d} is outside the expected reasonable range [5.0, 25.0]"
    assert std_d > 0, f"std_D {std_d} must be positive"

    expected_mean, expected_std = independently_expected_posterior()
    mean_tolerance = max(0.75, expected_mean * 0.10)
    std_tolerance = max(0.35, expected_std * 0.25)
    assert abs(mean_d - expected_mean) <= mean_tolerance, \
        f"mean_D {mean_d} disagrees with the posterior recomputed from the video ({expected_mean:.3f})"
    assert abs(std_d - expected_std) <= std_tolerance, \
        f"std_D {std_d} disagrees with the posterior recomputed from the video ({expected_std:.3f})"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
