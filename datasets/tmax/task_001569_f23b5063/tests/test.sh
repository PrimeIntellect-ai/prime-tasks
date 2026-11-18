#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import functools
import os
import re
import socket
import subprocess
import tarfile
import tempfile
import time
import uuid

import cv2
import pytest

HOST = "127.0.0.1"
PORT = 5050
TOKEN = b"AUTH storage_sec_token_v1\n"


def recv_line(sock):
    data = b""
    while not data.endswith(b"\n"):
        chunk = sock.recv(1024)
        if not chunk:
            break
        data += chunk
    return data


@functools.lru_cache(maxsize=1)
def expected_video_count():
    cap = cv2.VideoCapture("/app/console_recording.mp4")
    assert cap.isOpened(), "Could not open /app/console_recording.mp4"
    count = 0
    candidates = 0
    try:
        while True:
            ok, frame = cap.read()
            if not ok:
                break

            # The fixture's breach text is white, while ordinary console text is
            # green. OCR only the white-text candidates, deriving the answer from
            # the supplied recording rather than embedding it in the verifier.
            white = cv2.inRange(frame, (180, 180, 180), (255, 255, 255))
            if cv2.countNonZero(white) < 50:
                continue
            candidates += 1
            ys, xs = white.nonzero()
            crop = frame[max(0, ys.min() - 12):min(frame.shape[0], ys.max() + 13),
                         max(0, xs.min() - 12):min(frame.shape[1], xs.max() + 13)]
            crop = cv2.resize(crop, None, fx=2, fy=2, interpolation=cv2.INTER_CUBIC)
            encoded_ok, encoded = cv2.imencode(".png", crop)
            assert encoded_ok
            result = subprocess.run(
                ["tesseract", "stdin", "stdout", "--psm", "7",
                 "-c", "tessedit_char_whitelist=ABCDEFGHIJKLMNOPQRSTUVWXYZ_"],
                input=encoded.tobytes(), stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL, check=True,
            )
            if "BREACH_DETECTED" in result.stdout.decode("utf-8", "replace"):
                count += 1
    finally:
        cap.release()

    assert candidates > 0, "No candidate text frames were found in the recording"
    assert count > 0, "OCR did not find BREACH_DETECTED in the recording"
    return count


def listener_pids():
    inodes = set()
    try:
        with open("/proc/net/tcp", "r") as f:
            for line in f.readlines()[1:]:
                fields = line.split()
                if len(fields) > 9 and fields[3] == "0A":
                    _, port_hex = fields[1].split(":")
                    if int(port_hex, 16) == PORT:
                        inodes.add(fields[9])
    except OSError:
        return []

    found = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    found.append(int(entry))
                    break
        except OSError:
            continue
    return found


def connect_authenticated():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(3)
    s.connect((HOST, PORT))
    s.sendall(TOKEN)
    assert recv_line(s) == b"OK\n"
    return s


def make_tar(path, members):
    with tarfile.open(path, "w", format=tarfile.USTAR_FORMAT) as tf:
        for name, payload in members:
            info = tarfile.TarInfo(name=name)
            info.size = len(payload)
            tf.addfile(info, fileobj=__import__("io").BytesIO(payload))
    os.chmod(path, 0o644)


