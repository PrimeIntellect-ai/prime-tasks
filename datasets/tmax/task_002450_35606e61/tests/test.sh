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

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import shutil
import subprocess
import time

import pytest
import requests

BASE = "http://127.0.0.1:8080"


def compute_expected_correlation(csv_path):
    data = []
    with open(csv_path, "r") as f:
        for row in csv.reader(f):
            if row:
                data.append([float(x) for x in row])

    assert data and all(len(row) == 4 for row in data)
    cols = [[row[i] for row in data] for i in range(4)]
    matrix = []
    for x in cols:
        out_row = []
        for y in cols:
            mean_x = sum(x) / len(x)
            mean_y = sum(y) / len(y)
            num = sum((a - mean_x) * (b - mean_y) for a, b in zip(x, y))
            den = math.sqrt(sum((a - mean_x) ** 2 for a in x) *
                            sum((b - mean_y) ** 2 for b in y))
            out_row.append(num / den if den else 0.0)
        matrix.append(out_row)
    return matrix


def get_json(path):
    try:
        response = requests.get(BASE + path, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to {BASE + path}: {exc}")
    assert response.status_code == 200, response.text
    try:
        return response.json()
    except ValueError:
        pytest.fail(f"Response from {path} is not valid JSON")


def assert_matrix(actual, expected):
    assert isinstance(actual, list), "Expected JSON array of arrays"
    assert len(actual) == 4, f"Expected 4 rows, got {len(actual)}"
    for i in range(4):
        assert isinstance(actual[i], list), f"Row {i} is not a list"
        assert len(actual[i]) == 4, f"Expected 4 columns in row {i}"
        for j in range(4):
            assert isinstance(actual[i][j], (int, float))
            assert math.isclose(actual[i][j], expected[i][j], rel_tol=1e-3,
                                abs_tol=1e-3), \
                f"Mismatch at ({i}, {j}): expected {expected[i][j]}, got {actual[i][j]}"


def output_contains_matrix(text, expected):
    numbers = [float(x) for x in re.findall(
        r"(?<![A-Za-z_])[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?", text)]
    wanted = [v for row in expected for v in row]
    # Allow numeric row/column labels between matrix entries, but require all
    # sixteen computed values in order.
    for start in range(len(numbers)):
        if not math.isclose(numbers[start], wanted[0], rel_tol=5e-3, abs_tol=5e-3):
            continue
        pos = start + 1
        ok = True
        for value in wanted[1:]:
            found = False
            for candidate in range(pos, min(pos + 6, len(numbers))):
                if math.isclose(numbers[candidate], value, rel_tol=5e-3, abs_tol=5e-3):
                    pos = candidate + 1
                    found = True
                    break
            if not found:
                ok = False
                break
        if ok:
            return True
    return False


def test_original_correlation_endpoint():
    assert_matrix(get_json("/correlation"), compute_expected_correlation("/app/data.csv"))


def test_original_tune_endpoint():
    data = get_json("/tune")
    assert isinstance(data, dict), "Expected JSON object"
    assert "best_lambda" in data, "Missing 'best_lambda'"
    assert "k_folds" in data, "Missing 'k_folds'"
    assert data["k_folds"] == 5, f"Expected k_folds 5, got {data['k_folds']}"
    assert math.isclose(data["best_lambda"], 0.5, rel_tol=1e-3, abs_tol=1e-3), \
        f"Expected best_lambda 0.5, got {data['best_lambda']}"


def test_c_engine_exists_links_gsl_and_processes_unseen_csv(tmp_path):
    source = "/home/user/engine.c"
    assert os.path.isfile(source) and not os.path.islink(source), \
        "/home/user/engine.c must be a regular C source file"
    assert os.path.getsize(source) > 0, "engine.c is empty"

    binary = tmp_path / "engine"
    build = subprocess.run(
        ["gcc", source, "-O2", "-o", str(binary), "-lgsl", "-lgslcblas", "-lm"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    assert build.returncode == 0, f"engine.c did not compile with GSL:\n{build.stderr}"

    linked = subprocess.run(["ldd", str(binary)], text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            timeout=10)
    assert "libgsl" in linked.stdout, "compiled engine is not linked to GSL"
    symbols = subprocess.run(["nm", "-u", str(binary)], text=True,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             timeout=10)
    assert re.search(r"\bgsl_[A-Za-z0-9_]+", symbols.stdout), \
        "engine does not use any GSL routine"

    hidden_csv = tmp_path / "unseen.csv"
    rows = [
        [0.2, 1.7, 4.1, 2.0], [1.4, 0.3, 3.5, 2.8],
        [2.1, 2.8, 0.4, 4.2], [3.7, 1.1, 2.2, 1.5],
        [4.4, 3.9, 1.3, 5.1], [5.8, 2.0, 4.8, 3.3],
        [6.2, 5.1, 2.7, 6.4], [7.9, 4.0, 5.9, 4.7],
        [8.3, 6.4, 3.0, 7.8], [9.6, 5.3, 7.1, 5.5],
        [10.7, 8.2, 4.6, 9.1], [12.1, 7.0, 8.4, 6.9],
    ]
    with open(hidden_csv, "w", newline="") as f:
        csv.writer(f).writerows(rows)
    expected = compute_expected_correlation(hidden_csv)
    run = subprocess.run([str(binary), str(hidden_csv)], text=True,
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                         timeout=15)
    assert run.returncode == 0, f"engine failed on an unseen CSV:\n{run.stdout}"
    assert output_contains_matrix(run.stdout, expected), \
        f"engine output did not contain the unseen CSV's correlation matrix:\n{run.stdout}"


def test_service_uses_current_csv_and_ocr_configuration(tmp_path):
    data_backup = tmp_path / "data.csv.backup"
    config_backup = tmp_path / "config.png.backup"
    shutil.copy2("/app/data.csv", data_backup)
    shutil.copy2("/app/config.png", config_backup)

    try:
        # This matrix is deliberately different from the image's original data.
        rows = [
            [0, 4, 1, 8], [1, 1, 7, 3], [2, 6, 2, 9], [3, 2, 9, 1],
            [4, 8, 3, 6], [5, 3, 8, 4], [6, 9, 4, 7], [7, 5, 6, 2],
            [8, 11, 5, 10], [9, 7, 10, 5], [10, 13, 0, 12], [11, 10, 11, 0],
        ]
        with open("/app/data.csv", "w", newline="") as f:
            csv.writer(f).writerows(rows)
        expected = compute_expected_correlation("/app/data.csv")
        time.sleep(0.2)
        assert_matrix(get_json("/correlation"), expected)

        # Use perfectly correlated columns so every fold has average correlation
        # 1.0; among the OCR-provided candidates, 0.9 is unambiguously optimal.
        with open("/app/data.csv", "w", newline="") as f:
            writer = csv.writer(f)
            for x in range(1, 13):
                writer.writerow([x, 2*x + 1, 5*x - 3, 0.5*x + 7])
        subprocess.run([
            "convert", "-size", "500x200", "xc:white", "-font", "DejaVu-Sans",
            "-pointsize", "24", "-fill", "black",
            "-draw", "text 10,50 'K_FOLDS=3'",
            "-draw", "text 10,100 'LAMBDA_VALS=0.2,0.9,2.0'",
            "/app/config.png"
        ], check=True, timeout=15)
        time.sleep(0.3)
        tuned = get_json("/tune")
        assert isinstance(tuned, dict)
        assert tuned.get("k_folds") == 3, \
            f"service did not OCR the changed K_FOLDS: {tuned}"
        assert isinstance(tuned.get("best_lambda"), (int, float))
        assert math.isclose(tuned["best_lambda"], 0.9, rel_tol=1e-3, abs_tol=1e-3), \
            f"service did not use the changed OCR lambda grid: {tuned}"
    finally:
        shutil.copy2(data_backup, "/app/data.csv")
        shutil.copy2(config_backup, "/app/config.png")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
