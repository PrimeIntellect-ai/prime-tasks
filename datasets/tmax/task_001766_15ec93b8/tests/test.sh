#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import random
import re
import subprocess

import pytest

HOME = "/home/user"
APP = f"{HOME}/app"
LIB = f"{HOME}/libsolver.so"


def test_files_exist():
    """Check that the required source and build files exist."""
    required_files = [
        f"{HOME}/solver.cpp",
        f"{HOME}/Makefile",
        LIB,
        APP,
    ]
    for file_path in required_files:
        assert os.path.isfile(file_path), f"Required file {file_path} is missing."


def test_output_txt():
    """Keep the original validation-output assertion."""
    output_path = f"{HOME}/output.txt"
    assert os.path.isfile(output_path), f"File {output_path} is missing. Did the app run successfully?"
    with open(output_path, "r", encoding="utf-8") as f:
        content = f.read().strip()
    expected = "TEST1: VALID\nTEST2: CORRECT_NO_SOLUTION"
    assert content == expected, (
        f"Output file content is incorrect.\nExpected:\n{expected}\n\nGot:\n{content}"
    )


def _without_comments_and_literals(source):
    source = re.sub(r"/\*.*?\*/", " ", source, flags=re.S)
    source = re.sub(r"//[^\n]*", " ", source)
    source = re.sub(r'R\"[^\n]*?\(.*?\)[^\n]*?\"', '""', source, flags=re.S)
    source = re.sub(r'"(?:\\.|[^"\\])*"', '""', source)
    source = re.sub(r"'(?:\\.|[^'\\])*'", "''", source)
    return source


def test_solver_source_has_required_implementation_structure():
    """Check for the requested C ABI, custom adjacency type, and backtracking state undo."""
    path = f"{HOME}/solver.cpp"
    source = open(path, "r", encoding="utf-8", errors="replace").read()
    assert re.search(r'extern\s+"C"\s+int\s+solve_csp\s*\(', source), \
        "solver.cpp does not define solve_csp with the required C ABI."

    code = _without_comments_and_literals(source)
    assert re.search(r"\b(?:class|struct)\s+[A-Za-z_]\w*", code), \
        "solver.cpp must define a custom C++ graph/adjacency data structure."
    assert re.search(r"\b(?:adj(?:acency)?|neighbou?r(?:s)?|edges?)\w*\b", code, re.I), \
        "No adjacency/neighbor/edge storage is evident in the custom solver source."

    # Accept conventionally named backtracking routines, recursive helpers, or
    # explicit assignment undo used by an iterative backtracking implementation.
    has_named_backtracking = bool(re.search(r"\bbacktrack\w*\b", code, re.I))
    definitions = re.findall(
        r"\b(?:bool|int|void|auto|long|short|size_t)\s+([A-Za-z_]\w*)\s*\([^;{}]*\)\s*\{",
        code,
    )
    has_recursive_helper = any(
        len(re.findall(r"\b" + re.escape(name) + r"\s*\(", code)) >= 3
        for name in definitions if name != "solve_csp"
    )
    has_explicit_undo = bool(re.search(
        r"(?:assign\w*|colors?|workers?)\s*\[[^\]]+\]\s*=\s*-1\s*;", code, re.I
    ))
    assert has_named_backtracking or has_recursive_helper or has_explicit_undo, \
        "solver.cpp does not show a backtracking search or assignment undo."


def test_makefile_rebuilds_required_artifacts():
    """Build the submitted sources rather than trusting pre-existing artifacts."""
    os.remove(APP)
    os.remove(LIB)
    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)
    result = subprocess.run(
        ["make", "-B"], cwd=HOME, env=env, capture_output=True, text=True, timeout=60
    )
    assert result.returncode == 0, f"make -B failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(APP), "Makefile did not produce /home/user/app."
    assert os.path.isfile(LIB), "Makefile did not produce /home/user/libsolver.so."
    assert os.access(APP, os.X_OK), "/home/user/app is not executable."
    for path in (APP, LIB):
        with open(path, "rb") as f:
            assert f.read(4) == b"\x7fELF", f"{path} is not an ELF artifact."


def test_dynamic_linking_and_rpath():
    """Keep the original dynamic dependency and rpath assertions."""
    assert os.path.isfile(APP), f"Executable {APP} is missing."
    try:
        result = subprocess.run(
            ["readelf", "-d", APP], capture_output=True, text=True, check=True
        )
    except FileNotFoundError:
        pytest.fail("readelf command not found. Cannot verify dynamic linking.")
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to run readelf on app. Error: {e.stderr}")

    output = result.stdout
    assert "libsolver.so" in output, "The executable 'app' is not dynamically linked to libsolver.so."

    has_valid_rpath = False
    for line in output.splitlines():
        if "(RPATH)" in line or "(RUNPATH)" in line:
            if "." in line or "/home/user" in line or "$ORIGIN" in line:
                has_valid_rpath = True
                break
    assert has_valid_rpath, (
        "The executable 'app' does not have a valid RPATH or RUNPATH pointing to "
        "the current directory (e.g., '.', '/home/user', or '$ORIGIN').\n"
        f"readelf output:\n{output}"
    )


