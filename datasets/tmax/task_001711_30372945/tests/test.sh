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
import json
import os
import random
import re
import subprocess

import pytest
import requests

C_FILE = "/home/user/motif_scorer.c"
TARGET_FILE = "/home/user/target.txt"
EXECUTABLE = "/tmp/motif_scorer_verified"
MOTIF = "TACCATGC"


def expected_result(target):
    best_score = None
    best_index = None
    for i in range(len(target) - len(MOTIF) + 1):
        score = sum(1 if a == b else -1 for a, b in zip(MOTIF, target[i:i + len(MOTIF)]))
        if best_score is None or score > best_score:
            best_score = score
            best_index = i
    return best_score, best_index


def parse_program_output(output):
    try:
        data = json.loads(output.strip())
        if isinstance(data, dict) and "max_score" in data and "index" in data:
            return int(data["max_score"]), int(data["index"])
    except (ValueError, TypeError):
        pass

    score_match = re.search(r"max(?:imum)?(?:[_ ]+)?score\s*[:=]\s*(-?\d+)", output, re.I)
    index_match = re.search(r"index\s*[:=]\s*(-?\d+)", output, re.I)
    if score_match and index_match:
        return int(score_match.group(1)), int(index_match.group(1))

    numbers = re.findall(r"-?\d+", output)
    assert len(numbers) == 2, f"Could not unambiguously parse score and index from output: {output!r}"
    return int(numbers[0]), int(numbers[1])


def compile_program():
    result = subprocess.run(
        ["gcc", "-O2", "-std=c11", "-fopenmp", C_FILE, "-o", EXECUTABLE],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, f"C program failed to compile with -fopenmp:\n{result.stderr}"

    linked = subprocess.run(
        ["ldd", EXECUTABLE], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=5
    )
    assert linked.returncode == 0 and "libgomp" in linked.stdout.lower(), \
        "Compiled scorer is not linked to the OpenMP runtime"


def run_program(threads):
    env = os.environ.copy()
    env["OMP_NUM_THREADS"] = str(threads)
    result = subprocess.run(
        [EXECUTABLE], env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
    )
    assert result.returncode == 0, \
        f"Scorer exited with {result.returncode} using {threads} threads:\n{result.stderr}"
    return parse_program_output(result.stdout)


def test_c_file_exists_and_uses_openmp():
    """The C source must contain real OpenMP work sharing and compile with OpenMP."""
    assert os.path.isfile(C_FILE), f"C program not found at {C_FILE}"

    with open(C_FILE, "r") as f:
        content = f.read()

    # Preserve the original basic assertion.
    assert "omp" in content.lower(), \
        "C program does not appear to use OpenMP (missing 'omp' pragmas or headers)."

    # Ignore comments when checking that OpenMP is used for domain decomposition.
    clean = re.sub(r"/\*.*?\*/", "", content, flags=re.S)
    clean = re.sub(r"//.*", "", clean)
    assert re.search(r"^\s*#\s*pragma\s+omp\s+parallel\b", clean, re.I | re.M), \
        "Missing an OpenMP parallel region"

    combined_parallel_for = re.search(
        r"^\s*#\s*pragma\s+omp\s+parallel\s+for\b", clean, re.I | re.M
    )
    separate_workshare = re.search(
        r"^\s*#\s*pragma\s+omp\s+for\b", clean, re.I | re.M
    )
    explicit_chunks = (
        re.search(r"\bomp_get_thread_num\s*\(", clean)
        and re.search(r"\bomp_get_num_threads\s*\(", clean)
    )
    assert combined_parallel_for or separate_workshare or explicit_chunks, \
        "OpenMP region does not decompose the sliding-window domain among threads"

    compile_program()


def test_compiled_scorer_on_unseen_targets():
    """Execute the submitted scorer on verifier-generated targets and check tie handling."""
    compile_program()
    with open(TARGET_FILE, "rb") as f:
        original_target = f.read()

    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    bases = "ACGT"

    target1 = [rng.choice(bases) for _ in range(12000)]
    first = rng.randrange(1000, 3500)
    second = rng.randrange(7000, 10500)
    for index in (first, second):
        target1[index:index + len(MOTIF)] = MOTIF
    target1 = "".join(target1)

    # A second case has no perfect match, so the implementation must compute
    # mismatch scores rather than merely search for the motif.
    while True:
        target2 = "".join(rng.choice(bases) for _ in range(9000))
        if expected_result(target2)[0] < len(MOTIF):
            break

    try:
        for target in (target1, target2):
            expected = expected_result(target)
            with open(TARGET_FILE, "w") as f:
                f.write(target)
            for threads in (1, 2, 4):
                for _ in range(2):
                    actual = run_program(threads)
                    assert actual == expected, \
                        f"Expected score/index {expected}, got {actual} with {threads} threads"
    finally:
        with open(TARGET_FILE, "wb") as f:
            f.write(original_target)


def test_network_service_response():
    """The service must return the score actually implied by the supplied target."""
    with open(TARGET_FILE, "r") as f:
        target = "".join(f.read().split()).upper()
    derived_score, derived_index = expected_result(target)

    # Preserve the original fixture assertions as well as deriving its answer.
    assert derived_score == 8, f"Expected fixture max_score to be 8, got {derived_score}"
    assert derived_index == 42000, f"Expected fixture index to be 42000, got {derived_index}"

    url = "http://127.0.0.1:8080/score"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the network service at {url}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")

    assert "max_score" in data, "JSON response missing 'max_score' key"
    assert "index" in data, "JSON response missing 'index' key"
    assert data["max_score"] == derived_score, \
        f"Expected max_score to be {derived_score}, got {data['max_score']}"
    assert data["index"] == derived_index, \
        f"Expected index to be {derived_index}, got {data['index']}"
    assert data["max_score"] == 8, f"Expected max_score to be 8, got {data['max_score']}"
    assert data["index"] == 42000, f"Expected index to be 42000, got {data['index']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
