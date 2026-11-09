#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import shutil
import stat
import subprocess
from pathlib import Path

import pytest

ORACLE_PATH = Path("/app/legacy_scorer")
PROJECT_PATH = Path("/home/user/new_scorer")
AGENT_PATH = PROJECT_PATH / "target/release/new_scorer"
NUM_ITERATIONS = 1000


def run_scorer(path, input_str):
    return subprocess.run(
        [str(path)],
        input=input_str,
        text=True,
        capture_output=True,
        timeout=5,
    )


def test_01_rust_release_build_and_independent_equivalence():
    assert ORACLE_PATH.exists(), f"Oracle binary missing at {ORACLE_PATH}"
    assert PROJECT_PATH.is_dir(), f"Rust project missing at {PROJECT_PATH}"

    cargo_toml = PROJECT_PATH / "Cargo.toml"
    main_rs = PROJECT_PATH / "src/main.rs"
    assert cargo_toml.is_file(), f"Missing {cargo_toml}"
    assert main_rs.is_file(), f"Missing Rust source at {main_rs}"

    cargo_text = cargo_toml.read_text()
    release_profile = re.search(
        r"(?ms)^\s*\[profile\.release\]\s*(.*?)(?=^\s*\[|\Z)",
        cargo_text,
    )
    assert release_profile, "Cargo.toml must explicitly configure [profile.release]"
    assert re.search(
        r'(?m)^\s*opt-level\s*=\s*(?:3|"3")\s*(?:#.*)?$',
        release_profile.group(1),
    ), "[profile.release] must configure opt-level = 3"

    oracle_bytes = ORACLE_PATH.read_bytes()
    oracle_mode = stat.S_IMODE(ORACLE_PATH.stat().st_mode)

    # Remove access to the legacy executable while rebuilding and exercising the
    # submission, so a forwarding wrapper cannot satisfy the independent tests.
    ORACLE_PATH.unlink()
    try:
        target = PROJECT_PATH / "target"
        if target.exists() or target.is_symlink():
            assert not target.is_symlink(), "The Cargo target directory must not be a symlink"
            shutil.rmtree(target)

        build = subprocess.run(
            ["cargo", "build", "--release"],
            cwd=PROJECT_PATH,
            text=True,
            capture_output=True,
            timeout=120,
        )
        assert build.returncode == 0, (
            "cargo build --release failed:\n" + build.stdout + build.stderr
        )

        assert AGENT_PATH.is_file(), f"Release binary missing at {AGENT_PATH}"
        assert not AGENT_PATH.is_symlink(), "Release binary must not be a symlink"
        assert os.access(AGENT_PATH, os.X_OK), f"Agent binary at {AGENT_PATH} is not executable"
        assert AGENT_PATH.read_bytes()[:4] == b"\x7fELF", "Release artifact must be an ELF binary"
        assert AGENT_PATH.read_bytes() != oracle_bytes, "Submission must not be the legacy binary"

        rng = random.SystemRandom()
        for i in range(NUM_ITERATIONS):
            values = [rng.uniform(-100.0, 100.0) for _ in range(4)]
            fields = [f"{value:.6f}" for value in values]
            x1, x2, x3, x4 = map(float, fields)
            input_str = ",".join(fields) + "\n"
            expected = f"{2.0 * x1 * x1 - 3.5 * x2 + 1.5 * x3 * x4 + 42.0:.4f}"

            agent_proc = run_scorer(AGENT_PATH, input_str)
            assert agent_proc.returncode == 0, (
                f"Agent failed on independent iteration {i + 1}: {agent_proc.stderr}"
            )
            assert agent_proc.stdout.strip() == expected, (
                f"Mismatch on independent iteration {i + 1}.\n"
                f"Input: {input_str.strip()}\n"
                f"Expected output: {expected}\n"
                f"Agent output: {agent_proc.stdout.strip()}"
            )
    finally:
        ORACLE_PATH.write_bytes(oracle_bytes)
        os.chmod(ORACLE_PATH, oracle_mode)


def test_02_original_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle binary missing at {ORACLE_PATH}"
    assert os.path.exists(AGENT_PATH), f"Agent binary missing at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary at {AGENT_PATH} is not executable"

    random.seed(42)

    for i in range(NUM_ITERATIONS):
        x1 = random.uniform(-100.0, 100.0)
        x2 = random.uniform(-100.0, 100.0)
        x3 = random.uniform(-100.0, 100.0)
        x4 = random.uniform(-100.0, 100.0)
        input_str = f"{x1:.6f},{x2:.6f},{x3:.6f},{x4:.6f}\n"

        oracle_proc = run_scorer(ORACLE_PATH, input_str)
        oracle_out = oracle_proc.stdout.strip()
        agent_proc = run_scorer(AGENT_PATH, input_str)
        agent_out = agent_proc.stdout.strip()

        assert oracle_out == agent_out, (
            f"Mismatch on iteration {i + 1}.\n"
            f"Input: {input_str.strip()}\n"
            f"Oracle output: {oracle_out}\n"
            f"Agent output: {agent_out}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
