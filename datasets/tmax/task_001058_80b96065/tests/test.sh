#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import json
import math
import os
import secrets
import subprocess
import sys
import tempfile

import numpy as np
import pytest
import requests
from scipy.optimize import fsolve

URL = "http://127.0.0.1:8080/simulate"
HEADERS = {
    "Authorization": "Bearer sim_token_xyz",
    "Content-Type": "application/json",
}

TRUSTED_C = r'''#include <stdlib.h>
#include <math.h>
void generate_samples(int seed, int n, double* out) {
    srand(seed);
    for (int i = 0; i < n; i++) {
        double r1 = (double)rand() / RAND_MAX;
        double r2 = (double)rand() / RAND_MAX;
        double z0 = sqrt(-2.0 * log(r1)) * cos(2.0 * M_PI * r2);
        out[i] = z0 * 5.0 + 10.0;
    }
}
'''


def configure_sampler(lib):
    lib.generate_samples.argtypes = [
        ctypes.c_int,
        ctypes.c_int,
        ctypes.POINTER(ctypes.c_double),
    ]
    lib.generate_samples.restype = None
    return lib


def samples_from(lib, seed, n):
    output = (ctypes.c_double * n)()
    lib.generate_samples(seed, n, output)
    return np.ctypeslib.as_array(output).copy()


def values_from_samples(samples):
    n = len(samples)
    energy = math.fsum(samples ** 2)
    f_avg = math.fsum(samples) / n

    def equation(x):
        return 1.2 * x ** 3 + 0.8 * x - f_avg

    displacement = fsolve(equation, 0.0)[0]
    return energy, displacement


def get_expected_values():
    # Preserve the original assertion against the supplied C source.
    c_src = "/app/src/mc_sampler.c"
    assert os.path.isfile(c_src), "C source file missing at /app/src/mc_sampler.c"

    with tempfile.TemporaryDirectory() as tmpdir:
        so_path = os.path.join(tmpdir, "sampler.so")
        subprocess.run(
            ["gcc", "-shared", "-o", so_path, "-fPIC", c_src, "-lm"],
            check=True,
        )
        lib = configure_sampler(ctypes.CDLL(so_path))
        return values_from_samples(samples_from(lib, 42, 1000000))


@pytest.fixture(scope="session")
def trusted_sampler():
    with tempfile.TemporaryDirectory() as tmpdir:
        source = os.path.join(tmpdir, "trusted_sampler.c")
        library = os.path.join(tmpdir, "trusted_sampler.so")
        with open(source, "w", encoding="utf-8") as f:
            f.write(TRUSTED_C)
        subprocess.run(
            ["gcc", "-shared", "-o", library, "-fPIC", source, "-lm"],
            check=True,
        )
        yield configure_sampler(ctypes.CDLL(library))


