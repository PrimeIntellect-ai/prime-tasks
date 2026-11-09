#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import stat
import subprocess
import tempfile
import uuid


def run(cmd, cwd=None, env=None, timeout=120):
    return subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True, timeout=timeout)


def normalized_report():
    path = "/home/user/pipeline/cycle_report.txt"
    assert os.path.exists(path), f"Cycle report missing at {path}"
    with open(path, "r") as f:
        return f.read().strip().replace(" ", "").replace("\n", "")


def test_cycle_report_content():
    """Retain the original assertion for the supplied dependency graph."""
    expected = "mathservice/algebra,mathservice/geometry"
    content = normalized_report()
    assert content == expected, f"Incorrect cycle report. Expected '{expected}', got '{content}'"


def test_cycle_detector_handles_derived_runtime_graphs():
    """Run the submitted detector through CI against unpredictable graphs."""
    deps_path = "/home/user/pipeline/deps.json"
    report_path = "/home/user/pipeline/cycle_report.txt"
    ci_path = "/home/user/run_ci.sh"

    with open(deps_path, "rb") as f:
        original_deps = f.read()
    original_report = None
    if os.path.exists(report_path):
        with open(report_path, "rb") as f:
            original_report = f.read()

    token = uuid.uuid4().hex
    a, b, c, d, e, leaf = [f"node_{token}_{x}" for x in "abcdef"]
    graphs = [
        (
            {
                a: [b, leaf],
                b: [a],
                c: [d],
                d: [e],
                e: [c],
                leaf: [],
            },
            ",".join(sorted([a, b])),
        ),
        (
            {
                a: [b],
                b: [c],
                c: [a, leaf],
                d: [e],
                e: [leaf],
                leaf: [],
            },
            ",".join(sorted([a, b, c])),
        ),
    ]

    try:
        for graph, expected in graphs:
            with open(deps_path, "w") as f:
                json.dump(graph, f)
            if os.path.exists(report_path):
                os.remove(report_path)
            result = run([ci_path], timeout=180)
            assert result.returncode == 0, (
                f"run_ci.sh failed on a generated dependency graph:\n"
                f"Stdout: {result.stdout}\nStderr: {result.stderr}"
            )
            actual = normalized_report()
            assert actual == expected, (
                f"Cycle detector did not derive the unique shortest cycle. "
                f"Expected '{expected}', got '{actual}'"
            )
    finally:
        with open(deps_path, "wb") as f:
            f.write(original_deps)
        if original_report is None:
            if os.path.exists(report_path):
                os.remove(report_path)
        else:
            with open(report_path, "wb") as f:
                f.write(original_report)


def test_go_code_refactored_and_compiles():
    """Retain the original build assertion and verify the requested package structure."""
    service_dir = "/home/user/service"
    assert os.path.isdir(service_dir), f"Service directory missing at {service_dir}"

    build_result = run(["go", "build", "./..."], cwd=service_dir)
    assert build_result.returncode == 0, (
        f"'go build ./...' failed:\nStdout: {build_result.stdout}\nStderr: {build_result.stderr}"
    )

    types_dir = os.path.join(service_dir, "types")
    assert os.path.isdir(types_dir), "Required mathservice/types package is missing"
    type_sources = ""
    for name in os.listdir(types_dir):
        if name.endswith(".go") and not name.endswith("_test.go"):
            with open(os.path.join(types_dir, name), "r") as f:
                type_sources += f.read() + "\n"
    assert re.search(r"\btype\s+Point\s+struct\b", type_sources), "types package must define Point as a struct"
    assert re.search(r"\btype\s+Vector\s+struct\b", type_sources), "types package must define Vector as a struct"

    listing = run(
        ["go", "list", "-f", "{{.ImportPath}}|{{join .Imports \",\"}}", "./algebra", "./geometry"],
        cwd=service_dir,
    )
    assert listing.returncode == 0, listing.stderr
    imports = {}
    for line in listing.stdout.splitlines():
        package, _, package_imports = line.partition("|")
        imports[package] = set(filter(None, package_imports.split(",")))
    assert "mathservice/types" in imports.get("mathservice/algebra", set()), "algebra must import mathservice/types"
    assert "mathservice/types" in imports.get("mathservice/geometry", set()), "geometry must import mathservice/types"
    assert "mathservice/geometry" not in imports.get("mathservice/algebra", set()), "algebra still imports geometry"
    assert "mathservice/algebra" not in imports.get("mathservice/geometry", set()), "geometry still imports algebra"


