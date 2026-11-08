#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import signal
import struct
import subprocess
import sys
import time

import pytest
import requests

WAL_PATH = "/app/db_system.wal"
FILTERED_WAL_PATH = "/home/user/filtered.wal"
VIDEO_PATH = "/app/server_room_cam.mp4"
FRAMES_DIR = "/home/user/frames"
BASE_URL = "http://127.0.0.1:8000"
AUTH_HEADER = {"Authorization": "Bearer archiver_token_x7z"}
BAD_AUTH_HEADER = {"Authorization": "Bearer incorrect_token"}


def pack_records(records):
    data = b""
    for ts, rtype, payload in records:
        data += struct.pack(">Q B I", ts, rtype, len(payload))
        data += payload
    return data


def get_expected_wal_content():
    return pack_records([
        (1700000015, 0x03, b"OOM Killer invoked"),
        (1700000025, 0x03, b"Disk write failure sector 8"),
    ])


def request(path, headers=None):
    try:
        return requests.get(f"{BASE_URL}{path}", headers=headers, timeout=2)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to API: {exc}")


def decode_rgb(path):
    proc = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-frames:v", "1",
         "-pix_fmt", "rgb24", "-f", "rawvideo", "pipe:1"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert proc.returncode == 0, f"ffmpeg could not decode {path}: {proc.stderr.decode(errors='replace')}"
    return proc.stdout


