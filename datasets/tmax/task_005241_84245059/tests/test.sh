#!/bin/bash
set -e
mkdir -p /logs/verifier

ORACLE_BINARY=/app/legacy_cfg_manager
AGENT_SCRIPT=/home/user/pack_ccf.py

if [ ! -f "$ORACLE_BINARY" ] || [ ! -f "$AGENT_SCRIPT" ]; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

# The agent was allowed to inspect the legacy utility while working, but its
# submitted packer must run without access to it during verification.
ORIGINAL_MODE=$(stat -c '%a' "$ORACLE_BINARY")
chmod 000 "$ORACLE_BINARY"
chmod a+r "$AGENT_SCRIPT"
trap 'chmod "$ORIGINAL_MODE" "$ORACLE_BINARY" 2>/dev/null || true' EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import re
import stat
import string
import struct
import subprocess
import tempfile

import pytest

AGENT_SCRIPT = "/home/user/pack_ccf.py"
AGENT_USER = pwd.getpwnam("user")


def generate_random_string(length):
    return ''.join(random.choices(string.ascii_letters + string.digits + "_", k=length))


def generate_random_file_content(size):
    if random.choice([True, False]):
        return ''.join(random.choices(string.printable, k=size)).encode('utf-8')
    return os.urandom(size)


def create_random_directory_tree(base_dir):
    num_files = random.randint(1, 15)
    for _ in range(num_files):
        depth = random.randint(0, 4)
        current_dir = base_dir
        for _ in range(depth):
            dir_name = generate_random_string(random.randint(3, 12))
            current_dir = os.path.join(current_dir, dir_name)
            os.makedirs(current_dir, exist_ok=True)

        file_name = generate_random_string(random.randint(3, 12))
        file_path = os.path.join(current_dir, file_name)
        file_size = random.randint(0, 100 * 1024)
        with open(file_path, 'wb') as f:
            f.write(generate_random_file_content(file_size))


def expected_archive(input_dir):
    files_to_pack = []
    for root, _, files in os.walk(input_dir):
        for filename in files:
            full_path = os.path.join(root, filename)
            rel_path = os.path.relpath(full_path, input_dir).replace('\\', '/')
            files_to_pack.append((rel_path, full_path))
    files_to_pack.sort(key=lambda item: item[0])

    result = bytearray(b'CCF\x01')
    result.extend(struct.pack('<I', len(files_to_pack)))
    for rel_path, full_path in files_to_pack:
        path_bytes = rel_path.encode('utf-8')
        with open(full_path, 'rb') as f:
            data = f.read()
        result.extend(struct.pack('<H', len(path_bytes)))
        result.extend(path_bytes)
        result.extend(struct.pack('<I', len(data)))
        result.extend(bytes(byte ^ 0x5A for byte in data))
    return bytes(result)


def demote_to_agent_user():
    os.setgroups([])
    os.setgid(AGENT_USER.pw_gid)
    os.setuid(AGENT_USER.pw_uid)


@pytest.fixture(scope="module", autouse=True)
def validate_submission():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"
    mode = os.lstat(AGENT_SCRIPT).st_mode
    assert stat.S_ISREG(mode), f"Agent script is not a regular file: {AGENT_SCRIPT}"
    random.seed(42)


@pytest.mark.parametrize("iteration", range(50))
def test_fuzz_equivalence(iteration):
    with tempfile.TemporaryDirectory() as temp_dir:
        os.chmod(temp_dir, 0o777)
        input_dir = os.path.join(temp_dir, "input")
        os.makedirs(input_dir)
        create_random_directory_tree(input_dir)

        agent_output = os.path.join(temp_dir, "agent.ccf")
        trace_output = os.path.join(temp_dir, "exec.trace")
        expected_data = expected_archive(input_dir)

        agent_cmd = [
            "strace", "-f", "-qq", "-e", "trace=execve", "-o", trace_output,
            "python3", AGENT_SCRIPT, input_dir, agent_output,
        ]
        agent_proc = subprocess.run(
            agent_cmd,
            capture_output=True,
            preexec_fn=demote_to_agent_user,
        )
        assert agent_proc.returncode == 0, (
            f"Agent failed: {agent_proc.stderr.decode(errors='replace')}"
        )
        assert os.path.exists(agent_output), "Agent did not produce output file"
        assert os.path.isfile(agent_output), "Agent output is not a regular file"

        # A clean Python implementation needs only the initial Python exec.
        # Reject delegation to the legacy utility, including copies made under
        # another path during the reverse-engineering phase.
        with open(trace_output, 'r', errors='replace') as f:
            trace = f.read()
        successful_execs = re.findall(r'execve\("([^"]+)".*\)\s+=\s+0', trace)
        assert len(successful_execs) == 1, (
            f"Submitted packer delegated to another executable: {successful_execs}"
        )
        assert os.path.basename(successful_execs[0]).startswith("python3"), (
            f"Unexpected program execution: {successful_execs[0]}"
        )

        with open(agent_output, "rb") as f:
            agent_data = f.read()
        assert agent_data == expected_data, (
            f"Mismatch on iteration {iteration}. Output differs from expected archive."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
