#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import select
import shutil
import struct
import subprocess
import uuid

import pytest
from PIL import Image, ImageDraw

SCRIPT = "/home/user/consolidate.sh"
WAL_DIR = "/home/user/wal_logs"
OUTPUT_DIR = "/home/user/output"
TARGET = "/home/user/output/latest_config.json"
SYMLINK = "/home/user/current_config"
IMAGE = "/app/schema_info.png"

IN_MOVED_FROM = 0x00000040
IN_MOVED_TO = 0x00000080
WATCH_MASK = IN_MOVED_FROM | IN_MOVED_TO

baseline_complete = False


def write_schema(keys):
    img = Image.new("RGB", (800, 200), color=(255, 255, 255))
    draw = ImageDraw.Draw(img)
    draw.text((10, 10), "SCHEMA_ID: 9942\nALLOWED_KEYS: " + ", ".join(keys), fill=(0, 0, 0))
    img.save(IMAGE)


def write_wals(chunks):
    os.makedirs(WAL_DIR, exist_ok=True)
    for name in os.listdir(WAL_DIR):
        path = os.path.join(WAL_DIR, name)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)
    for name, content in chunks.items():
        with open(os.path.join(WAL_DIR, name), "w", encoding="utf-8") as f:
            f.write(content)


def run_script_and_capture_renames():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    libc = ctypes.CDLL(None, use_errno=True)
    fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    if fd < 0:
        raise OSError(ctypes.get_errno(), "inotify_init1 failed")
    wd = libc.inotify_add_watch(fd, OUTPUT_DIR.encode(), WATCH_MASK)
    if wd < 0:
        err = ctypes.get_errno()
        os.close(fd)
        raise OSError(err, "inotify_add_watch failed")

    proc = subprocess.Popen(
        ["bash", SCRIPT], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    events = []
    while proc.poll() is None:
        ready, _, _ = select.select([fd], [], [], 0.05)
        if ready:
            events.extend(read_events(fd))
    for _ in range(5):
        ready, _, _ = select.select([fd], [], [], 0.02)
        if not ready:
            break
        events.extend(read_events(fd))
    stdout, stderr = proc.communicate(timeout=2)
    os.close(fd)
    assert proc.returncode == 0, (
        f"consolidate.sh exited with {proc.returncode}\nstdout:\n{stdout}\nstderr:\n{stderr}"
    )
    return events


def read_events(fd):
    result = []
    while True:
        try:
            data = os.read(fd, 65536)
        except BlockingIOError:
            break
        if not data:
            break
        offset = 0
        while offset + 16 <= len(data):
            wd, mask, cookie, length = struct.unpack_from("iIII", data, offset)
            offset += 16
            raw_name = data[offset:offset + length]
            offset += length
            name = raw_name.split(b"\0", 1)[0].decode(errors="replace")
            result.append((mask, cookie, name))
    return result


def assert_atomic_replacement(events):
    moved_to = [e for e in events if e[0] & IN_MOVED_TO and e[2] == "latest_config.json"]
    assert moved_to, "Final output was not installed using an atomic rename."
    assert any(
        cookie != 0 and any(
            (mask & IN_MOVED_FROM) and other_cookie == cookie and name != "latest_config.json"
            for mask, other_cookie, name in events
        )
        for _, cookie, _ in moved_to
    ), "The temporary output was not renamed from within the output directory."


def read_and_validate_minified(expected):
    assert os.path.isfile(TARGET), f"Output file {TARGET} does not exist."
    with open(TARGET, "r", encoding="utf-8") as f:
        content = f.read()
    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        pytest.fail(f"File {TARGET} does not contain valid JSON.")
    assert data == expected, f"JSON content {data} does not match expected {expected}."
    assert content == json.dumps(data, separators=(",", ":"), ensure_ascii=False), (
        "JSON output is not strictly minified or contains a trailing newline."
    )
    return content


def test_script_exists():
    """Verify the bash script was created at the requested location."""
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."


def test_execute_baseline_wal():
    global baseline_complete
    write_schema(["host", "port", "user", "pass", "dbname", "timeout", "retries"])
    write_wals({
        "chunk_01.log": "SET host old.example.com\nSET port 5432\nSET dbname prod_db\nSET temp_cache 1024\n",
        "chunk_02.log": "SET host db.example.com\nDELETE dbname\nSET timeout 30\nSET user admin\n",
        "chunk_03.log": "SET pass secret123\nDELETE timeout\nSET retries 3\nSET temp_cache 2048\n",
    })
    if os.path.lexists(SYMLINK):
        os.unlink(SYMLINK)
    if os.path.exists(TARGET):
        os.unlink(TARGET)
    events = run_script_and_capture_renames()
    assert_atomic_replacement(events)
    baseline_complete = True


def test_symlink_exists_and_correct():
    """Verify the symlink points to the correct target."""
    assert baseline_complete
    assert os.path.islink(SYMLINK), f"{SYMLINK} is not a symbolic link."
    assert os.readlink(SYMLINK) == TARGET, f"Symlink {SYMLINK} does not point to {TARGET}."


def test_json_content_and_size():
    """Verify the JSON output is correct and minified."""
    assert baseline_complete
    expected = {
        "host": "db.example.com",
        "port": "5432",
        "user": "admin",
        "pass": "secret123",
        "retries": "3",
    }
    content = read_and_validate_minified(expected)
    file_size = len(content)
    threshold = 90
    assert file_size <= threshold, (
        f"File size is {file_size} bytes, expected <= {threshold} bytes. "
        "The JSON is not sufficiently minified."
    )


def test_dynamic_wal_and_ocr_schema():
    token = uuid.uuid4().hex
    host_old = "old-" + token
    host_final = "db-" + token + ".example"
    region_old = "west-" + token
    region_final = "east-" + token
    retry_value = str(int(token[:6], 16))

    # This schema intentionally differs from the original and includes a new key,
    # so the allowed-key list must actually be obtained from the image.
    write_schema(["host", "region", "retries"])
    write_wals({
        "chunk_01.log": (
            f"SET host {host_old}\n"
            f"SET region {region_old}\n"
            f"SET user forbidden-{token}\n"
        ),
        "chunk_02.log": (
            "DELETE host\n"
            f"SET retries discarded-{token}\n"
            f"SET port {token[:4]}\n"
        ),
        "chunk_10.log": (
            f"SET host {host_final}\n"
            "DELETE retries\n"
            f"SET region {region_final}\n"
        ),
        "chunk_11.log": f"SET retries {retry_value}\nSET temp_cache {token}\n",
    })

    with open(TARGET, "w", encoding="utf-8") as f:
        f.write('{"sentinel":"old"}')
    if os.path.lexists(SYMLINK):
        os.unlink(SYMLINK)

    events = run_script_and_capture_renames()
    assert_atomic_replacement(events)
    read_and_validate_minified({
        "host": host_final,
        "region": region_final,
        "retries": retry_value,
    })
    assert os.path.islink(SYMLINK), f"{SYMLINK} is not a symbolic link."
    assert os.readlink(SYMLINK) == TARGET, f"Symlink {SYMLINK} does not point to {TARGET}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
