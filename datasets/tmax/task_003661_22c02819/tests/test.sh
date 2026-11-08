#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pathlib
import re
import subprocess
import tempfile
import uuid

WORKSPACE = "/home/user/monitor_workspace"


def run(command, cwd=None, timeout=180):
    result = subprocess.run(
        command,
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"Command failed: {' '.join(command)}\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )
    return result


def test_mock_proc_uptime_content():
    mock_file = "/home/user/mock_proc/uptime"
    assert os.path.isfile(mock_file), f"Mock file {mock_file} does not exist"

    with open(mock_file, "r") as f:
        content = f.read().strip()

    assert content == "12345.67 890.12", (
        "Mock uptime file content is incorrect. "
        f"Expected '12345.67 890.12', got '{content}'"
    )


def test_workspace_compiles():
    assert os.path.isdir(WORKSPACE), f"Workspace directory {WORKSPACE} does not exist"
    run(["cargo", "check", "--workspace"], cwd=WORKSPACE)
    run(["cargo", "build", "--workspace"], cwd=WORKSPACE)


def test_cargo_tests_really_pass():
    result = run(["cargo", "test", "--workspace"], cwd=WORKSPACE)
    output = result.stdout + "\n" + result.stderr
    assert re.search(r"\b[1-9][0-9]* passed\b", output), (
        "cargo test succeeded, but no executed passing test was reported"
    )


def test_cargo_test_results():
    results_file = "/home/user/test_results.txt"
    assert os.path.isfile(results_file), f"Test results file {results_file} does not exist"

    with open(results_file, "r") as f:
        content = f.read()

    assert "test result: ok" in content, (
        "Cargo tests did not pass. 'test result: ok' not found in test_results.txt"
    )
    passed_tests_found = "passed" in content and any(
        str(i) + " passed" in content for i in range(1, 10)
    )
    assert passed_tests_found, (
        "No tests were executed or recorded as passed in test_results.txt"
    )


def test_circular_dependency_removed():
    core_cargo = os.path.join(WORKSPACE, "core", "Cargo.toml")
    assert os.path.isfile(core_cargo), f"{core_cargo} does not exist"

    with open(core_cargo, "r") as f:
        content = f.read()

    assert "api =" not in content and '{ path = "../api" }' not in content, (
        "Circular dependency still present in core/Cargo.toml"
    )


def test_agent_added_required_mock_integration_test():
    api_dir = pathlib.Path(WORKSPACE) / "api"
    candidates = [api_dir / "src" / "lib.rs"]
    tests_dir = api_dir / "tests"
    if tests_dir.is_dir():
        candidates.extend(tests_dir.rglob("*.rs"))

    found = False
    for path in candidates:
        if not path.is_file():
            continue
        text = path.read_text()
        if (
            re.search(r"#\s*\[\s*test\s*\]", text)
            and "/home/user/mock_proc" in text
            and "12345.67" in text
            and "assert" in text
        ):
            found = True
            break

    assert found, (
        "No Rust test in api/src/lib.rs or api/tests/ uses "
        "/home/user/mock_proc and asserts the expected 12345.67 uptime"
    )


def test_read_uptime_and_api_json_behavior():
    # Use an unpredictable verifier-created proc directory so the implementation
    # must honor proc_dir rather than hardcoding either /proc or the supplied fixture.
    expected = 20000.0 + (uuid.uuid4().int % 700000) / 100.0

    with tempfile.TemporaryDirectory(prefix="verifier_proc_") as proc_dir, \
         tempfile.TemporaryDirectory(prefix="monitor_harness_") as harness_dir:
        pathlib.Path(proc_dir, "uptime").write_text(f"{expected:.2f} 17.25\n")

        pathlib.Path(harness_dir, "Cargo.toml").write_text(f'''\
[package]
name = "monitor_verifier_harness"
version = "0.1.0"
edition = "2021"

[dependencies]
monitor_core = {{ package = "core", path = "{WORKSPACE}/core" }}
api = {{ path = "{WORKSPACE}/api" }}
serde_json = "1.0"
''')
        src = pathlib.Path(harness_dir, "src")
        src.mkdir()
        proc_literal = json.dumps(proc_dir)
        pathlib.Path(src, "main.rs").write_text(f'''\
fn main() {{
    let proc_dir: &str = {proc_literal};
    let expected: f64 = {expected:.2f};

    let direct = monitor_core::read_uptime(proc_dir);
    assert!((direct - expected).abs() < 1e-9, "read_uptime returned {{}}", direct);

    let body = api::get_uptime_json(proc_dir);
    let parsed: serde_json::Value = serde_json::from_str(&body)
        .expect("API response was not valid JSON");
    let object = parsed.as_object().expect("API response was not a JSON object");
    assert_eq!(object.len(), 1, "API JSON must contain only the uptime field");
    let uptime = object.get("uptime")
        .and_then(|v| v.as_f64())
        .expect("API JSON lacked a numeric uptime field");
    assert!((uptime - expected).abs() < 1e-9, "API returned {{}}", uptime);
}}
''')
        run(["cargo", "run", "--quiet"], cwd=harness_dir)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
