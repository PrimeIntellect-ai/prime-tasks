#!/bin/bash
set -u
mkdir -p /logs/verifier

# Prevent an agent-owned helper process from acting as a proxy outside the sandbox.
pkill -KILL -u user 2>/dev/null || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import shutil
import string
import subprocess
import tempfile

import pytest

ORACLE = "/app/legacy_transformer"
AGENT = "/home/user/new_transformer"
SOURCE = "/home/user/new_transformer.go"


def generate_random_csv(seed):
    rng = random.Random(seed)

    num_metrics = rng.randint(1, 5)
    metrics = []
    for _ in range(num_metrics):
        metric_len = rng.randint(3, 8)
        metrics.append("".join(rng.choices(string.ascii_letters, k=metric_len)))

    header = ["host"] + metrics
    num_rows = rng.randint(1, 20)
    rows = []
    for _ in range(num_rows):
        host_len = rng.randint(5, 10)
        host = "".join(rng.choices(string.ascii_letters + string.digits, k=host_len))
        row = [host]
        for _ in range(num_metrics):
            choice = rng.random()
            if choice < 0.8:
                value = str(rng.randint(-10, 150))
            elif choice < 0.9:
                value = ""
            else:
                value_len = rng.randint(1, 5)
                value = "".join(rng.choices(string.ascii_letters, k=value_len))
            row.append(value)
        rows.append(row)

    return "\n".join([",".join(header)] + [",".join(row) for row in rows]) + "\n"


def isolated_run(binary, csv_input):
    # Run with only the tested executable visible. In particular, /app and any
    # agent-created proxy files are absent, so the executable cannot delegate to
    # the legacy program by pathname.
    with tempfile.TemporaryDirectory(prefix="transformer-jail-") as jail:
        jailed_binary = os.path.join(jail, "program")
        shutil.copyfile(binary, jailed_binary)
        os.chmod(jailed_binary, 0o755)
        os.chmod(jail, 0o555)

        def enter_jail():
            os.chroot(jail)
            os.chdir("/")
            os.setgroups([])
            os.setgid(65534)
            os.setuid(65534)

        return subprocess.run(
            ["/program"],
            input=csv_input,
            text=True,
            capture_output=True,
            timeout=10,
            preexec_fn=enter_jail,
        )


def test_fuzz_equivalence():
    assert os.path.isfile(AGENT), f"Agent binary not found at {AGENT}"
    assert os.access(AGENT, os.X_OK), f"Agent binary at {AGENT} is not executable"
    assert os.path.isfile(SOURCE), f"Go source not found at {SOURCE}"

    metadata = subprocess.run(
        ["go", "version", "-m", AGENT], text=True, capture_output=True, timeout=10
    )
    assert metadata.returncode == 0, "Submitted executable is not a Go executable"

    with open(AGENT, "rb") as submitted, open(ORACLE, "rb") as oracle:
        assert submitted.read() != oracle.read(), "Submitted executable is the legacy binary"

    with tempfile.TemporaryDirectory(prefix="source-build-") as build_dir:
        rebuilt = os.path.join(build_dir, "new_transformer")
        env = os.environ.copy()
        env["CGO_ENABLED"] = "0"
        build = subprocess.run(
            ["go", "build", "-o", rebuilt, SOURCE],
            text=True,
            capture_output=True,
            timeout=60,
            env=env,
        )
        assert build.returncode == 0, f"Go source failed to compile:\n{build.stderr}"

        # Unpredictable verification-time seeds prevent hardcoding the corpus.
        seeds = [secrets.randbits(128) for _ in range(100)]
        for i, seed in enumerate(seeds):
            csv_input = generate_random_csv(seed)

            oracle_res = subprocess.run(
                [ORACLE],
                input=csv_input,
                text=True,
                capture_output=True,
                timeout=10,
            )
            assert oracle_res.returncode == 0, (
                f"Oracle failed on input {i}:\n{oracle_res.stderr}"
            )

            for label, binary in (("submitted executable", AGENT), ("rebuilt Go source", rebuilt)):
                try:
                    agent_res = isolated_run(binary, csv_input)
                except (subprocess.SubprocessError, OSError) as exc:
                    pytest.fail(f"{label} failed on input {i}: {exc}\nInput was:\n{csv_input}")

                assert agent_res.returncode == 0, (
                    f"{label} failed on input {i}:\n{agent_res.stderr}\n"
                    f"Input was:\n{csv_input}"
                )
                assert agent_res.stdout == oracle_res.stdout, (
                    f"Output mismatch for {label} on input {i}.\n"
                    f"Input:\n{csv_input}\n"
                    f"Expected (Oracle):\n{oracle_res.stdout}\n"
                    f"Got:\n{agent_res.stdout}"
                )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
