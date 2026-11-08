#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import json
import os
import shutil
import stat
import subprocess
import tempfile
import time
import uuid

import pytest


def test_test_pipeline_script_exists_and_executable():
    script_path = "/home/user/test_pipeline.sh"
    assert os.path.isfile(script_path), f"Test script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Test script {script_path} is not executable."


def test_test_pipeline_execution():
    script_path = "/home/user/test_pipeline.sh"
    result = subprocess.run([script_path], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, f"test_pipeline.sh failed with exit code {result.returncode}. Stderr: {result.stderr}"


def test_report_json_valid_and_complete():
    report_path = "/home/user/diagnostics/report.json"
    assert os.path.isfile(report_path), f"Report file {report_path} is missing."

    with open(report_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Report file {report_path} is not valid JSON.")

    assert isinstance(data, list), "Report JSON is not a list."
    assert len(data) == 5, f"Report JSON contains {len(data)} entries, expected exactly 5."


def test_root_cause_logic():
    report_path = "/home/user/diagnostics/report.json"
    with open(report_path, 'r') as f:
        data = json.load(f)

    results = {item['file']: item['root_cause'] for item in data}

    assert 'app err 1.log' in results, "Missing entry for 'app err 1.log'"
    assert results['app err 1.log'] == 'E103', "Incorrect root cause for 'app err 1.log'"

    assert 'app err 2.log' in results, "Missing entry for 'app err 2.log'"
    assert results['app err 2.log'] in ['E201', 'E202'], "Incorrect root cause for 'app err 2.log'"

    assert 'sys log 3.log' in results, "Missing entry for 'sys log 3.log'"
    assert results['sys log 3.log'] == 'E302', "Incorrect root cause for 'sys log 3.log'"

    assert 'db err 4.log' in results, "Missing entry for 'db err 4.log'"
    assert results['db err 4.log'] in ['E401', 'E402', 'E403'], "Incorrect root cause for 'db err 4.log'"

    assert 'net log 5.log' in results, "Missing entry for 'net log 5.log'"
    assert results['net log 5.log'] == 'E501', "Incorrect root cause for 'net log 5.log'"


def test_run_pipeline_fixes():
    script_path = "/home/user/diagnostics/run_pipeline.sh"
    with open(script_path, 'r') as f:
        content = f.read()

    assert "$(ls" not in content, "run_pipeline.sh still uses $(ls ...) which breaks on spaces."
    assert ' "$' in content or '"${' in content, "run_pipeline.sh does not appear to quote the filename variable properly."


def test_parse_trace_locking():
    script_path = "/home/user/diagnostics/parse_trace.py"
    with open(script_path, 'r') as f:
        content = f.read()

    assert "fcntl" in content and ("flock" in content or "lockf" in content), "parse_trace.py does not appear to use fcntl file locking."


def test_regression_script_really_clears_runs_and_validates():
    pipeline = "/home/user/diagnostics/run_pipeline.sh"
    report = "/home/user/diagnostics/report.json"
    marker = f"/tmp/pipeline-marker-{uuid.uuid4().hex}"
    with open(pipeline, "rb") as f:
        original = f.read()
    original_mode = stat.S_IMODE(os.stat(pipeline).st_mode)

    try:
        with open(report, "w") as f:
            json.dump([{"old": True}] * 5, f)
        fake = f'''#!/bin/bash
if [ -e {report!r} ]; then
    echo NOT_CLEARED > {marker!r}
else
    echo CLEARED > {marker!r}
fi
printf '%s' 'not valid json' > {report!r}
exit 0
'''
        with open(pipeline, "w") as f:
            f.write(fake)
        os.chmod(pipeline, 0o755)

        result = subprocess.run(["/home/user/test_pipeline.sh"], capture_output=True, text=True, timeout=30)
        assert os.path.isfile(marker), "test_pipeline.sh did not execute run_pipeline.sh"
        with open(marker) as f:
            marker_value = f.read().strip()
        assert marker_value == "CLEARED", "test_pipeline.sh did not clear the old report before running the pipeline"
        assert result.returncode != 0, "test_pipeline.sh accepted a report that was not valid JSON"
    finally:
        with open(pipeline, "wb") as f:
            f.write(original)
        os.chmod(pipeline, original_mode)
        if os.path.exists(marker):
            os.remove(marker)


def test_pipeline_on_generated_logs_with_real_concurrency():
    diagnostics = "/home/user/diagnostics"
    pipeline = os.path.join(diagnostics, "run_pipeline.sh")
    parser = os.path.join(diagnostics, "parse_trace.py")
    report = os.path.join(diagnostics, "report.json")
    logs = "/home/user/logs"
    token = uuid.uuid4().hex
    backup_logs = f"/home/user/logs.verifier-backup-{token}"
    original_parser = f"/tmp/parse-trace-original-{token}.py"
    state_file = f"/tmp/parser-state-{token}.json"

    with open(parser, "rb") as f:
        parser_bytes = f.read()
    parser_mode = stat.S_IMODE(os.stat(parser).st_mode)
    with open(original_parser, "wb") as f:
        f.write(parser_bytes)
    os.chmod(original_parser, parser_mode)

    expected = {}
    os.rename(logs, backup_logs)
    os.mkdir(logs)

    try:
        for i in range(24):
            filename = f"generated diagnostic {i} {token[:8]}.log"
            a = f"X{token[:10]}_{i}_A"
            b = f"X{token[:10]}_{i}_B"
            c = f"X{token[:10]}_{i}_C"
            if i % 3 == 0:
                body = f"ERROR_ID: {a}\nCaused by: {b}\nERROR_ID: {b}\nCaused by: {c}\nERROR_ID: {c}\n"
                expected[filename] = c
            elif i % 3 == 1:
                body = f"ERROR_ID: {a}\nCaused by: {b}\nERROR_ID: {b}\nCaused by: {c}\nERROR_ID: {c}\nCaused by: {b}\n"
                expected[filename] = c
            else:
                body = f"ERROR_ID: {a}\n"
                expected[filename] = a
            with open(os.path.join(logs, filename), "w") as f:
                f.write(body)

        with open(state_file, "w") as f:
            json.dump({"active": 0, "maximum": 0, "arguments": []}, f)

        wrapper = f'''import fcntl
import json
import os
import subprocess
import sys
import time

state_path = {state_file!r}
original_parser = {original_parser!r}

def update(starting):
    with open(state_path, "r+") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        state = json.load(handle)
        if starting:
            state["active"] += 1
            state["maximum"] = max(state["maximum"], state["active"])
            state["arguments"].append(os.path.basename(sys.argv[1]) if len(sys.argv) > 1 else None)
        else:
            state["active"] -= 1
        handle.seek(0)
        handle.truncate()
        json.dump(state, handle)
        handle.flush()
        os.fsync(handle.fileno())
        fcntl.flock(handle, fcntl.LOCK_UN)

update(True)
try:
    time.sleep(0.35)
    completed = subprocess.run([sys.executable, original_parser] + sys.argv[1:])
    raise SystemExit(completed.returncode)
finally:
    update(False)
'''
        with open(parser, "w") as f:
            f.write(wrapper)
        os.chmod(parser, parser_mode)
        if os.path.exists(report):
            os.remove(report)

        started = time.monotonic()
        result = subprocess.run([pipeline], capture_output=True, text=True, timeout=40)
        elapsed = time.monotonic() - started
        if elapsed < 0.30:
            time.sleep(1.0)

        assert result.returncode == 0, f"run_pipeline.sh failed: {result.stderr}"
        assert elapsed >= 0.30, "run_pipeline.sh returned without waiting for its background processors"

        with open(state_file) as f:
            state = json.load(f)
        assert state["maximum"] > 1, "run_pipeline.sh did not launch Python processors concurrently"
        assert sorted(state["arguments"]) == sorted(expected), "run_pipeline.sh did not pass every spaced filename intact"

        assert os.path.isfile(report), "The real pipeline did not create report.json"
        with open(report) as f:
            data = json.load(f)
        assert isinstance(data, list), "Generated report is not a JSON array"
        assert len(data) == len(expected), f"Generated report has {len(data)} entries; expected {len(expected)}"
        assert all(isinstance(item, dict) and "file" in item and "root_cause" in item for item in data)
        assert len({item["file"] for item in data}) == len(data), "Generated report contains duplicate or lost entries"
        actual = {item["file"]: item["root_cause"] for item in data}
        assert actual == expected, "Root-cause tracing failed on generated chains or cycles"
    finally:
        with open(parser, "wb") as f:
            f.write(parser_bytes)
        os.chmod(parser, parser_mode)
        if os.path.isdir(logs):
            shutil.rmtree(logs)
        if os.path.exists(backup_logs):
            os.rename(backup_logs, logs)
        for path in (original_parser, state_file):
            if os.path.exists(path):
                os.remove(path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
