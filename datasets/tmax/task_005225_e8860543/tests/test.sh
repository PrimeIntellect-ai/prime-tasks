#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import math
import os
import random
import shutil
import stat
import subprocess
import tempfile
import uuid

import pytest


def assert_bash_script(path):
    assert os.path.isfile(path), f"Error: {path} is missing"
    st = os.stat(path)
    assert st.st_mode & stat.S_IXUSR, f"Error: {path} is not executable"
    with open(path, "rb") as f:
        first_line = f.readline().decode("utf-8", "replace").strip()
    assert first_line.startswith("#!") and "bash" in first_line, f"Error: {path} must be a Bash script"
    syntax = subprocess.run(["bash", "-n", path], capture_output=True, text=True)
    assert syntax.returncode == 0, f"Error: {path} has invalid Bash syntax: {syntax.stderr}"


def expected_search_output(query_path, dataset_path, top_k):
    def norm(v):
        return math.sqrt(sum(x * x for x in v))

    def dot(v1, v2):
        return sum(x * y for x, y in zip(v1, v2))

    with open(query_path, newline="") as f:
        q = [float(x) for x in next(csv.reader(f))]

    docs = []
    with open(dataset_path, newline="") as f:
        for row in csv.reader(f):
            doc_id = row[0]
            v = [float(x) for x in row[1:]]
            sim = dot(q, v) / (norm(q) * norm(v))
            docs.append((doc_id, sim))

    docs.sort(key=lambda x: x[1], reverse=True)
    return "\n".join(f"{doc_id},{sim:.4f}" for doc_id, sim in docs[:top_k])


def run_and_check_search(query_path, dataset_path, top_k):
    cmd = ["/home/user/search.sh", query_path, dataset_path, str(top_k)]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, f"search.sh failed with error: {result.stderr}"
    actual_output = result.stdout.strip()
    expected_output = expected_search_output(query_path, dataset_path, top_k)
    assert actual_output == expected_output, (
        f"Mismatch for top_k={top_k}!\nExpected:\n{expected_output}\nActual:\n{actual_output}"
    )


def test_search_script_exists_and_executable():
    assert_bash_script("/home/user/search.sh")


def test_benchmark_script_exists_and_executable():
    assert_bash_script("/home/user/benchmark.sh")


def test_search_script_output():
    # Keep the original shipped-data assertion.
    run_and_check_search(
        "/home/user/data/query.csv",
        "/home/user/data/dataset.csv",
        3,
    )


def test_search_script_on_unseen_inputs_and_top_k_values():
    rng = random.SystemRandom()
    with tempfile.TemporaryDirectory(prefix="cosine_hidden_") as td:
        for case, (dim, top_k) in enumerate(((3, 1), (5, 2), (8, 7))):
            query = [rng.randint(-9000, 9000) / 10000.0 for _ in range(dim)]
            if all(x == 0 for x in query):
                query[0] = 0.5

            token = uuid.uuid4().hex[:10]
            docs = []
            # Two identical best vectors verify stable tie handling.
            docs.append((f"hidden_{token}_first", list(query)))
            for i in range(11):
                vec = [rng.randint(-9000, 9000) / 10000.0 for _ in range(dim)]
                if all(x == 0 for x in vec):
                    vec[0] = 0.25
                docs.append((f"hidden_{token}_{i:02d}", vec))
            docs.insert(4, (f"hidden_{token}_second", list(query)))

            query_path = os.path.join(td, f"query_{case}.csv")
            dataset_path = os.path.join(td, f"dataset_{case}.csv")
            with open(query_path, "w", newline="") as f:
                csv.writer(f).writerow(query)
            with open(dataset_path, "w", newline="") as f:
                writer = csv.writer(f)
                for doc_id, vec in docs:
                    writer.writerow([doc_id] + vec)

            run_and_check_search(query_path, dataset_path, top_k)


