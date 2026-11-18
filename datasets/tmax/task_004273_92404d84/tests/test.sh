#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import shutil
import stat
import subprocess
import tempfile

ORACLE = "/app/cleaner_oracle"
SOURCE = "/home/user/cleaner.c"
AGENT = "/home/user/cleaner"


def generate_fuzz_input(num_lines=1000):
    random.seed(42)
    lines = []
    lines.append(str(random.randint(-50000, 50000)))
    val = random.randint(-50000, 50000)
    lines.append(" ".join([str(val)] * 50))
    lines.append(f"{random.randint(-50000, 50000)} {random.randint(-50000, 50000)}")
    lines.append("")
    lines.append(" ".join([str(random.choice([-50000, 50000])) for _ in range(10)]))

    for _ in range(num_lines - len(lines)):
        length = random.randint(1, 100)
        nums = [str(random.randint(-50000, 50000)) for _ in range(length)]
        lines.append(" ".join(nums))
    return "\n".join(lines) + "\n"


def expected_output(input_data):
    output = []
    for line in input_data.splitlines():
        nums = [int(token) for token in line.split()]
        if not nums:
            output.append("")
            continue
        low, high = min(nums), max(nums)
        if high == low:
            output.append(" ".join("0" for _ in nums))
        else:
            output.append(" ".join(str((value - low) * 255 // (high - low)) for value in nums))
    return "\n".join(output) + "\n"


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(65536), b""):
            digest.update(block)
    return digest.digest()


def assert_regular(path, description):
    try:
        mode = os.lstat(path).st_mode
    except FileNotFoundError:
        raise AssertionError(f"{description} not found at {path}")
    assert stat.S_ISREG(mode), f"{description} must be a regular file, not a symlink or wrapper file"


def copy_runtime_libraries(binary, root):
    proc = subprocess.run(["ldd", binary], text=True, capture_output=True)
    combined = proc.stdout + proc.stderr
    if proc.returncode != 0:
        assert "not a dynamic executable" in combined or "statically linked" in combined, combined
        return

    libraries = set()
    for line in proc.stdout.splitlines():
        tokens = line.replace("=>", " ").split()
        for token in tokens:
            if token.startswith("/") and os.path.exists(token):
                libraries.add(token)

    for library in libraries:
        real = os.path.realpath(library)
        assert real.startswith(("/lib/", "/lib64/", "/usr/lib/", "/usr/lib64/")), \
            f"Unexpected non-system runtime dependency: {library}"
        destination = os.path.join(root, library.lstrip("/"))
        os.makedirs(os.path.dirname(destination), exist_ok=True)
        shutil.copy2(real, destination)


def run_in_empty_chroot(binary, input_data, include_runtime_libraries):
    with tempfile.TemporaryDirectory(prefix="cleaner-jail-") as root:
        jailed_binary = os.path.join(root, "cleaner")
        shutil.copy2(binary, jailed_binary)
        os.chmod(jailed_binary, 0o755)
        if include_runtime_libraries:
            copy_runtime_libraries(binary, root)

        def enter_jail():
            os.chroot(root)
            os.chdir("/")

        return subprocess.run(
            ["/cleaner"],
            input=input_data,
            text=True,
            capture_output=True,
            timeout=20,
            preexec_fn=enter_jail,
        )


def test_fuzz_equivalence_and_independent_c_source():
    assert_regular(SOURCE, "C source")
    assert_regular(AGENT, "Agent binary")
    assert os.access(AGENT, os.X_OK), f"Agent binary at {AGENT} is not executable"

    with open(AGENT, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "Agent binary must be a compiled ELF executable"

    assert not os.path.samefile(AGENT, ORACLE), "Agent binary must not be the oracle itself"
    assert sha256(AGENT) != sha256(ORACLE), "Agent binary must not be a copy of the oracle"

    input_data = generate_fuzz_input(1000)
    expected = expected_output(input_data)

    oracle_proc = subprocess.run(
        [ORACLE], input=input_data, text=True, capture_output=True, check=True, timeout=20
    )

    agent_proc = subprocess.run(
        [AGENT], input=input_data, text=True, capture_output=True, timeout=20
    )
    assert agent_proc.returncode == 0, \
        f"Agent program failed with return code {agent_proc.returncode}\nStderr: {agent_proc.stderr}"

    oracle_lines = oracle_proc.stdout.splitlines()
    agent_lines = agent_proc.stdout.splitlines()
    assert len(oracle_lines) == len(agent_lines), \
        f"Output line count mismatch. Oracle: {len(oracle_lines)}, Agent: {len(agent_lines)}"

    input_lines = input_data.splitlines()
    for i, (oracle_line, agent_line) in enumerate(zip(oracle_lines, agent_lines)):
        assert oracle_line == agent_line, \
            f"Mismatch on line {i+1}.\nInput: {input_lines[i]}\nOracle: {oracle_line}\nAgent:  {agent_line}"

    assert oracle_proc.stdout == expected, "Oracle output disagreed with independently derived answers"
    assert agent_proc.stdout == expected, "Agent output disagreed with independently derived answers"

    jailed_agent = run_in_empty_chroot(AGENT, input_data, include_runtime_libraries=True)
    assert jailed_agent.returncode == 0, \
        f"Submitted executable is not independent of external files (exit {jailed_agent.returncode}): {jailed_agent.stderr}"
    assert jailed_agent.stdout == expected, \
        "Submitted executable failed when isolated from the provided oracle"

    with tempfile.TemporaryDirectory(prefix="cleaner-build-") as build_dir:
        rebuilt = os.path.join(build_dir, "cleaner")
        compile_proc = subprocess.run(
            ["gcc", "-O3", "-static", SOURCE, "-o", rebuilt],
            text=True,
            capture_output=True,
            timeout=30,
        )
        assert compile_proc.returncode == 0, \
            f"cleaner.c did not compile as C source:\n{compile_proc.stdout}{compile_proc.stderr}"

        rebuilt_proc = run_in_empty_chroot(rebuilt, input_data, include_runtime_libraries=False)
        assert rebuilt_proc.returncode == 0, \
            f"Program rebuilt from cleaner.c failed in isolation (exit {rebuilt_proc.returncode}): {rebuilt_proc.stderr}"
        assert rebuilt_proc.stdout == expected, \
            "Program rebuilt from cleaner.c does not implement the required transformation independently"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
