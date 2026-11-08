#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import hashlib
import json
import os
import random
import struct
import subprocess
import sys
import tempfile
import time

AGENT_SCRIPT = "/home/user/safe_extract.py"
ORACLE_SCRIPT = "/tests/oracle_extractor.py"


def get_salt():
    with tempfile.TemporaryDirectory() as td:
        frame_path = os.path.join(td, "frame.png")
        subprocess.run(
            ["ffmpeg", "-y", "-i", "/app/evidence.mp4", "-ss", "00:00:05.000", "-vframes", "1", frame_path],
            check=True,
            capture_output=True,
        )
        with open(frame_path, "rb") as f:
            return hashlib.sha256(f.read()).hexdigest()


def create_sbk(path, files_spec, salt, bad_magic=False):
    magic = b"SBK1" if not bad_magic else b"BAD1"
    manifest = []
    data_section = bytearray()

    for spec in files_spec:
        fpath = spec["path"]
        data = spec["data"]
        bad_checksum = spec.get("bad_checksum", False)
        offset = len(data_section)
        data_section.extend(data)
        checksum = hashlib.sha256(data + salt.encode("utf-8")).hexdigest()
        if bad_checksum:
            checksum = hashlib.sha256(b"bad" + data).hexdigest()
        manifest.append({
            "path": fpath,
            "size": len(data),
            "checksum": checksum,
            "offset": offset,
        })

    manifest_bytes = json.dumps(manifest).encode("utf-8")
    with open(path, "wb") as f:
        f.write(magic)
        f.write(struct.pack("<I", len(manifest_bytes)))
        f.write(manifest_bytes)
        f.write(data_section)


def get_dir_state(d):
    state = {}
    for root, dirs, files in os.walk(d):
        for name in files:
            if name == ".extraction_lock":
                continue
            path = os.path.join(root, name)
            rel = os.path.relpath(path, d)
            with open(path, "rb") as f:
                state[rel] = f.read()
    return state


def test_video_artifact_saved():
    expected_hash = get_salt()
    candidates = []
    for base in ("/home/user", "/tmp", "/var/tmp", "/dev/shm"):
        if not os.path.isdir(base):
            continue
        for root, dirs, files in os.walk(base):
            for name in files:
                if name.lower().endswith(".png"):
                    candidates.append(os.path.join(root, name))

    assert candidates, "No saved PNG frame was found"
    for path in candidates:
        try:
            with open(path, "rb") as f:
                if hashlib.sha256(f.read()).hexdigest() == expected_hash:
                    return
        except OSError:
            pass
    raise AssertionError("No saved PNG matches the exact frame at 00:00:05.000")


def test_script_and_reference_are_distinct():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"
    assert os.path.isfile(ORACLE_SCRIPT), f"Verifier oracle missing at {ORACLE_SCRIPT}"
    with open(AGENT_SCRIPT, "rb") as f:
        agent_bytes = f.read()
    with open(ORACLE_SCRIPT, "rb") as f:
        oracle_bytes = f.read()
    assert agent_bytes != oracle_bytes, "Agent submission is byte-identical to the reference implementation"


def test_actual_exclusive_locking_before_write():
    salt = get_salt()
    payload = os.urandom(1024 * 1024)
    with tempfile.TemporaryDirectory() as td:
        sbk_path = os.path.join(td, "lock_test.sbk")
        out_dir = os.path.join(td, "output")
        os.makedirs(out_dir)
        create_sbk(sbk_path, [{"path": "locked.bin", "data": payload}], salt)

        lock_path = os.path.join(out_dir, ".extraction_lock")
        lock_file = open(lock_path, "a+")
        fcntl.flock(lock_file, fcntl.LOCK_EX)
        proc = subprocess.Popen(
            [sys.executable, AGENT_SCRIPT, sbk_path, out_dir, salt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        try:
            deadline = time.time() + 1.0
            while time.time() < deadline and proc.poll() is None:
                time.sleep(0.02)
            assert proc.poll() is None, "Extractor did not block on the held .extraction_lock"
            assert not os.path.exists(os.path.join(out_dir, "locked.bin")), (
                "Extractor created or wrote an extracted file before acquiring the lock"
            )
        finally:
            fcntl.flock(lock_file, fcntl.LOCK_UN)
            lock_file.close()

        stdout, stderr = proc.communicate(timeout=15)
        assert proc.returncode == 0, stderr.decode(errors="replace")
        assert stdout == b"", "Extractor printed to stdout for a valid archive"
        assert os.path.isfile(lock_path), ".extraction_lock was not created"
        with open(os.path.join(out_dir, "locked.bin"), "rb") as f:
            assert f.read() == payload


def test_fuzz_equivalence():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"
    assert os.path.exists(ORACLE_SCRIPT), f"Oracle script missing at {ORACLE_SCRIPT}"

    salt = get_salt()
    random.seed(42)

    with tempfile.TemporaryDirectory() as td:
        for i in range(50):
            sbk_path = os.path.join(td, f"test_{i}.sbk")
            out_agent = os.path.join(td, f"out_agent_{i}")
            out_oracle = os.path.join(td, f"out_oracle_{i}")
            os.makedirs(out_agent, exist_ok=True)
            os.makedirs(out_oracle, exist_ok=True)

            files_spec = []
            for j in range(random.randint(1, 20)):
                choice = random.random()
                if choice < 0.1:
                    path = f"../escaped_{j}.txt"
                elif choice < 0.2:
                    path = f"/tmp/absolute_{j}.txt"
                elif choice < 0.3:
                    path = f"valid_dir/file_{j}.txt"
                else:
                    path = f"file_{j}.txt"
                files_spec.append({
                    "path": path,
                    "data": os.urandom(random.randint(0, 10240)),
                    "bad_checksum": random.random() < 0.1,
                })

            create_sbk(sbk_path, files_spec, salt, random.random() < 0.05)
            agent_res = subprocess.run(
                [sys.executable, AGENT_SCRIPT, sbk_path, out_agent, salt],
                capture_output=True,
            )
            oracle_res = subprocess.run(
                [sys.executable, ORACLE_SCRIPT, sbk_path, out_oracle, salt],
                capture_output=True,
            )

            assert agent_res.returncode == oracle_res.returncode, (
                f"Exit code mismatch on input {i}:\n"
                f"Agent exit code: {agent_res.returncode}\n"
                f"Oracle exit code: {oracle_res.returncode}\n"
                f"Agent stderr: {agent_res.stderr.decode(errors='replace')}\n"
            )

            agent_state = get_dir_state(out_agent)
            oracle_state = get_dir_state(out_oracle)
            assert agent_state.keys() == oracle_state.keys(), (
                f"Extracted files mismatch on input {i}.\n"
                f"Agent extracted: {sorted(agent_state.keys())}\n"
                f"Oracle extracted: {sorted(oracle_state.keys())}"
            )
            for key in agent_state:
                assert agent_state[key] == oracle_state[key], (
                    f"File content mismatch for {key} on input {i}."
                )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
