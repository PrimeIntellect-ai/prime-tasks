#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import stat
import subprocess
import tempfile

PROCESSOR = "/home/user/processor"
SOURCE = "/home/user/process_metrics.c"


def normalized_file(path):
    with open(path, "r", newline="") as f:
        return [line.strip() for line in f.read().splitlines() if line.strip()]


def expected_lines(rows):
    best = {}
    for timestamp, cpu, memory in rows:
        if cpu < 0 or cpu > 100 or memory < 0:
            continue
        candidate = (cpu, memory)
        if timestamp not in best or candidate > best[timestamp]:
            best[timestamp] = candidate

    assert best, "Verifier-generated cases must contain valid records"
    first = min(best)
    last = max(best)
    valid_times = sorted(best)
    next_valid = {valid_times[i]: valid_times[i + 1] for i in range(len(valid_times) - 1)}

    result = ["timestamp,cpu_usage,memory_mb"]
    previous_valid = None
    for timestamp in range(first, last + 1):
        if timestamp in best:
            cpu, memory = best[timestamp]
            previous_valid = timestamp
        else:
            following = next_valid[previous_valid]
            missing_count = following - previous_valid - 1
            if missing_count <= 5:
                cpu, memory = best[previous_valid]
            else:
                cpu, memory = -1, -1
        result.append(f"{timestamp},{cpu},{memory}")
    return result


def run_case(binary, rows, case_number):
    with tempfile.TemporaryDirectory(prefix=f"metrics_case_{case_number}_") as directory:
        input_path = os.path.join(directory, f"input data {case_number}.csv")
        output_path = os.path.join(directory, f"result data {case_number}.csv")
        with open(input_path, "w", newline="") as f:
            f.write("timestamp,cpu_usage,memory_mb\n")
            for timestamp, cpu, memory in rows:
                f.write(f"{timestamp},{cpu},{memory}\n")

        completed = subprocess.run(
            [binary, input_path, output_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert completed.returncode == 0, (
            f"{binary} failed on generated case {case_number}: {completed.stderr}"
        )
        assert os.path.isfile(output_path), (
            f"{binary} did not create the requested output path"
        )
        assert normalized_file(output_path) == expected_lines(rows), (
            f"{binary} produced incorrect output on generated case {case_number}"
        )


def generated_cases():
    # Explicitly exercise the five-missing-second boundary, a larger gap,
    # invalid rows, duplicate CPU values, and memory tie-breaking.
    cases = [[
        (106, 20, 200),
        (100, 10, 100),
        (100, 10, 150),
        (100, 9, 999),
        (113, 30, 300),
        (106, 101, 9999),
        (99, -1, 10),
        (114, 50, -1),
    ]]

    # Use fresh data unknown to the agent while deriving answers independently.
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    for case_number in range(7):
        base = rng.randint(200000, 900000)
        timestamps = [base]
        for _ in range(rng.randint(4, 8)):
            timestamps.append(timestamps[-1] + rng.randint(1, 9))

        rows = []
        for timestamp in timestamps:
            cpu = rng.randint(0, 100)
            memory = rng.randint(0, 10000)
            rows.append((timestamp, cpu, memory))
            rows.append((timestamp, cpu, memory + rng.randint(1, 500)))
            rows.append((timestamp, max(0, cpu - 1), memory + 1000))
            rows.append((timestamp, 101 + rng.randint(0, 20), memory))
            rows.append((timestamp, cpu, -1 - rng.randint(0, 20)))

        # Invalid records outside the valid range must not extend resampling.
        rows.append((base - rng.randint(1, 20), -1, 50))
        rows.append((timestamps[-1] + rng.randint(1, 20), 50, -1))
        rng.shuffle(rows)
        cases.append(rows)
    return cases


def test_processor_executable_exists():
    executable_path = PROCESSOR
    assert os.path.exists(executable_path), f"The executable {executable_path} is missing."
    assert os.path.isfile(executable_path), f"The path {executable_path} is not a file."
    st = os.stat(executable_path)
    assert bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)), (
        f"The file {executable_path} is not executable."
    )
    with open(executable_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The processor must be a compiled executable."


def test_clean_metrics_output():
    output_path = "/home/user/clean_metrics.csv"
    assert os.path.exists(output_path), f"The output file {output_path} is missing."

    expected_output = """timestamp,cpu_usage,memory_mb
1700000000,45,1024
1700000001,45,1024
1700000002,55,1040
1700000003,55,1040
1700000004,55,1040
1700000005,60,2048
1700000006,-1,-1
1700000007,-1,-1
1700000008,-1,-1
1700000009,-1,-1
1700000010,-1,-1
1700000011,-1,-1
1700000012,70,1024
1700000013,70,1024
1700000014,70,1024
1700000015,70,1024
1700000016,15,512"""

    actual_lines = normalized_file(output_path)
    expected = [line.strip() for line in expected_output.splitlines() if line.strip()]
    assert actual_lines == expected, (
        "The generated clean_metrics.csv does not match the expected resampled and deduplicated output."
    )


def test_source_compiles_and_both_artifacts_process_arbitrary_paths():
    assert os.path.exists(SOURCE), f"The C source file {SOURCE} is missing."
    assert os.path.isfile(SOURCE), f"The path {SOURCE} is not a file."

    with tempfile.TemporaryDirectory(prefix="compile_metrics_") as directory:
        rebuilt = os.path.join(directory, "rebuilt_processor")
        compile_result = subprocess.run(
            ["gcc", SOURCE, "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert compile_result.returncode == 0, (
            f"process_metrics.c does not compile with gcc: {compile_result.stderr}"
        )

        cases = generated_cases()
        for binary in (PROCESSOR, rebuilt):
            for case_number, rows in enumerate(cases):
                run_case(binary, rows, case_number)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
