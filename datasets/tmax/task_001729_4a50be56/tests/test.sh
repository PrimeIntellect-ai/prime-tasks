#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import math
import os
import shutil
import stat
import subprocess
import tempfile
import textwrap
import time

import pytest
import requests

ROOT = "/app/nano_ode_aligner-2.1.0"
BINARY = os.path.join(ROOT, "bin/nano_align")
H0 = "/home/user/ref_H0.fasta"
H1 = "/home/user/ref_H1.fasta"
URL = "http://127.0.0.1:9090/analyze"
AUTH = {"X-Nano-Auth": "spectro-secure-token", "Content-Type": "application/json"}


def run_score(ref, signal):
    proc = subprocess.run(
        [BINARY, ref] + [repr(float(x)) for x in signal],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    assert proc.returncode == 0, (
        f"nano_align failed for {ref}: stdout={proc.stdout!r}, stderr={proc.stderr!r}"
    )
    try:
        value = float(proc.stdout.strip())
    except ValueError:
        pytest.fail(f"nano_align did not emit a numeric likelihood: {proc.stdout!r}")
    assert math.isfinite(value), f"nano_align emitted a non-finite likelihood: {value}"
    return value


def post_signal(signal, headers=AUTH):
    try:
        return requests.post(URL, headers=headers, json={"signal": signal}, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the service or request timed out: {exc}")


def test_binary_compiled_and_runs_after_real_build():
    assert os.path.isfile(BINARY), f"Compiled binary not found at {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Binary at {BINARY} is not executable"

    dry = subprocess.run(
        ["make", "-B", "-n", "bin/nano_align"], cwd=ROOT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15
    )
    assert dry.returncode == 0, f"Makefile cannot build nano_align:\n{dry.stdout}"
    compile_lines = [line for line in dry.stdout.splitlines() if "gcc" in line or "cc " in line]
    assert compile_lines, f"Makefile did not provide a compiler command:\n{dry.stdout}"
    assert any("-fopenmp" in line for line in compile_lines), (
        f"The actual nano_align compiler/link command does not use -fopenmp:\n{dry.stdout}"
    )

    built = subprocess.run(
        ["make", "-B", "bin/nano_align"], cwd=ROOT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert built.returncode == 0, f"A clean forced build failed:\n{built.stdout}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK)
    with open(BINARY, "rb") as fh:
        assert fh.read(4) == b"\x7fELF", "nano_align is not a compiled ELF binary"

    # Execute both scoring paths and ensure the repaired solver produces finite scores.
    for signal in ([1.12, 1.15, 0.98], [8.5, -3.0, 0.01, 12.0]):
        run_score(H0, signal)
        run_score(H1, signal)


def test_makefile_fixed():
    makefile_path = os.path.join(ROOT, "Makefile")
    assert os.path.isfile(makefile_path), f"Makefile not found at {makefile_path}"
    with open(makefile_path, "r") as f:
        content = f.read()
    assert "-fopenmp" in content, "Makefile was not fixed to include -fopenmp"


def test_solver_fixed_and_adapts_downward():
    solver_path = os.path.join(ROOT, "src/solver.c")
    assert os.path.isfile(solver_path), f"solver.c not found at {solver_path}"
    with open(solver_path, "r") as f:
        content = f.read()
    assert "dt = dt * 1.5;" not in content, (
        "solver.c still contains the buggy step size adaptation logic"
    )

    so_path = "/tmp/libnano_solver_test.so"
    proc = subprocess.run(
        ["gcc", "-shared", "-fPIC", "-O2", "-o", so_path, solver_path, "-lm"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
    )
    assert proc.returncode == 0, f"solver.c does not compile independently: {proc.stderr}"
    lib = ctypes.CDLL(so_path)
    lib.adapt_step_size.argtypes = [ctypes.c_double, ctypes.c_double, ctypes.c_double]
    lib.adapt_step_size.restype = ctypes.c_double
    lib.solve_ode.argtypes = [ctypes.POINTER(ctypes.c_double), ctypes.c_int]
    lib.solve_ode.restype = ctypes.c_double

    for dt, error, tol in ((0.1, 0.2, 0.1), (1.0, 100.0, 0.01), (0.005, 0.006, 0.005)):
        adapted = lib.adapt_step_size(dt, error, tol)
        assert math.isfinite(adapted) and 0.0 < adapted < dt, (
            f"When error exceeds tolerance, step size must decrease: "
            f"dt={dt}, error={error}, tol={tol}, result={adapted}"
        )
    stable = lib.adapt_step_size(0.1, 0.01, 0.1)
    assert math.isfinite(stable) and stable > 0.0
    solved = lib.solve_ode(None, 0)
    assert math.isfinite(solved) and solved != -999.0, (
        "solve_ode still follows the divergence/failure path"
    )


def test_service_analyze_valid_request_and_real_scores():
    signal = [1.12, 1.15, 0.98, 0.85, 1.01, 1.05, 0.99]
    expected_h0 = run_score(H0, signal)
    expected_h1 = run_score(H1, signal)
    expected_ratio = expected_h1 - expected_h0

    response = post_signal(signal)
    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response body: {response.text}")

    assert "variant" in data, "Response JSON missing 'variant' key"
    assert "log_ratio" in data, "Response JSON missing 'log_ratio' key"
    assert isinstance(data["variant"], bool), (
        f"'variant' must be a boolean, got {type(data['variant'])}"
    )
    assert isinstance(data["log_ratio"], (float, int)) and not isinstance(data["log_ratio"], bool), (
        f"'log_ratio' must be a float, got {type(data['log_ratio'])}"
    )
    assert math.isclose(float(data["log_ratio"]), expected_ratio, rel_tol=1e-7, abs_tol=1e-7), (
        f"Service returned log_ratio={data['log_ratio']}, but nano_align scores imply {expected_ratio}"
    )
    assert data["variant"] is (expected_ratio > 5.0), (
        "Variant classification does not implement the strict log_ratio > 5.0 rule"
    )


def test_service_auth_required():
    response = post_signal([1.12, 1.15, 0.98], headers={"Content-Type": "application/json"})
    assert response.status_code in (401, 403), (
        f"Expected 401 or 403 for missing auth header, got {response.status_code}"
    )
    response = post_signal(
        [1.12, 1.15, 0.98],
        headers={"X-Nano-Auth": "wrong-token", "Content-Type": "application/json"},
    )
    assert response.status_code in (401, 403), (
        f"Expected 401 or 403 for invalid auth header, got {response.status_code}"
    )


def test_service_invokes_nano_align_for_varied_signals_and_strict_threshold():
    # Replace the executable briefly with an instrumented executable. A correct service
    # invokes this path once for each reference on every request, so this both detects
    # constant responses and tests score subtraction and the strict threshold boundary.
    backup = BINARY + ".verifier-backup"
    log_path = "/tmp/nano_align_verifier_calls.jsonl"
    shutil.copy2(BINARY, backup)
    with open(log_path, "w"):
        pass
    os.chmod(log_path, 0o666)

    shim = textwrap.dedent(f'''\
        #!/usr/bin/env python3
        import json, os, sys
        ref = sys.argv[1] if len(sys.argv) > 1 else ""
        nums = []
        for arg in sys.argv[2:]:
            try:
                nums.append(float(arg))
            except ValueError:
                pass
        with open({log_path!r}, "a") as fh:
            fh.write(json.dumps({{"ref": ref, "signal": nums}}) + "\\n")
        if not nums:
            sys.exit(2)
        if "H0" in os.path.basename(ref):
            print(-100.0)
        elif "H1" in os.path.basename(ref):
            print(-100.0 + nums[0])
        else:
            sys.exit(3)
    ''')

    fd, replacement = tempfile.mkstemp(prefix=".nano_align_test_", dir=os.path.dirname(BINARY))
    try:
        with os.fdopen(fd, "w") as fh:
            fh.write(shim)
        os.chmod(replacement, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                              stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)
        os.replace(replacement, BINARY)

        cases = [
            ([5.0, 101.125, -7.75], 5.0, False),
            ([5.25, 202.25, 0.125], 5.25, True),
            ([-2.5, 303.5, 9.75], -2.5, False),
        ]
        for signal, expected_ratio, expected_variant in cases:
            with open(log_path, "w"):
                pass
            os.chmod(log_path, 0o666)
            response = post_signal(signal)
            assert response.status_code == 200, response.text
            data = response.json()
            assert isinstance(data.get("variant"), bool)
            assert isinstance(data.get("log_ratio"), (int, float)) and not isinstance(data.get("log_ratio"), bool)
            assert math.isclose(float(data["log_ratio"]), expected_ratio, rel_tol=1e-7, abs_tol=1e-7), (
                f"For signal {signal}, expected ratio {expected_ratio}, got {data['log_ratio']}"
            )
            assert data["variant"] is expected_variant, (
                f"Strict threshold failed for log ratio {expected_ratio}"
            )

            # The request is complete, so both synchronous scoring calls must be logged.
            with open(log_path) as fh:
                calls = [json.loads(line) for line in fh if line.strip()]
            h0_calls = [c for c in calls if "H0" in os.path.basename(c.get("ref", ""))]
            h1_calls = [c for c in calls if "H1" in os.path.basename(c.get("ref", ""))]
            assert h0_calls and h1_calls, (
                f"Service did not invoke nano_align for both H0 and H1; calls={calls}"
            )
            for call in (h0_calls[-1], h1_calls[-1]):
                observed = call.get("signal", [])
                assert len(observed) == len(signal) and all(
                    math.isclose(a, b, rel_tol=1e-9, abs_tol=1e-9)
                    for a, b in zip(observed, signal)
                ), f"Service did not forward the complete signal to nano_align: {call}"
    finally:
        if os.path.exists(backup):
            os.replace(backup, BINARY)
        if os.path.exists(replacement):
            os.unlink(replacement)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
