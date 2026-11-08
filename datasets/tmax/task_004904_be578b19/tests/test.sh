#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import re
import stat
import shutil
import subprocess
import tempfile
import random
import resource
import pytest

ORACLE_PATH = "/app/obfuscator_oracle"
AGENT_PATH = "/home/user/replica"
AGENT_SRC = "/home/user/replica.cpp"


def test_agent_files_exist():
    assert os.path.exists(AGENT_SRC), f"Agent source not found at {AGENT_SRC}"
    assert os.path.exists(AGENT_PATH), f"Agent binary not found at {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH), f"{AGENT_PATH} is not a file"
    assert os.access(AGENT_PATH, os.X_OK), f"{AGENT_PATH} is not executable"
    assert stat.S_ISREG(os.lstat(AGENT_SRC).st_mode), f"{AGENT_SRC} must be a regular file"
    assert stat.S_ISREG(os.lstat(AGENT_PATH).st_mode), f"{AGENT_PATH} must be a regular file, not a symlink"


@pytest.fixture(scope="session")
def isolated_replica():
    workdir = tempfile.mkdtemp(prefix="replica_verify_")
    built = os.path.join(workdir, "built_replica")

    compile_proc = subprocess.run(
        ["g++", "-O2", "-o", built, AGENT_SRC],
        capture_output=True,
        timeout=60,
    )
    assert compile_proc.returncode == 0, (
        "replica.cpp did not compile successfully.\n"
        f"stdout: {compile_proc.stdout.decode(errors='replace')}\n"
        f"stderr: {compile_proc.stderr.decode(errors='replace')}"
    )
    assert stat.S_ISREG(os.lstat(built).st_mode), "Compiled replica is not a regular file"
    with open(built, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Compiled replica is not an ELF executable"

    # Run the verifier-built artifact in an empty, read-only chroot. Only its
    # dynamic linker dependencies are supplied; the oracle and any agent-created
    # helper executables are deliberately unavailable at runtime.
    root = os.path.join(workdir, "root")
    os.mkdir(root, 0o755)
    shutil.copy2(built, os.path.join(root, "replica"))
    os.chmod(os.path.join(root, "replica"), 0o755)

    ldd_proc = subprocess.run(["ldd", built], capture_output=True, text=True, timeout=10)
    ldd_text = ldd_proc.stdout + ldd_proc.stderr
    if "not a dynamic executable" not in ldd_text and "statically linked" not in ldd_text:
        assert ldd_proc.returncode == 0, f"Unable to inspect replica dependencies: {ldd_text}"
        dependencies = set()
        for line in ldd_text.splitlines():
            match = re.search(r"=>\s+(/[^\s]+)\s+\(", line)
            if match:
                dependencies.add(match.group(1))
                continue
            match = re.match(r"\s*(/[^\s]+)\s+\(", line)
            if match:
                dependencies.add(match.group(1))

        for dependency in dependencies:
            assert os.path.isfile(dependency), f"Missing runtime dependency: {dependency}"
            destination = os.path.join(root, dependency.lstrip("/"))
            os.makedirs(os.path.dirname(destination), mode=0o755, exist_ok=True)
            shutil.copy2(dependency, destination)

    for directory, subdirs, files in os.walk(root):
        os.chmod(directory, 0o555)
        for name in files:
            path = os.path.join(directory, name)
            os.chmod(path, os.stat(path).st_mode | 0o555)

    def enter_sandbox():
        os.chroot(root)
        os.chdir("/")
        os.setgroups([])
        os.setgid(65534)
        os.setuid(65534)
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
        resource.setrlimit(resource.RLIMIT_FSIZE, (16 * 1024 * 1024, 16 * 1024 * 1024))
        resource.setrlimit(resource.RLIMIT_AS, (512 * 1024 * 1024, 512 * 1024 * 1024))

    return enter_sandbox


def test_fuzz_equivalence(isolated_replica):
    assert os.path.exists(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"

    random.seed(42)
    # 1000 iterations is sufficient to find edge cases without timing out the test runner
    num_iterations = 1000

    for i in range(num_iterations):
        length = random.randint(0, 4096)

        # Generate random bytes
        if length > 0:
            input_data = bytearray(random.getrandbits(8) for _ in range(length))
        else:
            input_data = bytearray()

        # Inject known patterns to trigger specific logic
        if i % 5 == 0:
            pattern = b"TOKEN=secret123"
            insert_pos = random.randint(0, max(0, len(input_data) - len(pattern)))
            input_data[insert_pos:insert_pos] = pattern
        if i % 7 == 0:
            pattern = b"<html><script>alert('XSS')</script></html>"
            insert_pos = random.randint(0, max(0, len(input_data) - len(pattern)))
            input_data[insert_pos:insert_pos] = pattern

        input_bytes = bytes(input_data)

        oracle_proc = subprocess.run([ORACLE_PATH], input=input_bytes, capture_output=True)
        agent_proc = subprocess.run([AGENT_PATH], input=input_bytes, capture_output=True)
        isolated_proc = subprocess.run(
            ["/replica"],
            input=input_bytes,
            capture_output=True,
            preexec_fn=isolated_replica,
            timeout=10,
        )

        assert agent_proc.returncode == oracle_proc.returncode, (
            f"Return code mismatch on iteration {i} (input length {len(input_bytes)}).\n"
            f"Oracle: {oracle_proc.returncode}, Agent: {agent_proc.returncode}"
        )
        assert agent_proc.stdout == oracle_proc.stdout, (
            f"Stdout mismatch on iteration {i} (input length {len(input_bytes)}).\n"
            f"Input snippet: {input_bytes[:100]!r}\n"
            f"Oracle stdout snippet: {oracle_proc.stdout[:200]!r}\n"
            f"Agent stdout snippet: {agent_proc.stdout[:200]!r}"
        )
        assert isolated_proc.returncode == oracle_proc.returncode, (
            f"Verifier-compiled replica return code mismatch on iteration {i} "
            f"(input length {len(input_bytes)}).\n"
            f"Oracle: {oracle_proc.returncode}, Replica: {isolated_proc.returncode}"
        )
        assert isolated_proc.stdout == oracle_proc.stdout, (
            f"Verifier-compiled replica stdout mismatch on iteration {i} "
            f"(input length {len(input_bytes)}).\n"
            f"Input snippet: {input_bytes[:100]!r}\n"
            f"Oracle stdout snippet: {oracle_proc.stdout[:200]!r}\n"
            f"Replica stdout snippet: {isolated_proc.stdout[:200]!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
