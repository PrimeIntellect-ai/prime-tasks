#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pwd
import secrets
import subprocess

import pytest

SOURCE = "/home/user/bootstrap_mcmc.go"
SAMPLES = "/home/user/mcmc_samples.csv"
SUMMARY = "/home/user/posterior_summary.json"
SUBMISSION_BIN = "/tmp/bootstrap_submission"
ORACLE_BIN = "/tmp/bootstrap_oracle"


def test_go_source_file_exists():
    file_path = SOURCE
    assert os.path.exists(file_path), f"The Go source file {file_path} does not exist."
    assert os.path.isfile(file_path), f"The path {file_path} is not a file."
    assert not os.path.islink(file_path), f"The Go source file {file_path} must not be a symlink."


def test_json_output_file_exists():
    file_path = SUMMARY
    assert os.path.exists(file_path), f"The JSON output file {file_path} does not exist."
    assert os.path.isfile(file_path), f"The path {file_path} is not a file."


def test_json_output_contents():
    file_path = SUMMARY

    with open(file_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {file_path} does not contain valid JSON.")

    assert "mean" in data, "The JSON output is missing the 'mean' key."
    assert "ci_lower" in data, "The JSON output is missing the 'ci_lower' key."
    assert "ci_upper" in data, "The JSON output is missing the 'ci_upper' key."

    mean = data["mean"]
    ci_lower = data["ci_lower"]
    ci_upper = data["ci_upper"]

    assert isinstance(mean, (int, float)), f"Expected 'mean' to be a number, got {type(mean)}"
    assert isinstance(ci_lower, (int, float)), f"Expected 'ci_lower' to be a number, got {type(ci_lower)}"
    assert isinstance(ci_upper, (int, float)), f"Expected 'ci_upper' to be a number, got {type(ci_upper)}"

    assert abs(mean - 2.41) < 1e-4, f"Mean incorrect: expected ~2.41, got {mean}"
    assert 1.8 <= ci_lower <= 2.3, f"ci_lower out of expected range (1.8 - 2.3): got {ci_lower}"
    assert 2.5 <= ci_upper <= 3.1, f"ci_upper out of expected range (2.5 - 3.1): got {ci_upper}"


def build_programs():
    build = subprocess.run(
        ["go", "build", "-o", SUBMISSION_BIN, "bootstrap_mcmc.go"],
        cwd="/home/user", text=True, capture_output=True, timeout=60
    )
    assert build.returncode == 0, f"Go source did not compile:\n{build.stdout}\n{build.stderr}"

    dependency_check = subprocess.run(
        ["go", "list", "-deps", "-f", "{{if and (not .Standard) (ne .ImportPath \"command-line-arguments\")}}{{.ImportPath}}{{end}}", "bootstrap_mcmc.go"],
        cwd="/home/user", text=True, capture_output=True, timeout=60
    )
    assert dependency_check.returncode == 0, dependency_check.stderr
    nonstandard = [line for line in dependency_check.stdout.splitlines() if line.strip()]
    assert not nonstandard, f"Non-standard-library dependencies are not allowed: {nonstandard}"

    oracle_source = r'''package main
import (
    "bufio"
    "encoding/json"
    "fmt"
    "math/rand"
    "os"
    "sort"
    "strconv"
    "strings"
)
type result struct {
    Mean float64 `json:"mean"`
    Lower float64 `json:"ci_lower"`
    Upper float64 `json:"ci_upper"`
}
func main() {
    if len(os.Args) != 2 { panic("sample path required") }
    f, err := os.Open(os.Args[1]); if err != nil { panic(err) }
    defer f.Close()
    values := []float64{}
    scanner := bufio.NewScanner(f)
    for scanner.Scan() {
        s := strings.TrimSpace(scanner.Text())
        if s == "" { continue }
        v, err := strconv.ParseFloat(s, 64); if err != nil { panic(err) }
        values = append(values, v)
    }
    if err := scanner.Err(); err != nil { panic(err) }
    if len(values) == 0 { panic("no samples") }
    sum := 0.0
    for _, v := range values { sum += v }
    means := make([]float64, 10000)
    rng := rand.New(rand.NewSource(42))
    for i := 0; i < 10000; i++ {
        resampleSum := 0.0
        for j := 0; j < len(values); j++ {
            resampleSum += values[rng.Intn(len(values))]
        }
        means[i] = resampleSum / float64(len(values))
    }
    sort.Float64s(means)
    out := result{sum / float64(len(values)), means[250], means[9749]}
    if err := json.NewEncoder(os.Stdout).Encode(out); err != nil { panic(err) }
    fmt.Fprint(os.Stderr, "")
}
'''
    oracle_path = "/tmp/bootstrap_oracle.go"
    with open(oracle_path, "w") as f:
        f.write(oracle_source)
    build_oracle = subprocess.run(
        ["go", "build", "-o", ORACLE_BIN, oracle_path],
        text=True, capture_output=True, timeout=60
    )
    assert build_oracle.returncode == 0, build_oracle.stderr


def run_oracle():
    result = subprocess.run(
        [ORACLE_BIN, SAMPLES], text=True, capture_output=True, timeout=20
    )
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


def run_submission():
    if os.path.lexists(SUMMARY):
        os.unlink(SUMMARY)

    account = pwd.getpwnam("user")
    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    result = subprocess.run(
        [SUBMISSION_BIN], cwd="/home/user", env={**os.environ, "HOME": "/home/user"},
        text=True, capture_output=True, timeout=20, preexec_fn=demote
    )
    assert result.returncode == 0, f"Compiled program failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(SUMMARY), "Running the program did not generate posterior_summary.json"
    with open(SUMMARY) as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"Program generated invalid JSON: {exc}")
    for key in ("mean", "ci_lower", "ci_upper"):
        assert key in data, f"Generated JSON is missing {key}"
        assert isinstance(data[key], (int, float)) and not isinstance(data[key], bool), f"{key} must be numeric"
    return data


def assert_matches(actual, expected):
    for key in ("mean", "ci_lower", "ci_upper"):
        assert abs(actual[key] - expected[key]) <= 1e-10, \
            f"{key} is incorrect: expected {expected[key]!r}, got {actual[key]!r}"


def test_compiled_program_implements_seeded_bootstrap():
    build_programs()
    original_samples = open(SAMPLES, "rb").read()
    original_summary = open(SUMMARY, "rb").read() if os.path.isfile(SUMMARY) else None
    try:
        # First require execution to reproduce the supplied data set exactly.
        assert_matches(run_submission(), run_oracle())

        # Unpredictable verification-time data prevents hardcoded plausible output.
        rng = secrets.SystemRandom()
        for size in (11, 37, 83):
            values = []
            for i in range(size):
                value = (rng.randrange(-900000, 1400000) / 10000.0) + (i * i) / 137.0
                if i % 13 == 0:
                    value += rng.choice((-250.125, 310.875))
                values.append(value)
            with open(SAMPLES, "w") as f:
                for value in values:
                    f.write(format(value, ".12g") + "\n")
            expected = run_oracle()
            actual = run_submission()
            assert_matches(actual, expected)
    finally:
        with open(SAMPLES, "wb") as f:
            f.write(original_samples)
        if original_summary is None:
            if os.path.lexists(SUMMARY):
                os.unlink(SUMMARY)
        else:
            with open(SUMMARY, "wb") as f:
                f.write(original_summary)
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
