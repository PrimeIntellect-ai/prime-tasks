#!/bin/bash
set -e
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gc
import importlib.util
import json
import os
import subprocess
import sys
import tempfile

PROCESSOR = "/home/user/log_processor.py"
REQUESTS = "/home/user/requests.log"
EXPECTED_CORRUPTED = [142, 888, 2045, 3333, 4999]


def independently_analyze_log():
    corrupted = []
    total = 0
    with open(REQUESTS, "r") as f:
        for line_number, line in enumerate(f, 1):
            try:
                data = json.loads(line)
            except json.JSONDecodeError:
                corrupted.append(line_number)
                continue
            total += data.get("val", 0)
    return corrupted, total


def test_corrupted_lines_file():
    path = "/home/user/corrupted_lines.txt"
    assert os.path.isfile(path), f"Missing required file: {path}"

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [str(n) for n in EXPECTED_CORRUPTED]
    assert lines == expected_lines, f"Expected {path} to contain {expected_lines}, but got {lines}"

    detected, _ = independently_analyze_log()
    assert detected == EXPECTED_CORRUPTED, "The supplied request log no longer has the expected corrupted lines"
    assert lines == [str(n) for n in detected]


def test_final_total_file():
    path = "/home/user/final_total.txt"
    assert os.path.isfile(path), f"Missing required file: {path}"

    _, expected_total = independently_analyze_log()
    with open(path, "r") as f:
        actual_total = f.read().strip()

    assert actual_total == str(expected_total), f"Expected {path} to contain {expected_total}, but got {actual_total}"


def run_processor(input_path):
    result = subprocess.run(
        [sys.executable, PROCESSOR, input_path],
        text=True,
        capture_output=True,
        timeout=20,
    )
    assert result.returncode == 0, result.stderr
    return result.stdout.strip()


def test_log_processor_fixed_and_executable():
    assert os.path.isfile(PROCESSOR), f"Missing required file: {PROCESSOR}"

    with open(PROCESSOR, "r") as f:
        content = f.read()

    # Preserve the original check while also testing actual behavior below.
    assert "failed_requests.append" not in content, "The memory leak is still present: 'failed_requests.append' was found in log_processor.py"

    _, expected_total = independently_analyze_log()
    assert run_processor(REQUESTS) == str(expected_total)

    with tempfile.NamedTemporaryFile("w", delete=False) as f:
        dynamic_path = f.name
        f.write('{"id": 1, "val": 17}\n')
        f.write('{"id": 2, "val": }\n')
        f.write('{"id": 3, "val": 25}\n')
        f.write('not json\n')
    try:
        assert run_processor(dynamic_path) == "42"
    finally:
        os.unlink(dynamic_path)


def test_malformed_input_is_not_retained_unboundedly():
    with tempfile.NamedTemporaryFile("w", delete=False) as f:
        stress_path = f.name
        payload = "x" * 16384
        for _ in range(384):
            f.write("{" + payload + "\n")

    helper = r'''
import gc
import importlib.util
import json
import resource
import sys
import tracemalloc

resource.setrlimit(resource.RLIMIT_AS, (256 * 1024 * 1024, 256 * 1024 * 1024))
processor_path, input_path = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("submitted_log_processor", processor_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
assert callable(getattr(module, "process_file", None)), "log_processor.py must retain its process_file entry point"
tracemalloc.start()
result1 = module.process_file(input_path)
gc.collect()
current1, _ = tracemalloc.get_traced_memory()
result2 = module.process_file(input_path)
result3 = module.process_file(input_path)
gc.collect()
current3, _ = tracemalloc.get_traced_memory()
assert result1 == result2 == result3 == 0
print(json.dumps({"growth": current3 - current1}))
'''
    try:
        result = subprocess.run(
            [sys.executable, "-c", helper, PROCESSOR, stress_path],
            text=True,
            capture_output=True,
            timeout=30,
        )
        assert result.returncode == 0, f"Processor failed under repeated malformed input: {result.stderr}"
        output_lines = [line for line in result.stdout.splitlines() if line.strip()]
        measurement = json.loads(output_lines[-1])
        assert measurement["growth"] < 2 * 1024 * 1024, (
            f"Repeated malformed inputs retained {measurement['growth']} bytes; "
            "failed input appears to be cached without a bound"
        )
    finally:
        os.unlink(stress_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