def test_app_execution_succeeds():
    """Run the rebuilt app without LD_LIBRARY_PATH and validate its fresh output."""
    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)
    try:
        result = subprocess.run(
            [APP], env=env, cwd=HOME, capture_output=True, text=True, timeout=15
        )
        assert result.returncode == 0, (
            f"Running {APP} failed with return code {result.returncode}.\nStderr: {result.stderr}"
        )
    except Exception as e:
        pytest.fail(f"Failed to execute {APP}: {e}")

    with open(f"{HOME}/output.txt", "r", encoding="utf-8") as f:
        content = f.read().strip()
    assert content == "TEST1: VALID\nTEST2: CORRECT_NO_SOLUTION"


def _is_colorable(num_tasks, num_workers, edges):
    neighbors = [set() for _ in range(num_tasks)]
    for u, v in edges:
        neighbors[u].add(v)
        neighbors[v].add(u)
    order = sorted(range(num_tasks), key=lambda x: len(neighbors[x]), reverse=True)
    assigned = [-1] * num_tasks

    def search(pos):
        if pos == num_tasks:
            return True
        task = order[pos]
        forbidden = {assigned[n] for n in neighbors[task] if assigned[n] >= 0}
        for worker in range(num_workers):
            if worker not in forbidden:
                assigned[task] = worker
                if search(pos + 1):
                    return True
                assigned[task] = -1
        return False

    return search(0)


def test_shared_library_solves_generated_csp_instances():
    """Call the submitted C ABI directly on generated cases with independently derived answers."""
    cases = [
        (1, 1, []),
        (2, 1, [(0, 1)]),
        (5, 2, [(0, 1), (1, 2), (2, 3), (3, 4), (4, 0)]),
        (6, 2, [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 0)]),
        (5, 4, [(i, j) for i in range(5) for j in range(i + 1, 5)]),
        (5, 5, [(i, j) for i in range(5) for j in range(i + 1, 5)]),
    ]

    rng = random.SystemRandom()
    for _ in range(48):
        n = rng.randrange(2, 10)
        workers = rng.randrange(1, min(5, n) + 1)
        density = rng.choice((0.12, 0.27, 0.43, 0.61, 0.78))
        edges = [
            (i, j) for i in range(n) for j in range(i + 1, n)
            if rng.random() < density
        ]
        cases.append((n, workers, edges))

    expected = [_is_colorable(n, w, edges) for n, w, edges in cases]
    payload = [
        {"n": n, "w": w, "edges": edges}
        for n, w, edges in cases
    ]

    helper = r'''
import ctypes, json, sys
lib = ctypes.CDLL("/home/user/libsolver.so")
solve = lib.solve_csp
solve.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.POINTER(ctypes.c_int), ctypes.c_int, ctypes.POINTER(ctypes.c_int)]
solve.restype = ctypes.c_int
results = []
for case in json.load(sys.stdin):
    flat = [x for edge in case["edges"] for x in edge]
    conflicts = (ctypes.c_int * len(flat))(*flat)
    assignments = (ctypes.c_int * case["n"])(*([-777] * case["n"]))
    result = solve(case["n"], case["w"], conflicts, len(case["edges"]), assignments)
    results.append({"result": int(result), "assignments": list(assignments)})
json.dump(results, sys.stdout)
'''
    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)
    proc = subprocess.run(
        ["python3", "-c", helper], input=json.dumps(payload), text=True,
        capture_output=True, env=env, timeout=25
    )
    assert proc.returncode == 0, (
        "Direct invocation of libsolver.so failed or crashed.\n"
        f"stdout: {proc.stdout}\nstderr: {proc.stderr}"
    )
    try:
        actual = json.loads(proc.stdout)
    except Exception as exc:
        pytest.fail(f"Solver helper returned invalid output: {exc}: {proc.stdout!r}")
    assert len(actual) == len(cases)

    for index, ((n, workers, edges), can_solve, answer) in enumerate(zip(cases, expected, actual)):
        result = answer["result"]
        assignments = answer["assignments"]
        assert result in (0, 1), f"Case {index}: solve_csp returned {result}, not 0 or 1."
        assert bool(result) == can_solve, (
            f"Case {index}: wrong satisfiability result for n={n}, workers={workers}, edges={edges}."
        )
        if result:
            assert len(assignments) == n
            assert all(0 <= value < workers for value in assignments), (
                f"Case {index}: assignment contains an invalid worker ID: {assignments}"
            )
            assert all(assignments[u] != assignments[v] for u, v in edges), (
                f"Case {index}: assignment violates a conflict: {assignments}, edges={edges}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
