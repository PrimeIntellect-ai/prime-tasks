#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import itertools
import os
import re
import subprocess
import pytest

ROOT = "/home/user/pr_review"
_original_solution = None
_runtime_stdout = None
_build_stdout = None


def setup_module(module):
    global _original_solution, _runtime_stdout, _build_stdout

    solution_path = os.path.join(ROOT, "solution.txt")
    assert os.path.isfile(solution_path), f"{solution_path} does not exist. Did you run the program and redirect output?"
    with open(solution_path, "rb") as f:
        _original_solution = f.read()

    clean = subprocess.run(
        ["make", "clean"], cwd=ROOT, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, timeout=30
    )
    assert clean.returncode == 0, f"make clean failed:\n{clean.stdout}"

    executable = os.path.join(ROOT, "magic_square")
    if os.path.exists(executable):
        os.remove(executable)

    build = subprocess.run(
        ["make"], cwd=ROOT, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, timeout=30
    )
    _build_stdout = build.stdout
    assert build.returncode == 0, f"make failed:\n{build.stdout}"
    assert os.path.isfile(executable), "make did not produce magic_square"
    assert os.access(executable, os.X_OK), "make produced a non-executable magic_square"

    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", "magic_square is not an ELF executable"

    nm = subprocess.run(
        ["nm", executable], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, timeout=10
    )
    assert nm.returncode == 0, f"Could not inspect magic_square symbols:\n{nm.stdout}"
    assert re.search(r"^[0-9a-fA-F]+\s+[Tt]\s+fast_sum$", nm.stdout, re.MULTILINE), \
        "The freshly linked executable does not define the fast_sum routine"

    run = subprocess.run(
        [executable], cwd=ROOT, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=10
    )
    assert run.returncode == 0, f"magic_square exited with status {run.returncode}: {run.stderr.decode(errors='replace')}"
    assert run.stderr == b"", f"magic_square wrote unexpected stderr: {run.stderr.decode(errors='replace')}"
    _runtime_stdout = run.stdout


def first_magic_square():
    for values in itertools.permutations(range(1, 10)):
        grid = [values[0:3], values[3:6], values[6:9]]
        if any(sum(row) != 15 for row in grid):
            continue
        if any(sum(grid[r][c] for r in range(3)) != 15 for c in range(3)):
            continue
        if grid[0][0] + grid[1][1] + grid[2][2] != 15:
            continue
        if grid[0][2] + grid[1][1] + grid[2][0] != 15:
            continue
        return [list(row) for row in grid]
    raise AssertionError("No magic square found")


def test_solution_txt():
    path = "/home/user/pr_review/solution.txt"
    assert os.path.isfile(path), f"{path} does not exist. Did you run the program and redirect output?"

    with open(path, "r") as f:
        content = f.read().strip()

    lines = content.split('\n')
    assert len(lines) == 3, f"solution.txt must contain exactly 3 lines, found {len(lines)}"

    grid = []
    for line in lines:
        parts = line.strip().split()
        assert len(parts) == 3, f"Each line must contain exactly 3 numbers, got: '{line}'"
        try:
            grid.append([int(p) for p in parts])
        except ValueError:
            pytest.fail(f"Could not parse integers from line: '{line}'")

    used = set()
    for row in grid:
        for val in row:
            assert 1 <= val <= 9, f"Value {val} out of range 1-9"
            used.add(val)
    assert len(used) == 9, "Grid must contain all numbers 1-9 exactly once"

    for i in range(3):
        assert sum(grid[i]) == 15, f"Row {i} does not sum to 15"
        assert sum(grid[r][i] for r in range(3)) == 15, f"Column {i} does not sum to 15"

    assert grid[0][0] + grid[1][1] + grid[2][2] == 15, "Main diagonal does not sum to 15"
    assert grid[0][2] + grid[1][1] + grid[2][0] == 15, "Anti-diagonal does not sum to 15"

    expected = [
        [2, 7, 6],
        [9, 5, 1],
        [4, 3, 8]
    ]
    assert expected == first_magic_square(), "Verifier's expected square does not match backtracking order"
    assert grid == expected, f"Expected the first valid magic square {expected}, but got {grid}"


def test_fresh_executable_output_matches_solution():
    saved = _original_solution.decode("utf-8").strip()
    runtime = _runtime_stdout.decode("utf-8").strip()
    assert runtime == saved, "The freshly built executable's stdout does not match the submitted solution.txt"


def test_executable_exists():
    path = "/home/user/pr_review/magic_square"
    assert os.path.isfile(path), f"Executable {path} does not exist. Did you run make?"
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def test_makefile_fixed():
    path = "/home/user/pr_review/Makefile"
    assert os.path.isfile(path), f"Makefile {path} does not exist."
    with open(path, "r") as f:
        content = f.read()

    assert "fast_sum" in content, "Makefile does not appear to include fast_sum.s in the build."


def test_cpp_fixed():
    path = "/home/user/pr_review/magic_square.cpp"
    assert os.path.isfile(path), f"Source file {path} does not exist."
    with open(path, "r") as f:
        content = f.read()

    has_anti_diag = re.search(r'fast_sum\s*\([^)]*grid\[0\]\[2\]', content) or \
                    re.search(r'fast_sum\s*\([^)]*grid\[2\]\[0\]', content)

    assert has_anti_diag, "magic_square.cpp does not appear to contain the anti-diagonal check using fast_sum."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
