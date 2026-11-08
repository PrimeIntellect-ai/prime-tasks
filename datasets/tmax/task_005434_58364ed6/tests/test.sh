#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import io
import os
import re
import select
import signal
import struct
import subprocess
import tarfile
import threading
import time
import zipfile
import secrets


def test_organizer_throughput():
    script_path = "/home/user/organizer.py"
    master_log_path = "/home/user/master_log.txt"
    dropzone_path = "/home/user/dropzone"

    assert os.path.exists(script_path), f"Agent script not found at {script_path}"
    assert os.path.isfile(script_path), f"Agent script is not a regular file: {script_path}"

    subprocess.run(["pkill", "-f", "log_emitter"], check=False)
    subprocess.run(["rm", "-rf", dropzone_path], check=False)
    subprocess.run(["rm", "-f", master_log_path], check=False)
    os.makedirs(dropzone_path, mode=0o777, exist_ok=True)
    os.chmod(dropzone_path, 0o777)

    # Record every archive atomically published by the real emitter. Its archive
    # filename contains the same timestamp and random number as event.log.
    libc = ctypes.CDLL(None, use_errno=True)
    fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    assert fd >= 0, "Could not initialize inotify"
    IN_MOVED_TO = 0x00000080
    wd = libc.inotify_add_watch(fd, dropzone_path.encode(), IN_MOVED_TO)
    assert wd >= 0, "Could not watch dropzone"

    emitted_lines = set()
    emitted_lock = threading.Lock()
    stop_watcher = threading.Event()
    archive_re = re.compile(r"^archive_(\d+)_(\d+)\.zip$")

    def consume_events():
        while True:
            try:
                data = os.read(fd, 65536)
            except BlockingIOError:
                return
            if not data:
                return
            offset = 0
            while offset + 16 <= len(data):
                _, mask, _, name_len = struct.unpack_from("iIII", data, offset)
                offset += 16
                raw_name = data[offset:offset + name_len]
                offset += name_len
                name = raw_name.split(b"\0", 1)[0].decode(errors="replace")
                if mask & IN_MOVED_TO:
                    match = archive_re.match(name)
                    if match:
                        line = f"LOG_LINE_{match.group(1)}_{match.group(2)}"
                        with emitted_lock:
                            emitted_lines.add(line)

    def watch_dropzone():
        while not stop_watcher.is_set():
            ready, _, _ = select.select([fd], [], [], 0.05)
            if ready:
                consume_events()
        consume_events()

    watcher = threading.Thread(target=watch_dropzone, daemon=True)
    watcher.start()

    proc = None
    challenge_lines = set()
    try:
        proc = subprocess.Popen(["python3", script_path])

        # Add valid archives whose contents cannot be inferred from their names.
        # This verifies that the organizer really opens and extracts nested data.
        for i in range(8):
            value = secrets.randbelow(2**62)
            line = f"LOG_LINE_{int(time.time())}_{value}"
            challenge_lines.add(line)

            event_data = (line + "\n").encode()
            tar_buffer = io.BytesIO()
            with tarfile.open(fileobj=tar_buffer, mode="w:gz") as tf:
                info = tarfile.TarInfo("event.log")
                info.size = len(event_data)
                tf.addfile(info, io.BytesIO(event_data))

            zip_buffer = io.BytesIO()
            with zipfile.ZipFile(zip_buffer, "w", compression=zipfile.ZIP_DEFLATED) as zf:
                zf.writestr("inner.tar.gz", tar_buffer.getvalue())

            stem = f"probe_{i}_{secrets.token_hex(8)}"
            tmp_path = os.path.join(dropzone_path, stem + ".tmp")
            zip_path = os.path.join(dropzone_path, stem + ".zip")
            with open(tmp_path, "wb") as f:
                f.write(zip_buffer.getvalue())
                f.flush()
                os.fsync(f.fileno())
            os.replace(tmp_path, zip_path)

        # Allow it to run for exactly 15 seconds.
        time.sleep(15.0)

        proc.send_signal(signal.SIGINT)
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=1)

        stop_watcher.set()
        watcher.join(timeout=1)

        lines = []
        if os.path.exists(master_log_path):
            with open(master_log_path, "r", errors="replace") as f:
                lines = [line.strip() for line in f if line.strip()]

        # Preserve the original throughput assertion.
        count = len(lines)
        assert count >= 200, f"Throughput too low: extracted {count} lines, expected >= 200"

        with emitted_lock:
            valid_lines = set(emitted_lines)
        valid_lines.update(challenge_lines)

        invalid = [line for line in lines if line not in valid_lines]
        assert not invalid, f"Master log contains lines not produced by tested archives: {invalid[:5]}"
        assert challenge_lines.issubset(set(lines)), \
            "Organizer did not extract all verifier-supplied nested archives"
    finally:
        stop_watcher.set()
        watcher.join(timeout=1)
        os.close(fd)
        if proc is not None and proc.poll() is None:
            proc.kill()
            proc.wait(timeout=1)
        subprocess.run(["pkill", "-f", "log_emitter"], check=False)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
