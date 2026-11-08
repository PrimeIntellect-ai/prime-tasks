#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import pwd
import secrets
import shutil
import subprocess
import tempfile
import uuid

import pytest

PROJECT = "/home/user/project"


def user_uid():
    try:
        return pwd.getpwnam("user").pw_uid
    except KeyError:
        return 1000


def parse_single_float(text, description):
    lines = text.splitlines()
    assert len(lines) == 1 and lines[0].strip(), f"{description} must contain exactly one non-empty line."
    try:
        value = float(lines[0].strip())
    except ValueError:
        pytest.fail(f"{description} contains non-numeric data: {text!r}")
    assert math.isfinite(value), f"{description} is not finite: {value}"
    return value


def test_final_output_exists_and_correct():
    log_path = "/home/user/project/final_output.log"
    assert os.path.isfile(log_path), f"Output file {log_path} does not exist. Did you run ./sim_app and redirect output?"

    with open(log_path, "r") as f:
        raw = f.read()
    content = raw.strip()

    assert content, "final_output.log is empty."

    try:
        val = float(content)
    except ValueError:
        pytest.fail(f"final_output.log contains non-numeric data: {content}")

    assert not math.isnan(val), "The computed value is NaN. Numerical instability was not fixed properly."
    assert 0.99 < val < 1.01, f"The computed value {val} is not close to 1.0. Numerical instability was not fixed or incorrect input was used."
    parse_single_float(raw, "final_output.log")


def test_config_file_exists():
    config_path = f"/tmp/.sim_config_{user_uid()}.dat"
    assert os.path.isfile(config_path), f"Configuration file {config_path} is missing. Did you use strace to find the required file path?"

    with open(config_path, "r") as f:
        content = f.read().strip()

    try:
        val = float(content)
        assert val > 0 and val < 1e-10, f"Config file contains {val}, expected a small value like 1e-15."
    except ValueError:
        pytest.fail(f"Config file contains non-numeric data: {content}")

    assert content == "1e-15", "The configuration file must contain exactly 1e-15."


def test_env_sh_fixed():
    env_path = "/home/user/project/env.sh"
    assert os.path.isfile(env_path), f"Environment script {env_path} is missing."
    with open(env_path, "r") as f:
        content = f.read()
    assert "-L/invalid/path/that/breaks/build" not in content, "env.sh still contains the invalid LDFLAGS path."


def test_clean_build_and_executable_output():
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "bash", "-c", "source ./env.sh && make clean && make"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=90,
    )
    assert result.returncode == 0, f"make clean && make failed:\n{result.stdout}"

    for name in ("calc_weights", "sim_app"):
        path = os.path.join(PROJECT, name)
        assert os.path.isfile(path), f"Build did not create {name}."
        assert os.access(path, os.X_OK), f"{name} is not executable."
        with open(path, "rb") as f:
            assert f.read(4) == b"\x7fELF", f"{name} is not a compiled ELF executable."

    weights_path = os.path.join(PROJECT, "weights.bin")
    assert os.path.isfile(weights_path), "The build did not run calc_weights to create weights.bin."
    with open(weights_path, "r") as f:
        weight = parse_single_float(f.read(), "weights.bin")
    assert math.isclose(weight, math.expm1(1e-15) / 1e-15, rel_tol=1e-5, abs_tol=1e-8)

    run = subprocess.run(
        ["runuser", "-u", "user", "--", "./sim_app"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert run.returncode == 0, f"sim_app failed: {run.stderr}"
    actual = parse_single_float(run.stdout, "sim_app output")
    assert math.isclose(actual, math.expm1(1e-15) / 1e-15, rel_tol=1e-5, abs_tol=1e-8)

    with open(os.path.join(PROJECT, "final_output.log"), "r") as f:
        recorded = parse_single_float(f.read(), "final_output.log")
    assert math.isclose(recorded, actual, rel_tol=1e-12, abs_tol=1e-12), "final_output.log is not the output produced by sim_app."


def test_calc_weights_source_is_numerically_stable():
    source = os.path.join(PROJECT, "src", "calc_weights.cpp")
    assert os.path.isfile(source), "src/calc_weights.cpp is missing."

    binary = f"/tmp/verifier_calc_weights_{uuid.uuid4().hex}"
    run_dir = tempfile.mkdtemp(prefix="verifier_calc_run_")
    os.chmod(run_dir, 0o777)
    config_path = f"/tmp/.sim_config_{user_uid()}.dat"

    compile_result = subprocess.run(
        ["/usr/bin/g++", "-O2", "-std=c++11", source, "-o", binary],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=45,
    )
    assert compile_result.returncode == 0, f"src/calc_weights.cpp does not compile independently:\n{compile_result.stdout}"

    rng = secrets.SystemRandom()
    values = [1e-15, -1e-15]
    values.extend(rng.uniform(-9e-15, 9e-15) or 3e-15 for _ in range(3))
    values.extend(rng.uniform(-0.9, 0.9) or 0.25 for _ in range(3))

    try:
        for x in values:
            with open(config_path, "w") as f:
                f.write(f"{x:.17g}\n")

            output_path = os.path.join(run_dir, "weights.bin")
            if os.path.exists(output_path):
                os.remove(output_path)

            result = subprocess.run(
                ["runuser", "-u", "user", "--", binary],
                cwd=run_dir,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=15,
            )
            assert result.returncode == 0, f"Independently compiled calc_weights failed for x={x}: {result.stderr}"
            assert os.path.isfile(output_path), f"calc_weights did not create weights.bin for x={x}."
            with open(output_path, "r") as f:
                actual = parse_single_float(f.read(), f"calc_weights output for x={x}")

            expected = math.expm1(x) / x
            assert math.isclose(actual, expected, rel_tol=1e-5, abs_tol=1e-8), \
                f"Unstable or incorrect computation for x={x}: got {actual}, expected {expected}"
    finally:
        with open(config_path, "w") as f:
            f.write("1e-15\n")
        if os.path.exists(binary):
            os.remove(binary)
        shutil.rmtree(run_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