def test_benchmark_script_execution_and_output():
    search_path = "/home/user/search.sh"
    backup_path = f"/tmp/search.sh.backup.{uuid.uuid4().hex}"
    results_path = "/home/user/benchmark_results.csv"

    td = tempfile.mkdtemp(prefix="benchmark_hidden_")
    log_path = os.path.join(td, "calls.log")
    delay_path = os.path.join(td, "delays.txt")

    sizes = [100, 200, 300, 400, 500]
    delays = [0.12, 0.28, 0.44, 0.60, 0.76]
    random.SystemRandom().shuffle(delays)
    delay_by_size = dict(zip(sizes, delays))
    with open(delay_path, "w") as f:
        for size in sizes:
            f.write(f"{size} {delay_by_size[size]:.2f}\n")

    wrapper = r'''#!/bin/bash
set -e
query=$1
dataset=$2
top_k=$3
lines=$(wc -l < "$dataset")
dataset_hash=$(sha256sum "$dataset" | awk '{print $1}')
query_hash=$(sha256sum "$query" | awk '{print $1}')
printf '%s|%s|%s|%s\n' "$lines" "$top_k" "$dataset_hash" "$query_hash" >> "$BENCH_CALL_LOG"
delay=$(awk -v n="$lines" '$1 == n {print $2}' "$BENCH_DELAY_FILE")
[ -n "$delay" ]
sleep "$delay"
i=1
while [ "$i" -le 5 ]; do
    printf 'probe_%s,0.0000\n' "$i"
    i=$((i + 1))
done
'''

    shutil.move(search_path, backup_path)
    try:
        with open(search_path, "w") as f:
            f.write(wrapper)
        os.chmod(search_path, 0o755)
        if os.path.exists(results_path):
            os.remove(results_path)

        env = os.environ.copy()
        env["BENCH_CALL_LOG"] = log_path
        env["BENCH_DELAY_FILE"] = delay_path
        cmd = [
            "/home/user/benchmark.sh",
            "/home/user/data/query.csv",
            "/home/user/data/dataset.csv",
        ]
        result = subprocess.run(
            cmd,
            cwd="/home/user",
            env=env,
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"benchmark.sh failed with error: {result.stderr}"

        assert os.path.isfile(log_path), "benchmark.sh did not invoke search.sh"
        with open(log_path) as f:
            calls = [line.strip().split("|") for line in f if line.strip()]
        assert len(calls) == 5, f"benchmark.sh must invoke search.sh exactly five times; got {len(calls)}"

        with open("/home/user/data/query.csv", "rb") as f:
            expected_query_hash = hashlib.sha256(f.read()).hexdigest()
        with open("/home/user/data/dataset.csv", "rb") as f:
            dataset_lines = f.readlines()

        for index, size in enumerate(sizes):
            assert len(calls[index]) == 4, "Malformed benchmark search invocation record"
            actual_size, actual_top_k, actual_hash, actual_query_hash = calls[index]
            assert actual_size == str(size), f"Expected subset of {size} lines, got {actual_size}"
            assert actual_top_k == "5", f"Expected top_k=5, got {actual_top_k}"
            expected_hash = hashlib.sha256(b"".join(dataset_lines[:size])).hexdigest()
            assert actual_hash == expected_hash, f"The {size}-line subset is not the first {size} dataset lines"
            assert actual_query_hash == expected_query_hash, "benchmark.sh passed the wrong query to search.sh"

        assert os.path.isfile(results_path), f"Error: {results_path} not found"
        with open(results_path) as f:
            lines = [line.strip() for line in f if line.strip()]

        assert len(lines) == 5, f"Error: {results_path} should have exactly 5 lines, found {len(lines)}"
        expected_lines = ["100", "200", "300", "400", "500"]
        for i, line in enumerate(lines):
            parts = line.split(",")
            assert len(parts) == 2, f"Error: Line {i+1} in {results_path} is not properly comma-separated"
            assert parts[0] == expected_lines[i], (
                f"Error: Expected line {i+1} to start with {expected_lines[i]}, got {parts[0]}"
            )
            try:
                measured = float(parts[1])
            except ValueError:
                pytest.fail(f"Error: Execution time '{parts[1]}' on line {i+1} is not a valid float")
            assert math.isfinite(measured) and measured >= 0, "Execution time must be a finite nonnegative number"
            injected = delay_by_size[int(parts[0])]
            assert injected - 0.035 <= measured <= injected + 0.30, (
                f"Timing {measured} for {parts[0]} lines does not reflect the measured search.sh runtime"
            )
    finally:
        if os.path.exists(search_path):
            os.remove(search_path)
        shutil.move(backup_path, search_path)
        shutil.rmtree(td, ignore_errors=True)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
