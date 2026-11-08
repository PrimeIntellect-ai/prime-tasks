#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import tempfile


def test_anomaly_time_file():
    anomaly_file = "/home/user/anomaly_time.txt"
    assert os.path.isfile(anomaly_file), f"The file {anomaly_file} does not exist."

    with open(anomaly_file, 'r') as f:
        content = f.read().strip()

    assert content == "[02:00:04]", f"The content of {anomaly_file} is incorrect. Expected '[02:00:04]', got '{content}'."


def test_aggregator_cpp_fixed():
    cpp_path = "/home/user/aggregator.cpp"
    assert os.path.isfile(cpp_path), f"The file {cpp_path} does not exist."

    with open(cpp_path, 'r') as f:
        content = f.read()

    # Preserve the original source-level regression check.
    assert "i = 1;" not in content or "for (size_t i = 0;" in content or "for(size_t i=0;" in content or "for(int i=0;" in content or "for (int i = 0;" in content or "for (auto" in content or "accumulate" in content, \
        "The off-by-one bug in aggregator.cpp does not appear to be fixed correctly."


def test_aggregator_executable_exists():
    exe_path = "/home/user/aggregator"
    assert os.path.isfile(exe_path), f"The compiled executable {exe_path} does not exist."
    assert os.access(exe_path, os.X_OK), f"The file {exe_path} is not executable."
    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"The file {exe_path} is not a compiled executable."


def test_service_b_fixed_log_content():
    log_path = "/home/user/logs/service_b_fixed.log"
    assert os.path.isfile(log_path), f"The file {log_path} does not exist."

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "[01:59:59] 10",
        "[02:00:04] 108",
        "[02:00:09] 20"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {log_path}, but found {len(lines)}."

    for i, expected in enumerate(expected_lines):
        assert lines[i] == expected, f"Line {i+1} in {log_path} is incorrect. Expected '{expected}', got '{lines[i]}'."


def test_source_and_deployed_executable_on_derived_inputs():
    source = "/home/user/aggregator.cpp"
    deployed = "/home/user/aggregator"
    input_path = "/home/user/logs/service_a.log"
    output_path = "/home/user/logs/service_b_fixed.log"

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "aggregator_from_source")
        compile_result = subprocess.run(
            ["g++", "-std=c++17", source, "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, \
            f"The repaired source does not compile:\n{compile_result.stderr}"

        rng = random.SystemRandom()
        start = rng.randrange(0, 24 * 60 * 60 - 40)
        batch_count = rng.randrange(3, 7)
        values = []
        # Make every first item significant so the original skip-first defect is exposed.
        for batch_index in range(batch_count):
            first = rng.randrange(300, 900)
            rest = [rng.randrange(1, 150) for _ in range(4)]
            values.extend([first] + rest)
        # An incomplete trailing batch must not produce an output line.
        values.extend(rng.randrange(1, 900) for _ in range(rng.randrange(1, 5)))

        input_lines = []
        timestamps = []
        for offset, value in enumerate(values):
            second = start + offset
            ts = f"[{second // 3600:02d}:{(second % 3600) // 60:02d}:{second % 60:02d}]"
            timestamps.append(ts)
            input_lines.append(f"{ts} {value}")

        expected = []
        for batch_index in range(batch_count):
            begin = batch_index * 5
            batch = values[begin:begin + 5]
            expected.append(f"{timestamps[begin + 4]} {sum(batch) // 5}")

        original_input = open(input_path, "rb").read()
        output_existed = os.path.exists(output_path)
        original_output = open(output_path, "rb").read() if output_existed else None

        def exercise(executable):
            with open(input_path, "w") as f:
                f.write("\n".join(input_lines) + "\n")
            if os.path.exists(output_path):
                os.remove(output_path)

            result = subprocess.run(
                [executable],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=15,
            )
            assert result.returncode == 0, \
                f"{executable} exited with {result.returncode}: {result.stderr}"
            assert os.path.isfile(output_path), \
                f"{executable} did not generate {output_path}."
            with open(output_path, "r") as f:
                actual = [line.strip() for line in f if line.strip()]
            assert actual == expected, \
                f"{executable} produced incorrect averages. Expected {expected}, got {actual}."

        try:
            exercise(deployed)
            exercise(rebuilt)
        finally:
            with open(input_path, "wb") as f:
                f.write(original_input)
            if output_existed:
                with open(output_path, "wb") as f:
                    f.write(original_output)
            elif os.path.exists(output_path):
                os.remove(output_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