def source_rgb(timestamp):
    proc = subprocess.run(
        ["ffmpeg", "-v", "error", "-ss", f"{timestamp:.1f}", "-i", VIDEO_PATH,
         "-frames:v", "1", "-pix_fmt", "rgb24", "-f", "rawvideo", "pipe:1"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert proc.returncode == 0, f"Could not extract reference frame at {timestamp}: {proc.stderr.decode(errors='replace')}"
    assert proc.stdout, f"No source frame was available at {timestamp}"
    return proc.stdout


def mean_abs_error(a, b):
    assert len(a) == len(b), "Extracted frame dimensions do not match the source video"
    return sum(abs(x - y) for x, y in zip(a, b)) / len(a)


def test_filtered_wal_exists_and_correct():
    assert os.path.exists(FILTERED_WAL_PATH), f"Filtered WAL file not found at {FILTERED_WAL_PATH}"
    with open(FILTERED_WAL_PATH, "rb") as f:
        content = f.read()
    assert content == get_expected_wal_content(), "Filtered WAL file content does not match expected critical records"


def test_frames_extracted_from_requested_video_timestamps():
    assert os.path.isdir(FRAMES_DIR), f"Frames directory not found at {FRAMES_DIR}"
    target_refs = {sec: source_rgb(float(sec)) for sec in range(10, 16)}

    for sec in range(10, 16):
        frame_path = os.path.join(FRAMES_DIR, f"frame_{sec}.jpg")
        assert os.path.exists(frame_path), f"Frame for second {sec} not found at {frame_path}"
        assert os.path.isfile(frame_path), f"Frame for second {sec} is not a regular file"
        assert os.path.getsize(frame_path) > 0, f"Frame for second {sec} is empty"

        submitted = decode_rgb(frame_path)
        target_error = mean_abs_error(submitted, target_refs[sec])
        assert target_error <= 20.0, f"frame_{sec}.jpg does not visually match the source video at second {sec}"

        comparison_refs = [target_refs[s] for s in range(10, 16) if s != sec]
        if sec > 0:
            comparison_refs.append(source_rgb(sec - 0.1))
        comparison_refs.append(source_rgb(sec + 0.1))
        other_errors = [mean_abs_error(submitted, ref) for ref in comparison_refs]
        assert target_error <= min(other_errors), f"frame_{sec}.jpg is not the frame at the requested timestamp"


def test_api_wal_no_auth():
    resp = request("/api/wal")
    assert resp.status_code == 401, f"Expected HTTP 401 without auth, got {resp.status_code}"


def test_api_wal_with_auth():
    resp = request("/api/wal", AUTH_HEADER)
    assert resp.status_code == 200, f"Expected HTTP 200 with auth, got {resp.status_code}"
    assert resp.headers.get("Content-Type") == "application/octet-stream", "Incorrect Content-Type for WAL"
    assert resp.content == get_expected_wal_content(), "API returned incorrect WAL content"


def test_authentication_is_enforced_on_every_endpoint():
    paths = ["/api/wal"] + [f"/api/frame/{sec}" for sec in range(10, 16)] + ["/api/frame/99"]
    for path in paths:
        for headers, description in [(None, "missing"), (BAD_AUTH_HEADER, "incorrect")]:
            resp = request(path, headers)
            assert resp.status_code == 401, f"Expected HTTP 401 for {description} auth on {path}, got {resp.status_code}"


def test_api_frames_with_auth_return_corresponding_files():
    for sec in range(10, 16):
        resp = request(f"/api/frame/{sec}", AUTH_HEADER)
        assert resp.status_code == 200, f"Expected HTTP 200 for frame {sec} with auth, got {resp.status_code}"
        assert resp.headers.get("Content-Type") == "image/jpeg", f"Incorrect Content-Type for frame {sec}"
        frame_path = os.path.join(FRAMES_DIR, f"frame_{sec}.jpg")
        with open(frame_path, "rb") as f:
            expected = f.read()
        assert resp.content == expected, f"API did not return the corresponding frame_{sec}.jpg file"


def test_api_frame_not_found():
    resp = request("/api/frame/99", AUTH_HEADER)
    assert resp.status_code == 404, f"Expected HTTP 404 for missing frame, got {resp.status_code}"


def read_inotify_events(fd):
    events = []
    while True:
        try:
            chunk = os.read(fd, 65536)
        except BlockingIOError:
            break
        if not chunk:
            break
        offset = 0
        while offset + 16 <= len(chunk):
            wd, mask, cookie, name_len = struct.unpack_from("iIII", chunk, offset)
            offset += 16
            raw_name = chunk[offset:offset + name_len]
            offset += name_len
            name = raw_name.split(b"\0", 1)[0].decode(errors="replace")
            events.append((mask, cookie, name))
    return events


def test_wal_script_filters_dynamic_input_and_uses_atomic_rename():
    candidates = []
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d != "frames"]
        for filename in files:
            if not filename.endswith(".py"):
                continue
            path = os.path.join(root, filename)
            try:
                text = open(path, "r", encoding="utf-8").read()
            except (OSError, UnicodeError):
                continue
            if "/app/db_system.wal" in text and "filtered.wal" in text:
                candidates.append(path)
    assert candidates, "The required Python WAL-processing script was not found under /home/user"

    challenge_records = [
        (1800000001, 0x02, b"ignore this warning"),
        (1800000002, 0x03, b"dynamic critical alpha"),
        (1800000003, 0x01, b"ignore this info"),
        (1800000004, 0x03, b"dynamic critical omega"),
    ]
    challenge_wal = pack_records(challenge_records)
    challenge_expected = pack_records([challenge_records[1], challenge_records[3]])

    with open(WAL_PATH, "rb") as f:
        original_wal = f.read()
    with open(FILTERED_WAL_PATH, "rb") as f:
        original_filtered = f.read()

    libc = ctypes.CDLL(None, use_errno=True)
    IN_MOVED_FROM = 0x00000040
    IN_MOVED_TO = 0x00000080
    failures = []
    passed = False

    try:
        for script in candidates:
            proc = None
            fd = -1
            try:
                with open(WAL_PATH, "wb") as f:
                    f.write(challenge_wal)
                try:
                    os.unlink(FILTERED_WAL_PATH)
                except FileNotFoundError:
                    pass

                fd = libc.inotify_init1(os.O_NONBLOCK)
                assert fd >= 0, "Could not initialize filesystem monitoring"
                wd = libc.inotify_add_watch(fd, b"/home/user", IN_MOVED_FROM | IN_MOVED_TO)
                assert wd >= 0, "Could not monitor /home/user for atomic rename"

                proc = subprocess.Popen(
                    [sys.executable, script],
                    cwd=os.path.dirname(script) or "/home/user",
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    start_new_session=True,
                )
                try:
                    proc.wait(timeout=4)
                except subprocess.TimeoutExpired:
                    pass
                time.sleep(0.2)
                events = read_inotify_events(fd)

                content = b""
                if os.path.isfile(FILTERED_WAL_PATH):
                    with open(FILTERED_WAL_PATH, "rb") as f:
                        content = f.read()

                moved_from = {(cookie, name) for mask, cookie, name in events if mask & IN_MOVED_FROM}
                atomic_move = any(
                    (mask & IN_MOVED_TO) and name == "filtered.wal" and
                    any(old_cookie == cookie and old_name != "filtered.wal" for old_cookie, old_name in moved_from)
                    for mask, cookie, name in events
                )
                if content == challenge_expected and atomic_move:
                    passed = True
                    break
                failures.append(f"{script}: dynamic output correct={content == challenge_expected}, atomic rename observed={atomic_move}")
            except Exception as exc:
                failures.append(f"{script}: {exc}")
            finally:
                if proc is not None:
                    try:
                        os.killpg(proc.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    try:
                        proc.wait(timeout=1)
                    except Exception:
                        pass
                if fd >= 0:
                    os.close(fd)
    finally:
        with open(WAL_PATH, "wb") as f:
            f.write(original_wal)
        restore_tmp = "/home/user/.verifier_restore_filtered.wal"
        with open(restore_tmp, "wb") as f:
            f.write(original_filtered)
        os.replace(restore_tmp, FILTERED_WAL_PATH)

    assert passed, "No WAL script correctly filtered a changed input using a same-directory atomic rename. " + "; ".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