def post_simulation(seed, n):
    payload = {"seed": seed, "num_samples": n}
    try:
        response = requests.post(URL, json=payload, headers=HEADERS, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to API at {URL}: {exc}")

    assert response.status_code == 200, (
        f"Expected 200 OK, got {response.status_code}. "
        f"Response body: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Failed to parse JSON response. Response body: {response.text}")

    assert "energy" in data, f"Response JSON missing 'energy'. Got: {data}"
    assert "displacement" in data, f"Response JSON missing 'displacement'. Got: {data}"
    assert isinstance(data["energy"], (int, float)) and math.isfinite(data["energy"])
    assert isinstance(data["displacement"], (int, float)) and math.isfinite(data["displacement"])
    return data


def test_api_simulate():
    # Preserve the original fixed-case behavioral assertion.
    expected_energy, expected_displacement = get_expected_values()
    data = post_simulation(42, 1000000)
    assert math.isclose(data["energy"], expected_energy, rel_tol=1e-9), (
        f"Energy mismatch: expected {expected_energy}, got {data['energy']}"
    )
    assert math.isclose(data["displacement"], expected_displacement, rel_tol=1e-7), (
        "Displacement mismatch: expected "
        f"{expected_displacement}, got {data['displacement']}"
    )


def test_api_varied_unpredictable_inputs(trusted_sampler):
    # Cases are selected only after the agent has finished, preventing a fixed table.
    rng = secrets.SystemRandom()
    cases = [(rng.randrange(1, 2**31), n) for n in (7, 113, 997, 4093)]
    for seed, n in cases:
        expected_energy, expected_displacement = values_from_samples(
            samples_from(trusted_sampler, seed, n)
        )
        data = post_simulation(seed, n)
        assert math.isclose(
            data["energy"], expected_energy, rel_tol=1e-12, abs_tol=1e-10
        ), f"Energy mismatch for seed={seed}, num_samples={n}"
        assert math.isclose(
            data["displacement"], expected_displacement, rel_tol=1e-10, abs_tol=1e-10
        ), f"Displacement mismatch for seed={seed}, num_samples={n}"


def test_compiled_sampler_exists_and_executes(trusted_sampler):
    candidates = []
    for root, _, files in os.walk("/app"):
        if "sampler.so" in files:
            candidates.append(os.path.join(root, "sampler.so"))

    assert candidates, "Compiled sampler.so is missing under /app"
    seed = secrets.randbelow(2**31 - 1) + 1
    expected = samples_from(trusted_sampler, seed, 64)
    errors = []

    for path in candidates:
        try:
            with open(path, "rb") as f:
                assert f.read(4) == b"\x7fELF", "not an ELF shared object"
            candidate = configure_sampler(ctypes.CDLL(path))
            actual = samples_from(candidate, seed, 64)
            if np.array_equal(actual, expected):
                return
            errors.append(f"{path}: generated incorrect samples")
        except Exception as exc:
            errors.append(f"{path}: {exc}")

    pytest.fail("No executable sampler.so implements the supplied sampler: " + "; ".join(errors))


def test_simulate_uses_reproducible_summation():
    path = "/app/src/simulate.py"
    assert os.path.isfile(path), "Missing /app/src/simulate.py"

    probe = r'''
import json
import math
import sys
import numpy as np
sys.path.insert(0, "/app/src")
import simulate
samples = np.array([1.0e8] + [1.0] * 10001, dtype=np.float64)
a = float(simulate.compute_energy(samples))
b = float(simulate.compute_energy(samples[::-1]))
expected = math.fsum(samples ** 2)
print("VERIFIER_RESULT=" + json.dumps([a, b, expected]))
'''
    result = subprocess.run(
        [sys.executable, "-c", probe],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        "Unable to execute compute_energy from simulate.py: " + result.stderr
    )
    marker = [line for line in result.stdout.splitlines() if line.startswith("VERIFIER_RESULT=")]
    assert marker, f"compute_energy probe produced no result: {result.stdout}"
    a, b, expected = json.loads(marker[-1].split("=", 1)[1])
    assert a == expected and b == expected, (
        "compute_energy must use an order-independent accurate reduction such as "
        "math.fsum or Kahan summation"
    )


def test_fsolve_is_used_in_an_implemented_function():
    found = False
    parse_errors = []
    for root, dirs, files in os.walk("/app"):
        dirs[:] = [d for d in dirs if d not in {"__pycache__", ".git"}]
        for name in files:
            if not name.endswith(".py"):
                continue
            path = os.path.join(root, name)
            try:
                with open(path, "r", encoding="utf-8") as f:
                    tree = ast.parse(f.read(), filename=path)
            except (OSError, UnicodeError, SyntaxError) as exc:
                parse_errors.append(f"{path}: {exc}")
                continue

            aliases = {"fsolve"}
            for node in ast.walk(tree):
                if isinstance(node, ast.ImportFrom) and node.module == "scipy.optimize":
                    for imported in node.names:
                        if imported.name == "fsolve":
                            aliases.add(imported.asname or imported.name)

            for fn in [n for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))]:
                for node in ast.walk(fn):
                    if not isinstance(node, ast.Call):
                        continue
                    if isinstance(node.func, ast.Name) and node.func.id in aliases:
                        found = True
                    if isinstance(node.func, ast.Attribute) and node.func.attr == "fsolve":
                        found = True
    assert found, "No implemented function under /app calls scipy.optimize.fsolve"


def test_api_auth_required():
    payload = {"seed": 42, "num_samples": 1000000}
    try:
        response = requests.post(URL, json=payload, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to API at {URL}: {exc}")
    assert response.status_code in (401, 403), (
        f"Expected 401 or 403 for missing auth, got {response.status_code}. "
        f"Response body: {response.text}"
    )


def test_api_rejects_wrong_bearer_token():
    response = requests.post(
        URL,
        json={"seed": 17, "num_samples": 31},
        headers={"Authorization": "Bearer wrong_token"},
        timeout=5,
    )
    assert response.status_code in (401, 403), (
        f"Expected 401 or 403 for an invalid token, got {response.status_code}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
