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

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import itertools
import json
import math
import os
import re
import secrets
import shlex
import stat
import subprocess

import pytest
import requests

URL = "http://127.0.0.1:8000/analyze"
PROPS = {
    "M": (149, 1.9),
    "A": (89, 1.8),
    "S": (105, -0.8),
    "G": (75, -0.4),
    "Y": (181, -1.3),
}
MARKER = "/tmp/verifier_engine_invocations"


def energy(seq):
    total = 0.0
    for left, right in zip(seq, seq[1:]):
        lm, lh = PROPS[left]
        rm, rh = PROPS[right]
        total += abs(lm - rm) * (lh + rh)
    return total


def exact_permutation_p(seq):
    original = energy(seq)
    count = 0
    total = 0
    # Position permutations correctly model uniformly shuffling a sequence,
    # including sequences containing repeated residues.
    for perm in itertools.permutations(seq):
        total += 1
        if energy(perm) <= original + 1e-12:
            count += 1
    return count / total


def post(seq, timeout=30):
    try:
        response = requests.post(URL, json={"sequence": seq}, timeout=timeout)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to API at {URL}: {exc}")
    assert response.status_code == 200, (
        f"Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")
    return data


def assert_result(data, seq):
    assert "original_energy" in data, f"Missing 'original_energy' in response JSON: {data}"
    assert "p_value" in data, f"Missing 'p_value' in response JSON: {data}"

    actual_energy = data["original_energy"]
    assert isinstance(actual_energy, (int, float)) and not isinstance(actual_energy, bool), \
        "original_energy must be a number"
    assert math.isfinite(actual_energy), "original_energy must be finite"
    expected_energy = energy(seq)
    assert math.isclose(actual_energy, expected_energy, abs_tol=0.1), \
        f"Expected original_energy for {seq} to be approximately {expected_energy}, got {actual_energy}"

    p_val = data["p_value"]
    assert isinstance(p_val, (int, float)) and not isinstance(p_val, bool), \
        "p_value must be a number"
    assert math.isfinite(p_val), "p_value must be finite"
    assert 0.0 <= p_val <= 1.0, f"p_value must be between 0.0 and 1.0, got {p_val}"
    expected_p = exact_permutation_p(seq)
    # One million trials have standard error at most 0.0005. This tolerance is
    # deliberately generous while still rejecting fabricated constant values.
    assert abs(p_val - expected_p) <= 0.01, \
        f"p_value for {seq} should be near {expected_p}, got {p_val}"


def find_cpp_sources():
    found = []
    for root in ("/app", "/home/user"):
        if not os.path.isdir(root):
            continue
        for directory, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in {".git", "__pycache__", "node_modules"}]
            for name in files:
                if name.endswith((".cpp", ".cc", ".cxx", ".C")):
                    found.append(os.path.join(directory, name))
    return found


def is_openmp_elf(path):
    try:
        if not os.path.isfile(path) or os.path.islink(path):
            return False
        mode = os.stat(path).st_mode
        if not mode & stat.S_IXUSR:
            return False
        with open(path, "rb") as handle:
            head = handle.read(4)
        if head != b"\x7fELF":
            return False
        result = subprocess.run(
            ["ldd", path], capture_output=True, text=True, timeout=5, check=False
        )
        if "libgomp" in result.stdout + result.stderr:
            return True
        with open(path, "rb") as handle:
            return b"GOMP_" in handle.read()
    except (OSError, subprocess.SubprocessError):
        return False


def find_openmp_binaries():
    found = []
    for root in ("/app", "/home/user"):
        if not os.path.isdir(root):
            continue
        for directory, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in {".git", "__pycache__", "node_modules"}]
            for name in files:
                path = os.path.join(directory, name)
                if is_openmp_elf(path):
                    found.append(path)
    return found


def delegate_wrapper(path, real_path):
    body = (
        "#!/bin/sh\n"
        + "printf '%s\\n' " + shlex.quote(path) + " >> " + shlex.quote(MARKER) + "\n"
        + "exec " + shlex.quote(real_path) + " \"$@\"\n"
    )
    with open(path, "w") as handle:
        handle.write(body)
    os.chmod(path, 0o755)


