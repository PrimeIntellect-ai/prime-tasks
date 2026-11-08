#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import subprocess

import pytest

PROCESSOR_DIR = "/home/user/processor"


def run(cmd, cwd=PROCESSOR_DIR, env=None):
    return subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True, check=True)


def go_slice(values):
    return "[]string{" + ", ".join(json.dumps(v) for v in values) + "}"


def test_vendored_package_fixed():
    version_go_path = "/app/semver/version.go"
    assert os.path.isfile(version_go_path), f"File missing: {version_go_path}"
    with open(version_go_path, "r") as f:
        content = f.read()
    assert "package semver" in content, "The typo 'pacakge semver' was not fixed to 'package semver' in /app/semver/version.go"
    assert "pacakge semver" not in content, "The typo 'pacakge semver' is still present in /app/semver/version.go"


def test_local_dependency_configuration():
    assert os.path.isdir(PROCESSOR_DIR), f"Directory missing: {PROCESSOR_DIR}"
    try:
        mod = json.loads(run(["go", "mod", "edit", "-json"]).stdout)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Could not parse go.mod:\n{e.stdout}\n{e.stderr}")

    requires = {entry["Path"]: entry["Version"] for entry in mod.get("Require", [])}
    assert requires.get("github.com/Masterminds/semver/v3") == "v3.2.1", \
        "go.mod must require github.com/Masterminds/semver/v3 v3.2.1"

    replacements = mod.get("Replace") or []
    matching = [r for r in replacements if r.get("Old", {}).get("Path") == "github.com/Masterminds/semver/v3"]
    assert len(matching) == 1, "go.mod must contain a replace directive for github.com/Masterminds/semver/v3"
    new = matching[0].get("New", {})
    assert new.get("Path") == "/app/semver" and not new.get("Version"), \
        "github.com/Masterminds/semver/v3 must be replaced by the local /app/semver directory"

    env = os.environ.copy()
    env.update({"GOPROXY": "off", "GOSUMDB": "off", "GOWORK": "off"})
    try:
        info = json.loads(run(
            ["go", "list", "-m", "-json", "github.com/Masterminds/semver/v3"], env=env
        ).stdout)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"The project cannot resolve the dependency with network access disabled:\n{e.stdout}\n{e.stderr}")

    assert os.path.realpath(info.get("Dir", "")) == os.path.realpath("/app/semver"), \
        f"semver resolved from {info.get('Dir')!r}, not /app/semver"


