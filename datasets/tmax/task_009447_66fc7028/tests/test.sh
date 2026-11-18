#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import statistics
import subprocess

import pytest

PROJECT = "/home/user/gbm_sim"


def rust_env():
    env = os.environ.copy()
    env.update({
        "HOME": "/home/user",
        "CARGO_HOME": "/home/user/.cargo",
        "RUSTUP_HOME": "/home/user/.rustup",
    })
    return env


@pytest.fixture(scope="session")
def built_binary():
    assert os.path.isfile(os.path.join(PROJECT, "Cargo.toml")), "Cargo.toml is missing."

    result = subprocess.run(
        ["cargo", "build", "--release"],
        cwd=PROJECT,
        env=rust_env(),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=300,
    )
    assert result.returncode == 0, f"cargo build --release failed:\n{result.stdout}\n{result.stderr}"

    metadata_result = subprocess.run(
        ["cargo", "metadata", "--format-version", "1", "--no-deps"],
        cwd=PROJECT,
        env=rust_env(),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert metadata_result.returncode == 0, f"cargo metadata failed: {metadata_result.stderr}"
    metadata = json.loads(metadata_result.stdout)

    manifest = os.path.realpath(os.path.join(PROJECT, "Cargo.toml"))
    packages = [p for p in metadata["packages"] if os.path.realpath(p["manifest_path"]) == manifest]
    assert packages, "Could not identify the gbm_sim package in cargo metadata."
    package = packages[0]
    assert any(dep["name"] == "rayon" for dep in package["dependencies"]), \
        "The Rust project must directly depend on the rayon crate."

    bin_targets = [t for t in package["targets"] if "bin" in t["kind"]]
    assert bin_targets, "The Rust project has no binary target."
    binary = os.path.join(metadata["target_directory"], "release", bin_targets[0]["name"])
    assert os.path.isfile(binary) and os.access(binary, os.X_OK), \
        f"Release executable was not produced at {binary}."

    rust_sources = []
    for root, dirs, files in os.walk(os.path.join(PROJECT, "src")):
        dirs[:] = [d for d in dirs if d != "target"]
        for name in files:
            if name.endswith(".rs"):
                with open(os.path.join(root, name), "r", errors="replace") as f:
                    rust_sources.append(f.read())
    source = "\n".join(rust_sources).lower()
    assert "rayon" in source, "Rust source does not import or reference rayon."
    assert "into_par_iter" in source or "par_iter" in source, \
        "Rust source does not use a rayon parallel iterator for path simulation."

    return binary


def run_sim(binary, n, dt, threads=2):
    env = rust_env()
    env["RAYON_NUM_THREADS"] = str(threads)
    result = subprocess.run(
        [binary, str(n), str(dt)],
        cwd=PROJECT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, \
        f"Simulation failed for N={n}, dt={dt}:\nstdout={result.stdout}\nstderr={result.stderr}"
    output = result.stdout.strip()
    assert re.fullmatch(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?", output), \
        f"Expected exactly one floating-point KS distance on stdout, got: {result.stdout!r}"
    value = float(output)
    assert math.isfinite(value) and 0.0 <= value <= 1.0, f"Invalid KS distance: {value}"
    return value


def test_project_and_scripts_exist():
    """Verify that the Rust project directory and bash scripts exist."""
    assert os.path.isdir("/home/user/gbm_sim"), "Rust project directory /home/user/gbm_sim does not exist."
    assert os.path.isfile("/home/user/run_convergence.sh"), "Script /home/user/run_convergence.sh does not exist."
    assert os.path.isfile("/home/user/profile_parallel.sh"), "Script /home/user/profile_parallel.sh does not exist."


def test_convergence_log():
    """Verify the existence, format, and convergence logic of convergence.log."""
    log_path = "/home/user/convergence.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 lines in {log_path}, found {len(lines)}."

    expected_dts = ["0.1", "0.01", "0.001"]
    ks_distances = []

    for i, line in enumerate(lines):
        parts = line.split(",")
        assert len(parts) == 2, f"Line {i+1} in {log_path} is not in the format <dt>,<KS_distance>. Found: {line}"
        dt_str, ks_str = parts[0].strip(), parts[1].strip()

        assert dt_str == expected_dts[i], f"Expected dt={expected_dts[i]} on line {i+1}, found {dt_str}."

        try:
            ks_val = float(ks_str)
            ks_distances.append(ks_val)
        except ValueError:
            assert False, f"KS distance on line {i+1} is not a valid float: {ks_str}"

        assert math.isfinite(ks_val) and 0.0 <= ks_val <= 1.0, \
            f"KS distance on line {i+1} is outside [0,1]: {ks_val}"

    ks_1 = ks_distances[0]
    ks_3 = ks_distances[2]
    assert ks_3 < ks_1, f"Convergence not demonstrated: KS distance for dt=0.001 ({ks_3}) is not smaller than for dt=0.1 ({ks_1})."


def test_profile_log():
    """Verify the existence, format, and speedup logic of profile.log."""
    log_path = "/home/user/profile.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {log_path}, found {len(lines)}."

    thread_times = {}
    for i, line in enumerate(lines):
        match = re.match(r"^threads=(\d+),time=([0-9]*\.?[0-9]+)$", line)
        assert match, f"Line {i+1} in {log_path} does not match expected format 'threads=X,time=Y'. Found: {line}"

        threads = int(match.group(1))
        time_val = float(match.group(2))
        assert math.isfinite(time_val) and time_val > 0.0, f"Invalid execution time: {time_val}"
        thread_times[threads] = time_val

    assert 1 in thread_times, f"Missing 'threads=1' entry in {log_path}."
    assert 4 in thread_times, f"Missing 'threads=4' entry in {log_path}."

    t1 = thread_times[1]
    t4 = thread_times[4]
    assert t4 < t1, f"Parallel speedup not demonstrated: time for threads=4 ({t4}) is not smaller than time for threads=1 ({t1})."


def test_executable_has_empirical_ks_scaling(built_binary):
    """Execute hidden workloads and check the independently expected 1/sqrt(N) KS scale."""
    n_small = random.SystemRandom().randint(180, 320)
    n_large = random.SystemRandom().randint(9000, 14000)

    small = [run_sim(built_binary, n_small, 0.01) for _ in range(5)]
    large = [run_sim(built_binary, n_large, 0.01) for _ in range(3)]
    small_med = statistics.median(small)
    large_med = statistics.median(large)

    small_scaled = small_med * math.sqrt(n_small)
    large_scaled = large_med * math.sqrt(n_large)
    assert 0.30 < small_scaled < 2.8, \
        f"Small-sample KS values are inconsistent with an empirical CDF: {small}"
    assert 0.25 < large_scaled < 3.2, \
        f"Large-sample KS values are inconsistent with GBM samples: {large}"
    assert small_med > 1.5 * large_med, \
        f"KS distance did not decrease with sample count: small={small}, large={large}"


def test_executable_detects_euler_time_step_bias(built_binary):
    """One Euler step is measurably different from the target lognormal law; fine steps converge."""
    n = random.SystemRandom().randint(25000, 35000)
    coarse = [run_sim(built_binary, n, 1.0) for _ in range(3)]
    fine = [run_sim(built_binary, n, 0.01) for _ in range(3)]
    coarse_med = statistics.median(coarse)
    fine_med = statistics.median(fine)

    assert 0.015 < coarse_med < 0.12, \
        f"Reported one-step Euler KS distance is inconsistent with GBM: {coarse}"
    assert fine_med < 0.035, f"Fine-step simulation is not statistically accurate: {fine}"
    assert coarse_med > fine_med + 0.010, \
        f"Executable does not show Euler-Maruyama time-step convergence: coarse={coarse}, fine={fine}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
