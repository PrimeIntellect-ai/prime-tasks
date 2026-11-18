#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import shutil
import subprocess
import tempfile

PROJECT = "/home/user/logprocessor"
BINARY = os.path.join(PROJECT, "bin/logprocessor")


def run(cmd, *, cwd=None, env=None, timeout=15):
    return subprocess.run(
        cmd,
        cwd=cwd,
        env=env,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def go_env():
    env = os.environ.copy()
    env["GOPROXY"] = "direct"
    env["GOSUMDB"] = "off"
    return env


def test_processor_modified_and_behavior():
    processor_path = os.path.join(PROJECT, "processor.go")
    assert os.path.isfile(processor_path), f"File {processor_path} is missing."
    with open(processor_path, "r") as f:
        content = f.read()
    assert "ConvergeMetric" in content

    probe_path = os.path.join(PROJECT, "verifier_probe.go")
    probe = '''package main

import (
    "fmt"
    "math"
    "os"
)

func main() {
    if got := ConvergeMetric(-5.0); got != 0.0 {
        fmt.Fprintf(os.Stderr, "ConvergeMetric(-5.0) = %v, want 0.0\\n", got)
        os.Exit(1)
    }
    if got := ConvergeMetric(25.0); math.Abs(got-5.0) > 0.0001 {
        fmt.Fprintf(os.Stderr, "ConvergeMetric(25.0) = %v, want approximately 5.0\\n", got)
        os.Exit(1)
    }
}
'''
    try:
        with open(probe_path, "w") as f:
            f.write(probe)
        result = run(
            ["go", "run", "processor.go", "verifier_probe.go"],
            cwd=PROJECT,
            env=go_env(),
            timeout=8,
        )
        assert result.returncode == 0, (
            "Direct ConvergeMetric probe failed or did not terminate:\n"
            f"{result.stdout}\n{result.stderr}"
        )
    finally:
        if os.path.exists(probe_path):
            os.remove(probe_path)


def test_test_file_exists_and_passes():
    test_path = os.path.join(PROJECT, "processor_test.go")
    assert os.path.isfile(test_path), f"File {test_path} is missing."

    with open(test_path, "r") as f:
        content = f.read()
    assert "TestConvergeMetric_Negative" in content, "Test function TestConvergeMetric_Negative is missing."
    assert "-5.0" in content or "-5" in content, "Test does not pass -5.0 to ConvergeMetric."
    assert "ConvergeMetric" in content, "Regression test does not call ConvergeMetric."
    assert "t.Errorf" in content, "Regression test must fail with t.Errorf."

    result = run(
        ["go", "test", "-v", "-run", "^TestConvergeMetric_Negative$"],
        cwd=PROJECT,
        env=go_env(),
    )
    assert result.returncode == 0, f"go test failed:\n{result.stdout}\n{result.stderr}"

    # Verify that the supplied regression test actually detects the negative-input bug.
    with tempfile.TemporaryDirectory() as tmp:
        mutant = os.path.join(tmp, "logprocessor")
        shutil.copytree(PROJECT, mutant)
        with open(os.path.join(mutant, "processor.go"), "w") as f:
            f.write('''package main

import "math"

func ConvergeMetric(v float64) float64 {
    if v < 0 {
        return 1.0
    }
    return math.Sqrt(v)
}
''')
        bad = run(
            ["go", "test", "-run", "^TestConvergeMetric_Negative$"],
            cwd=mutant,
            env=go_env(),
        )
        assert bad.returncode != 0, "Regression test passes when negative input incorrectly returns 1.0."


def test_source_builds():
    with tempfile.TemporaryDirectory() as tmp:
        output = os.path.join(tmp, "logprocessor")
        result = run(["go", "build", "-o", output, "."], cwd=PROJECT, env=go_env())
        assert result.returncode == 0, f"go build failed:\n{result.stdout}\n{result.stderr}"
        assert os.path.isfile(output) and os.access(output, os.X_OK)


def test_binary_exists_executable_and_processes_logs():
    assert os.path.isfile(BINARY), f"Compiled binary {BINARY} is missing."
    assert os.access(BINARY, os.X_OK), f"Binary {BINARY} is not executable."

    build_info = run(["go", "version", "-m", BINARY])
    assert build_info.returncode == 0, f"{BINARY} is not a Go executable:\n{build_info.stderr}"

    values = [
        float(secrets.randbelow(80) + 1),
        float(secrets.randbelow(80) + 81),
        -float(secrets.randbelow(100) + 1),
        0.0,
    ]
    expected = sum(math.sqrt(v) if v >= 0 else 0.0 for v in values)
    with tempfile.NamedTemporaryFile("w", delete=False) as log:
        for i, value in enumerate(values):
            log.write(f"ENTRY{i}, {value}\n")
        log.write("MALFORMED\n")
        log.write("ENTRY_BAD, not-a-number\n")
        log_path = log.name
    try:
        result = run([BINARY, log_path], timeout=8)
    finally:
        os.unlink(log_path)
    assert result.returncode == 0, f"Binary execution failed:\n{result.stdout}\n{result.stderr}"
    assert result.stdout.strip() == f"{expected:.4f}", (
        f"Binary returned {result.stdout.strip()!r}; expected {expected:.4f} for verifier-generated input."
    )


def test_result_txt_matches_binary_execution():
    result_path = "/home/user/result.txt"
    assert os.path.isfile(result_path), f"File {result_path} is missing."
    with open(result_path, "r") as f:
        content = f.read().strip()

    # Preserve the original expected-production-result assertion.
    assert "14.0000" in content, f"Expected 14.0000 in {result_path}, but got '{content}'"
    assert content == "14.0000", f"Expected exactly 14.0000 in {result_path}, but got '{content}'"

    executed = run([BINARY, "/home/user/data/server.log"], timeout=8)
    assert executed.returncode == 0, f"Production-log execution failed:\n{executed.stdout}\n{executed.stderr}"
    assert executed.stdout.strip() == content, (
        "result.txt does not match the standard output produced by the compiled binary on server.log."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