def test_filter_versions_correctness_and_independent_benchmark():
    token = secrets.token_hex(8)
    test_name = "TestVerifier" + token
    bench_name = "BenchmarkVerifier" + token
    test_path = os.path.join(PROCESSOR_DIR, f"verifier_{token}_test.go")

    rng = random.SystemRandom()
    cases = []
    for _ in range(8):
        major = rng.randint(1, 8)
        low_minor = rng.randint(2, 15)
        high_minor = low_minor + rng.randint(2, 8)
        low_patch = rng.randint(0, 15)
        versions = []
        expected = []
        for _ in range(30):
            m = rng.choice([major - 1, major, major + 1])
            n = rng.randint(0, high_minor + 5)
            p = rng.randint(0, 20)
            prefix = "v" if rng.randrange(4) == 0 else ""
            suffix = f"+build.{rng.randint(1, 99)}" if rng.randrange(5) == 0 else ""
            value = f"{prefix}{m}.{n}.{p}{suffix}"
            versions.append(value)
            if (m, n, p) >= (major, low_minor, low_patch) and (m, n, p) < (major, high_minor, 0):
                expected.append(value)
        versions.insert(rng.randrange(len(versions) + 1), "not-a-version-" + secrets.token_hex(3))
        constraint = f">= {major}.{low_minor}.{low_patch}, < {major}.{high_minor}.0"
        cases.append((versions, constraint, expected))

    # These cases exercise prerelease handling, build metadata, v-prefixes,
    # compatible-release ranges, OR constraints, malformed versions, and order preservation.
    cases.extend([
        (["1.2.3", "1.5.0-alpha.1", "1.5.0", "v1.7.2", "1.9.9+build.4", "2.0.0", "bad"],
         ">= 1.5.0, < 2.0.0",
         ["1.5.0", "v1.7.2", "1.9.9+build.4"]),
        (["1.4.1", "1.4.2", "1.4.99", "1.5.0", "2.0.0", "2.0.8", "2.1.0"],
         "~1.4.2 || >= 2.0.0, < 2.1.0",
         ["1.4.2", "1.4.99", "2.0.0", "2.0.8"]),
    ])

    case_literals = []
    for versions, constraint, expected in cases:
        case_literals.append(
            "\t\t{" + go_slice(versions) + ", " + json.dumps(constraint) + ", " + go_slice(expected) + "},"
        )

    source = f'''package main

import "testing"

func verifierEqual{token}(a, b []string) bool {{
    if len(a) != len(b) {{ return false }}
    for i := range a {{ if a[i] != b[i] {{ return false }} }}
    return true
}}

func {test_name}(t *testing.T) {{
    cases := []struct {{
        versions []string
        constraint string
        expected []string
    }}{{
{chr(10).join(case_literals)}
    }}
    for i, tc := range cases {{
        got, err := FilterVersions(tc.versions, tc.constraint)
        if err != nil {{
            t.Fatalf("case %d returned unexpected error: %v", i, err)
        }}
        if !verifierEqual{token}(got, tc.expected) {{
            t.Fatalf("case %d: got %#v, expected %#v", i, got, tc.expected)
        }}
    }}
    if _, err := FilterVersions([]string{{}}, ">= definitely-not-semver"); err == nil {{
        t.Fatal("an invalid constraint must return an error even when the version list is empty")
    }}
}}

var verifierSink{token} []string
var verifierErr{token} error

func {bench_name}(b *testing.B) {{
    versions := make([]string, 100)
    for i := 0; i < 100; i++ {{
        versions[i] = "1." + verifierItoa{token}(i) + ".0"
    }}
    b.ResetTimer()
    for i := 0; i < b.N; i++ {{
        verifierSink{token}, verifierErr{token} = FilterVersions(versions, ">= 1.50.0")
    }}
}}

func verifierItoa{token}(n int) string {{
    if n == 0 {{ return "0" }}
    var buf [20]byte
    i := len(buf)
    for n > 0 {{
        i--
        buf[i] = byte('0' + n%10)
        n /= 10
    }}
    return string(buf[i:])
}}
'''

    with open(test_path, "x") as f:
        f.write(source)

    try:
        env = os.environ.copy()
        env.update({"GOPROXY": "off", "GOSUMDB": "off", "GOWORK": "off"})
        try:
            result = run([
                "go", "test",
                "-run", f"^{test_name}$",
                "-bench", f"^{bench_name}$",
                "-benchtime=10000x",
                "-count=1",
            ], env=env)
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Independent correctness tests or benchmark failed:\n{e.stdout}\n{e.stderr}")

        match = re.search(rf'{re.escape(bench_name)}.*?\s+\d+\s+([\d.]+)\s+ns/op', result.stdout)
        assert match is not None, f"Could not find independent ns/op metric in output:\n{result.stdout}"
        ns_op = float(match.group(1))
        assert ns_op <= 10000.0, \
            f"Independent FilterVersions benchmark took {ns_op} ns/op, exceeding 10000 ns/op"
    finally:
        try:
            os.remove(test_path)
        except FileNotFoundError:
            pass


def test_benchmark_performance():
    processor_dir = "/home/user/processor"
    assert os.path.isdir(processor_dir), f"Directory missing: {processor_dir}"

    try:
        result = subprocess.run(
            ["go", "test", "-bench=BenchmarkFilterVersions", "-benchtime=10000x"],
            cwd=processor_dir,
            capture_output=True,
            text=True,
            check=True
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"go test failed to run or compile. Output:\n{e.stdout}\n{e.stderr}")

    output = result.stdout
    match = re.search(r'BenchmarkFilterVersions.*?\s+\d+\s+([\d.]+)\s+ns/op', output)
    assert match is not None, f"Could not find ns/op metric in benchmark output:\n{output}"

    ns_op = float(match.group(1))
    threshold = 10000.0
    assert ns_op <= threshold, f"Benchmark execution time {ns_op} ns/op is greater than threshold {threshold} ns/op. Optimization is insufficient."


def test_cross_compiled_binaries():
    amd64_path = "/home/user/processor/build/processor-amd64"
    arm64_path = "/home/user/processor/build/processor-arm64"

    assert os.path.isfile(amd64_path), f"Binary missing: {amd64_path}"
    assert os.path.isfile(arm64_path), f"Binary missing: {arm64_path}"

    try:
        amd64_file = subprocess.run(["file", amd64_path], capture_output=True, text=True, check=True).stdout
        arm64_file = subprocess.run(["file", arm64_path], capture_output=True, text=True, check=True).stdout
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to run 'file' command on binaries. Error:\n{e.stderr}")

    assert "x86-64" in amd64_file, f"Expected x86-64 architecture for {amd64_path}, got: {amd64_file}"
    assert "aarch64" in arm64_file, f"Expected aarch64 architecture for {arm64_path}, got: {arm64_file}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
