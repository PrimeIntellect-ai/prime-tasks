#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import secrets
import subprocess
import sys
import tempfile
from dataclasses import fields, is_dataclass

import pytest

PROJECT = "/home/user/rust_log_parser"
SUMMARY = os.path.join(PROJECT, "summary.json")


def run_main(input_path, output_path):
    subprocess.run(
        [sys.executable, os.path.join(PROJECT, "main.py"), input_path, output_path],
        cwd=PROJECT,
        check=True,
        timeout=10,
    )


def load_json(path):
    try:
        with open(path, "r") as f:
            return json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {path} does not contain valid JSON.")


def test_main_runs_and_writes_required_summary():
    run_main(os.path.join(PROJECT, "cargo_errors.jsonl"), SUMMARY)
    assert os.path.isfile(SUMMARY), f"The file {SUMMARY} does not exist. Did you run the main.py script?"


def test_summary_json_content():
    data = load_json(SUMMARY)
    assert isinstance(data, list), f"Expected the JSON in {SUMMARY} to be a list, but got {type(data).__name__}."
    assert len(data) == 2, f"Expected exactly 2 errors in {SUMMARY}, but found {len(data)}. The state machine bug might not be fully fixed."

    codes = [item.get("code") for item in data if isinstance(item, dict)]
    assert "E0596" in codes, "Expected error code 'E0596' to be present in the parsed errors."
    assert "E0382" in codes, "Expected error code 'E0382' to be present in the parsed errors."

    assert data == [
        {
            "code": "E0596",
            "message": "cannot borrow `x` as mutable, as it is not declared as mutable",
            "file_name": "src/main.rs",
            "line": 5,
        },
        {
            "code": "E0382",
            "message": "value borrowed here after move",
            "file_name": "src/main.rs",
            "line": 10,
        },
    ]


def test_models_and_finalize_preserve_error_structure():
    sys.path.insert(0, PROJECT)
    from models import RustError
    from parser import LogParser

    assert is_dataclass(RustError)
    assert [field.name for field in fields(RustError)] == ["code", "message", "file_name", "line"]

    token = secrets.token_hex(8)
    message = {
        "reason": "compiler-message",
        "message": {
            "message": f"final-{token}",
            "code": {"code": f"E{token}"},
            "level": "error",
            "spans": [{"file_name": f"src/{token}.rs", "line_start": 37}],
        },
    }
    parser = LogParser()
    parser.process_line(json.dumps(message))
    assert parser.errors == [], "The fixture must remain pending until end-of-stream finalization."
    assert callable(getattr(parser, "finalize", None)), "LogParser must define finalize()."
    parser.finalize()
    assert len(parser.errors) == 1
    error = parser.errors[0]
    assert error.__dict__ == {
        "code": f"E{token}",
        "message": f"final-{token}",
        "file_name": f"src/{token}.rs",
        "line": 37,
    }


def test_main_calls_finalize_and_parses_unseen_stream():
    with open(os.path.join(PROJECT, "main.py"), "r") as f:
        tree = ast.parse(f.read())
    assert any(
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr == "finalize"
        for node in ast.walk(tree)
    ), "main.py must call LogParser.finalize() after consuming the input."

    token = secrets.token_hex(8)
    expected = []
    lines = [{"reason": "compiler-artifact", "package_id": token}]
    for index in range(3):
        item = {
            "code": f"X{token}{index}",
            "message": f"random-message-{token}-{index}",
            "file_name": f"generated/{token}_{index}.rs",
            "line": 101 + index,
        }
        expected.append(item)
        lines.append({
            "reason": "compiler-message",
            "message": {
                "message": item["message"],
                "code": {"code": item["code"]},
                "level": "error",
                "spans": [{"file_name": item["file_name"], "line_start": item["line"]}],
            },
        })

    with tempfile.TemporaryDirectory() as tmpdir:
        input_path = os.path.join(tmpdir, "input.jsonl")
        output_path = os.path.join(tmpdir, "output.json")
        with open(input_path, "w") as f:
            f.write("not valid json\n")
            for line in lines:
                f.write(json.dumps(line) + "\n")
        run_main(input_path, output_path)
        assert os.path.isfile(output_path)
        assert load_json(output_path) == expected
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
