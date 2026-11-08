#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess
import tempfile
import shutil
import hashlib
import pytest

ORACLE_PATH = "/tests/oracle_applier"
AGENT_SCRIPT = "/home/user/wal_applier.py"
CORRECT_PASSPHRASE = "delta charlie niner"


def get_dir_state(dir_path):
    state = {}
    for root, _, files in os.walk(dir_path):
        for file in files:
            full_path = os.path.join(root, file)
            rel_path = os.path.relpath(full_path, dir_path)
            with open(full_path, "rb") as f:
                state[rel_path] = hashlib.sha256(f.read()).hexdigest()
    return state


def generate_random_file(dir_path, filename, file_type):
    path = os.path.join(dir_path, filename)
    if file_type == 'binary':
        size = random.randint(100, 5000)
        with open(path, "wb") as f:
            f.write(os.urandom(size))
    elif file_type == 'kv':
        lines = []
        for _ in range(random.randint(5, 20)):
            k = ''.join(random.choices(string.ascii_letters, k=5))
            v = ''.join(random.choices(string.ascii_letters + string.digits, k=8))
            lines.append(f"{k}={v}")
            if random.random() < 0.2:
                lines.append("invalid_line_no_equals")
        with open(path, "w") as f:
            f.write("\n".join(lines))
    else:
        with open(path, "w") as f:
            f.write(''.join(random.choices(string.ascii_letters, k=100)))


def generate_wal(wal_path, files_in_dir):
    commands = []
    num_cmds = random.randint(1, 10)
    for _ in range(num_cmds):
        cmd_type = random.choice(['RENAME_EXT', 'CHUNK_FILE', 'CONVERT_KV_JSON'])
        if cmd_type == 'RENAME_EXT':
            old_ext = random.choice(['ini', 'conf', 'dat', 'txt', 'bin'])
            new_ext = random.choice(['new', 'bak', 'tmp', 'cfg'])
            commands.append(f"RENAME_EXT {old_ext} {new_ext}")
        elif cmd_type == 'CHUNK_FILE':
            if files_in_dir:
                target = random.choice(files_in_dir)
                chunk_size = random.randint(50, 1000)
                commands.append(f"CHUNK_FILE {target} {chunk_size}")
        elif cmd_type == 'CONVERT_KV_JSON':
            if files_in_dir:
                target = random.choice(files_in_dir)
                commands.append(f"CONVERT_KV_JSON {target}")

    with open(wal_path, "w") as f:
        f.write("\n".join(commands))


def test_historical_state_extracted():
    target_dir = "/home/user/test_state"
    assert os.path.exists(target_dir), f"Directory {target_dir} does not exist. Did you extract the archive?"
    assert os.path.isdir(target_dir), f"{target_dir} is not a directory."
    files = os.listdir(target_dir)
    assert len(files) > 0, f"Directory {target_dir} is empty. The historical state was not extracted properly."

    expected = {
        "config.ini": b"sample config\n",
        "sample.wal": b"sample wal\n",
    }
    for name, contents in expected.items():
        path = os.path.join(target_dir, name)
        assert os.path.isfile(path), f"Expected extracted file {name} is missing."
        with open(path, "rb") as f:
            assert f.read() == contents, f"Extracted file {name} has incorrect contents."


def test_wal_applier_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), "Verification oracle is unavailable."
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} missing."
    assert not os.path.islink(AGENT_SCRIPT), "Agent script must be a real file, not a symlink."

    with open(AGENT_SCRIPT, "rb") as f:
        agent_bytes = f.read()
    with open(ORACLE_PATH, "rb") as f:
        oracle_bytes = f.read()
    assert agent_bytes != oracle_bytes, "Agent script must not be a byte-identical copy of the reference implementation."

    random.seed(42)

    for i in range(50):
        with tempfile.TemporaryDirectory() as base_dir:
            oracle_dir = os.path.join(base_dir, "oracle_dir")
            agent_dir = os.path.join(base_dir, "agent_dir")
            os.makedirs(oracle_dir)

            num_files = random.randint(5, 15)
            file_names = []
            for j in range(num_files):
                ext = random.choice(['.ini', '.conf', '.dat', '.txt', '.bin'])
                name = f"file_{j}{ext}"
                file_names.append(name)
                ftype = random.choice(['binary', 'kv', 'text'])
                generate_random_file(oracle_dir, name, ftype)

            shutil.copytree(oracle_dir, agent_dir)

            wal_path = os.path.join(base_dir, "test.wal")
            generate_wal(wal_path, file_names)

            is_correct_passphrase = random.random() >= 0.2
            passphrase = CORRECT_PASSPHRASE if is_correct_passphrase else "wrong passphrase here"

            oracle_cmd = ["python3", ORACLE_PATH, passphrase, wal_path, oracle_dir]
            agent_cmd = ["python3", AGENT_SCRIPT, passphrase, wal_path, agent_dir]

            oracle_proc = subprocess.run(oracle_cmd, capture_output=True)
            agent_proc = subprocess.run(agent_cmd, capture_output=True)

            assert agent_proc.returncode == oracle_proc.returncode, \
                f"Iteration {i}: Exit code mismatch. Oracle: {oracle_proc.returncode}, Agent: {agent_proc.returncode}. Passphrase: '{passphrase}'"

            oracle_state = get_dir_state(oracle_dir)
            agent_state = get_dir_state(agent_dir)

            assert agent_state == oracle_state, \
                f"Iteration {i}: Directory state mismatch.\nOracle files: {oracle_state}\nAgent files: {agent_state}\nWAL:\n{open(wal_path).read()}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
