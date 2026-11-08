#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import stat
import string
import struct
import subprocess
import tempfile

ORACLE_BIN = "/app/legacy_web_scanner"
AGENT_BIN = "/home/user/new_web_scanner"
NUM_TESTS = 50


def generate_random_string(min_len=4, max_len=8):
    length = random.randint(min_len, max_len)
    return ''.join(random.choices(string.ascii_lowercase, k=length))


def setup_random_directory(base_dir):
    num_users = random.randint(0, 20)
    user_names = set()
    while len(user_names) < num_users:
        user_names.add(generate_random_string())

    for user in user_names:
        user_dir = os.path.join(base_dir, user)
        os.makedirs(user_dir)

        if random.random() < 0.5:
            os.makedirs(os.path.join(user_dir, "public_html"))

        if random.random() < 0.5:
            tls_dir = os.path.join(user_dir, "tls")
            os.makedirs(tls_dir)
            target = f"/etc/certs/{generate_random_string()}.pem"
            os.symlink(target, os.path.join(tls_dir, "cert.pem"))


def elf_load_segments(path):
    data = open(path, "rb").read()
    assert data[:4] == b"\x7fELF", f"{path} is not an ELF executable"
    assert data[4] == 2 and data[5] == 1, f"{path} must be a 64-bit little-endian ELF executable"
    phoff = struct.unpack_from("<Q", data, 32)[0]
    phentsize = struct.unpack_from("<H", data, 54)[0]
    phnum = struct.unpack_from("<H", data, 56)[0]
    segments = []
    for i in range(phnum):
        off = phoff + i * phentsize
        p_type, _flags, p_offset, _vaddr, _paddr, p_filesz, _memsz, _align = struct.unpack_from(
            "<IIQQQQQQ", data, off
        )
        if p_type == 1:
            segments.append(data[p_offset:p_offset + p_filesz])
    assert segments, f"{path} has no loadable ELF segments"
    return data, segments


def expected_output(base_dir):
    lines = []
    users = []
    for name in os.listdir(base_dir):
        if name.startswith('.'):
            continue
        if os.path.isdir(os.path.join(base_dir, name)):
            users.append(name)

    for user in sorted(users, key=os.fsencode):
        public_html = os.path.join(base_dir, user, "public_html")
        cert = os.path.join(base_dir, user, "tls", "cert.pem")
        if os.path.isdir(public_html) and os.path.islink(cert):
            lines.append(f"User: {user} | Web: OK | TLS: {os.readlink(cert)}\n")
    return ''.join(lines)


def run_agent_without_oracle(base_dir):
    oracle_data = open(ORACLE_BIN, "rb").read()
    oracle_mode = stat.S_IMODE(os.stat(ORACLE_BIN).st_mode)
    trace_fd, trace_path = tempfile.mkstemp(prefix="scanner-trace-", dir="/tmp")
    os.close(trace_fd)
    os.chmod(trace_path, 0o666)
    user = pwd.getpwnam("user")

    def drop_privileges():
        os.setgroups([])
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    os.unlink(ORACLE_BIN)
    try:
        proc = subprocess.run(
            ["strace", "-f", "-e", "trace=execve", "-o", trace_path, AGENT_BIN, base_dir],
            capture_output=True,
            text=True,
            timeout=5,
            preexec_fn=drop_privileges,
        )
        with open(trace_path, "r", errors="replace") as f:
            exec_lines = [line for line in f if "execve(" in line]
        assert len(exec_lines) == 1, (
            "The submitted executable delegated work to another executable.\n" + ''.join(exec_lines)
        )
        return proc
    finally:
        try:
            os.unlink(trace_path)
        except FileNotFoundError:
            pass
        with open(ORACLE_BIN, "wb") as f:
            f.write(oracle_data)
        os.chmod(ORACLE_BIN, oracle_mode)


def test_agent_binary_exists_and_is_rust():
    assert os.path.exists(AGENT_BIN), f"Agent binary not found at {AGENT_BIN}"
    assert os.path.isfile(AGENT_BIN), f"{AGENT_BIN} is not a file"
    assert os.access(AGENT_BIN, os.X_OK), f"{AGENT_BIN} is not executable"

    agent_data, agent_segments = elf_load_segments(AGENT_BIN)
    oracle_data, oracle_segments = elf_load_segments(ORACLE_BIN)
    assert agent_data != oracle_data, "Submission is byte-identical to the legacy executable"
    assert agent_segments != oracle_segments, "Submission reuses the legacy executable's loadable image"

    loaded = b''.join(agent_segments)
    rust_markers = (b"/rustc/", b"library/std/src", b"library/core/src", b"rust_eh_personality")
    assert any(marker in loaded for marker in rust_markers), (
        "Submitted ELF does not contain evidence of a Rust implementation"
    )


def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_BIN), f"Oracle binary not found at {ORACLE_BIN}"
    assert os.path.exists(AGENT_BIN), f"Agent binary not found at {AGENT_BIN}"

    random.seed(42)
    for i in range(NUM_TESTS):
        with tempfile.TemporaryDirectory() as temp_dir:
            os.chmod(temp_dir, 0o755)
            setup_random_directory(temp_dir)
            expected = expected_output(temp_dir)

            oracle_proc = subprocess.run(
                [ORACLE_BIN, temp_dir], capture_output=True, text=True, timeout=5
            )
            oracle_out = oracle_proc.stdout
            assert oracle_proc.returncode == 0
            assert oracle_out == expected, f"Oracle disagreed with derived result on test {i+1}"

            agent_proc = run_agent_without_oracle(temp_dir)
            agent_out = agent_proc.stdout

            assert agent_proc.returncode == oracle_proc.returncode, (
                f"Return code mismatch on test {i+1}/{NUM_TESTS}.\n"
                f"Input dir: {temp_dir}\n"
                f"Oracle returncode: {oracle_proc.returncode}\n"
                f"Agent returncode: {agent_proc.returncode}"
            )
            assert agent_out == oracle_out, (
                f"Output mismatch on test {i+1}/{NUM_TESTS}.\n"
                f"Input dir: {temp_dir}\n"
                f"Oracle output:\n{oracle_out}\n"
                f"Agent output:\n{agent_out}"
            )
            assert agent_out == expected
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
