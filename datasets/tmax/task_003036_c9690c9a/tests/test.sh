#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import random
import shutil
import subprocess
import tempfile

import pytest

ORACLE_PATH = "/app/secure_logger_oracle"
AGENT_PATH = "/home/user/secure_logger"
SOURCE_PATH = "/home/user/logger_src"
N_ITERATIONS = 1000


def generate_random_input(length):
    choice = random.random()
    if choice < 0.2:
        chars = b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 \n\t&<>\"'"
        return bytes(random.choice(chars) for _ in range(length))
    elif choice < 0.4:
        res = bytearray()
        for _ in range(length):
            if random.random() < 0.1:
                res.append(random.choice(b"&<>\"'"))
            else:
                res.append(random.randint(0, 255))
        return bytes(res)
    return bytes(random.randint(0, 255) for _ in range(length))


def file_hash(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.digest()


def assert_elf(path):
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF executable"


def compile_exec_blocker(directory):
    source = os.path.join(directory, "block_exec.c")
    library = os.path.join(directory, "block_exec.so")
    with open(source, "w") as f:
        f.write(r'''
#define _GNU_SOURCE
#include <errno.h>
#include <stddef.h>
#include <stdlib.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <linux/filter.h>
#include <linux/seccomp.h>

static void install_filter(void) __attribute__((constructor));
static void install_filter(void) {
    struct sock_filter code[] = {
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, nr)),
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_execve, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | (EPERM & SECCOMP_RET_DATA)),
#ifdef __NR_execveat
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_execveat, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | (EPERM & SECCOMP_RET_DATA)),
#endif
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
    };
    struct sock_fprog prog = {
        .len = (unsigned short)(sizeof(code) / sizeof(code[0])),
        .filter = code,
    };
    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0 ||
        prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &prog) != 0) {
        _exit(126);
    }
}
''')
    subprocess.run(
        ["/usr/bin/gcc", "-shared", "-fPIC", "-O2", source, "-o", library],
        check=True,
        capture_output=True,
    )
    return library


def rebuild_rust_project(directory):
    target_dir = os.path.join(directory, "cargo-target")
    cargo_home = os.path.join(directory, "cargo-home")
    os.makedirs(cargo_home)

    env = {
        "PATH": "/usr/bin:/bin",
        "HOME": directory,
        "CARGO_HOME": cargo_home,
        "CARGO_TARGET_DIR": target_dir,
        "RUSTC": "/usr/bin/rustc",
        "RUSTC_WRAPPER": "",
        "RUSTC_WORKSPACE_WRAPPER": "",
        "LANG": "C.UTF-8",
    }
    proc = subprocess.run(
        [
            "/usr/bin/cargo", "build", "--release", "--offline",
            "--message-format=json-render-diagnostics",
        ],
        cwd=SOURCE_PATH,
        env=env,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert proc.returncode == 0, f"Rust project did not compile successfully:\n{proc.stderr}"

    executables = []
    for line in proc.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        executable = message.get("executable")
        target = message.get("target") or {}
        if executable and "bin" in target.get("kind", []):
            executables.append(executable)

    executables = list(dict.fromkeys(executables))
    assert len(executables) == 1, (
        "The Rust project must build exactly one binary executable; "
        f"Cargo reported {len(executables)}"
    )
    rebuilt = executables[0]
    assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK)
    assert_elf(rebuilt)
    return rebuilt


def run_checked(path, test_input, iteration, blocker=None):
    env = os.environ.copy()
    if blocker is not None:
        env["LD_PRELOAD"] = blocker
    try:
        proc = subprocess.run(
            [path],
            input=test_input,
            capture_output=True,
            timeout=2,
            check=True,
            env=env,
        )
        return proc.stdout
    except subprocess.CalledProcessError as e:
        pytest.fail(
            f"{path} failed on iteration {iteration} with input length "
            f"{len(test_input)}. Stderr: {e.stderr!r}"
        )
    except subprocess.TimeoutExpired:
        pytest.fail(
            f"{path} timed out on iteration {iteration} with input length {len(test_input)}"
        )


def test_agent_executable_exists():
    assert os.path.exists(AGENT_PATH), f"Agent binary not found at {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH), f"Agent path {AGENT_PATH} is not a file"
    assert not os.path.islink(AGENT_PATH), f"Agent path {AGENT_PATH} must not be a symlink"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary {AGENT_PATH} is not executable"
    assert_elf(AGENT_PATH)


def test_rust_project_exists():
    assert os.path.isdir(SOURCE_PATH), f"Rust project not found at {SOURCE_PATH}"
    assert not os.path.islink(SOURCE_PATH), f"Rust project {SOURCE_PATH} must not be a symlink"
    assert os.path.isfile(os.path.join(SOURCE_PATH, "Cargo.toml")), "Cargo.toml is missing"

    rust_sources = []
    for root, dirs, files in os.walk(SOURCE_PATH):
        dirs[:] = [d for d in dirs if d not in ("target", ".git")]
        for name in files:
            path = os.path.join(root, name)
            if name.endswith(".rs") and os.path.isfile(path) and not os.path.islink(path):
                rust_sources.append(path)
    assert rust_sources, "The project contains no regular Rust source (.rs) files"


def test_fuzz_equivalence_and_independent_build():
    assert os.path.exists(ORACLE_PATH), f"Oracle binary not found at {ORACLE_PATH}"
    assert os.path.isfile(ORACLE_PATH), f"Oracle path {ORACLE_PATH} is not a file"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle binary {ORACLE_PATH} is not executable"

    oracle_hash = file_hash(ORACLE_PATH)
    assert file_hash(AGENT_PATH) != oracle_hash, "Agent executable is a byte-identical copy of the oracle"

    for root, dirs, files in os.walk(SOURCE_PATH):
        dirs[:] = [d for d in dirs if d not in ("target", ".git")]
        for name in files:
            path = os.path.join(root, name)
            if os.path.isfile(path) and not os.path.islink(path):
                assert file_hash(path) != oracle_hash, f"Oracle binary was copied into the Rust project at {path}"

    random.seed(42)
    inputs = []
    expected = []
    for i in range(N_ITERATIONS):
        length = random.randint(0, 2048)
        test_input = generate_random_input(length)
        inputs.append(test_input)
        expected.append(run_checked(ORACLE_PATH, test_input, i))

    with tempfile.TemporaryDirectory(prefix="secure-logger-verify-") as tempdir:
        blocker = compile_exec_blocker(tempdir)
        rebuilt = rebuild_rust_project(tempdir)
        assert file_hash(rebuilt) != oracle_hash, "Rebuilt Rust artifact is a byte-identical oracle copy"

        hidden_oracle = os.path.join(tempdir, "reference.hidden")
        os.replace(ORACLE_PATH, hidden_oracle)
        try:
            for candidate in (AGENT_PATH, rebuilt):
                for i, (test_input, oracle_output) in enumerate(zip(inputs, expected)):
                    agent_output = run_checked(candidate, test_input, i, blocker)
                    if oracle_output != agent_output:
                        disp_input = test_input[:100] + b"..." if len(test_input) > 100 else test_input
                        disp_oracle = oracle_output[:100] + b"..." if len(oracle_output) > 100 else oracle_output
                        disp_agent = agent_output[:100] + b"..." if len(agent_output) > 100 else agent_output
                        pytest.fail(
                            f"Mismatch from {candidate} on iteration {i}.\n"
                            f"Input length: {len(test_input)}\n"
                            f"Input (truncated): {disp_input!r}\n"
                            f"Oracle output (truncated): {disp_oracle!r}\n"
                            f"Agent output (truncated): {disp_agent!r}"
                        )
        finally:
            os.replace(hidden_oracle, ORACLE_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
