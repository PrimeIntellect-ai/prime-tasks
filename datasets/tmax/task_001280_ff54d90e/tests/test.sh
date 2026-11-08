#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import math
import os
import subprocess
import sys

import pytest

HOME = "/home/user"


def _run_python(path, env=None, timeout=120):
    return subprocess.run(
        [sys.executable, path],
        cwd=HOME,
        env=env,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def test_output_json_types_and_values():
    pipeline_path = "/home/user/pipeline.py"
    output_path = "/home/user/output.json"
    assert os.path.isfile(pipeline_path), f"File {pipeline_path} is missing."

    if os.path.exists(output_path):
        os.remove(output_path)
    result = _run_python(pipeline_path)
    assert result.returncode == 0, f"{pipeline_path} failed to run. Stderr: {result.stderr}"
    assert os.path.isfile(output_path), f"File {output_path} is missing."

    with open(output_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{output_path} is not valid JSON.")

    assert isinstance(data, list), "Output JSON should be a list of records."

    with open("/home/user/data.csv", newline="") as f:
        source_rows = list(csv.DictReader(f))

    assert len(data) == len(source_rows), \
        f"Expected {len(source_rows)} output records, got {len(data)}."

    required_keys = {"doc_id", "text", "category_id", "token_length"}
    for i, (row, source) in enumerate(zip(data, source_rows)):
        assert isinstance(row, dict), f"Row {i} should be a JSON object."
        assert required_keys.issubset(row), f"Row {i} is missing required keys."

        expected_category = int(source["category_id"]) if source["category_id"] != "" else None
        expected_token_length = len(source["text"].split()) if source["text"] != "" else None

        cat_id = row.get("category_id")
        if cat_id is not None:
            assert isinstance(cat_id, int) and not isinstance(cat_id, float), \
                f"Row {i}: category_id should be int or null, got {type(cat_id).__name__} ({cat_id})"
            assert type(cat_id) is int

        tok_len = row.get("token_length")
        if tok_len is not None:
            assert isinstance(tok_len, int) and not isinstance(tok_len, float), \
                f"Row {i}: token_length should be int or null, got {type(tok_len).__name__} ({tok_len})"
            assert type(tok_len) is int

        assert cat_id == expected_category, \
            f"Row {i}: expected category_id {expected_category!r}, got {cat_id!r}."
        assert tok_len == expected_token_length, \
            f"Row {i}: expected token_length {expected_token_length!r}, got {tok_len!r}."


def test_pipeline_test_script_exists_and_runs(tmp_path):
    test_script_path = "/home/user/test_pipeline.py"
    assert os.path.isfile(test_script_path), f"File {test_script_path} is missing."

    result = _run_python(test_script_path)
    assert result.returncode == 0, f"{test_script_path} failed to run. Stderr: {result.stderr}"

    source = open(test_script_path, "r").read()
    tree = ast.parse(source, filename=test_script_path)
    constants = {n.value for n in ast.walk(tree) if isinstance(n, ast.Constant) and isinstance(n.value, str)}
    assert "category_id" in constants and "token_length" in constants, \
        "The test must check both category_id and token_length."
    assert any(isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)
               and n.func.attr == "load" for n in ast.walk(tree)), \
        "The test must load the generated JSON."
    assert any(isinstance(n, ast.Assert) and any(isinstance(x, ast.Name) and x.id == "float"
               for x in ast.walk(n.test)) for n in ast.walk(tree)), \
        "The test must contain an assertion that checks for float values."

    imported_names = set()
    module_aliases = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and node.module == "pipeline":
            imported_names.update(a.asname or a.name for a in node.names if a.name == "process_data")
        elif isinstance(node, ast.Import):
            module_aliases.update(a.asname or a.name for a in node.names if a.name == "pipeline")
    calls_pipeline = any(
        isinstance(node, ast.Call) and (
            (isinstance(node.func, ast.Name) and node.func.id in imported_names) or
            (isinstance(node.func, ast.Attribute) and node.func.attr == "process_data" and
             isinstance(node.func.value, ast.Name) and node.func.value.id in module_aliases)
        ) for node in ast.walk(tree)
    )
    assert calls_pipeline, "The test must import and call process_data from pipeline.py."
    assert "/home/user/output.json" in source, "The test must inspect /home/user/output.json."

    hook_dir = tmp_path / "test_hook"
    hook_dir.mkdir()
    (hook_dir / "sitecustomize.py").write_text(
        "import json, pipeline\n"
        "def bad_process_data():\n"
        "    rows = [\n"
        "      {'doc_id': 1, 'text': 'Hello world', 'category_id': 1.0, 'token_length': 2.0},\n"
        "      {'doc_id': 2, 'text': None, 'category_id': 2.0, 'token_length': None},\n"
        "      {'doc_id': 3, 'text': 'Another document', 'category_id': None, 'token_length': 2.0},\n"
        "      {'doc_id': 4, 'text': 'Final text', 'category_id': 3.0, 'token_length': 2.0}]\n"
        "    with open('/home/user/output.json', 'w') as f: json.dump(rows, f)\n"
        "pipeline.process_data = bad_process_data\n"
    )
    env = os.environ.copy()
    env["PYTHONPATH"] = str(hook_dir) + os.pathsep + env.get("PYTHONPATH", "")
    bad_result = _run_python(test_script_path, env=env)
    combined = bad_result.stdout + bad_result.stderr
    assert bad_result.returncode != 0 and "AssertionError" in combined, \
        "test_pipeline.py did not raise AssertionError when the pipeline produced floats."


def test_benchmark_script_and_output(tmp_path):
    benchmark_script = "/home/user/benchmark.py"
    benchmark_txt = "/home/user/benchmark.txt"
    assert os.path.isfile(benchmark_script), f"File {benchmark_script} is missing."

    source = open(benchmark_script, "r").read()
    tree = ast.parse(source, filename=benchmark_script)
    assert any(isinstance(n, ast.ImportFrom) and n.module == "pipeline" and
               any(a.name == "process_data" for a in n.names) for n in ast.walk(tree)), \
        "benchmark.py must import process_data from pipeline.py."
    assert any((isinstance(n, ast.Import) and any(a.name == "timeit" for a in n.names)) or
               (isinstance(n, ast.ImportFrom) and n.module == "timeit") for n in ast.walk(tree)), \
        "benchmark.py must import and use the timeit module."
    assert "/home/user/benchmark.txt" in source, \
        "benchmark.py must write /home/user/benchmark.txt."

    marker = tmp_path / "timeit_calls.jsonl"
    hook_dir = tmp_path / "benchmark_hook"
    hook_dir.mkdir()
    (hook_dir / "sitecustomize.py").write_text(f'''
import json
import pipeline
import timeit

_marker = {str(marker)!r}
_active = False
_count = 0
_original_process_data = pipeline.process_data
_original_timer_timeit = timeit.Timer.timeit

def counted_process_data(*args, **kwargs):
    global _count
    if _active:
        _count += 1
    return _original_process_data(*args, **kwargs)

pipeline.process_data = counted_process_data

def checked_timeit(self, number=timeit.default_number):
    global _active
    before = _count
    _active = True
    try:
        return _original_timer_timeit(self, number)
    finally:
        _active = False
        with open(_marker, "a") as f:
            f.write(json.dumps({{"number": number, "process_calls": _count - before}}) + "\\n")

timeit.Timer.timeit = checked_timeit
''')

    if os.path.exists(benchmark_txt):
        os.remove(benchmark_txt)
    env = os.environ.copy()
    env["PYTHONPATH"] = str(hook_dir) + os.pathsep + env.get("PYTHONPATH", "")
    result = _run_python(benchmark_script, env=env, timeout=180)
    assert result.returncode == 0, f"{benchmark_script} failed to run. Stderr: {result.stderr}"

    assert marker.is_file(), "benchmark.py did not invoke timeit."
    calls = [json.loads(line) for line in marker.read_text().splitlines() if line.strip()]
    assert any(item.get("number") == 100 and item.get("process_calls") == 100 for item in calls), \
        "benchmark.py must use timeit to run process_data exactly 100 times."

    assert os.path.isfile(benchmark_txt), f"File {benchmark_txt} is missing. Did the benchmark script produce it?"
    with open(benchmark_txt, "r") as f:
        content = f.read().strip()
    try:
        val = float(content)
    except ValueError:
        pytest.fail(f"Content of {benchmark_txt} is not a valid float string: '{content}'")
    assert math.isfinite(val) and val >= 0, "benchmark.txt must contain a finite, non-negative time."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
