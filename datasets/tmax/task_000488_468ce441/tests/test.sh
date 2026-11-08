#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess

BASE = "/home/user/perf_task"
PROCESSOR = os.path.join(BASE, "fast_processor")
SOURCE = os.path.join(BASE, "slow_processor.c")


def test_fast_processor_exists():
    assert os.path.isfile(PROCESSOR), f"Expected {PROCESSOR} to exist as a file."
    assert os.access(PROCESSOR, os.X_OK), f"Expected {PROCESSOR} to be executable."
    with open(PROCESSOR, "rb") as f:
        assert f.read(4) == b"\x7fELF", "fast_processor must be a compiled executable."


def test_source_uses_uint64_and_constant_time_metric():
    assert os.path.isfile(SOURCE), f"Expected {SOURCE} to exist."
    with open(SOURCE, "r", encoding="utf-8") as f:
        source = f.read()

    uncommented = re.sub(r"/\*.*?\*/|//[^\n]*", "", source, flags=re.S)
    assert re.search(r"\buint64_t\s+val\b", uncommented), (
        "The parsed log value must use uint64_t."
    )

    match = re.search(
        r"\bcompute_metric\s*\(([^)]*)\)\s*\{", uncommented, flags=re.S
    )
    assert match, "Expected a compute_metric function definition."
    assert re.search(r"\buint64_t\b", match.group(1)), (
        "compute_metric must accept the value using uint64_t."
    )

    start = match.end() - 1
    depth = 0
    end = None
    for index in range(start, len(uncommented)):
        if uncommented[index] == "{":
            depth += 1
        elif uncommented[index] == "}":
            depth -= 1
            if depth == 0:
                end = index
                break
    assert end is not None, "Could not parse the compute_metric function body."
    body = uncommented[start + 1:end]
    assert not re.search(r"\b(for|while)\s*\(|\bdo\s*\{", body), (
        "compute_metric must use an O(1) formula, not an iteration loop."
    )
    assert not re.search(r"\bcompute_metric\s*\(", body), (
        "compute_metric must not recursively iterate."
    )


def test_fast_processor_behavior_and_performance():
    values = [0, 1, 2, 3, 10, 1000000, 3000000000, 4000000000]
    rng = secrets.SystemRandom()
    values.extend(rng.randrange(0, 4000000001) for _ in range(24))

    input_lines = []
    expected_lines = []
    for i, value in enumerate(values):
        timestamp = f"2024-02-03 12:{i // 60:02d}:{i % 60:02d}"
        service = f"probe{i}"
        input_lines.append(f"{timestamp} [{service}] val={value}")
        metric = value * (value + 1) // 2
        expected_lines.append(f"{timestamp} | {service} | {value} | {metric}")

    try:
        result = subprocess.run(
            [PROCESSOR],
            input="\n".join(input_lines) + "\n",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=3,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        raise AssertionError("fast_processor did not complete in constant time") from exc

    assert result.returncode == 0, (
        f"fast_processor exited with {result.returncode}: {result.stderr}"
    )
    actual_lines = result.stdout.splitlines()
    assert actual_lines == expected_lines, (
        "fast_processor produced incorrect output for generated inputs.\n"
        f"Expected: {expected_lines}\nActual:   {actual_lines}"
    )


def test_original_fuzz_script_passes():
    fuzz_path = os.path.join(BASE, "fuzz_test.sh")
    assert os.path.isfile(fuzz_path), "fuzz_test.sh is missing."
    assert os.access(fuzz_path, os.X_OK), "fuzz_test.sh is not executable."
    try:
        result = subprocess.run(
            ["./fuzz_test.sh", "./fast_processor"],
            cwd=BASE,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=20,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        raise AssertionError("fuzz_test.sh timed out") from exc
    assert result.returncode == 0, f"fuzz_test.sh failed:\n{result.stdout}"
    assert "Fuzz testing passed!" in result.stdout


def test_unified_timeline_content():
    logs_dir = "/home/user/perf_task/logs"
    timeline_path = "/home/user/perf_task/unified_timeline.log"

    assert os.path.isfile(timeline_path), f"Expected {timeline_path} to exist."

    expected_entries = []
    log_pattern = re.compile(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) \[([^\]]+)\] val=(\d+)$")

    # Read and parse all original log files
    for filename in os.listdir(logs_dir):
        if filename.endswith(".log"):
            filepath = os.path.join(logs_dir, filename)
            with open(filepath, "r") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    match = log_pattern.match(line)
                    if match:
                        timestamp, service, val_str = match.groups()
                        val = int(val_str)
                        # Recompute the intent (triangular number sequence)
                        metric = (val * (val + 1)) // 2
                        expected_entries.append((timestamp, service, val, metric))

    # Sort chronologically by timestamp
    expected_entries.sort(key=lambda x: x[0])

    expected_lines = [
        f"{ts} | {svc} | {val} | {metric}"
        for ts, svc, val, metric in expected_entries
    ]

    # Read actual output
    with open(timeline_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in unified_timeline.log, "
        f"but got {len(actual_lines)}."
    )

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, (
            f"Line {i+1} mismatch in unified_timeline.log.\n"
            f"Expected: {expected}\n"
            f"Actual:   {actual}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
