#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import shutil
import subprocess

HOME = "/home/user"
SOURCE = os.path.join(HOME, "model.c")
RESULTS = os.path.join(HOME, "results.json")
BINARY = "/tmp/model_submission"

TARGET = b"ATGCGATCGATCGATCGATCGATCGATCGATC"
PRIMER = b"GATCGATC"


def compile_model():
    assert os.path.isfile(SOURCE) and not os.path.islink(SOURCE), \
        "/home/user/model.c must exist and be a regular C source file."
    proc = subprocess.run(
        ["gcc", "-std=c11", "-O0", SOURCE, "-o", BINARY, "-lm"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert proc.returncode == 0, f"model.c did not compile:\n{proc.stderr}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), \
        "Compilation did not produce an executable."


def run_binary(path):
    if os.path.lexists(RESULTS):
        os.remove(RESULTS)
    proc = subprocess.run(
        ["runuser", "-u", "user", "--", path],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert proc.returncode == 0, \
        f"Compiled model exited with status {proc.returncode}:\n{proc.stderr}"
    assert os.path.exists(RESULTS), \
        "Executing the compiled C program did not generate /home/user/results.json."
    with open(RESULTS, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"results.json is not valid JSON: {exc}")


def assert_report_shape(data):
    assert isinstance(data, dict), "results.json must contain a JSON object."
    assert "best_score" in data, "results.json is missing 'best_score'."
    assert "largest_stable_dt" in data, "results.json is missing 'largest_stable_dt'."
    assert "final_C_at_stable_dt" in data, "results.json is missing 'final_C_at_stable_dt'."


def expected_for_score(score):
    dts = [0.1, 0.01, 0.001, 0.0001, 0.00001]
    kon = score * 1000.0

    def deriv(c):
        return kon * (1.0 - c) * (1.0 - c) - 0.1 * c

    def integrate(dt):
        c = 0.0
        t = 0.0
        stable = True
        while t < 0.01 - 1e-15:
            k1 = deriv(c)
            k2 = deriv(c + 0.5 * dt * k1)
            k3 = deriv(c + 0.5 * dt * k2)
            k4 = deriv(c + dt * k3)
            c += dt * (k1 + 2.0*k2 + 2.0*k3 + k4) / 6.0
            t += dt
            if not math.isfinite(c) or c < 0.0 or c > 1.0:
                stable = False
                break
        return stable, c

    for dt in dts:
        stable, c = integrate(dt)
        if stable:
            return dt, round(c, 4)
    raise AssertionError("Oracle found no stable time step")


def make_patched_binary(name, target, primer):
    with open(BINARY, "rb") as f:
        image = f.read()
    assert TARGET in image, \
        "The compiled model does not contain or use the required target sequence."
    image = image.replace(TARGET, target)
    assert PRIMER in image, \
        "The compiled model does not contain or use the required primer sequence."
    image = image.replace(PRIMER, primer)
    path = f"/tmp/{name}"
    with open(path, "wb") as f:
        f.write(image)
    os.chmod(path, 0o755)
    return path


def test_compiled_program_and_original_report():
    compile_model()
    data = run_binary(BINARY)
    assert_report_shape(data)

    # Preserve the original verifier's assertions.
    assert data["best_score"] == 8, \
        f"Expected best_score to be 8, got {data['best_score']}."
    expected_dt = 0.0001
    assert math.isclose(data["largest_stable_dt"], expected_dt, rel_tol=1e-5), \
        f"Expected largest_stable_dt to be {expected_dt}, got {data['largest_stable_dt']}."
    expected_c = 0.9965
    assert math.isclose(data["final_C_at_stable_dt"], expected_c, abs_tol=0.0002), \
        f"Expected final_C_at_stable_dt to be close to {expected_c}, got {data['final_C_at_stable_dt']}."


def test_model_reacts_to_changed_sequences_and_recomputes_rk4():
    # Equal-length substitutions patch only the model's sequence data. These
    # cases prevent a program that merely writes the three known constants from
    # passing, while retaining the same alignment and integration task.
    cases = [
        ("model_score_zero", b"A" * len(TARGET), b"AAAACCCC", 0),
        ("model_score_two", b"A" * len(TARGET), b"AAAAACCC", 2),
    ]
    for name, target, primer, score in cases:
        variant = make_patched_binary(name, target, primer)
        data = run_binary(variant)
        assert_report_shape(data)
        expected_dt, expected_c = expected_for_score(score)
        assert data["best_score"] == score, \
            f"Model did not recompute alignment score for {name}."
        assert math.isclose(data["largest_stable_dt"], expected_dt, rel_tol=1e-6, abs_tol=1e-12), \
            f"Model did not recompute per-step RK4 stability for {name}."
        assert math.isclose(data["final_C_at_stable_dt"], expected_c, abs_tol=0.0002), \
            f"Model did not recompute the RK4 final concentration for {name}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
