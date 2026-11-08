#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import secrets
import subprocess


def test_etl_go_exists():
    etl_go_path = "/home/user/etl.go"
    assert os.path.exists(etl_go_path), f"File {etl_go_path} is missing."
    assert os.path.isfile(etl_go_path), f"Path {etl_go_path} is not a file."


def test_clean_data_exists_and_content():
    clean_data_path = "/home/user/clean_data.csv"

    assert os.path.exists(clean_data_path), f"File {clean_data_path} is missing. The Go script might not have been run or failed to produce output."
    assert os.path.isfile(clean_data_path), f"Path {clean_data_path} is not a file."

    expected_content = (
        "metric_A,metric_C\n"
        "1.0,1.0\n"
        "2.0,0.0\n"
        "4.0,0.0\n"
        "5.0,1.0"
    )

    with open(clean_data_path, "r") as f:
        content = f.read().strip()

    assert content == expected_content, f"Content of {clean_data_path} does not match the expected final state. Expected:\n{expected_content}\nGot:\n{content}"


def correlation(a, b):
    ma = sum(a) / len(a)
    mb = sum(b) / len(b)
    da = [x - ma for x in a]
    db = [x - mb for x in b]
    denom = math.sqrt(sum(x * x for x in da) * sum(y * y for y in db))
    assert denom != 0
    return sum(x * y for x, y in zip(da, db)) / denom


def expected_output(header, rows):
    clean = [row for row in rows if all(value != "NA" and value != "" for value in row)]
    numeric = [[float(value) for value in row] for row in clean]
    columns = [[row[i] for row in numeric] for i in range(len(header))]

    keep = []
    for current in range(len(header)):
        drop = any(abs(correlation(columns[earlier], columns[current])) > 0.85
                   for earlier in range(current))
        if not drop:
            keep.append(current)

    lines = [",".join(header[i] for i in keep)]
    for row in numeric:
        lines.append(",".join(f"{row[i]:.1f}" for i in keep))
    return "\n".join(lines)


def make_correlated_case(rng):
    while True:
        n = 14
        x = rng.sample(range(-40, 41), n)
        z = rng.sample(range(-45, 46), n)
        w = rng.sample(range(-50, 51), n)
        b = [3 * value + rng.choice([-1, 0, 1]) for value in x]
        d = [-2 * value + rng.choice([-1, 0, 1]) for value in z]
        cols = [x, b, z, d, w]
        desired = {(0, 1), (2, 3)}
        valid = True
        for i in range(len(cols)):
            for j in range(i + 1, len(cols)):
                value = abs(correlation(cols[i], cols[j]))
                if (i, j) in desired:
                    valid = valid and value > 0.93
                else:
                    valid = valid and value < 0.70
        if valid:
            break

    token = secrets.token_hex(4)
    header = [f"metric_{token}_{i}" for i in range(5)]
    rows = [[f"{cols[c][r]:.1f}" for c in range(5)] for r in range(n)]
    rows.insert(2, ["999.0", "NA", "-999.0", "1998.0", "777.0"])
    rows.insert(9, ["888.0", "1776.0", "", "-5.0", "-777.0"])
    return header, rows


def make_independent_case(rng):
    while True:
        cols = [rng.sample(range(-60, 61), 16) for _ in range(4)]
        if all(abs(correlation(cols[i], cols[j])) < 0.65
               for i in range(4) for j in range(i + 1, 4)):
            break

    token = secrets.token_hex(4)
    header = [f"sensor_{token}_{i}" for i in range(4)]
    rows = [[f"{cols[c][r]:.1f}" for c in range(4)] for r in range(16)]
    rows.insert(0, ["NA", "500.0", "500.0", "500.0"])
    rows.insert(8, ["-500.0", "", "-500.0", "-500.0"])
    return header, rows


def run_case(binary, header, rows):
    raw_path = "/home/user/raw_data.csv"
    output_path = "/home/user/clean_data.csv"
    with open(raw_path, "w", newline="") as f:
        f.write(",".join(header) + "\n")
        for row in rows:
            f.write(",".join(row) + "\n")

    if os.path.exists(output_path):
        os.remove(output_path)

    result = subprocess.run([binary], cwd="/home/user", text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            timeout=15)
    assert result.returncode == 0, f"ETL executable failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    assert os.path.isfile(output_path), "ETL executable did not create /home/user/clean_data.csv"

    with open(output_path, "r") as f:
        actual = f.read().strip()
    expected = expected_output(header, rows)
    assert actual == expected, f"Dynamic ETL result mismatch. Expected:\n{expected}\nGot:\n{actual}"


def test_etl_compiles_and_processes_unseen_inputs():
    binary = f"/tmp/etl_verify_{secrets.token_hex(6)}"
    build = subprocess.run(["go", "build", "-o", binary, "/home/user/etl.go"],
                           text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           timeout=30)
    assert build.returncode == 0, f"etl.go did not compile:\n{build.stdout}\n{build.stderr}"
    assert os.path.isfile(binary) and os.access(binary, os.X_OK), "go build did not produce an executable"

    rng = random.Random(secrets.randbits(128))
    try:
        run_case(binary, *make_correlated_case(rng))
        run_case(binary, *make_independent_case(rng))
    finally:
        if os.path.exists(binary):
            os.remove(binary)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
