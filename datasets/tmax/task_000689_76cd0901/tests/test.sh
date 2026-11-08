#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import stat
import subprocess

PROJ_DIR = "/home/user/pipeline_proj"
RESULTS_LOG = "/home/user/test_results.log"
TRANSFORMER_RS = os.path.join(PROJ_DIR, "src", "transformer.rs")
MAIN_RS = os.path.join(PROJ_DIR, "src", "main.rs")
E2E_SCRIPT = os.path.join(PROJ_DIR, "e2e_test.sh")
GENERATOR = os.path.join(PROJ_DIR, "generate_data.py")
REFERENCE = os.path.join(PROJ_DIR, "reference.py")
BINARY = os.path.join(PROJ_DIR, "target", "release", "pipeline_proj")


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def test_rust_project_compiles():
    """Verify that the Rust project compiles successfully without errors."""
    assert os.path.isdir(PROJ_DIR), f"{PROJ_DIR} does not exist."
    result = run(["cargo", "check"], cwd=PROJ_DIR)
    assert result.returncode == 0, f"cargo check failed in {PROJ_DIR}:\n{result.stderr}"


def test_transformer_rs_fixed():
    """Keep the original ownership/type assertions."""
    assert os.path.isfile(TRANSFORMER_RS), f"{TRANSFORMER_RS} is missing."
    with open(TRANSFORMER_RS, "r") as f:
        content = f.read()
    assert "Vec<String>" in content, f"Expected return type Vec<String> in {TRANSFORMER_RS}, but it was not found."
    assert "result.push(upper.as_str());" not in content, f"The bug 'result.push(upper.as_str());' is still present in {TRANSFORMER_RS}."
    with open(TRANSFORMER_RS, "rb") as f, open(REFERENCE, "rb") as r:
        assert f.read() != r.read(), "transformer.rs must not be a byte-identical copy of the reference file"


def test_release_binary_matches_transformation():
    """Exercise the submitted Rust program on independently derived cases."""
    result = run(["cargo", "build", "--release"], cwd=PROJ_DIR)
    assert result.returncode == 0, f"cargo build --release failed:\n{result.stderr}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), f"Missing executable release binary: {BINARY}"

    cases = [
        [],
        [{"name": "alice", "active": True}, {"name": "bob", "active": False}, {"name": "charlie", "active": True}],
        [{"name": "mixed Case", "active": True}, {"name": "ignored"}, {"name": "z9", "active": True}],
        [{"name": "first", "active": False}, {"name": "second", "active": True}, {"name": "third", "active": True}],
    ]
    for data in cases:
        expected_names = [item["name"].upper() for item in data if item.get("active", False)]
        expected = "".join(name + "\n" for name in expected_names)
        proc = run([BINARY], cwd=PROJ_DIR, input=json.dumps(data))
        assert proc.returncode == 0, f"Binary failed for input {data!r}:\n{proc.stderr}"
        assert proc.stdout == expected, f"For input {data!r}, expected {expected!r}, got {proc.stdout!r}"


def test_e2e_orchestrator_executes_and_detects_failure():
    """Execute the requested artifact and verify both FAILURE and SUCCESS paths."""
    assert os.path.isfile(E2E_SCRIPT), f"{E2E_SCRIPT} is missing"
    assert stat.S_ISREG(os.stat(E2E_SCRIPT).st_mode), "e2e_test.sh is not a regular file"
    assert os.access(E2E_SCRIPT, os.X_OK), "e2e_test.sh is not executable"
    syntax = run(["bash", "-n", E2E_SCRIPT])
    assert syntax.returncode == 0, f"e2e_test.sh has invalid shell syntax:\n{syntax.stderr}"

    with open(MAIN_RS, "rb") as f:
        original_main = f.read()
    with open(GENERATOR, "rb") as f:
        original_generator = f.read()
    main_mode = os.stat(MAIN_RS).st_mode
    generator_mode = os.stat(GENERATOR).st_mode
    marker = "/tmp/pipeline_generator_was_run"

    try:
        # A deliberately wrong but compilable program must make the orchestrator
        # record FAILURE, proving it checks output rather than merely self-reporting.
        with open(MAIN_RS, "w") as f:
            f.write('fn main() { println!("DELIBERATELY_WRONG"); }\n')
        if os.path.exists(BINARY):
            os.remove(BINARY)
        if os.path.exists(RESULTS_LOG):
            os.remove(RESULTS_LOG)
        proc = run([E2E_SCRIPT], cwd=PROJ_DIR)
        assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), "e2e_test.sh did not create the release binary"
        assert os.path.isfile(RESULTS_LOG), f"{RESULTS_LOG} was not created on mismatch"
        with open(RESULTS_LOG, "r") as f:
            assert f.read() == "FAILURE\n", "e2e_test.sh did not record exactly FAILURE on wrong output"

        # Restore the real program and wrap the standard generator with a marker,
        # so the successful run also proves that generate_data.py was executed.
        with open(MAIN_RS, "wb") as f:
            f.write(original_main)
        os.chmod(MAIN_RS, main_mode)
        if os.path.exists(marker):
            os.remove(marker)
        with open(GENERATOR, "w") as f:
            f.write("#!/usr/bin/env python3\n")
            f.write(f"open({marker!r}, 'w').write('ran')\n")
            f.write("import json\n")
            f.write("data = [\n")
            f.write("    {'name': 'alice', 'active': True},\n")
            f.write("    {'name': 'bob', 'active': False},\n")
            f.write("    {'name': 'charlie', 'active': True}\n")
            f.write("]\nprint(json.dumps(data))\n")
        os.chmod(GENERATOR, generator_mode)
        if os.path.exists(RESULTS_LOG):
            os.remove(RESULTS_LOG)
        proc = run([E2E_SCRIPT], cwd=PROJ_DIR)
        assert proc.returncode == 0, f"e2e_test.sh failed:\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
        assert os.path.isfile(marker), "e2e_test.sh did not execute generate_data.py"
    finally:
        with open(MAIN_RS, "wb") as f:
            f.write(original_main)
        os.chmod(MAIN_RS, main_mode)
        with open(GENERATOR, "wb") as f:
            f.write(original_generator)
        os.chmod(GENERATOR, generator_mode)
        if os.path.exists(marker):
            os.remove(marker)


def test_test_results_log_success():
    """Keep the original exact final-log assertion after executing the script."""
    assert os.path.isfile(RESULTS_LOG), f"{RESULTS_LOG} does not exist. Did you run the e2e script?"
    with open(RESULTS_LOG, "r") as f:
        content = f.read()
    assert content == "SUCCESS\n", f"Expected exactly 'SUCCESS\\n' in {RESULTS_LOG}, but got {content!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