def sentinel_wrapper(path):
    body = "#!/bin/sh\nprintf '%s\\n' '{\"original_energy\":12345.678,\"p_value\":0.314159}'\n"
    with open(path, "w") as handle:
        handle.write(body)
    os.chmod(path, 0o755)


def parse_binary_output(path, seq):
    result = subprocess.run(
        [path, seq], capture_output=True, text=True, timeout=30, check=False
    )
    assert result.returncode == 0, f"C++ engine failed when run directly: {result.stderr}"
    try:
        return json.loads(result.stdout.strip())
    except ValueError:
        pytest.fail(f"C++ engine stdout is not JSON: {result.stdout!r}")


def test_complete_pipeline():
    # Retain the original MASGY assertions, including the dictated sequence's
    # expected energy of 21.8.
    original = post("MASGY")
    assert_result(original, "MASGY")
    assert math.isclose(original["original_energy"], 21.8, abs_tol=0.1)

    sources = find_cpp_sources()
    assert sources, "No C++ source file was found under /app or /home/user"
    qualifying_source = False
    for path in sources:
        try:
            text = open(path, encoding="utf-8", errors="ignore").read()
        except OSError:
            continue
        normalized = text.replace("'", "").replace("_", "")
        omp_pragmas = re.findall(r"#\s*pragma\s+omp[^\n]*", text, flags=re.I)
        if ("1000000" in normalized and omp_pragmas
                and any("parallel" in pragma.lower() for pragma in omp_pragmas)):
            qualifying_source = True
            break
    assert qualifying_source, \
        "C++ source must contain the 1,000,000-trial simulation and OpenMP parallelization"

    binaries = find_openmp_binaries()
    assert binaries, "No executable OpenMP C++ binary was found under /app or /home/user"

    backups = {}
    try:
        try:
            os.unlink(MARKER)
        except FileNotFoundError:
            pass
        for index, path in enumerate(binaries):
            real_path = f"{path}.verifier-real-{os.getpid()}-{index}"
            os.rename(path, real_path)
            backups[path] = real_path
            delegate_wrapper(path, real_path)

        # Exercise the endpoint after instrumentation and verify that an actual
        # OpenMP executable is launched for a request.
        probe = post("AMSGY")
        assert_result(probe, "AMSGY")
        assert os.path.exists(MARKER), "The API did not invoke the compiled OpenMP binary"
        with open(MARKER) as handle:
            invoked = {line.strip() for line in handle if line.strip()}
        invoked &= set(backups)
        assert invoked, "The API did not invoke any discovered OpenMP executable"

        # Replace the invoked executable(s) with a sentinel producer. The API
        # must return that exact generated JSON, proving it does not calculate
        # or hardcode the response independently of the C++ engine.
        for path in invoked:
            sentinel_wrapper(path)
        sentinel = post("GYASM")
        assert sentinel.get("original_energy") == 12345.678, \
            "The API response was not generated by the invoked C++ executable"
        assert sentinel.get("p_value") == 0.314159, \
            "The API response was not generated by the invoked C++ executable"
        for path in invoked:
            delegate_wrapper(path, backups[path])

        # The engine itself must accept a sequence argument and emit the required
        # JSON, independently of the HTTP layer.
        direct_ok = False
        direct_errors = []
        for path in invoked:
            try:
                direct = parse_binary_output(backups[path], "SAYGM")
                assert_result(direct, "SAYGM")
                direct_ok = True
                break
            except (AssertionError, subprocess.SubprocessError) as exc:
                direct_errors.append(str(exc))
        assert direct_ok, "Invoked OpenMP binary failed direct CLI validation: " + "; ".join(direct_errors)

        # Use runtime-random orderings and repeated residues so a fixed MASGY
        # response or small table cannot pass. Expected values are independently
        # derived by exhaustive permutation enumeration.
        rng = secrets.SystemRandom()
        test_sequences = []
        for residues in (list("MMASGY"), list("AASSGYY"), list("MASGYY")):
            rng.shuffle(residues)
            test_sequences.append("".join(residues))
        for seq in test_sequences:
            assert_result(post(seq), seq)
    finally:
        for path, real_path in backups.items():
            try:
                if os.path.lexists(path):
                    os.unlink(path)
                os.rename(real_path, path)
            except OSError:
                pass
PYTEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
