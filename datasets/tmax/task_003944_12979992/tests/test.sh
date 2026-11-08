#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import shutil
import stat
import subprocess
import time

import pytest

LOG_FILE = "/home/user/server_logs.jsonl"
SOURCE = "/home/user/analyzer.cpp"
EXE = "/home/user/log_analyzer"
OUTPUT = "/home/user/summary.csv"
BUILD = "/app/build.sh"
BASELINE = "/app/baseline.py"


def run(cmd, timeout=120):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


@pytest.fixture(scope="module", autouse=True)
def preserve_original_log():
    backup = "/tmp/server_logs.original.jsonl"
    assert os.path.isfile(LOG_FILE), f"Log file missing: {LOG_FILE}"
    shutil.copy2(LOG_FILE, backup)
    yield
    shutil.copy2(backup, LOG_FILE)


def test_build_script_fixed_and_rebuilds_source():
    assert os.path.isfile(BUILD), f"Build script missing: {BUILD}"
    assert os.path.isfile(BASELINE), f"Baseline script missing: {BASELINE}"
    assert os.path.isfile(SOURCE), f"C++ source missing: {SOURCE}"
    assert stat.S_ISREG(os.lstat(SOURCE).st_mode) and not os.path.islink(SOURCE), \
        "analyzer.cpp must be a regular source file"

    with open(BUILD, "r", encoding="utf-8") as f:
        build_content = f.read()
    assert "-std=c++11" not in build_content, \
        "Build script still contains the incorrect -std=c++11 flag."
    assert any(flag in build_content for flag in ("-std=c++17", "-std=c++20", "-std=c++2a")), \
        "Build script must be updated to use -std=c++17 or higher."

    with open(SOURCE, "r", encoding="utf-8", errors="replace") as f:
        source_content = f.read()
    assert "simdjson" in source_content and "simdjson.h" in source_content, \
        "analyzer.cpp must include and use the vendored simdjson API"

    # Prove that build.sh actually compiles analyzer.cpp rather than installing an
    # unrelated prebuilt or scripted executable.
    original_source = open(SOURCE, "rb").read()
    try:
        with open(SOURCE, "ab") as f:
            f.write(b"\n#error verifier_source_dependency_probe\n")
        if os.path.lexists(EXE):
            os.remove(EXE)
        bad_build = run(["bash", BUILD])
        assert bad_build.returncode != 0 and not os.path.exists(EXE), \
            "build.sh does not actually compile /home/user/analyzer.cpp"
    finally:
        with open(SOURCE, "wb") as f:
            f.write(original_source)
        if os.path.lexists(EXE):
            os.remove(EXE)

    good_build = run(["bash", BUILD])
    assert good_build.returncode == 0, \
        f"Fixed build script failed. stdout={good_build.stdout!r} stderr={good_build.stderr!r}"
    assert os.path.isfile(EXE), f"Compiled executable missing: {EXE}"
    assert os.access(EXE, os.X_OK), f"File is not executable: {EXE}"
    with open(EXE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "log_analyzer must be a compiled ELF executable"


def read_and_validate_csv(path):
    assert os.path.isfile(path), f"Output CSV missing: {path}"
    with open(path, "r", encoding="utf-8", newline="") as f:
        text = f.read()
    lines = text.splitlines()
    assert lines and lines[0] == "endpoint,count,avg_latency,max_latency", \
        "CSV header must be exactly endpoint,count,avg_latency,max_latency"

    reader = csv.DictReader(lines)
    assert reader.fieldnames == ["endpoint", "count", "avg_latency", "max_latency"]
    rows = list(reader)
    endpoints = [row["endpoint"] for row in rows]
    assert endpoints == sorted(endpoints), "CSV rows are not sorted alphabetically by endpoint"

    four_places = re.compile(r"^-?\d+\.\d{4}$")
    parsed = {}
    for row in rows:
        assert row["endpoint"] not in parsed, "Duplicate endpoint row in output"
        assert re.fullmatch(r"\d+", row["count"] or ""), "Count must be an integer"
        assert four_places.fullmatch(row["avg_latency"] or ""), \
            "Average latency must have exactly four decimal places"
        assert four_places.fullmatch(row["max_latency"] or ""), \
            "Maximum latency must have exactly four decimal places"
        parsed[row["endpoint"]] = (
            int(row["count"]), float(row["avg_latency"]), float(row["max_latency"])
        )
    return parsed


def run_analyzer(lines):
    with open(LOG_FILE, "w", encoding="utf-8") as f:
        for line in lines:
            f.write(line.rstrip("\n") + "\n")
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = run([EXE], timeout=60)
    assert result.returncode == 0, \
        f"Agent C++ executable failed. stdout={result.stdout!r} stderr={result.stderr!r}"
    return read_and_validate_csv(OUTPUT)


def assert_expected(actual, expected):
    assert list(actual) == sorted(expected), "Output endpoints do not match expected endpoints"
    for endpoint, (count, avg, maximum) in expected.items():
        got_count, got_avg, got_max = actual[endpoint]
        assert got_count == count, f"Count mismatch for {endpoint}"
        assert abs(got_avg - avg) < 0.001, f"Average latency mismatch for {endpoint}"
        assert abs(got_max - maximum) < 0.001, f"Maximum latency mismatch for {endpoint}"


def test_behavior_on_unseen_inputs():
    lines = [
        '{"status":200,"endpoint":"/zeta","latency_ms":12.3456}',
        '{"latency_ms":1.0,"endpoint":"/alpha","status":200,"extra":true}',
        '{"status":404,"endpoint":"/alpha","latency_ms":999.0}',
        '{"status":200,"endpoint":"/alpha","latency_ms":2.0}',
        '{"status":"200","endpoint":"/wrong-string-status","latency_ms":3.0}',
        '{"status":200.0,"endpoint":"/wrong-float-status","latency_ms":4.0}',
        '{"endpoint":"/missing-status","latency_ms":5.0}',
        '{"status":200,"latency_ms":6.0}',
        '{"status":200,"endpoint":"/missing-latency"}',
        '{"status":200,"endpoint":123,"latency_ms":7.0}',
        '{"status":200,"endpoint":"/bad-latency","latency_ms":"8.0"}',
        'not valid json',
        '{"status":200,"endpoint":"/zeta","latency_ms":0.6544}'
    ]
    actual = run_analyzer(lines)
    assert_expected(actual, {
        "/alpha": (2, 1.5, 2.0),
        "/zeta": (2, 6.5, 12.3456),
    })

    # A second unrelated input prevents a program from merely emitting constants
    # for either the shipped log or the first test case.
    actual = run_analyzer([
        '{"status":500,"endpoint":"/ignored","latency_ms":1.0}',
        '{"status":200,"endpoint":"/only","latency_ms":3.125}',
        '{"status":200,"endpoint":"/only","latency_ms":4.875}',
        '{"status":201,"endpoint":"/ignored","latency_ms":2.0}'
    ])
    assert_expected(actual, {"/only": (2, 4.0, 4.875)})

    actual = run_analyzer([
        '{"status":404,"endpoint":"/none","latency_ms":1.0}',
        '{"endpoint":"/none","latency_ms":2.0}',
        'broken'
    ])
    assert actual == {}, "No qualifying records should produce only the CSV header"


def test_performance_and_correctness():
    # Generate a fresh, verifier-controlled workload so neither precomputed
    # constants nor modifications to the shipped log can satisfy the test.
    endpoints = ["/api/login", "/api/data", "/api/users", "/api/settings", "/api/checkout"]
    statuses = [200, 200, 200, 404, 500, 403]
    with open(LOG_FILE, "w", encoding="utf-8") as f:
        for i in range(500000):
            endpoint = endpoints[(i * 7 + 3) % len(endpoints)]
            latency = 10.0 + ((i * 37) % 49000) / 100.0
            if i % 101 == 0:
                f.write(f'{{"endpoint":"{endpoint}","latency_ms":{latency:.2f}}}\n')
            elif i % 103 == 0:
                f.write(f'{{"endpoint":"{endpoint}","status":{statuses[i % 6]}}}\n')
            else:
                f.write(f'{{"endpoint":"{endpoint}","status":{statuses[i % 6]},"latency_ms":{latency:.2f}}}\n')

    trusted_baseline = "/tmp/trusted_baseline.py"
    with open(trusted_baseline, "w", encoding="utf-8") as f:
        f.write('''import sys\nimport json\nimport pandas as pd\n\ndef main():\n    input_file, output_file = sys.argv[1], sys.argv[2]\n    data = []\n    with open(input_file, "r") as src:\n        for line in src:\n            try:\n                record = json.loads(line)\n                if record.get("status") == 200 and "endpoint" in record and "latency_ms" in record:\n                    data.append({"endpoint": record["endpoint"], "latency_ms": float(record["latency_ms"])})\n            except Exception:\n                pass\n    df = pd.DataFrame(data)\n    if df.empty:\n        pd.DataFrame(columns=["endpoint","count","avg_latency","max_latency"]).to_csv(output_file, index=False)\n        return\n    summary = df.groupby("endpoint").agg(count=("latency_ms", "count"), avg_latency=("latency_ms", "mean"), max_latency=("latency_ms", "max")).reset_index()\n    summary = summary.sort_values("endpoint")\n    summary["avg_latency"] = summary["avg_latency"].round(4)\n    summary["max_latency"] = summary["max_latency"].round(4)\n    summary.to_csv(output_file, index=False, float_format="%.4f")\n\nif __name__ == "__main__":\n    main()\n''')

    ref_csv = "/tmp/ref.csv"
    start = time.perf_counter()
    baseline_run = run(["python3", trusted_baseline, LOG_FILE, ref_csv], timeout=180)
    base_time = time.perf_counter() - start
    assert baseline_run.returncode == 0, f"Trusted baseline failed: {baseline_run.stderr}"
    reference = read_and_validate_csv(ref_csv)

    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    start = time.perf_counter()
    analyzer_run = run([EXE], timeout=60)
    cpp_time = time.perf_counter() - start
    assert analyzer_run.returncode == 0, f"Agent executable failed: {analyzer_run.stderr}"
    actual = read_and_validate_csv(OUTPUT)

    assert actual.keys() == reference.keys(), "The output endpoints do not match the baseline"
    for endpoint in reference:
        rc, ra, rm = reference[endpoint]
        ac, aa, am = actual[endpoint]
        assert ac == rc, f"Count mismatch for {endpoint}"
        assert abs(aa - ra) < 0.001, f"Average latency mismatch for {endpoint}"
        assert abs(am - rm) < 0.001, f"Maximum latency mismatch for {endpoint}"

    speedup = base_time / cpp_time
    assert speedup >= 5.0, \
        f"Speedup is {speedup:.2f}x (Baseline: {base_time:.3f}s, C++: {cpp_time:.3f}s), threshold is 5.0x"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
