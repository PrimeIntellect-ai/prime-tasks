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

cat <<'TEST_EOF' > /tmp/test_final_state.py
import gzip
import hashlib
import json
import os
import re
import signal
import subprocess
import time
from pathlib import Path

import requests

HOST = "127.0.0.1"
PORT = 9090
BASE = f"http://{HOST}:{PORT}"


def listener_pid():
    inode = None
    with open("/proc/net/tcp", "r") as f:
        for line in f.readlines()[1:]:
            fields = line.split()
            local, state = fields[1], fields[3]
            if local == "0100007F:2382" and state == "0A":
                inode = fields[9]
                break
    if inode is None:
        return None
    target = f"socket:[{inode}]"
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        fd_dir = proc / "fd"
        try:
            for fd in fd_dir.iterdir():
                try:
                    if os.readlink(fd) == target:
                        return int(proc.name)
                except OSError:
                    pass
        except OSError:
            pass
    return None


def wait_for_server(timeout=20):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            r = requests.get(BASE + "/api/stats", timeout=1)
            if r.status_code == 200:
                return r
        except requests.RequestException as e:
            last = e
        time.sleep(0.25)
    raise AssertionError(f"server did not become ready: {last}")


def video_frame_count():
    out = subprocess.check_output([
        "ffprobe", "-v", "error", "-select_streams", "v:0", "-count_frames",
        "-show_entries", "stream=nb_read_frames",
        "-of", "default=nokey=1:noprint_wrappers=1", "/app/experiment.mp4"
    ], text=True).strip()
    return int(out)


def independently_count_events(root):
    seen = set()
    total = 0
    for base, dirs, files in os.walk(root, followlinks=False):
        dirs[:] = [d for d in dirs if not os.path.islink(os.path.join(base, d))]
        for name in files:
            path = os.path.join(base, name)
            if not name.endswith(".gz") or os.path.islink(path):
                continue
            st = os.stat(path)
            identity = (st.st_dev, st.st_ino)
            if identity in seen:
                continue
            seen.add(identity)
            raw = gzip.open(path, "rb").read()
            if name == "sensor_b.log.gz":
                text = raw.decode("utf-16le")
            else:
                text = raw.decode("utf-8")
            total += sum(1 for line in text.splitlines() if line == "[EVENT]")
    return total


def get_stats():
    r = requests.get(BASE + "/api/stats", timeout=5)
    assert r.status_code == 200, f"Expected status 200, got {r.status_code}"
    try:
        data = r.json()
    except json.JSONDecodeError:
        raise AssertionError(f"Response is not valid JSON: {r.text}")
    assert "total_frames" in data, "Missing 'total_frames' in response"
    assert "total_events" in data, "Missing 'total_events' in response"
    assert set(data) == {"total_frames", "total_events"}, "Unexpected fields in stats JSON"
    assert isinstance(data["total_frames"], int) and not isinstance(data["total_frames"], bool)
    assert isinstance(data["total_events"], int) and not isinstance(data["total_events"], bool)
    return data


def jpeg_dimensions(path):
    out = subprocess.check_output([
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "stream=width,height", "-of", "csv=p=0:s=x", path
    ], text=True).strip()
    return out


def candidate_implementation_text():
    files = []
    for root in ("/home/user", "/app"):
        for base, dirs, names in os.walk(root, followlinks=False):
            if base.startswith("/app/dataset"):
                dirs[:] = []
                continue
            for name in names:
                if name.endswith((".cpp", ".cc", ".cxx", ".hpp", ".h", ".sh")):
                    p = os.path.join(base, name)
                    try:
                        if os.path.getsize(p) <= 1024 * 1024:
                            files.append(p)
                    except OSError:
                        pass
    cpp = [p for p in files if p.endswith((".cpp", ".cc", ".cxx"))]
    assert cpp, "No C++ source file was left in the submission"
    text = "\n".join(Path(p).read_text(errors="ignore") for p in files)
    cpp_text = "\n".join(Path(p).read_text(errors="ignore") for p in cpp)
    return text.lower(), cpp_text.lower()


def verify_all_frames(expected_frames):
    frames_dir = "/home/user/frames"
    serve_dir = "/home/user/serve"
    assert os.path.isdir(frames_dir), f"Frames directory {frames_dir} is missing"
    assert os.path.exists(serve_dir), f"Serve directory {serve_dir} is missing"
    assert os.path.isdir(serve_dir), f"Serve path {serve_dir} is not a directory"

    frame_names = sorted(f for f in os.listdir(frames_dir) if f.endswith(".jpg"))
    serve_names = sorted(f for f in os.listdir(serve_dir) if f.endswith(".jpg"))
    assert len(serve_names) > 0, f"No JPEG files found in {serve_dir}"
    assert len(frame_names) == expected_frames, "Not all video frames were extracted"
    assert serve_names == frame_names, "Atomic serve directory is not a complete copy of the frame set"

    numeric_ids = sorted(int(name[:-4]) for name in frame_names if re.fullmatch(r"[0-9]+\.jpg", name))
    assert numeric_ids == list(range(1, expected_frames + 1)), "Frames must be addressable as 1.jpg through N.jpg"

    hashes = set()
    for name in frame_names:
        frame = os.path.join(frames_dir, name)
        served = os.path.join(serve_dir, name)
        fst, sst = os.stat(frame), os.stat(served)
        assert (fst.st_dev, fst.st_ino) == (sst.st_dev, sst.st_ino), f"{name} is not a hardlink"
        content = Path(frame).read_bytes()
        assert len(content) > 1000, f"{name} is implausibly small"
        assert content.startswith(b"\xff\xd8") and content.endswith(b"\xff\xd9"), f"{name} is not a complete JPEG"
        assert jpeg_dimensions(frame) == "640x480", f"{name} has incorrect dimensions or is undecodable"
        hashes.add(hashlib.sha256(content).digest())
    assert len(hashes) >= int(expected_frames * 0.8), "Extracted frame set contains excessive duplicate images"

    for name in frame_names:
        r = requests.get(BASE + "/api/frames/" + name, timeout=5)
        assert r.status_code == 200, f"Could not retrieve {name}"
        assert r.headers.get("Content-Type", "").split(";", 1)[0] in ("image/jpeg", "image/jpg")
        assert r.content == Path(os.path.join(serve_dir, name)).read_bytes(), f"API did not serve hardlinked {name}"


