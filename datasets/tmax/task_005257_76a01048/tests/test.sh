#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import subprocess
import tempfile

import pytest

PROJECT = "/home/user/pipeline_project"
DIAGNOSTICS = "/home/user/diagnostics"
PIPELINE = os.path.join(PROJECT, "pipeline.py")


def clear_diagnostics():
    os.makedirs(DIAGNOSTICS, exist_ok=True)
    for name in ("trace.log", "corrupted_rows.log", "result.txt"):
        path = os.path.join(DIAGNOSTICS, name)
        if os.path.lexists(path):
            os.remove(path)


def run_main_pipeline():
    clear_diagnostics()
    result = subprocess.run(
        ["python3", PIPELINE],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"pipeline.py failed.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )


def test_build_script_fixed():
    build_path = os.path.join(PROJECT, "build.sh")
    assert os.path.isfile(build_path), f"Build script missing at {build_path}"
    with open(build_path, "r") as f:
        content = f.read()
    assert "req.txt" not in content, "Build script still contains the incorrect 'req.txt' reference."
    assert "requirements.txt" in content, "Build script does not contain the correct 'requirements.txt' reference."

    result = subprocess.run(
        [build_path],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"build.sh does not execute successfully.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )


def test_trace_log_content():
    run_main_pipeline()
    trace_path = os.path.join(DIAGNOSTICS, "trace.log")
    assert os.path.isfile(trace_path), f"Trace log missing at {trace_path}"
    with open(trace_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_ids = ["101", "102", "103", "104", "105", "106", "107", "108"]
    assert lines == expected_ids, f"Trace log contents do not match expected IDs. Got: {lines}"
    with open(trace_path, "rb") as f:
        assert f.read() == b"101\n102\n103\n104\n105\n106\n107\n108\n"


def test_corrupted_rows_log_content():
    run_main_pipeline()
    corrupted_path = os.path.join(DIAGNOSTICS, "corrupted_rows.log")
    assert os.path.isfile(corrupted_path), f"Corrupted rows log missing at {corrupted_path}"
    with open(corrupted_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_corrupted = ["104,CORRUPTED_DATA", "107,INVALID"]
    for expected in expected_corrupted:
        assert expected in lines, f"Expected corrupted row '{expected}' not found in {corrupted_path}"

    with open(corrupted_path, "rb") as f:
        raw = f.read()
    assert raw == b"104,CORRUPTED_DATA\n107,INVALID\n", (
        "Corrupted rows must be preserved exactly, including their original newline characters. "
        f"Got: {raw!r}"
    )


def test_result_txt_content():
    run_main_pipeline()
    result_path = os.path.join(DIAGNOSTICS, "result.txt")
    assert os.path.isfile(result_path), f"Result file missing at {result_path}"
    with open(result_path, "r") as f:
        content = f.read().strip()

    assert content == "300", f"Result file does not contain the correct sum. Expected '300', got '{content}'"


def test_process_data_on_unseen_input_and_exact_raw_recovery():
    base = secrets.randbelow(700000) + 200000
    ids = [str(base + i) for i in range(5)]
    values = [secrets.randbelow(500) + 1, secrets.randbelow(500) + 1, secrets.randbelow(500) + 1]
    bad1 = "BROKEN_" + secrets.token_hex(8)
    bad2 = "INVALID_" + secrets.token_hex(8)
    lines = [
        "id,value\r\n",
        f"{ids[0]},{values[0]}\r\n",
        f"{ids[1]},{bad1}\r\n",
        f"{ids[2]},{values[1]}\n",
        f"{ids[3]},{bad2}\n",
        f"{ids[4]},{values[2]}\r\n",
    ]
    expected_sum = sum(values)
    expected_corrupt = (lines[2] + lines[4]).encode()
    expected_trace = "".join(row_id + "\n" for row_id in ids).encode()

    clear_diagnostics()
    with tempfile.TemporaryDirectory() as td:
        input_path = os.path.join(td, "input.json")
        output_path = os.path.join(td, "output.json")
        with open(input_path, "w", encoding="utf-8") as f:
            json.dump(lines, f)

        code = f'''\nimport importlib.util, json\nspec = importlib.util.spec_from_file_location("submitted_pipeline", {PIPELINE!r})\nmodule = importlib.util.module_from_spec(spec)\nspec.loader.exec_module(module)\nwith open({input_path!r}, "r", encoding="utf-8") as f:\n    lines = json.load(f)\nresult = module.process_data(lines)\nwith open({output_path!r}, "w", encoding="utf-8") as f:\n    json.dump(result, f)\n'''
        result = subprocess.run(
            ["python3", "-c", code],
            cwd=PROJECT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"process_data failed on unseen input.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )
        assert os.path.isfile(output_path), "process_data did not return a JSON-serializable result"
        with open(output_path, "r", encoding="utf-8") as f:
            actual_sum = json.load(f)

    assert actual_sum == expected_sum, f"Expected dynamic sum {expected_sum}, got {actual_sum!r}"

    trace_path = os.path.join(DIAGNOSTICS, "trace.log")
    corrupted_path = os.path.join(DIAGNOSTICS, "corrupted_rows.log")
    assert os.path.isfile(trace_path), "process_data did not create trace.log"
    assert os.path.isfile(corrupted_path), "process_data did not create corrupted_rows.log"
    with open(trace_path, "rb") as f:
        assert f.read() == expected_trace
    with open(corrupted_path, "rb") as f:
        assert f.read() == expected_corrupt, "Corrupted input lines or their newline characters were changed"


def test_regression_test_exists_and_passes():
    test_path = os.path.join(PROJECT, "test_regression.py")
    assert os.path.isfile(test_path), f"Regression test file missing at {test_path}"

    with open(test_path, "r") as f:
        content = f.read()
    assert "test_corrupted_data_handling" in content, "Regression test file does not define 'test_corrupted_data_handling'"

    result = subprocess.run(
        ["pytest", test_path, "-v"],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"Regression test failed to run or did not pass.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    assert "test_corrupted_data_handling" in result.stdout, "The specific test 'test_corrupted_data_handling' was not executed by pytest."

    # Run the submitted test against an instrumented process_data. This verifies
    # that the named test really calls process_data with CSV strings and asserts
    # that its return value equals the sum of the valid rows.
    with tempfile.TemporaryDirectory() as td:
        copied_test = os.path.join(td, "test_regression.py")
        shutil.copyfile(test_path, copied_test)
        call_log = os.path.join(td, "calls.jsonl")
        fake_pipeline = os.path.join(td, "pipeline.py")
        with open(fake_pipeline, "w", encoding="utf-8") as f:
            f.write(r'''import json
import os

LOG = os.environ["PROCESS_DATA_CALL_LOG"]

class ObservedResult:
    def __eq__(self, other):
        with open(LOG, "a", encoding="utf-8") as out:
            out.write(json.dumps({"comparison": other if isinstance(other, (int, float, str)) else repr(other)}) + "\n")
        return os.environ.get("COMPARISON_RESULT") == "true"

    def __bool__(self):
        with open(LOG, "a", encoding="utf-8") as out:
            out.write(json.dumps({"truth_only": True}) + "\n")
        return False

def process_data(lines):
    with open(LOG, "a", encoding="utf-8") as out:
        out.write(json.dumps({"call": lines}) + "\n")
    return ObservedResult()
''')

        env = os.environ.copy()
        env["PROCESS_DATA_CALL_LOG"] = call_log
        env["COMPARISON_RESULT"] = "true"
        result = subprocess.run(
            ["python3", "-m", "pytest", copied_test + "::test_corrupted_data_handling", "-q"],
            cwd=td,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        assert result.returncode == 0, (
            "The regression test did not call and assert on process_data as required.\n"
            f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )

        with open(call_log, "r", encoding="utf-8") as f:
            records = [json.loads(line) for line in f if line.strip()]
        calls = [record["call"] for record in records if "call" in record]
        comparisons = [record["comparison"] for record in records if "comparison" in record]
        assert calls, "test_corrupted_data_handling never called process_data"

        valid_exercised_case = False
        for supplied_lines in calls:
            if not isinstance(supplied_lines, list) or not all(isinstance(x, str) for x in supplied_lines):
                continue
            nonempty = [line for line in supplied_lines if line.strip()]
            if len(nonempty) < 2:
                continue
            total = 0
            valid = 0
            corrupt = 0
            for line in nonempty[1:]:
                try:
                    value = line.strip().split(",")[1]
                    total += int(value)
                    valid += 1
                except (IndexError, ValueError):
                    corrupt += 1
            if valid and corrupt and total in comparisons:
                valid_exercised_case = True
                break
        assert valid_exercised_case, (
            "The regression test must pass CSV line strings containing valid and corrupted rows "
            "and compare process_data's return value with the valid-row sum."
        )

        os.remove(call_log)
        env["COMPARISON_RESULT"] = "false"
        result = subprocess.run(
            ["python3", "-m", "pytest", copied_test + "::test_corrupted_data_handling", "-q"],
            cwd=td,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        assert result.returncode != 0, "The regression test passes even when its expected sum comparison is false"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
