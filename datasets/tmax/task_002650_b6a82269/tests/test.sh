#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "numpy:numpy"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import subprocess
import tempfile

import numpy as np
import pytest

WORKSPACE = "/workspace"
BINARY = "/workspace/process_metrics"
OUTPUT = "/workspace/output.txt"
LOGS = "/workspace/logs.json"
SOURCE = "/workspace/process_metrics.cpp"


def run(command, timeout=30):
    return subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          text=True, timeout=timeout)


def test_vendored_json_builds_parses_and_preserves_double_precision():
    probe_source = r'''
#include <nlohmann/json.hpp>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

static std::uint64_t bits(double value)
{
    std::uint64_t result;
    std::memcpy(&result, &value, sizeof(result));
    return result;
}

int main()
{
    const std::vector<std::string> numbers = {
        "1.2345678901234567e-9",
        "9.876543210987654e-9",
        "0.10000000000000003",
        "123456.78901234567"
    };

    for (const auto& token : numbers)
    {
        const std::string input = "  \n\t" + token + "  \r\n";
        const nlohmann::json parsed = nlohmann::json::parse(input);
        const double actual = parsed.get<double>();
        char* end = nullptr;
        const double expected = std::strtod(token.c_str(), &end);
        if (end == token.c_str() || *end != '\0' || bits(actual) != bits(expected))
        {
            return 10;
        }
    }

    const auto document = nlohmann::json::parse(
        " \n\t [{\"latency\":1.2345678901234567e-9,\"ok\":true},"
        "null,[1,2,3],\"escaped\\ntext\"] \r\n");
    if (!document.is_array() || document.size() != 4 ||
        !document[0]["ok"].get<bool>() || document[2].size() != 3)
    {
        return 11;
    }
    return 0;
}
'''
    with tempfile.TemporaryDirectory() as directory:
        source = os.path.join(directory, "json_probe.cpp")
        binary = os.path.join(directory, "json_probe")
        with open(source, "w") as handle:
            handle.write(probe_source)

        compiled = run([
            "g++", "-std=c++11", "-I/app/json/include", source, "-o", binary
        ])
        assert compiled.returncode == 0, (
            "The vendored JSON headers still fail to compile:\n" + compiled.stderr
        )

        try:
            executed = run([binary], timeout=10)
        except subprocess.TimeoutExpired:
            pytest.fail("The vendored JSON parser hung while consuming valid JSON")
        assert executed.returncode == 0, (
            "The vendored JSON parser failed its parsing/precision probe "
            f"(exit {executed.returncode}). stderr:\n{executed.stderr}"
        )


def test_compile_and_run_process_metrics():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing."
    assert os.path.isfile(LOGS), f"Log file {LOGS} is missing."

    for path in (BINARY, OUTPUT):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    compiled = run([
        "g++", "-std=c++11", "-I/app/json/include", SOURCE, "-o", BINARY
    ])
    assert compiled.returncode == 0, (
        "process_metrics.cpp did not compile with the required command:\n" +
        compiled.stderr
    )
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), (
        "Compilation did not produce an executable /workspace/process_metrics"
    )
    with open(BINARY, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "process_metrics is not a compiled ELF executable"

    original_logs = open(LOGS, "rb").read()
    challenge_tokens = [
        "1.0000000100000001e-9",
        "1.0000000200000000e-9",
        "1.0000000300000001e-9",
        "1.0000000400000000e-9",
        "1.0000000500000001e-9",
        "1.0000000600000000e-9",
        "1.0000000700000001e-9",
        "1.0000000800000000e-9"
    ]
    challenge = "[" + ",".join(
        '{"latency":' + token + "}" for token in challenge_tokens
    ) + "]"
    challenge_error = None

    try:
        with open(LOGS, "w") as handle:
            handle.write(challenge)
        try:
            executed = run([BINARY], timeout=10)
        except subprocess.TimeoutExpired:
            pytest.fail("/workspace/process_metrics hung while parsing logs.json")
        assert executed.returncode == 0, (
            f"process_metrics exited with {executed.returncode}. stderr:\n{executed.stderr}"
        )
        assert os.path.isfile(OUTPUT), "process_metrics did not generate output.txt"

        with open(OUTPUT) as handle:
            challenge_output = float(handle.read().strip())
        values = [float(token) for token in challenge_tokens]
        mean = sum(values) / len(values)
        expected = math.sqrt(sum((value - mean) ** 2 for value in values) / len(values))
        assert math.isfinite(challenge_output)
        assert abs(challenge_output - expected) <= 1e-30, (
            "process_metrics did not preserve double precision on verifier-supplied logs: "
            f"expected {expected}, got {challenge_output}"
        )
    finally:
        with open(LOGS, "wb") as handle:
            handle.write(original_logs)
        try:
            rerun = run([BINARY], timeout=15)
            if rerun.returncode != 0:
                challenge_error = (
                    f"process_metrics failed on the original logs with exit {rerun.returncode}: "
                    + rerun.stderr
                )
        except subprocess.TimeoutExpired:
            challenge_error = "process_metrics hung on the original logs"

    assert challenge_error is None, challenge_error


def test_output_file_exists():
    path = "/workspace/output.txt"
    assert os.path.isfile(path), f"Output file {path} is missing. Did you successfully compile and run the program?"


def test_stddev_accuracy():
    logs_path = "/workspace/logs.json"
    output_path = "/workspace/output.txt"

    assert os.path.isfile(logs_path), f"Log file {logs_path} is missing."
    assert os.path.isfile(output_path), f"Output file {output_path} is missing."

    with open(logs_path, 'r') as f:
        data = json.load(f)

    latencies = [item["latency"] for item in data if "latency" in item]
    assert len(latencies) > 0, "No latencies found in logs.json"

    expected_stddev = np.std(latencies, dtype=np.float64, ddof=0)

    with open(output_path, 'r') as f:
        output_str = f.read().strip()

    try:
        agent_stddev = float(output_str)
    except ValueError:
        pytest.fail(f"Could not parse output in {output_path} as a float. Got: '{output_str}'")

    assert math.isfinite(agent_stddev), f"Output is not finite: {output_str}"
    abs_error = abs(expected_stddev - agent_stddev)

    threshold = 1e-22
    assert abs_error <= threshold, (
        f"Precision loss detected or incorrect calculation! "
        f"Expected stddev: {expected_stddev}, Agent stddev: {agent_stddev}. "
        f"Absolute Error: {abs_error} (Threshold: <= {threshold})"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