def test_metadata_search():
    output_file = "/home/user/compromised_files.txt"
    assert os.path.isfile(output_file), f"Output file {output_file} is missing."

    with open(output_file, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_files = set()
    for root, _, files in os.walk("/app/storage_metadata/"):
        for file in files:
            if not file.endswith(".json"):
                continue
            path = os.path.join(root, file)
            if os.path.getsize(path) > 10240:
                with open(path, "r") as f:
                    content = f.read()
                    if '"status":"compromised"' in content.replace(" ", ""):
                        expected_files.add(path)

    assert set(lines) == expected_files, f"Expected {expected_files}, but got {set(lines)} in {output_file}"


def test_daemon_artifacts_and_source_compile():
    source = "/home/user/daemon.c"
    binary = "/home/user/daemon"
    assert os.path.isfile(source), f"Missing {source}"
    assert os.path.isfile(binary), f"Missing {binary}"
    assert os.access(binary, os.X_OK), f"{binary} is not executable"
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{binary} is not an ELF executable"

    with open(source, "r", errors="replace") as f:
        text = f.read()
    without_comments = re.sub(r"/\*.*?\*/|//[^\n]*", "", text, flags=re.S)
    forbidden = re.compile(
        r"\b(system|popen|execl|execle|execlp|execv|execve|execvp|execvpe|posix_spawn|posix_spawnp)\s*\("
    )
    assert not forbidden.search(without_comments), "daemon.c delegates work to an external command"

    compiled = f"/tmp/daemon_compile_check_{os.getpid()}"
    result = subprocess.run(
        ["gcc", "-O2", "-pthread", source, "-o", compiled],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    assert result.returncode == 0, f"daemon.c does not compile:\n{result.stderr}"
    assert os.path.isfile(compiled) and os.access(compiled, os.X_OK)

    pids = listener_pids()
    assert pids, "Daemon is not listening on TCP port 5050"
    assert any(
        os.path.exists(f"/proc/{pid}/exe") and os.path.samefile(f"/proc/{pid}/exe", binary)
        for pid in pids
    ), "The process listening on port 5050 is not /home/user/daemon"


def test_daemon_unauthenticated_drop():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(2)
    try:
        s.connect((HOST, PORT))
        s.sendall(b"VIDEO_COUNT\n")
        response = s.recv(1024)
        assert response == b"", "Expected connection to be dropped without AUTH, but got response."
    except ConnectionRefusedError:
        pytest.fail("Daemon is not listening on 127.0.0.1:5050")
    finally:
        s.close()


def test_daemon_bad_auth_drop():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(2)
    try:
        s.connect((HOST, PORT))
        s.sendall(b"AUTH bad_token\n")
        response = s.recv(1024)
        assert response == b"", "Expected connection to be dropped with bad AUTH, but got response."
    finally:
        s.close()


def test_daemon_protocol():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(3)
    try:
        s.connect((HOST, PORT))
        s.sendall(TOKEN)
        response = recv_line(s).decode()
        assert response == "OK\n", f"Expected 'OK\\n', got {repr(response)}"

        expected = expected_video_count()
        s.sendall(b"VIDEO_COUNT\n")
        response = recv_line(s).decode()
        assert response == f"COUNT: {expected}\n", f"Expected 'COUNT: {expected}\\n', got {repr(response)}"

        s.sendall(b"INSPECT /app/test_safe.tar\n")
        response = recv_line(s).decode()
        assert response == "SAFE\n", f"Expected 'SAFE\\n', got {repr(response)}"

        s.sendall(b"INSPECT /app/test_malicious.tar\n")
        response = recv_line(s).decode()
        assert response == "MALICIOUS\n", f"Expected 'MALICIOUS\\n', got {repr(response)}"

        s.sendall(b"WATCH /home/user/dropzone\n")
        response = recv_line(s).decode()
        assert response == "WATCHING\n", f"Expected 'WATCHING\\n', got {repr(response)}"
    finally:
        s.close()


def test_daemon_watch_behavior():
    time.sleep(0.5)
    payload_path = "/home/user/dropzone/payload.tar"
    with tarfile.open(payload_path, "w") as tar:
        ti = tarfile.TarInfo(name="../etc/shadow")
        ti.size = 0
        tar.addfile(ti)

    time.sleep(1)
    log_path = "/home/user/archive_watch.log"
    assert os.path.isfile(log_path), f"Log file {log_path} was not created."
    with open(log_path, "r") as f:
        log_content = f.read()
    expected_log = "[NEW_FILE] payload.tar: MALICIOUS\n"
    assert expected_log in log_content, f"Expected {repr(expected_log)} in log file, got {repr(log_content)}"


def test_dynamic_archive_inspection_and_repeated_watch_events():
    root = tempfile.mkdtemp(prefix="verify_storage_", dir="/home/user")
    os.chmod(root, 0o755)
    nonce = uuid.uuid4().hex

    safe_path = os.path.join(root, f"safe_{nonce}.tar")
    traversal_path = os.path.join(root, f"traversal_{nonce}.tar")
    absolute_path = os.path.join(root, f"absolute_{nonce}.tar")

    # The safe archive deliberately contains traversal-looking bytes in file data.
    # A correct implementation must parse headers and skip payload blocks.
    make_tar(safe_path, [
        (f"records/{nonce}/report.txt", b"payload mentions ../ and /etc/passwd but is safe\n" * 40),
        (f"records/{nonce}/second.bin", os.urandom(777)),
    ])
    make_tar(traversal_path, [
        (f"ordinary/{nonce}.bin", os.urandom(900)),
        (f"ordinary/../../escape_{nonce}", b"x"),
    ])
    make_tar(absolute_path, [(f"/absolute_{nonce}", b"")])

    s = connect_authenticated()
    try:
        for path, expected in [
            (safe_path, b"SAFE\n"),
            (traversal_path, b"MALICIOUS\n"),
            (absolute_path, b"MALICIOUS\n"),
            (safe_path, b"SAFE\n"),
        ]:
            s.sendall(f"INSPECT {path}\n".encode())
            assert recv_line(s) == expected
    finally:
        s.close()

    watch_dir = os.path.join(root, f"watch_{nonce}")
    os.mkdir(watch_dir, 0o777)
    os.chmod(watch_dir, 0o777)
    s = connect_authenticated()
    try:
        s.sendall(f"WATCH {watch_dir}\n".encode())
        assert recv_line(s) == b"WATCHING\n"
    finally:
        s.close()

    events = []
    for index, malicious in enumerate((False, True, False)):
        basename = f"event_{index}_{uuid.uuid4().hex}.tar"
        path = os.path.join(watch_dir, basename)
        if malicious:
            make_tar(path, [(f"dir/../../../watch_escape_{uuid.uuid4().hex}", b"")])
            verdict = "MALICIOUS"
        else:
            make_tar(path, [(f"safe/{uuid.uuid4().hex}.txt", b"../ only in payload")])
            verdict = "SAFE"
        events.append(f"[NEW_FILE] {basename}: {verdict}")
        time.sleep(0.15)

    deadline = time.time() + 5
    log_content = ""
    while time.time() < deadline:
        try:
            with open("/home/user/archive_watch.log", "r") as f:
                log_content = f.read()
        except FileNotFoundError:
            pass
        if all(entry + "\n" in log_content for entry in events):
            break
        time.sleep(0.1)

    for entry in events:
        assert entry + "\n" in log_content, f"Missing dynamic watch entry {entry!r}; log was {log_content!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
