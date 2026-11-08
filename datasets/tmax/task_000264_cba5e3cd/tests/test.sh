#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/mp_trace_sitecustomize.py
import os
import multiprocessing.process

_original_start = multiprocessing.process.BaseProcess.start

def _traced_start(self, *args, **kwargs):
    marker = os.environ.get("MP_MARKER")
    if marker:
        with open(marker, "a") as f:
            f.write("process-started\n")
    return _original_start(self, *args, **kwargs)

multiprocessing.process.BaseProcess.start = _traced_start
PY_EOF

mkdir -p /tmp/mp_trace
cp /tmp/mp_trace_sitecustomize.py /tmp/mp_trace/sitecustomize.py

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import random
import stat
import string
import subprocess

SCRIPT = "/home/user/analyze_retries.py"
ETL = "/home/user/etl.log"
EVENTS = "/home/user/events.csv"
REPORT = "/home/user/duplicate_report.txt"
LOG = "/home/user/pipeline.log"
MARKER = "/tmp/multiprocessing_used"

ORIGINAL_ETL = open(ETL).read()
ORIGINAL_EVENTS = open(EVENTS).read()


def run_script():
    for path in (REPORT, LOG, MARKER):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env["MP_MARKER"] = MARKER
    env["PYTHONPATH"] = "/tmp/mp_trace" + (
        os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else ""
    )
    result = subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Script execution failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def assert_execution_log():
    assert os.path.exists(LOG), f"Pipeline log not found at {LOG}."
    with open(LOG) as f:
        logs = f.read()
    assert len(logs.strip()) > 0, "Pipeline log is empty."
    lowered = logs.lower()
    assert "start" in lowered, "Pipeline log does not record pipeline startup."
    assert any(word in lowered for word in ("finish", "complete", "completed", "end")), \
        "Pipeline log does not record pipeline completion."


def setup_module(module):
    assert os.path.exists(SCRIPT), f"Python script not found at {SCRIPT}."
    mode = os.stat(SCRIPT).st_mode
    assert stat.S_ISREG(mode), f"Script path is not a regular file: {SCRIPT}."
    assert os.path.getsize(SCRIPT) > 0, "Python script is empty."
    run_script()


def test_duplicate_report_content():
    report_path = REPORT
    assert os.path.exists(report_path), f"Report not found at {report_path}."

    expected_report = """Audit Report
============
Total Retried Jobs: 2
Affected Transactions:
- TXN_003 (Job: JOB_B, Amount: 200)
- TXN_005 (Job: JOB_D, Amount: 500)"""

    with open(report_path, "r") as f:
        actual_report = f.read().strip()

    assert actual_report == expected_report.strip(), f"Report content mismatch. Got:\n{actual_report}"


def test_pipeline_log_exists_and_not_empty():
    log_path = LOG
    assert os.path.exists(log_path), f"Pipeline log not found at {log_path}."

    with open(log_path, "r") as f:
        logs = f.read()

    assert len(logs.strip()) > 0, "Pipeline log is empty."
    assert_execution_log()


def test_script_uses_multiprocessing():
    script_path = SCRIPT
    assert os.path.exists(script_path), f"Python script not found at {script_path}."

    with open(script_path, "r") as f:
        script_content = f.read()

    assert "multiprocessing" in script_content, "Script does not use multiprocessing as required."
    tree = ast.parse(script_content, filename=script_path)
    imports_mp = any(
        (isinstance(node, ast.Import) and any(alias.name == "multiprocessing" or alias.name.startswith("multiprocessing.") for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module and (node.module == "multiprocessing" or node.module.startswith("multiprocessing.")))
        for node in ast.walk(tree)
    )
    assert imports_mp, "Script does not import Python's multiprocessing module."
    assert os.path.exists(MARKER) and os.path.getsize(MARKER) > 0, \
        "No multiprocessing worker process was started while executing the script."


def test_script_processes_changed_inputs_instead_of_hardcoding_report():
    suffix = "".join(random.SystemRandom().choices(string.ascii_uppercase + string.digits, k=10))
    retry_a = f"RJOB_A_{suffix}"
    retry_b = f"RJOB_B_{suffix}"
    normal = f"NJOB_{suffix}"
    txn_a = f"A_TXN_{suffix}"
    txn_z = f"Z_TXN_{suffix}"

    etl_text = f"""2026-01-01T00:00:00 {retry_a} START
2026-01-01T00:01:00 {retry_a} RETRY
2026-01-01T00:02:00 {retry_a} RETRY
2026-01-01T00:03:00 {retry_b} RETRY
2026-01-01T00:04:00 {normal} SUCCESS
"""
    events_text = f"""job_id,txn_id,amount
{retry_a},{txn_z},145
{retry_a},{txn_z},145
{retry_b},{txn_a},100
{retry_b},LOW_{suffix},99
{retry_a},BAD_{suffix},not_an_integer
{normal},IGNORED_{suffix},999
"""
    expected = f"""Audit Report
============
Total Retried Jobs: 2
Affected Transactions:
- {txn_a} (Job: {retry_b}, Amount: 100)
- {txn_z} (Job: {retry_a}, Amount: 145)"""

    try:
        with open(ETL, "w") as f:
            f.write(etl_text)
        with open(EVENTS, "w") as f:
            f.write(events_text)

        run_script()
        assert os.path.exists(REPORT), "Report was not generated for changed inputs."
        with open(REPORT) as f:
            actual = f.read().strip()
        assert actual == expected.strip(), f"Report does not reflect changed inputs. Got:\n{actual}"
        assert os.path.exists(MARKER) and os.path.getsize(MARKER) > 0, \
            "Changed CSV input was not processed using a multiprocessing worker."
        assert_execution_log()
    finally:
        with open(ETL, "w") as f:
            f.write(ORIGINAL_ETL)
        with open(EVENTS, "w") as f:
            f.write(ORIGINAL_EVENTS)
        run_script()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
