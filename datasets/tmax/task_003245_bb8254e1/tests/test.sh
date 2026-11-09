#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import os
import random
import re
import shutil
import subprocess
import tempfile
import pytest

ORACLE_PATH = "/app/oracle_scorer"
AGENT_PATH = "/home/user/solution"
SOURCE_PATH = "/home/user/solution.go"
NUM_TESTS = 1000


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=10, **kwargs)


def test_solution_exists_and_executable():
    assert os.path.exists(AGENT_PATH), f"Agent solution not found at {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH), f"{AGENT_PATH} is not a file"
    assert not os.path.islink(AGENT_PATH), f"{AGENT_PATH} must be a compiled file, not a symlink"
    assert os.access(AGENT_PATH, os.X_OK), f"{AGENT_PATH} is not executable"

    assert os.path.exists(SOURCE_PATH), f"Go source not found at {SOURCE_PATH}"
    assert os.path.isfile(SOURCE_PATH), f"{SOURCE_PATH} is not a file"
    assert not os.path.islink(SOURCE_PATH), f"{SOURCE_PATH} must not be a symlink"

    assert os.path.exists(ORACLE_PATH), f"Oracle not found at {ORACLE_PATH}"
    assert not filecmp.cmp(AGENT_PATH, ORACLE_PATH, shallow=False), \
        "Submitted executable must not be a copy of the oracle"

    metadata = run(["go", "version", "-m", AGENT_PATH])
    assert metadata.returncode == 0, \
        f"{AGENT_PATH} is not a recognized compiled Go executable: {metadata.stderr}"


def copy_dynamic_dependencies(binary, root):
    ldd = run(["ldd", binary])
    if ldd.returncode != 0:
        return

    paths = set()
    for line in ldd.stdout.splitlines():
        match = re.search(r"=>\s+(/\S+)", line)
        if match:
            paths.add(match.group(1))
            continue
        match = re.match(r"\s*(/\S+)", line)
        if match:
            paths.add(match.group(1))

    for path in paths:
        destination = os.path.join(root, path.lstrip("/"))
        os.makedirs(os.path.dirname(destination), exist_ok=True)
        shutil.copy2(path, destination, follow_symlinks=True)


def test_fuzz_equivalence():
    random.seed(42)
    cases = [[str(random.randint(-200, 200)) for _ in range(4)]
             for _ in range(NUM_TESTS)]

    expected = []
    for args in cases:
        oracle_res = run([ORACLE_PATH] + args)
        assert oracle_res.returncode == 0, \
            f"Oracle failed on inputs {args}: {oracle_res.stderr}"
        expected.append(oracle_res.stdout.strip())

    # Preserve the original check against the submitted executable.
    for args, oracle_output in zip(cases, expected):
        agent_res = run([AGENT_PATH] + args)
        assert agent_res.returncode == 0, \
            f"Agent solution failed on inputs {args}: {agent_res.stderr}"
        assert agent_res.stdout.strip() == oracle_output, (
            f"Mismatch on inputs {args}.\n"
            f"Oracle output: '{oracle_output}'\n"
            f"Agent output:  '{agent_res.stdout.strip()}'"
        )

    with tempfile.TemporaryDirectory(prefix="verify-go-") as work:
        rebuilt = os.path.join(work, "rebuilt_solution")
        build = run(["go", "build", "-o", rebuilt, SOURCE_PATH])
        assert build.returncode == 0, \
            f"Failed to compile {SOURCE_PATH} as Go: {build.stderr}"

        metadata = run(["go", "version", "-m", rebuilt])
        assert metadata.returncode == 0, \
            f"Rebuilt source is not a compiled Go executable: {metadata.stderr}"
        assert not filecmp.cmp(rebuilt, ORACLE_PATH, shallow=False), \
            "Go source rebuilt to a copy of the oracle"

        # Run the source-built program in a filesystem containing only the
        # program and any dynamic loader dependencies. /app/oracle_scorer and
        # copies left elsewhere by the agent are therefore unavailable.
        root = os.path.join(work, "root")
        os.makedirs(root)
        isolated_solution = os.path.join(root, "solution")
        shutil.copy2(rebuilt, isolated_solution)
        os.chmod(isolated_solution, 0o755)
        copy_dynamic_dependencies(rebuilt, root)

        for args, oracle_output in zip(cases, expected):
            agent_res = run(["chroot", root, "/solution"] + args)
            assert agent_res.returncode == 0, \
                f"Isolated Go solution failed on inputs {args}: {agent_res.stderr}"
            agent_output = agent_res.stdout.strip()
            assert agent_output == oracle_output, (
                f"Mismatch on inputs {args}.\n"
                f"Oracle output: '{oracle_output}'\n"
                f"Agent output:  '{agent_output}'"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
