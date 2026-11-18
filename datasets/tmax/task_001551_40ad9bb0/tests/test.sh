#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import math
import csv
import re
import secrets
import subprocess
import pytest

SRC_DIR = "/home/user/src"
EXE = os.path.join(SRC_DIR, "process_data")


def solve_newton(a, b, c):
    x = 0.0
    for _ in range(100):
        fx = a * math.exp(x) + b * x - c
        if abs(fx) < 1e-6:
            break
        dfx = a * math.exp(x) + b
        x = x - fx / dfx
    return x


def compute_expected_metrics(raw_data, ref_data):
    computed_x = []
    for row in raw_data:
        x = solve_newton(row['a'], row['b'], row['c'])
        computed_x.append(x)

    ref_x = [row['ref_x'] for row in ref_data]
    n = len(computed_x)

    sorted_computed = sorted(computed_x)
    sorted_ref = sorted(ref_x)
    w1 = sum(abs(sc - sr) for sc, sr in zip(sorted_computed, sorted_ref)) / n

    mean_c = sum(computed_x) / n
    mean_r = sum(ref_x) / n
    var_c = sum((x - mean_c) ** 2 for x in computed_x) / (n - 1)
    var_r = sum((x - mean_r) ** 2 for x in ref_x) / (n - 1)
    t_stat = (mean_c - mean_r) / math.sqrt(var_c / n + var_r / n)

    return computed_x, w1, t_stat


def remove_file_for_fresh_run(path):
    if os.path.lexists(path):
        assert os.path.isfile(path) or os.path.islink(path), f"Expected a file at {path}"
        os.unlink(path)