def test_complete_service():
    assert os.path.exists("/app/experiment.mp4"), "Video file missing"
    expected_frames = video_frame_count()
    expected_events = independently_count_events("/app/dataset/logs")
    assert expected_events == 35

    initial = wait_for_server()
    assert initial.status_code == 200
    data = get_stats()
    assert data["total_frames"] == expected_frames, f"Expected {expected_frames} frames, got {data['total_frames']}"
    assert data["total_events"] == expected_events, f"Expected {expected_events} events, got {data['total_events']}"

    # Preserve the original endpoint check for frame 10.
    r = requests.get(BASE + "/api/frames/10.jpg", timeout=5)
    assert r.status_code == 200, f"Expected status 200, got {r.status_code}"
    assert r.headers.get("Content-Type", "").split(";", 1)[0] in ("image/jpeg", "image/jpg")
    assert len(r.content) > 0 and r.content.startswith(b"\xff\xd8")

    pid = listener_pid()
    assert pid is not None, "No process is listening specifically on 127.0.0.1:9090"
    exe = os.readlink(f"/proc/{pid}/exe")
    assert os.path.isfile(exe), "Listening executable is unavailable"
    with open(f"/proc/{pid}/exe", "rb") as f:
        assert f.read(4) == b"\x7fELF", "HTTP server is not a compiled native executable"

    implementation, cpp = candidate_implementation_text()
    assert "[event]" in cpp, "C++ code does not parse event markers"
    assert any(x in cpp for x in ("gzopen", "gzread", "inflate", "zlib")), "C++ code does not read gzip streams directly"
    assert any(x in cpp for x in ("utf-16", "utf16", "codecvt", "little_endian")), "C++ code lacks UTF-16LE conversion"
    assert any(x in cpp for x in ("filesystem", "symlink", "recursive_directory")), "C++ code lacks filesystem traversal handling"
    assert any(x in implementation for x in ("create_hard_link", "link(", " link ", "ln ")), "No hardlink creation implementation found"
    assert any(x in implementation for x in ("rename(", "filesystem::rename", " mv ", "symlink(")), "No atomic directory publication operation found"

    verify_all_frames(expected_frames)

    # Replace both encoded inputs with verifier-chosen records, add decoy marker text,
    # and add aliases/loops. Restarting the submitted executable prevents fixed 35/90 responses.
    argv = [x.decode() for x in Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0") if x]
    cwd = os.readlink(f"/proc/{pid}/cwd")
    env = {}
    for item in Path(f"/proc/{pid}/environ").read_bytes().split(b"\0"):
        if b"=" in item:
            k, v = item.split(b"=", 1)
            env[k.decode(errors="ignore")] = v.decode(errors="ignore")
    env.setdefault("PATH", os.environ.get("PATH", "/usr/bin:/bin"))

    a_lines = []
    for i in range(7):
        a_lines += ["[EVENT]", f"A verifier record {i}", "x[EVENT] is not a marker", "[EVENT] trailing is not a marker"]
    b_lines = []
    for i in range(11):
        b_lines += ["[EVENT]", f"B verifier record {i}", "prefix [EVENT]", " [EVENT]"]
    with gzip.open("/app/dataset/logs/sensor_a.log.gz", "wb") as f:
        f.write(("\n".join(a_lines) + "\n").encode("utf-8"))
    with gzip.open("/app/dataset/logs/sensor_b.log.gz", "wb") as f:
        f.write(("\n".join(b_lines) + "\n").encode("utf-16le"))
    alias = "/app/dataset/logs/subdir/sensor_a_alias.log.gz"
    try:
        os.unlink(alias)
    except FileNotFoundError:
        pass
    os.link("/app/dataset/logs/sensor_a.log.gz", alias)

    expected_events = independently_count_events("/app/dataset/logs")
    assert expected_events == 18

    os.kill(pid, signal.SIGTERM)
    deadline = time.time() + 10
    while time.time() < deadline and os.path.exists(f"/proc/{pid}"):
        time.sleep(0.1)
    if os.path.exists(f"/proc/{pid}"):
        os.kill(pid, signal.SIGKILL)
        time.sleep(0.25)

    launch = [exe] + argv[1:]
    subprocess.Popen(launch, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)
    wait_for_server(25)

    changed = get_stats()
    assert changed["total_frames"] == expected_frames
    assert changed["total_events"] == expected_events, "Server did not actually parse verifier-chosen UTF-8/UTF-16LE gzip logs"
    verify_all_frames(expected_frames)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
