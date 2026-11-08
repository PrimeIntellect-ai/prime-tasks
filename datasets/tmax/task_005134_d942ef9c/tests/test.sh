#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import pytest

def test_published_directory_exists():
    curated_dir = "/home/user/published/release_1_curated"
    assert os.path.isdir(curated_dir), f"The directory {curated_dir} does not exist. Did the script publish the artifacts?"

def test_published_files_exist():
    curated_dir = "/home/user/published/release_1_curated"
    expected_files = ["binary.elf", "signature.bin", "metadata.json"]
    for f in expected_files:
        file_path = os.path.join(curated_dir, f)
        assert os.path.isfile(file_path), f"Expected file {f} is missing in {curated_dir}."

def test_binary_and_signature_contents():
    curated_dir = "/home/user/published/release_1_curated"

    sig_path = os.path.join(curated_dir, "signature.bin")
    if os.path.exists(sig_path):
        with open(sig_path, "r") as f:
            assert f.read() == "SIG-12345", "The content of signature.bin is incorrect."

    bin_path = os.path.join(curated_dir, "binary.elf")
    if os.path.exists(bin_path):
        with open(bin_path, "r") as f:
            assert f.read() == "ELF-DATA", "The content of binary.elf is incorrect."

def test_metadata_json_content():
    json_path = "/home/user/published/release_1_curated/metadata.json"
    assert os.path.isfile(json_path), f"File {json_path} does not exist."

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{json_path} does not contain valid JSON.")

    expected_data = {
        "build": {
            "version": "1.0.42",
            "arch": "amd64"
        },
        "runtime": {
            "env": "production"
        }
    }

    assert data == expected_data, f"The contents of {json_path} do not match the expected parsed INI structure."

