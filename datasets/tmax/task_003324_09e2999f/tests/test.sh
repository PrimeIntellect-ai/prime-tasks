#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import stat
import subprocess
import tempfile

ORACLE_PATH = "/app/sensor_calc_oracle"
AGENT_PATH = "/home/user/sensor_calc"
SOURCE_PATH = "/home/user/sensor_calc.c"
NUM_TESTS = 1000


def generate_test_case():
    k = random.randint(2, 50)
    is_clustered = random.random() < 0.5

    args = []
    if is_clustered:
        base = 1e8
        for _ in range(k):
            val = base + random.uniform(-1.0, 1.0)
            args.append(f"{val:.6f}")
    else:
        for _ in range(k):
            val = random.uniform(-1000.0, 1000.0)
            args.append(f"{val:.6f}")
    return args


def drop_privileges():
    os.setgroups([])
    os.setgid(65534)
    os.setuid(65534)


def test_sensor_calc_fuzz_equivalence():
    assert os.path.exists(AGENT_PATH), f"Agent's executable not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent's file at {AGENT_PATH} is not executable"
    assert os.path.exists(SOURCE_PATH), f"Corrected source not found at {SOURCE_PATH}"
    assert stat.S_ISREG(os.lstat(SOURCE_PATH).st_mode), f"Corrected source at {SOURCE_PATH} is not a regular file"
    assert not os.path.samefile(AGENT_PATH, ORACLE_PATH), "Agent executable is the oracle itself"
    assert not (os.path.getsize(AGENT_PATH) == os.path.getsize(ORACLE_PATH) and
                open(AGENT_PATH, "rb").read() == open(ORACLE_PATH, "rb").read()), \
        "Agent executable is byte-identical to the oracle"

    random.seed(42)
    cases = [generate_test_case() for _ in range(NUM_TESTS)]
    expected = []
    for args in cases:
        result = subprocess.run([ORACLE_PATH] + args, capture_output=True, text=True, timeout=5)
        expected.append((result.returncode, result.stdout))

    stash_dir = tempfile.mkdtemp(prefix="sensor-oracle-stash-", dir="/root")
    os.chmod(stash_dir, 0o700)
    stashed_oracle = os.path.join(stash_dir, "oracle")
    os.rename(ORACLE_PATH, stashed_oracle)

    build_dir = tempfile.mkdtemp(prefix="sensor-build-", dir="/tmp")
    jail_dir = tempfile.mkdtemp(prefix="sensor-jail-", dir="/tmp")
    compiled_path = os.path.join(build_dir, "sensor_calc")
    jailed_path = os.path.join(jail_dir, "sensor_calc")

    try:
        compile_res = subprocess.run(
            ["gcc", "-std=c11", "-O2", "-static", SOURCE_PATH, "-o", compiled_path],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert compile_res.returncode == 0, f"Corrected source did not compile:\n{compile_res.stderr}"
        shutil.copy2(compiled_path, jailed_path)
        os.chmod(jail_dir, 0o755)
        os.chmod(jailed_path, 0o755)

        for i, args in enumerate(cases):
            oracle_returncode, oracle_stdout = expected[i]

            agent_res = subprocess.run(
                [AGENT_PATH] + args,
                capture_output=True,
                text=True,
                timeout=5,
                preexec_fn=drop_privileges,
            )
            assert agent_res.returncode == oracle_returncode, (
                f"Test case {i+1} failed.\n"
                f"Arguments: {' '.join(args)}\n"
                f"Oracle return code: {oracle_returncode}\n"
                f"Agent return code: {agent_res.returncode}\n"
            )
            assert agent_res.stdout == oracle_stdout, (
                f"Test case {i+1} failed.\n"
                f"Arguments: {' '.join(args)}\n"
                f"Oracle stdout:\n{oracle_stdout}\n"
                f"Agent stdout:\n{agent_res.stdout}\n"
            )

            source_res = subprocess.run(
                ["chroot", "--userspec=65534:65534", jail_dir, "/sensor_calc"] + args,
                capture_output=True,
                text=True,
                timeout=5,
            )
            assert source_res.returncode == oracle_returncode, (
                f"Freshly compiled source failed test case {i+1}.\n"
                f"Arguments: {' '.join(args)}\n"
                f"Oracle return code: {oracle_returncode}\n"
                f"Source return code: {source_res.returncode}\n"
            )
            assert source_res.stdout == oracle_stdout, (
                f"Freshly compiled source failed test case {i+1}.\n"
                f"Arguments: {' '.join(args)}\n"
                f"Oracle stdout:\n{oracle_stdout}\n"
                f"Source stdout:\n{source_res.stdout}\n"
            )
    finally:
        if os.path.exists(stashed_oracle):
            os.rename(stashed_oracle, ORACLE_PATH)
        shutil.rmtree(stash_dir, ignore_errors=True)
        shutil.rmtree(build_dir, ignore_errors=True)
        shutil.rmtree(jail_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
