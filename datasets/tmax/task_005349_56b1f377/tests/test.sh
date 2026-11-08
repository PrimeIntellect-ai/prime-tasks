#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile
import time
import uuid


def test_required_artifacts_and_libcsv_usage():
    c_bin = "/home/user/graph_etl"
    c_src = "/home/user/graph_etl.c"
    benchmark = "/home/user/run_benchmark.sh"

    assert os.path.isfile(c_bin), f"Missing compiled C program: {c_bin}"
    assert os.access(c_bin, os.X_OK), f"Program is not executable: {c_bin}"
    assert os.path.isfile(c_src), f"Missing C source: {c_src}"
    assert os.path.isfile(benchmark), f"Missing benchmark script: {benchmark}"

    with open(c_src, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()
    assert re.search(r"#\s*include\s*[<\"]csv\.h[>\"]", source), "graph_etl.c does not include libcsv's csv.h"
    assert re.search(r"\bcsv_(?:init|parse)\s*\(", source), "graph_etl.c does not call libcsv"

    makefile_in = "/app/libcsv-3.0.3/Makefile.in"
    libcsv_c = "/app/libcsv-3.0.3/libcsv.c"
    assert os.path.isfile(makefile_in)
    assert os.path.isfile(libcsv_c)
    with open(makefile_in, "r", encoding="utf-8", errors="replace") as f:
        assert "-wyntax_error_flag" not in f.read(), "The perturbed libcsv compiler flag was not fixed"
    with open(libcsv_c, "r", encoding="utf-8", errors="replace") as f:
        assert "// missing include" not in f.read(), "The missing libcsv include was not restored"

    ldd = subprocess.run(["ldd", c_bin], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    nm = subprocess.run(["nm", "-a", c_bin], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    evidence = ldd.stdout + "\n" + nm.stdout
    assert re.search(r"libcsv|\bcsv_(?:init|parse)\b", evidence), "Compiled program has no evidence of linkage to libcsv"


def test_graph_etl_dynamic_filter_sort_and_pagination():
    c_bin = "/home/user/graph_etl"
    token = uuid.uuid4().hex
    wanted = "Person_" + token
    other = "Company_" + token
    prop = "rank_" + token

    rows = [
        f'201,{wanted},"{{""{prop}"": 3.25, ""note"": ""a,b""}}"',
        f'202,{other},"{{""{prop}"": 999.0}}"',
        f'203,{wanted},"{{""{prop}"": -2}}"',
        f'204,{wanted},"{{""{prop}"": 11.0}}"',
        f'205,{wanted},"{{""{prop}"": 7.5}}"',
        f'206,{wanted},"{{""unrelated"": 100}}"',
    ]

    with tempfile.TemporaryDirectory() as td:
        input_path = os.path.join(td, "input.csv")
        output_path = os.path.join(td, "output.csv")
        with open(input_path, "wb") as f:
            f.write(("\n".join(rows) + "\n").encode("utf-8"))

        subprocess.run([
            c_bin,
            "--input", input_path,
            "--filter-label", wanted,
            "--sort-prop", prop,
            "--limit", "2",
            "--offset", "1",
            "--output", output_path,
        ], check=True, timeout=20)

        assert os.path.isfile(output_path), "C program did not produce the requested output"
        with open(output_path, "rb") as f:
            actual = f.read()
        expected = (rows[3] if False else rows[4]) + "\n" + rows[0] + "\n"
        assert actual == expected.encode("utf-8"), "Filtering, numeric descending sort, pagination, or exact row preservation is incorrect"

        second_output = os.path.join(td, "other.csv")
        subprocess.run([
            c_bin,
            "--input", input_path,
            "--filter-label", other,
            "--sort-prop", prop,
            "--limit", "5",
            "--offset", "0",
            "--output", second_output,
        ], check=True, timeout=20)
        with open(second_output, "rb") as f:
            assert f.read() == (rows[1] + "\n").encode("utf-8"), "Exact label filtering is incorrect"


def test_graph_etl_correctness_and_speedup():
    c_bin = "/home/user/graph_etl"
    py_script = "/home/user/slow_reference.py"
    input_csv = "/home/user/graph_results.csv"

    out_c = "/home/user/output_c.csv"
    out_py = "/home/user/output_py.csv"

    args = [
        "--input", input_csv,
        "--filter-label", "Person",
        "--sort-prop", "score",
        "--limit", "100",
        "--offset", "10"
    ]

    start_py = time.time()
    subprocess.run(["python3", py_script] + args + ["--output", out_py], check=True)
    time_py = time.time() - start_py

    start_c = time.time()
    subprocess.run([c_bin] + args + ["--output", out_c], check=True)
    time_c = time.time() - start_c

    assert os.path.exists(out_c), "C program did not produce the output file."
    assert os.path.exists(out_py), "Python program did not produce the output file."

    with open(out_c, 'r') as f_c, open(out_py, 'r') as f_py:
        c_lines = f_c.read().strip().splitlines()
        py_lines = f_py.read().strip().splitlines()

    assert c_lines == py_lines, "Output of C program does not match Python reference."

    speedup = time_py / time_c if time_c > 0 else float('inf')
    assert speedup >= 5.0, f"Speedup is {speedup:.2f}, which is less than the threshold of 5.0 (C time: {time_c:.4f}s, Py time: {time_py:.4f}s)"


def test_benchmark_script_runs():
    benchmark = "/home/user/run_benchmark.sh"
    subprocess.run(["bash", "-n", benchmark], check=True)
    subprocess.run(["bash", benchmark], cwd="/home/user", check=True, timeout=120)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
