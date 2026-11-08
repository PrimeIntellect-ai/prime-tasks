#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

SOURCE_PATH = Path("/home/user/process_logs.go")
CSV_PATH = Path("/home/user/pipeline_logs.csv")
OUTPUT_PATH = Path("/home/user/etl_summary.json")

FIXTURES = [
    """TaskID,PipelineID,TaskName,DurationSec,RowsProcessed
T01,PipeA,Extract,120,500
T02,PipeA,Transform,150,550
T03,PipeA,Load,45,1000
T04,PipeB,Extract,300,2000
T05,PipeB,Transform,300,0
T06,PipeB,Validate,300,100
T07,PipeB,Load,200,1900
T08,PipeC,Extract,10,0
T09,PipeC,Load,5,0
T10,PipeD,Extract,60,100
""",
    """TaskID,PipelineID,TaskName,DurationSec,RowsProcessed
Z9,PipeZ,Load,4,40
A3,PipeA,Third,7,30
A0,PipeA,First,8,10
A2,PipeA,Filtered,100,0
A1,PipeA,Second,7,20
M1,PipeM,Only,12,99
Z1,PipeZ,Extract,15,5
Z2,PipeZ,Transform,15,6
Z3,PipeZ,Filtered,1000,0
""",
    """TaskID,PipelineID,TaskName,DurationSec,RowsProcessed
C9,PipeQ,Third,99,999
B9,PipeQ,Second,100,1
A9,PipeQ,First,100,2
X1,EmptyPipe,Filtered,500,0
""",
]


def remove_path(path):
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.exists():
        shutil.rmtree(path)


def get_expected_data():
    if not CSV_PATH.exists():
        pytest.fail(f"Input file {CSV_PATH} is missing.")

    with CSV_PATH.open("r", encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f))

    valid_rows = [r for r in rows if int(r["RowsProcessed"]) != 0]
    pipelines = {}
    for r in valid_rows:
        pipelines.setdefault(r["PipelineID"], []).append({
            "task_id": r["TaskID"],
            "duration_sec": int(r["DurationSec"]),
            "rows_processed": int(r["RowsProcessed"]),
        })

    expected = []
    for pid in sorted(pipelines):
        tasks = pipelines[pid]
        tasks.sort(key=lambda x: (-x["duration_sec"], x["task_id"]))
        top_tasks = tasks[:2]
        expected.append({
            "pipeline_id": pid,
            "top_tasks": [
                {
                    "task_id": task["task_id"],
                    "rank": index + 1,
                    "duration_sec": task["duration_sec"],
                }
                for index, task in enumerate(top_tasks)
            ],
            "top_2_rows_processed": sum(task["rows_processed"] for task in top_tasks),
        })
    return expected


def assert_output_is_correct():
    assert OUTPUT_PATH.exists(), f"The file {OUTPUT_PATH} was not created."
    assert OUTPUT_PATH.is_file(), f"The path {OUTPUT_PATH} is not a file."

    content = OUTPUT_PATH.read_text(encoding="utf-8")
    try:
        actual_data = json.loads(content)
    except json.JSONDecodeError:
        pytest.fail(f"The file {OUTPUT_PATH} does not contain valid JSON.")

    expected_data = get_expected_data()
    assert actual_data == expected_data, (
        f"The parsed JSON content in {OUTPUT_PATH} does not match the expected output. "
        f"Expected: {expected_data}\nActual: {actual_data}"
    )

    assert "\n" in content, "The JSON output does not appear to be pretty-printed (missing newlines)."
    assert "  " in content, "The JSON output does not appear to use 2 spaces for indentation."


def test_go_program_exists_and_runs_on_multiple_inputs():
    assert SOURCE_PATH.exists(), f"The required Go program {SOURCE_PATH} is missing."
    assert SOURCE_PATH.is_file(), f"The path {SOURCE_PATH} is not a file."

    for fixture in FIXTURES:
        remove_path(CSV_PATH)
        CSV_PATH.write_text(fixture, encoding="utf-8")
        remove_path(OUTPUT_PATH)

        result = subprocess.run(
            ["go", "run", str(SOURCE_PATH)],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=45,
        )
        assert result.returncode == 0, (
            "The Go program failed to run.\n"
            f"stdout:\n{result.stdout}\n"
            f"stderr:\n{result.stderr}"
        )
        assert_output_is_correct()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
