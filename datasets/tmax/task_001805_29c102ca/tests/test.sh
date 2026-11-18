#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import atexit
import math
import os
import random
import resource
import secrets
import subprocess
import sys
import time
import zlib

import pytest

SCRIPT_PATH = "/home/user/build_prep.sh"
LOG_PATH = "/home/user/prep_results.log"
LIBS_PATH = "/home/user/deps/libs.txt"
EXPR_PATH = "/home/user/deps/config.expr"
PAYLOAD_PATH = "/home/user/deps/payload.dat"


def parse_log():
    assert os.path.isfile(LOG_PATH), f"The log file {LOG_PATH} does not exist."
    with open(LOG_PATH, "r") as f:
        log_content = f.read()

    results = {}
    for line in log_content.strip().split("\n"):
        if ":" in line:
            key, val = line.split(":", 1)
            results[key.strip()] = val.strip()
    return results


def test_script_executes_and_generates_correct_results():
    # Preserve the original existence and executable assertions.
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"The script {SCRIPT_PATH} is not executable."

    for path in (LIBS_PATH, EXPR_PATH, PAYLOAD_PATH):
        assert os.path.isfile(path), f"{path} is missing."

    originals = {}
    for path in (LIBS_PATH, EXPR_PATH, PAYLOAD_PATH):
        with open(path, "rb") as f:
            originals[path] = f.read()

    # Use unpredictable inputs so a pre-created fixture log cannot pass.
    base = random.randint(20, 80)
    versions = [
        f"{base}.9.7",
        f"{base + 1}.0.0",
        f"{base}.15.99",
        f"{base + 1}.0.3",
        f"{base - 1}.99.99",
    ]
    random.shuffle(versions)
    expected_version = f"{base + 1}.0.3"

    a = random.randint(300, 900)
    b = random.randint(40, 90)
    c = random.randint(100, 900)
    d = random.randint(1, 99)
    expr = f"{a} * {b} + {c} - {d}"
    expected_buffer_size = str(eval(expr))

    payload_size = 262144 + random.randint(0, 65536)
    payload = secrets.token_bytes(payload_size)
    expected_adler32 = f"{zlib.adler32(payload) & 0xffffffff:08x}"

    # Calibrate the actual work represented by 10,000 Adler-32 operations.
    ref_cpu_start = time.process_time()
    ref_wall_start = time.perf_counter()
    checksum = 0
    for _ in range(10000):
        checksum = zlib.adler32(payload)
    ref_wall = time.perf_counter() - ref_wall_start
    ref_cpu = time.process_time() - ref_cpu_start
    assert checksum & 0xffffffff == int(expected_adler32, 16)

    trace_dir = f"/tmp/build_prep_trace_{secrets.token_hex(8)}"
    os.mkdir(trace_dir)
    trace_file = os.path.join(trace_dir, "zlib_calls")
    with open(os.path.join(trace_dir, "sitecustomize.py"), "w") as f:
        f.write('''import atexit\nimport os\nimport zlib\n_count = 0\n_bytes = 0\n_orig = zlib.adler32\ndef _wrapped(data, *args, **kwargs):\n    global _count, _bytes\n    _count += 1\n    try:\n        _bytes += len(data)\n    except Exception:\n        pass\n    return _orig(data, *args, **kwargs)\nzlib.adler32 = _wrapped\ndef _save():\n    path = os.environ.get("BP_TRACE_FILE")\n    if path:\n        with open(path, "a") as out:\n            out.write(f"{_count} {_bytes}\\n")\natexit.register(_save)\n''')

    try:
        with open(LIBS_PATH, "w") as f:
            f.write("\n".join(versions) + "\n")
        with open(EXPR_PATH, "w") as f:
            f.write(expr + "\n")
        with open(PAYLOAD_PATH, "wb") as f:
            f.write(payload)

        if os.path.exists(LOG_PATH):
            os.remove(LOG_PATH)

        env = os.environ.copy()
        old_pythonpath = env.get("PYTHONPATH")
        env["PYTHONPATH"] = trace_dir if not old_pythonpath else trace_dir + os.pathsep + old_pythonpath
        env["BP_TRACE_FILE"] = trace_file

        before_children = resource.getrusage(resource.RUSAGE_CHILDREN)
        wall_start = time.perf_counter()
        proc = subprocess.run(
            [SCRIPT_PATH],
            cwd="/home/user",
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=120,
        )
        wall_elapsed = time.perf_counter() - wall_start
        after_children = resource.getrusage(resource.RUSAGE_CHILDREN)
        child_cpu = (
            after_children.ru_utime + after_children.ru_stime
            - before_children.ru_utime - before_children.ru_stime
        )

        assert proc.returncode == 0, (
            f"build_prep.sh exited with {proc.returncode}.\n"
            f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
        )
        assert os.path.isfile(LOG_PATH), (
            f"The script did not create {LOG_PATH} when executed."
        )

        results = parse_log()

        # Preserve the original derived-result assertions.
        assert "HIGHEST_VERSION" in results, "HIGHEST_VERSION missing from log."
        assert results["HIGHEST_VERSION"] == expected_version, (
            f"Expected HIGHEST_VERSION {expected_version}, got {results['HIGHEST_VERSION']}."
        )

        assert "BUFFER_SIZE" in results, "BUFFER_SIZE missing from log."
        assert results["BUFFER_SIZE"] == expected_buffer_size, (
            f"Expected BUFFER_SIZE {expected_buffer_size}, got {results['BUFFER_SIZE']}."
        )

        assert "PAYLOAD_ADLER32" in results, "PAYLOAD_ADLER32 missing from log."
        assert results["PAYLOAD_ADLER32"] == expected_adler32, (
            f"Expected PAYLOAD_ADLER32 {expected_adler32}, got {results['PAYLOAD_ADLER32']}."
        )

        assert "BENCHMARK_TIME" in results, "BENCHMARK_TIME missing from log."
        try:
            benchmark_time = float(results["BENCHMARK_TIME"])
        except ValueError:
            pytest.fail(f"BENCHMARK_TIME is not a valid float: {results['BENCHMARK_TIME']}")
        assert math.isfinite(benchmark_time), "BENCHMARK_TIME must be finite."
        assert benchmark_time > 0, "BENCHMARK_TIME must be greater than 0."

        # The reported benchmark and process resource use must be consistent
        # with actually checksumming this large random payload 10,000 times.
        assert benchmark_time >= ref_wall * 0.40, (
            "BENCHMARK_TIME is too small for 10,000 checksum operations."
        )
        assert benchmark_time <= wall_elapsed * 1.5 + 0.1, (
            "BENCHMARK_TIME exceeds the script's observed execution time."
        )
        assert child_cpu >= ref_cpu * 0.60, (
            "The script used too little CPU to perform the required 10,000-iteration benchmark."
        )

        # For standard-library zlib implementations, directly account for the
        # number of Adler-32 calls and bytes processed inside spawned Python.
        if os.path.isfile(trace_file):
            traced_calls = 0
            traced_bytes = 0
            with open(trace_file, "r") as f:
                for line in f:
                    fields = line.split()
                    if len(fields) == 2:
                        traced_calls += int(fields[0])
                        traced_bytes += int(fields[1])
            if traced_calls:
                assert traced_calls >= 10000, (
                    f"Only {traced_calls} zlib.adler32 calls were made; at least 10,000 are required."
                )
                assert traced_bytes >= payload_size * 10000, (
                    "The traced Adler-32 calls did not process the payload 10,000 times."
                )
    finally:
        for path, data in originals.items():
            with open(path, "wb") as f:
                f.write(data)
        if os.path.isdir(trace_dir):
            for name in os.listdir(trace_dir):
                try:
                    os.remove(os.path.join(trace_dir, name))
                except FileNotFoundError:
                    pass
            os.rmdir(trace_dir)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
