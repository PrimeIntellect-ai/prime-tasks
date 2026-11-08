#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import glob
import json
import math
import os
import random
import resource
import secrets
import shutil
import subprocess
import tempfile

PIPELINE = "/home/user/legacy_pipeline"
VALIDATOR = os.path.join(PIPELINE, "validator.py")
ENGINE = "/app/core_engine"


def no_core_dumps():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def test_helper_compiled():
    so_path = os.path.join(PIPELINE, "helper.so")
    build_path = os.path.join(PIPELINE, "build_helper.sh")

    assert os.path.isfile(so_path), f"Expected compiled shared object at {so_path} but it was not found. Did you fix the build script and run it?"
    assert os.path.isfile(build_path), f"Build script {build_path} missing."

    # Require the repaired build step itself to successfully produce a fresh artifact.
    backup = so_path + ".verifier-backup"
    if os.path.exists(backup):
        os.unlink(backup)
    os.replace(so_path, backup)
    try:
        result = subprocess.run(
            ["bash", build_path], cwd=PIPELINE, capture_output=True, text=True, timeout=20
        )
        assert result.returncode == 0, (
            f"build_helper.sh failed with exit code {result.returncode}:\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(so_path), "build_helper.sh did not create helper.so"
        assert os.path.getsize(so_path) > 0, "helper.so is empty"

        elf = subprocess.run(["readelf", "-h", so_path], capture_output=True, text=True)
        assert elf.returncode == 0 and "DYN (Shared object file)" in elf.stdout, (
            "helper.so is not a valid ELF shared object"
        )

        probe = r'''
import ctypes, math, sys
lib = ctypes.CDLL(sys.argv[1])
fn = lib.compute
fn.argtypes = [ctypes.c_double]
fn.restype = ctypes.c_double
for value in (-12.5, -1.0, 0.0, 3.25, 19.0):
    got = fn(value)
    if not math.isclose(got, abs(value), rel_tol=1e-12, abs_tol=1e-12):
        raise SystemExit(2)
'''
        loaded = subprocess.run(
            ["python3", "-c", probe, so_path], capture_output=True, text=True, timeout=10
        )
        assert loaded.returncode == 0, (
            "helper.so could not be loaded and exercised through its compute symbol: "
            + loaded.stderr
        )
    finally:
        if os.path.exists(backup):
            os.unlink(backup)


def test_validator_clean_corpus():
    clean_dir = "/home/user/corpora/clean"

    assert os.path.isfile(VALIDATOR), f"Validator script {VALIDATOR} missing."
    assert os.path.isdir(clean_dir), f"Clean corpus directory {clean_dir} missing."

    clean_files = glob.glob(os.path.join(clean_dir, "*.json"))
    assert len(clean_files) > 0, "No clean corpus files found."

    failed_files = []
    for path in clean_files:
        result = subprocess.run(["python3", VALIDATOR, path], capture_output=True)
        if result.returncode != 0:
            failed_files.append(os.path.basename(path))

    if failed_files:
        assert False, f"{len(failed_files)} of {len(clean_files)} clean files were incorrectly rejected (exit code != 0). Offending files: {', '.join(failed_files[:10])}{'...' if len(failed_files) > 10 else ''}"


def test_validator_evil_corpus():
    evil_dir = "/home/user/corpora/evil"

    assert os.path.isfile(VALIDATOR), f"Validator script {VALIDATOR} missing."
    assert os.path.isdir(evil_dir), f"Evil corpus directory {evil_dir} missing."

    evil_files = glob.glob(os.path.join(evil_dir, "*.json"))
    assert len(evil_files) > 0, "No evil corpus files found."

    failed_files = []
    for path in evil_files:
        result = subprocess.run(["python3", VALIDATOR, path], capture_output=True)
        if result.returncode == 0:
            failed_files.append(os.path.basename(path))

    if failed_files:
        assert False, f"{len(failed_files)} of {len(evil_files)} evil files bypassed validation (exit code == 0). Offending files: {', '.join(failed_files[:10])}{'...' if len(failed_files) > 10 else ''}"


def engine_accepts(path):
    try:
        result = subprocess.run(
            [ENGINE, path],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=3,
            preexec_fn=no_core_dumps,
            cwd="/tmp",
        )
        return result.returncode == 0
    except subprocess.TimeoutExpired:
        return False


def test_validator_on_hidden_randomized_inputs():
    assert os.path.isfile(VALIDATOR), f"Validator script {VALIDATOR} missing."
    assert os.path.isfile(ENGINE), f"Core engine {ENGINE} missing."

    rng = random.SystemRandom()
    payloads = [
        '{"coordinates": []}',
        '{"coordinates": [0, 1, -1, 99999999, -99999999]}',
        '{"coordinates": [100000000, -100000000]}',
        '{"coordinates": [0.12345678, -9.87654321]}',
        '{"coordinates": [100000001]}',
        '{"coordinates": [-100000001]}',
        '{"coordinates": [0.123456789]}',
        '{"coordinates": [-12.000000001]}',
        '{"coordinates": [NaN]}',
        '{"coordinates": [Infinity]}',
        '{"coordinates": [-Infinity]}',
        '{"coordinates": [1.23456789e2]}',
        '{"coordinates": [1.234567891e2]}',
    ]

    for _ in range(55):
        kind = rng.randrange(5)
        if kind == 0:
            value = rng.randint(-100000000, 100000000)
            payloads.append(f'{{"coordinates": [{value}]}}')
        elif kind == 1:
            whole = rng.randint(-999999, 999999)
            frac = rng.randint(0, 99999999)
            payloads.append(f'{{"coordinates": [{whole}.{frac:08d}]}}')
        elif kind == 2:
            sign = -1 if rng.randrange(2) else 1
            value = sign * rng.randint(100000001, 900000000)
            payloads.append(f'{{"coordinates": [{value}]}}')
        elif kind == 3:
            whole = rng.randint(-9999, 9999)
            frac = rng.randint(0, 999999999)
            payloads.append(f'{{"coordinates": [{whole}.{frac:09d}]}}')
        else:
            token = rng.choice(["NaN", "Infinity", "-Infinity"])
            payloads.append(f'{{"coordinates": [{token}]}}')

    rng.shuffle(payloads)

    with tempfile.TemporaryDirectory(prefix="validator-cases-") as case_dir:
        cases = []
        for payload in payloads:
            path = os.path.join(case_dir, secrets.token_hex(16) + ".json")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(payload)
            cases.append((path, engine_accepts(path)))

        # The validator is a pre-filter, so do not let it delegate decisions to the
        # crashing executable while these hidden cases are being checked.
        with open(ENGINE, "rb") as handle:
            engine_bytes = handle.read()
        engine_mode = os.stat(ENGINE).st_mode & 0o7777
        os.unlink(ENGINE)
        mismatches = []
        try:
            for path, expected_safe in cases:
                try:
                    result = subprocess.run(
                        ["python3", VALIDATOR, path],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        timeout=3,
                    )
                    actual_safe = result.returncode == 0
                except subprocess.TimeoutExpired:
                    actual_safe = False
                if actual_safe != expected_safe:
                    mismatches.append((os.path.basename(path), expected_safe))
        finally:
            with open(ENGINE, "wb") as handle:
                handle.write(engine_bytes)
            os.chmod(ENGINE, engine_mode)

        assert not mismatches, (
            f"Validator disagreed with core_engine on {len(mismatches)} of "
            f"{len(cases)} hidden randomized inputs. First mismatches: {mismatches[:10]}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
