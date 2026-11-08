#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import stat
import subprocess
import time

import pytest

PIPELINE_DIR = "/home/user/pipeline"
RUN_PIPELINE = os.path.join(PIPELINE_DIR, "run_pipeline.sh")
TEST_PIPELINE = os.path.join(PIPELINE_DIR, "test_pipeline.sh")
PROCESSOR_JS = os.path.join(PIPELINE_DIR, "processor.js")
INGESTER_PY = os.path.join(PIPELINE_DIR, "ingester.py")


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=5, **kwargs)


def test_test_pipeline_script_exists_and_executable():
    assert os.path.isfile(TEST_PIPELINE), f"Regression test script {TEST_PIPELINE} is missing."
    assert os.access(TEST_PIPELINE, os.X_OK), f"Regression test script {TEST_PIPELINE} is not executable."


def test_test_pipeline_script_succeeds():
    result = run([TEST_PIPELINE])
    assert result.returncode == 0, f"{TEST_PIPELINE} failed with exit code {result.returncode}. Output: {result.stdout} {result.stderr}"


def test_run_pipeline_env_var_configured():
    with open(RUN_PIPELINE, "r") as f:
        content = f.read()
    assert "PIPELINE_MODE=production" in content, f"{RUN_PIPELINE} does not set PIPELINE_MODE=production."


def test_run_pipeline_output_success():
    result = run([RUN_PIPELINE])
    assert result.returncode == 0, f"{RUN_PIPELINE} failed to execute properly."
    assert "SUCCESS: critical" in result.stdout, f"Expected output 'SUCCESS: critical' not found in {RUN_PIPELINE} output."


def test_ingester_production_output_is_valid_json():
    env = os.environ.copy()
    env["PIPELINE_MODE"] = "production"
    result = run(["python3", INGESTER_PY], env=env)
    assert result.returncode == 0, result.stderr
    parsed = json.loads(result.stdout)
    assert parsed["status"] == "critical"
    assert parsed["payload"] == "alert data"
    assert parsed["tags"] == ["urgent", "nightly"]


def test_processor_handles_derived_valid_input():
    status = "probe-" + secrets.token_hex(12)
    payload = json.dumps({"status": status, "payload": secrets.token_hex(8), "tags": ["x"]}) + "\n"
    result = subprocess.run(
        ["node", PROCESSOR_JS], input=payload, capture_output=True, text=True, timeout=5
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == f"SUCCESS: {status}"


def test_processor_js_infinite_recursion_fixed():
    env = os.environ.copy()
    env["PIPELINE_MODE"] = "legacy"

    try:
        p1 = subprocess.Popen(["python3", INGESTER_PY], stdout=subprocess.PIPE, env=env)
        p2 = subprocess.Popen(
            ["node", PROCESSOR_JS], stdin=p1.stdout,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        p1.stdout.close()
        stdout, stderr = p2.communicate(timeout=3)
        p1.wait(timeout=3)

        assert p2.returncode != 0, "Processor should fail when parsing legacy output, but it succeeded."
        recursion_signatures = ("RangeError", "Maximum call stack", "stack overflow")
        assert not any(s.lower() in stderr.lower() for s in recursion_signatures), (
            "Processor still fails through runaway recursion instead of bounded parse retries: " + stderr
        )
    except subprocess.TimeoutExpired:
        p2.kill()
        p1.kill()
        pytest.fail("processor.js timed out, indicating the infinite recursion bug is not fixed.")


def test_run_pipeline_really_runs_ingester_and_processor_with_production_env():
    status = "pipeline-probe-" + secrets.token_hex(12)
    marker = "/tmp/ingester-marker-" + secrets.token_hex(12)
    with open(INGESTER_PY, "rb") as f:
        original = f.read()
    original_mode = stat.S_IMODE(os.stat(INGESTER_PY).st_mode)

    probe = f'''import json
import os
with open({marker!r}, "w") as f:
    f.write(os.environ.get("PIPELINE_MODE", ""))
if os.environ.get("PIPELINE_MODE") != "production":
    print("not valid json [")
else:
    print(json.dumps({{"status": {status!r}, "payload": "probe", "tags": []}}))
'''
    try:
        with open(INGESTER_PY, "w") as f:
            f.write(probe)
        os.chmod(INGESTER_PY, original_mode)
        result = run([RUN_PIPELINE])
        assert result.returncode == 0, result.stderr
        assert os.path.isfile(marker), "run_pipeline.sh did not execute ingester.py"
        with open(marker) as f:
            assert f.read() == "production", "run_pipeline.sh did not pass PIPELINE_MODE=production to ingester.py"
        assert f"SUCCESS: {status}" in result.stdout, (
            "run_pipeline.sh did not pipe the dynamically derived ingester output through the processor"
        )
    finally:
        with open(INGESTER_PY, "wb") as f:
            f.write(original)
        os.chmod(INGESTER_PY, original_mode)
        try:
            os.remove(marker)
        except FileNotFoundError:
            pass


def test_regression_test_actually_runs_and_validates_pipeline():
    marker = "/tmp/pipeline-marker-" + secrets.token_hex(12)
    with open(RUN_PIPELINE, "rb") as f:
        original = f.read()
    original_mode = stat.S_IMODE(os.stat(RUN_PIPELINE).st_mode)

    probe = f'''#!/bin/bash
printf invoked > {marker!r}
printf '%s\n' "$PROBE_OUTPUT"
exit "$PROBE_EXIT"
'''
    try:
        with open(RUN_PIPELINE, "w") as f:
            f.write(probe)
        os.chmod(RUN_PIPELINE, 0o755)

        env = os.environ.copy()
        env["PROBE_OUTPUT"] = "SUCCESS: critical"
        env["PROBE_EXIT"] = "0"
        result = run([TEST_PIPELINE], env=env)
        assert result.returncode == 0, "Regression test rejected a successful pipeline result"
        assert os.path.isfile(marker), "Regression test did not run run_pipeline.sh"

        os.remove(marker)
        env["PROBE_OUTPUT"] = "FAILURE: " + secrets.token_hex(12)
        env["PROBE_EXIT"] = "0"
        result = run([TEST_PIPELINE], env=env)
        assert result.returncode == 1, "Regression test did not reject output lacking SUCCESS: critical"
        assert os.path.isfile(marker), "Regression test did not run run_pipeline.sh on its failure path"

        os.remove(marker)
        env["PROBE_OUTPUT"] = "SUCCESS: critical"
        env["PROBE_EXIT"] = "7"
        result = run([TEST_PIPELINE], env=env)
        assert result.returncode == 1, "Regression test ignored a failing pipeline exit status"
        assert os.path.isfile(marker), "Regression test did not run run_pipeline.sh on its exit-status path"
    finally:
        with open(RUN_PIPELINE, "wb") as f:
            f.write(original)
        os.chmod(RUN_PIPELINE, original_mode)
        try:
            os.remove(marker)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