def test_go_apis_preserve_required_behavior():
    """Compile and execute independent tests against the refactored public APIs."""
    service_dir = "/home/user/service"
    verifier_test = os.path.join(service_dir, "algebra", "zz_verifier_behavior_test.go")
    source = r'''package algebra_test

import (
    "testing"
    "mathservice/algebra"
    "mathservice/geometry"
    "mathservice/types"
)

func TestVerifierSolveAndDistance(t *testing.T) {
    got := algebra.Solve(types.Point{X: 1, Y: 2})
    if got.X != 1 || got.Y != 2 {
        t.Fatalf("Solve returned (%v,%v), want (1,2)", got.X, got.Y)
    }
    if gotDistance := geometry.Distance(types.Vector{X: 3, Y: 4}); gotDistance != 25 {
        t.Fatalf("Distance returned %v, want 25", gotDistance)
    }
}
'''
    assert not os.path.exists(verifier_test)
    try:
        with open(verifier_test, "w") as f:
            f.write(source)
        result = run(["go", "test", "./algebra"], cwd=service_dir)
        assert result.returncode == 0, (
            f"Refactored APIs do not preserve the required behavior:\n"
            f"Stdout: {result.stdout}\nStderr: {result.stderr}"
        )
    finally:
        if os.path.exists(verifier_test):
            os.remove(verifier_test)


def test_go_unit_test_exists_and_passes():
    """Retain the original unit-test assertions and ensure it exercises Solve."""
    service_dir = "/home/user/service"
    test_file_path = os.path.join(service_dir, "algebra/algebra_test.go")
    assert os.path.exists(test_file_path), f"Unit test file missing at {test_file_path}"

    test_result = run(["go", "test", "./..."], cwd=service_dir)
    assert test_result.returncode == 0, (
        f"'go test ./...' failed:\nStdout: {test_result.stdout}\nStderr: {test_result.stderr}"
    )

    listed = run(["go", "test", "-list", "^Test", "./algebra"], cwd=service_dir)
    assert listed.returncode == 0, listed.stderr
    assert any(line.startswith("Test") for line in listed.stdout.splitlines()), "algebra_test.go defines no runnable test"
    with open(test_file_path, "r") as f:
        test_source = f.read()
    assert re.search(r"\bSolve\s*\(", test_source), "algebra_test.go does not call Solve"
    assert "1" in test_source and "2" in test_source and "X" in test_source and "Y" in test_source, (
        "algebra_test.go does not check the requested Point/Vector values"
    )


def test_run_ci_script_executable_and_passes():
    """Retain the original CI assertion and observe both required Go commands."""
    script_path = "/home/user/run_ci.sh"
    assert os.path.exists(script_path), f"CI script missing at {script_path}"
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"CI script at {script_path} is not executable"

    with tempfile.TemporaryDirectory() as wrapper_dir:
        trace_path = os.path.join(wrapper_dir, "go.trace")
        wrapper_path = os.path.join(wrapper_dir, "go")
        with open(wrapper_path, "w") as f:
            f.write("#!/bin/bash\nprintf '%s\\n' \"$*\" >> \"$GO_TRACE_FILE\"\nexec /usr/bin/go \"$@\"\n")
        os.chmod(wrapper_path, 0o755)
        env = os.environ.copy()
        env["PATH"] = wrapper_dir + os.pathsep + env.get("PATH", "")
        env["GO_TRACE_FILE"] = trace_path
        ci_result = run([script_path], env=env, timeout=180)
        assert ci_result.returncode == 0, (
            f"run_ci.sh failed with exit code {ci_result.returncode}:\n"
            f"Stdout: {ci_result.stdout}\nStderr: {ci_result.stderr}"
        )
        assert os.path.exists(trace_path), "run_ci.sh did not invoke Go"
        with open(trace_path, "r") as f:
            calls = [line.strip().split() for line in f if line.strip()]
        assert any(call[:2] == ["build", "./..."] for call in calls), "run_ci.sh did not run 'go build ./...'"
        assert any(call[:2] == ["test", "./..."] for call in calls), "run_ci.sh did not run 'go test ./...'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
