#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import random
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid

import pytest

UNPACKED = "/app/unpacked"
AUDIO_LINKS = "/app/audio_links"
SERVICE_ROOT = "/app/storage_service"
BASE_URL = "http://127.0.0.1:8080"


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def expected_manifest():
    expected = {}
    data_hash = hashlib.sha256(b"data\n").hexdigest()
    for i in range(1, 31):
        expected[f"file_{i}.txt"] = data_hash
    for i in range(31, 55):
        expected[f"data_{i}.dat"] = data_hash

    with tempfile.TemporaryDirectory() as td:
        audio = os.path.join(td, "audio.wav")
        sound = os.path.join(td, "sound.wav")
        subprocess.check_call(["espeak", "-w", audio, "audio"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.check_call(["espeak", "-w", sound, "sound"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        audio_hash = sha256(audio)
        sound_hash = sha256(sound)

    for i in range(1, 7):
        expected[f"audio_{i}.wav"] = audio_hash
    for i in range(7, 13):
        expected[f"sound_{i}.wav"] = sound_hash
    return expected


EXPECTED = expected_manifest()


def actual_files():
    result = []
    for root, _, files in os.walk(UNPACKED):
        for name in files:
            result.append(os.path.join(root, name))
    return result


def live_counts():
    files_count = sum(len(files) for _, _, files in os.walk(UNPACKED))
    audio_links_count = sum(
        os.path.islink(os.path.join(AUDIO_LINKS, name))
        for name in os.listdir(AUDIO_LINKS)
    )
    return files_count, audio_links_count


def request(method, path, payload=None):
    body = None
    headers = {}
    if payload is not None:
        body = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(BASE_URL + path, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            raw = response.read()
            return response.status, json.loads(raw.decode("utf-8")) if raw else None
    except urllib.error.HTTPError as e:
        raw = e.read()
        parsed = json.loads(raw.decode("utf-8")) if raw else None
        return e.code, parsed
    except (urllib.error.URLError, TimeoutError, socket.timeout) as e:
        pytest.fail(f"Failed to connect to {req.full_url}: {e}")


def listener_pids():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local, state, inode = fields[1], fields[3], fields[9]
                    if int(local.rsplit(":", 1)[1], 16) == 8080 and state == "0A":
                        inodes.add(inode)
        except FileNotFoundError:
            pass

    pids = set()
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
                    pids.add(int(entry))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return pids


def test_unpacked_directory_state():
    assert os.path.isdir(UNPACKED), f"Directory {UNPACKED} does not exist"
    files = actual_files()
    assert len(files) == len(EXPECTED), f"Expected {len(EXPECTED)} extracted files, found {len(files)}"

    found = {}
    for path in files:
        name = os.path.basename(path)
        assert name not in found, f"Duplicate extracted basename: {name}"
        found[name] = sha256(path)
        _, ext = os.path.splitext(path)
        if ext:
            assert ext == ext.lower(), f"File extension is not lowercase: {path}"
            assert ext not in [".tar", ".gz", ".zip", ".tgz"], f"Found intermediate archive file: {path}"

    assert set(found) == set(EXPECTED), "Extracted filenames do not match the supplied nested archive"
    for name, digest in EXPECTED.items():
        assert found[name] == digest, f"Extracted file content does not match the archive: {name}"


def test_audio_links_directory_state():
    assert os.path.isdir(AUDIO_LINKS), f"Directory {AUDIO_LINKS} does not exist"
    entries = os.listdir(AUDIO_LINKS)
    wav_files = [p for p in actual_files() if os.path.splitext(p)[1] == ".wav"]
    assert len(entries) == len(wav_files) == 12, f"Expected 12 audio links, found {len(entries)}"

    resolved = []
    for name in entries:
        path = os.path.join(AUDIO_LINKS, name)
        assert os.path.islink(path), f"Not a symlink: {path}"
        target = os.readlink(path)
        assert target.endswith(".wav"), f"Symlink target does not end with .wav: {target}"
        assert os.path.exists(path), f"Broken symlink: {path} -> {target}"
        resolved.append(os.path.realpath(path))

    assert len(set(resolved)) == 12, "Audio links do not have 12 distinct targets"
    assert set(resolved) == {os.path.realpath(p) for p in wav_files}, "Audio links do not cover every extracted .wav file exactly once"


def test_service_is_compiled_rust_application():
    assert os.path.isdir(SERVICE_ROOT), f"Missing Rust project directory: {SERVICE_ROOT}"
    assert os.path.isfile(os.path.join(SERVICE_ROOT, "Cargo.toml")), "Missing Cargo.toml"
    rust_sources = []
    for root, _, files in os.walk(SERVICE_ROOT):
        for name in files:
            if name.endswith(".rs"):
                rust_sources.append(os.path.join(root, name))
    assert rust_sources, "No Rust source files found"
    assert all(os.path.getsize(path) > 0 for path in rust_sources), "Empty Rust source file found"

    pids = listener_pids()
    assert pids, "No process is listening on port 8080"
    valid = False
    details = []
    for pid in pids:
        try:
            exe_link = os.readlink(f"/proc/{pid}/exe")
            normalized = exe_link.removesuffix(" (deleted)")
            with open(f"/proc/{pid}/exe", "rb") as f:
                binary = f.read(100 * 1024 * 1024)
            details.append(normalized)
            if (normalized.startswith(SERVICE_ROOT + os.sep)
                    and os.sep + "target" + os.sep in normalized
                    and binary.startswith(b"\x7fELF")
                    and any(marker in binary for marker in (b"rust_begin_unwind", b"library/core/src", b"library/std/src"))):
                valid = True
        except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
            continue
    assert valid, f"Port 8080 is not served by a compiled Rust binary from {SERVICE_ROOT}: {details}"


def test_service_stats_endpoint_uses_live_filesystem_counts():
    expected_files, expected_links = live_counts()
    status, data = request("GET", "/stats")
    assert status == 200, f"Expected status code 200, got {status}"
    assert isinstance(data, dict), "Stats response is not a JSON object"
    assert "files_count" in data, "Response missing 'files_count'"
    assert "audio_links_count" in data, "Response missing 'audio_links_count'"
    assert data["files_count"] == expected_files, f"Expected files_count {expected_files}, got {data['files_count']}"
    assert data["audio_links_count"] == expected_links, f"Expected audio_links_count {expected_links}, got {data['audio_links_count']}"

    token = uuid.uuid4().hex
    extra_file = os.path.join(UNPACKED, f"verifier_{token}.dat")
    extra_link = os.path.join(AUDIO_LINKS, f"verifier_{token}.wav")
    wav_target = next(p for p in actual_files() if p.endswith(".wav"))
    try:
        with open(extra_file, "wb") as f:
            f.write(os.urandom(37))
        os.symlink(wav_target, extra_link)

        deadline = time.time() + 5
        last = None
        while time.time() < deadline:
            status, last = request("GET", "/stats")
            if status == 200 and last.get("files_count") == expected_files + 1 and last.get("audio_links_count") == expected_links + 1:
                break
            time.sleep(0.1)
        assert status == 200
        assert last["files_count"] == expected_files + 1, "Stats endpoint does not compute the live file count"
        assert last["audio_links_count"] == expected_links + 1, "Stats endpoint does not compute the live symlink count"
    finally:
        if os.path.lexists(extra_link):
            os.unlink(extra_link)
        if os.path.exists(extra_file):
            os.unlink(extra_file)

    status, data = request("GET", "/stats")
    assert status == 200
    assert data["files_count"] == expected_files
    assert data["audio_links_count"] == expected_links


def punctuated_variant():
    words = ["storage", "vault", "alpha"]
    punctuation = ["!!!", "...", ",,,", "???", "---", "___"]
    rendered = []
    for word in words:
        mixed = "".join(ch.upper() if random.choice((True, False)) else ch.lower() for ch in word)
        rendered.append(random.choice(punctuation) + mixed + random.choice(punctuation))
    return " ".join(rendered)


def test_service_unlock_endpoint_success_and_normalization():
    variants = [
        "storage vault alpha",
        "STORAGE VAULT ALPHA",
        "!!!Storage??? Vault, Alpha...",
        punctuated_variant(),
        punctuated_variant(),
    ]
    for phrase in variants:
        status, data = request("POST", "/unlock", {"passphrase": phrase})
        assert status == 200, f"Expected 200 for case/punctuation-equivalent passphrase {phrase!r}, got {status}"
        assert isinstance(data, dict) and data.get("status") == "unlocked", f"Expected unlocked response for {phrase!r}"


def test_service_unlock_endpoint_failure():
    for phrase in ("wrong", "storage vault beta", "storage alpha", uuid.uuid4().hex):
        status, _ = request("POST", "/unlock", {"passphrase": phrase})
        assert status == 403, f"Expected 403 for incorrect passphrase {phrase!r}, got {status}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