def test_success_log_exists_and_matches():
    log_path = "/home/user/success.log"
    assert os.path.isfile(log_path), f"The file {log_path} does not exist. Did you copy the metadata.json file?"

    with open(log_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{log_path} does not contain valid JSON.")

    expected_data = {
        "build": {
            "version": "1.0.42",
            "arch": "amd64"
        },
        "runtime": {
            "env": "production"
        }
    }

    assert data == expected_data, f"The contents of {log_path} do not match the expected JSON output."
TEST_EOF

cat << 'TEST_EOF' > /tmp/test_curator_behavior.py
import ctypes
import io
import json
import os
import select
import shutil
import signal
import struct
import subprocess
import tarfile
import tempfile
import time
import uuid
import zipfile

SCRIPT = "/home/user/curator.py"
INCOMING = "/home/user/incoming"
PUBLISHED = "/home/user/published"
IN_CREATE = 0x00000100
IN_MOVED_TO = 0x00000080


def stop_existing_curators():
    me = os.getpid()
    victims = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == me:
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                args = [a.decode(errors="ignore") for a in f.read().split(b"\\0") if a]
            if SCRIPT in args:
                os.kill(int(entry), signal.SIGTERM)
                victims.append(int(entry))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    if victims:
        time.sleep(0.5)
        for pid in victims:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def test_curator_processes_unseen_bundle_and_publishes_atomically():
    assert os.path.isfile(SCRIPT), f"Required Python script {SCRIPT} does not exist"
    with open(SCRIPT, "rb") as f:
        source = f.read()
    compile(source, SCRIPT, "exec")

    stop_existing_curators()
    os.makedirs(INCOMING, exist_ok=True)
    os.makedirs(PUBLISHED, exist_ok=True)
    for name in os.listdir(INCOMING):
        if name.endswith(".zip"):
            os.unlink(os.path.join(INCOMING, name))

    token = uuid.uuid4().hex
    bundle_name = f"dynamic_{token}.zip"
    curated_name = f"dynamic_{token}_curated"
    destination = os.path.join(PUBLISHED, curated_name)
    shutil.rmtree(destination, ignore_errors=True)

    binary = os.urandom(257)
    signature = os.urandom(113)
    version = f"{int(token[:4], 16)}.{int(token[4:8], 16)}"
    arch = f"arch-{token[8:16]}"
    environment = f"env-{token[16:24]}"
    channel = f"channel-{token[24:]}"
    metadata = (
        f"[build]\\nversion={version}\\narch={arch}\\n"
        f"[runtime]\\nenv={environment}\\nchannel={channel}\\n"
    ).encode()
    expected_json = {
        "build": {"version": version, "arch": arch},
        "runtime": {"env": environment, "channel": channel},
    }

    workspace = tempfile.mkdtemp(prefix="curator-verifier-")
    proc = None
    fd = -1
    try:
        inner_path = os.path.join(workspace, "inner.tar.gz")
        with tarfile.open(inner_path, "w:gz") as tf:
            for name, payload in (("binary.elf", binary), ("metadata.ini", metadata)):
                info = tarfile.TarInfo(name)
                info.size = len(payload)
                tf.addfile(info, io.BytesIO(payload))

        staged_zip = os.path.join(workspace, bundle_name)
        with zipfile.ZipFile(staged_zip, "w", compression=zipfile.ZIP_DEFLATED) as zf:
            zf.write(inner_path, "inner.tar.gz")
            zf.writestr("signature.bin", signature)

        libc = ctypes.CDLL(None, use_errno=True)
        libc.inotify_init1.argtypes = [ctypes.c_int]
        libc.inotify_init1.restype = ctypes.c_int
        libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
        libc.inotify_add_watch.restype = ctypes.c_int
        fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
        assert fd >= 0, f"inotify_init1 failed: errno {ctypes.get_errno()}"
        wd = libc.inotify_add_watch(fd, PUBLISHED.encode(), IN_CREATE | IN_MOVED_TO)
        assert wd >= 0, f"inotify_add_watch failed: errno {ctypes.get_errno()}"

        proc = subprocess.Popen(
            ["python3", SCRIPT],
            cwd="/home/user",
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
        time.sleep(1.0)
        assert proc.poll() is None, "curator.py exited instead of continuing to watch the incoming directory"

        os.replace(staged_zip, os.path.join(INCOMING, bundle_name))

        deadline = time.time() + 30
        publication_mask = None
        while time.time() < deadline and publication_mask is None:
            if proc.poll() is not None:
                stderr = proc.stderr.read().decode(errors="replace")
                raise AssertionError(f"curator.py exited while processing the new bundle: {stderr}")
            ready, _, _ = select.select([fd], [], [], 0.25)
            if not ready:
                continue
            data = os.read(fd, 65536)
            offset = 0
            while offset < len(data):
                _, mask, _, length = struct.unpack_from("iIII", data, offset)
                offset += 16
                raw_name = data[offset:offset + length]
                offset += length
                name = raw_name.split(b"\\0", 1)[0].decode(errors="replace")
                if name == curated_name:
                    if mask & IN_CREATE:
                        raise AssertionError("The final curated directory was created directly instead of being atomically renamed into place")
                    if mask & IN_MOVED_TO:
                        publication_mask = mask
                        break

        assert publication_mask is not None, "No atomic rename/move published the dynamically generated bundle"
        assert os.path.isdir(destination), "Atomic publication event did not produce the curated directory"

        binary_path = os.path.join(destination, "binary.elf")
        signature_path = os.path.join(destination, "signature.bin")
        json_path = os.path.join(destination, "metadata.json")
        assert os.path.isfile(binary_path)
        assert os.path.isfile(signature_path)
        assert os.path.isfile(json_path)
        with open(binary_path, "rb") as f:
            assert f.read() == binary
        with open(signature_path, "rb") as f:
            assert f.read() == signature
        with open(json_path, "r") as f:
            assert json.load(f) == expected_json
        assert proc.poll() is None, "curator.py did not remain running as a directory watcher after processing"
    finally:
        if proc is not None and proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
        if fd >= 0:
            os.close(fd)
        shutil.rmtree(workspace, ignore_errors=True)
        try:
            os.unlink(os.path.join(INCOMING, bundle_name))
        except FileNotFoundError:
            pass
        shutil.rmtree(destination, ignore_errors=True)
TEST_EOF

ok=1
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || ok=0
python3 -m pytest /tmp/test_curator_behavior.py -x --tb=short 2>&1 || ok=0

if [ "$ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