@pytest.fixture(scope="session", autouse=True)
def build_and_run_pipeline():
    remove_file_for_fresh_run(EXE)
    remove_file_for_fresh_run("/home/user/data/processed.csv")
    remove_file_for_fresh_run("/home/user/data/report.txt")

    build = subprocess.run(
        ["make", "-B"], cwd=SRC_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60
    )
    assert build.returncode == 0, f"Makefile build failed:\n{build.stdout}"
    assert os.path.isfile(EXE), "Makefile did not create /home/user/src/process_data"
    assert os.access(EXE, os.X_OK), "process_data is not executable"
    with open(EXE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "process_data is not a compiled executable"

    run = subprocess.run([
        EXE,
        "/home/user/data/raw_data.csv",
        "/home/user/data/ref_states.csv",
        "/home/user/data/processed.csv",
        "/home/user/data/report.txt",
    ], cwd=SRC_DIR, text=True, stdout=subprocess.PIPE,
       stderr=subprocess.STDOUT, timeout=30)
    assert run.returncode == 0, f"process_data failed on the required inputs:\n{run.stdout}"


def test_source_files_exist():
    """Check that the C++ source and Makefile exist."""
    assert os.path.isfile("/home/user/src/pipeline.cpp"), "Missing /home/user/src/pipeline.cpp"
    assert os.path.isfile("/home/user/src/Makefile"), "Missing /home/user/src/Makefile"

    with open("/home/user/src/Makefile", "r") as f:
        makefile_content = f.read()
    assert "g++" in makefile_content, "Makefile does not appear to use g++."
    assert "-O3" in makefile_content, "Makefile must compile with -O3."
    assert "-std=c++17" in makefile_content, "Makefile must compile with -std=c++17."


def test_processed_csv():
    """Verify the computed roots in processed.csv."""
    processed_file = "/home/user/data/processed.csv"
    assert os.path.isfile(processed_file), f"Missing {processed_file}"

    raw_file = "/home/user/data/raw_data.csv"
    raw_data = []
    with open(raw_file, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            raw_data.append({
                'id': int(row['id']),
                'a': float(row['a']),
                'b': float(row['b']),
                'c': float(row['c'])
            })

    expected_x = {row['id']: solve_newton(row['a'], row['b'], row['c']) for row in raw_data}
    seen_ids = []

    with open(processed_file, "r") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["id", "computed_x"], "Header of processed.csv must be 'id,computed_x'"

        for row in reader:
            row_id = int(row['id'])
            assert re.fullmatch(r"[+-]?\d+\.\d{6}", row['computed_x']) is not None, \
                "computed_x values must have exactly 6 decimal places"
            comp_x = float(row['computed_x'])
            assert row_id in expected_x, f"Unexpected id {row_id} in processed.csv"
            assert row_id not in seen_ids, f"Duplicate id {row_id} in processed.csv"
            seen_ids.append(row_id)
            assert math.isclose(comp_x, expected_x[row_id], abs_tol=1e-4), \
                f"Computed x for id {row_id} is {comp_x}, expected {expected_x[row_id]}"

    assert set(seen_ids) == set(expected_x), "processed.csv must contain every expected id"
    assert len(seen_ids) == len(expected_x), "processed.csv must contain exactly one row per input row"


def test_report_metrics():
    """Verify the calculated metrics in report.txt."""
    report_file = "/home/user/data/report.txt"
    assert os.path.isfile(report_file), f"Missing {report_file}"

    raw_file = "/home/user/data/raw_data.csv"
    ref_file = "/home/user/data/ref_states.csv"

    raw_data = []
    with open(raw_file, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            raw_data.append({
                'id': int(row['id']),
                'a': float(row['a']),
                'b': float(row['b']),
                'c': float(row['c'])
            })

    ref_data = []
    with open(ref_file, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            ref_data.append({
                'id': int(row['id']),
                'ref_x': float(row['ref_x'])
            })

    _, expected_w1, expected_t = compute_expected_metrics(raw_data, ref_data)

    with open(report_file, "r") as f:
        content = f.read()

    w1_match = re.search(r"Wasserstein Distance:\s*([+-]?\d*\.\d+)", content)
    assert w1_match is not None, "Could not find 'Wasserstein Distance: <value>' in report.txt"
    w1_val = float(w1_match.group(1))
    assert math.isclose(w1_val, expected_w1, abs_tol=1e-3), \
        f"Wasserstein Distance is {w1_val}, expected ~{expected_w1}"

    t_match = re.search(r"T-Statistic:\s*([+-]?\d*\.\d+)", content)
    assert t_match is not None, "Could not find 'T-Statistic: <value>' in report.txt"
    t_val = float(t_match.group(1))
    assert math.isclose(t_val, expected_t, abs_tol=1e-2), \
        f"T-Statistic is {t_val}, expected ~{expected_t}"

    lines = content.splitlines()
    assert len(lines) == 2, "report.txt must contain exactly the two required lines"
    assert re.fullmatch(r"Wasserstein Distance: [+-]?\d+\.\d{6}", lines[0])
    assert re.fullmatch(r"T-Statistic: [+-]?\d+\.\d{6}", lines[1])


def test_pipeline_on_generated_inputs(tmp_path):
    """Exercise the executable on fresh values whose answers are derived by the verifier."""
    rng = secrets.SystemRandom()
    raw_path = tmp_path / "raw.csv"
    ref_path = tmp_path / "ref.csv"
    processed_path = tmp_path / "processed.csv"
    report_path = tmp_path / "report.txt"

    generated = []
    refs = []
    first_id = rng.randrange(1000, 9000)
    for i in range(7):
        row_id = first_id + 3 * i
        target_x = rng.uniform(-0.30, 1.10)
        a = rng.uniform(0.6, 2.2)
        b = rng.uniform(0.8, 3.0)
        c = a * math.exp(target_x) + b * target_x
        ref_x = target_x + rng.uniform(-0.35, 0.35)
        generated.append((row_id, a, b, c))
        refs.append((row_id, ref_x))

    with open(raw_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "a", "b", "c"])
        for row in generated:
            writer.writerow([row[0], f"{row[1]:.12f}", f"{row[2]:.12f}", f"{row[3]:.12f}"])

    with open(ref_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "ref_x"])
        for row in refs:
            writer.writerow([row[0], f"{row[1]:.12f}"])

    run = subprocess.run(
        [EXE, str(raw_path), str(ref_path), str(processed_path), str(report_path)],
        cwd=SRC_DIR, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        timeout=30
    )
    assert run.returncode == 0, f"process_data failed on generated inputs:\n{run.stdout}"
    assert processed_path.is_file(), "Generated run did not create processed.csv"
    assert report_path.is_file(), "Generated run did not create report.txt"

    raw_data = []
    with open(raw_path) as f:
        for row in csv.DictReader(f):
            raw_data.append({'id': int(row['id']), 'a': float(row['a']),
                             'b': float(row['b']), 'c': float(row['c'])})
    ref_data = []
    with open(ref_path) as f:
        for row in csv.DictReader(f):
            ref_data.append({'id': int(row['id']), 'ref_x': float(row['ref_x'])})

    expected_roots, expected_w1, expected_t = compute_expected_metrics(raw_data, ref_data)
    expected_by_id = {row['id']: x for row, x in zip(raw_data, expected_roots)}

    with open(processed_path) as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["id", "computed_x"]
        rows = list(reader)
    assert len(rows) == len(expected_by_id), "Generated output has the wrong number of rows"
    ids = [int(row['id']) for row in rows]
    assert len(ids) == len(set(ids)), "Generated output contains duplicate ids"
    assert set(ids) == set(expected_by_id), "Generated output is missing or adding ids"
    for row in rows:
        assert re.fullmatch(r"[+-]?\d+\.\d{6}", row['computed_x'])
        row_id = int(row['id'])
        assert math.isclose(float(row['computed_x']), expected_by_id[row_id], abs_tol=2e-6)

    with open(report_path) as f:
        lines = f.read().splitlines()
    assert len(lines) == 2
    w1_match = re.fullmatch(r"Wasserstein Distance: ([+-]?\d+\.\d{6})", lines[0])
    t_match = re.fullmatch(r"T-Statistic: ([+-]?\d+\.\d{6})", lines[1])
    assert w1_match is not None
    assert t_match is not None
    assert math.isclose(float(w1_match.group(1)), expected_w1, abs_tol=2e-6)
    assert math.isclose(float(t_match.group(1)), expected_t, abs_tol=2e-6)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
