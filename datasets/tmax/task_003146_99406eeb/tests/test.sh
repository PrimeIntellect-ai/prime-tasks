#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import re
import shutil
import stat
import subprocess
import tempfile
import pytest

ORACLE_PATH = "/app/semver_oracle"
AGENT_PATH = "/home/user/vparser_cpp/vparser"
PROJECT_PATH = "/home/user/vparser_cpp"
NUM_TESTS = 1000


def generate_fuzz_inputs(seed=42):
    random.seed(seed)
    lines = []
    tags = ["dev", "alpha", "beta", "rc", "final", ""]
    malformed_tags = ["omega", "gamma", "unknown"]

    for _ in range(NUM_TESTS):
        num_versions = random.randint(2, 15)
        versions = []
        for _ in range(num_versions):
            is_malformed = random.random() < 0.1
            if is_malformed:
                malform_type = random.choice(["missing_minor", "invalid_tag", "not_a_version"])
                if malform_type == "missing_minor":
                    versions.append(f"{random.randint(0, 50)}")
                elif malform_type == "invalid_tag":
                    versions.append(f"{random.randint(0, 50)}.{random.randint(0, 50)}.{random.randint(0, 50)}-{random.choice(malformed_tags)}")
                else:
                    versions.append("just-some-random-string")
            else:
                major = random.randint(0, 50)
                minor = random.randint(0, 50)
                patch = random.randint(0, 50)
                tag = random.choice(tags)
                if tag:
                    versions.append(f"{major}.{minor}.{patch}-{tag}")
                else:
                    versions.append(f"{major}.{minor}.{patch}")
        lines.append(" ".join(versions))
    return "\n".join(lines) + "\n"


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.digest()


def assert_elf(path):
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "vparser must be a compiled ELF executable"


def copy_runtime_dependencies(binary, jail):
    result = subprocess.run(["ldd", binary], text=True, capture_output=True, check=True)
    dependencies = set()
    for line in result.stdout.splitlines():
        match = re.search(r"=>\s+(/\S+)", line)
        if match:
            dependencies.add(match.group(1))
            continue
        stripped = line.strip()
        if stripped.startswith("/"):
            dependencies.add(stripped.split()[0])

    for source in dependencies:
        destination = os.path.join(jail, source.lstrip("/"))
        os.makedirs(os.path.dirname(destination), exist_ok=True)
        shutil.copy2(source, destination)


def run_agent_in_isolation(input_data):
    # Only the submitted executable and its ELF runtime libraries are placed in
    # the jail. In particular, /app/semver_oracle and the rest of the agent's
    # filesystem are unavailable.
    with tempfile.TemporaryDirectory(prefix="vparser-jail-") as jail:
        jailed_binary = os.path.join(jail, "vparser")
        shutil.copy2(AGENT_PATH, jailed_binary)
        os.chmod(jailed_binary, 0o555)
        copy_runtime_dependencies(AGENT_PATH, jail)

        for root, dirs, files in os.walk(jail, topdown=False):
            for name in files:
                os.chmod(os.path.join(root, name), 0o555)
            for name in dirs:
                os.chmod(os.path.join(root, name), 0o555)
        os.chmod(jail, 0o555)

        return subprocess.run(
            ["chroot", "--userspec=65534:65534", jail, "/vparser"],
            input=input_data,
            text=True,
            capture_output=True,
        )


def compare_process_output(oracle_proc, agent_proc):
    if oracle_proc.stdout != agent_proc.stdout:
        oracle_lines = oracle_proc.stdout.splitlines()
        agent_lines = agent_proc.stdout.splitlines()

        for i, (o_line, a_line) in enumerate(zip(oracle_lines, agent_lines)):
            if o_line != a_line:
                pytest.fail(f"Stdout mismatch at output line {i+1}.\nOracle: {o_line!r}\nAgent:  {a_line!r}")

        if len(oracle_lines) != len(agent_lines):
            pytest.fail(f"Stdout line count mismatch. Oracle lines: {len(oracle_lines)}, Agent lines: {len(agent_lines)}")

        pytest.fail("Stdout mismatch (exact content differs).")

    if oracle_proc.stderr != agent_proc.stderr:
        pytest.fail(f"Stderr mismatch.\nOracle stderr: {oracle_proc.stderr!r}\nAgent stderr: {agent_proc.stderr!r}")


def test_agent_binary_exists():
    assert os.path.exists(AGENT_PATH), f"Agent binary not found at {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH), f"Expected file at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary at {AGENT_PATH} is not executable"

    mode = os.lstat(AGENT_PATH).st_mode
    assert stat.S_ISREG(mode), "vparser must be a regular file, not a symlink or wrapper path"
    assert_elf(AGENT_PATH)

    cpp_sources = []
    for root, dirs, files in os.walk(PROJECT_PATH):
        dirs[:] = [d for d in dirs if d not in {".git", "build", "cmake-build-debug", "cmake-build-release"}]
        for name in files:
            if name.endswith((".cpp", ".cc", ".cxx")):
                path = os.path.join(root, name)
                if stat.S_ISREG(os.lstat(path).st_mode):
                    cpp_sources.append(path)
    assert cpp_sources, "No regular C++ source file was found in the required project"

    assert not os.path.samefile(AGENT_PATH, ORACLE_PATH), "vparser must not be the oracle"
    assert sha256(AGENT_PATH) != sha256(ORACLE_PATH), "vparser must not be a byte-identical copy of the oracle"


def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle binary not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle binary at {ORACLE_PATH} is not executable"

    input_data = generate_fuzz_inputs(seed=1337)

    oracle_proc = subprocess.run(
        [ORACLE_PATH],
        input=input_data,
        text=True,
        capture_output=True
    )

    agent_proc = subprocess.run(
        [AGENT_PATH],
        input=input_data,
        text=True,
        capture_output=True
    )

    compare_process_output(oracle_proc, agent_proc)


def test_fuzz_equivalence_without_oracle_access():
    input_data = generate_fuzz_inputs(seed=7331)
    oracle_proc = subprocess.run(
        [ORACLE_PATH],
        input=input_data,
        text=True,
        capture_output=True
    )
    agent_proc = run_agent_in_isolation(input_data)
    compare_process_output(oracle_proc, agent_proc)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
