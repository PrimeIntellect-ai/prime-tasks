#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv

class LCG:
    def __init__(self):
        self.state = 42
    def next_float(self):
        value = self.state / 4294967296.0
        self.state = (1664525 * self.state + 1013904223) & 0xFFFFFFFF
        return value

def percolates(grid):
    stack = [(0, c) for c in range(10) if grid[0][c] == 1]
    visited = set(stack)
    while stack:
        r, c = stack.pop()
        if r == 9:
            return True
        for dr, dc in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
            nr, nc = r + dr, c + dc
            if 0 <= nr < 10 and 0 <= nc < 10:
                if grid[nr][nc] == 1 and (nr, nc) not in visited:
                    visited.add((nr, nc))
                    stack.append((nr, nc))
    return False

def compute_expected_results():
    lcg = LCG()
    p_vals = [0.4, 0.5, 0.55, 0.6]
    p_theos = [0.05, 0.25, 0.50, 0.75]

    expected = []
    for p, p_theo in zip(p_vals, p_theos):
        successes = 0
        for _ in range(100):
            grid = [[0]*10 for _ in range(10)]
            for r in range(10):
                for c in range(10):
                    if lcg.next_float() < p:
                        grid[r][c] = 1
            if percolates(grid):
                successes += 1
        p_sim = successes / 100.0
        abs_error = abs(p_sim - p_theo)
        expected.append((p, p_theo, p_sim, abs_error))
    return expected

def test_results_csv_exists():
    assert os.path.exists("/home/user/results.csv"), "/home/user/results.csv does not exist."
    assert os.path.isfile("/home/user/results.csv"), "/home/user/results.csv is not a file."

def test_results_csv_content():
    expected_data = compute_expected_results()

    with open("/home/user/results.csv", "r") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header is not None, "results.csv is empty."
        assert [h.strip() for h in header] == ["p", "P_theo", "P_sim", "abs_error"], "Header in results.csv is incorrect."

        rows = list(reader)
        assert len(rows) == len(expected_data), f"Expected {len(expected_data)} rows, found {len(rows)}."

        for i, (row, exp) in enumerate(zip(rows, expected_data)):
            exp_p, exp_ptheo, exp_psim, exp_err = exp

            p = float(row[0].strip())
            p_theo = float(row[1].strip())
            p_sim = float(row[2].strip())
            abs_error = float(row[3].strip())

            assert abs(p - exp_p) < 1e-6, f"Row {i+1}: expected p ~ {exp_p}, got {p}"
            assert abs(p_theo - exp_ptheo) < 1e-6, f"Row {i+1}: expected P_theo ~ {exp_ptheo}, got {p_theo}"
            assert abs(p_sim - exp_psim) < 1e-6, f"Row {i+1}: expected P_sim ~ {exp_psim}, got {p_sim}"
            assert abs(abs_error - exp_err) < 1e-6, f"Row {i+1}: expected abs_error ~ {exp_err}, got {abs_error}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
