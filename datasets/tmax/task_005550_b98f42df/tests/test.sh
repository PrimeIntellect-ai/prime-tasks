#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import builtins
import glob
import json
import os
import subprocess
from unittest import mock

import pytest

PROJECT = "/home/user/project"
DATA_DIR = os.path.join(PROJECT, "data")
BUILD_PATH = os.path.join(PROJECT, "build.py")
OUTPUT_PATH = os.path.join(PROJECT, "output.json")
BAD_PATH = os.path.join(DATA_DIR, "file_387.txt")


def data_files():
    return sorted(glob.glob(os.path.join(DATA_DIR, "*.txt")))


def derived_bad_files():
    bad = []
    for path in data_files():
        with open(path, "r", encoding="utf-8", errors="strict") as f:
            try:
                f.read()
            except UnicodeDecodeError:
                bad.append(path)
    return bad


def test_bad_file_log():
    log_path = "/home/user/bad_file.log"
    assert os.path.exists(log_path), f"File {log_path} is missing."
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert content == "file_387.txt", f"Expected 'file_387.txt' in {log_path}, got '{content}'"

    bad = derived_bad_files()
    assert len(bad) == 1, f"Expected exactly one undecodable input, found: {bad}"
    assert content == os.path.basename(bad[0]), "bad_file.log does not name the actual undecodable input."


def test_mre_py():
    mre_path = "/home/user/mre.py"
    assert os.path.exists(mre_path), f"File {mre_path} is missing."
    with open(mre_path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "file_387.txt" in content, "mre.py does not reference the corrupt file 'file_387.txt'."
    result = subprocess.run(["python3", mre_path], capture_output=True, text=True)
    assert result.returncode != 0, "mre.py should crash with an error, but it exited successfully."
    assert "UnicodeDecodeError" in result.stderr, "mre.py did not trigger a UnicodeDecodeError."

    # Ensure the error comes from reading only the bad file with default text decoding,
    # rather than from constructing or explicitly raising an exception.
    tree = ast.parse(content, filename=mre_path)
    assert not any(isinstance(node, ast.Raise) for node in ast.walk(tree)), "mre.py must not explicitly raise an exception."
    assert not any(isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "UnicodeDecodeError" for node in ast.walk(tree)), "mre.py must not manufacture a UnicodeDecodeError."

    open_calls = [
        node for node in ast.walk(tree)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "open"
    ]
    assert len(open_calls) == 1, "mre.py must contain exactly one open() call."
    call = open_calls[0]
    assert len(call.args) >= 2 and isinstance(call.args[1], ast.Constant) and call.args[1].value == "r", "mre.py must use open(..., 'r')."
    assert not any(kw.arg in ("encoding", "errors") for kw in call.keywords), "mre.py must use the default text decoder."
    assert any(isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == "read" for node in ast.walk(tree)), "mre.py must read the opened file."

    opened = []
    real_open = builtins.open

    def tracking_open(path, *args, **kwargs):
        opened.append(os.path.realpath(os.fspath(path)))
        return real_open(path, *args, **kwargs)

    code = compile(content, mre_path, "exec")
    namespace = {"__name__": "__main__", "__file__": mre_path}
    with mock.patch("builtins.open", tracking_open):
        with pytest.raises(UnicodeDecodeError):
            exec(code, namespace, namespace)
    assert opened == [os.path.realpath(BAD_PATH)], f"mre.py must open only the actual bad file; opened {opened}"


def test_build_py_fixed_and_executed():
    assert os.path.exists(BUILD_PATH), f"File {BUILD_PATH} is missing."
    with open(BUILD_PATH, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "errors=" in content and ("'replace'" in content or '"replace"' in content), "build.py does not contain errors='replace'."
    assert "encoding=" in content and ("'utf-8'" in content or '"utf-8"' in content or "'utf8'" in content or '"utf8"' in content), "build.py does not contain encoding='utf-8'."

    tree = ast.parse(content, filename=BUILD_PATH)
    qualifying_calls = []
    for node in ast.walk(tree):
        if not (isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "open"):
            continue
        keywords = {kw.arg: kw.value for kw in node.keywords if kw.arg is not None}
        enc = keywords.get("encoding")
        err = keywords.get("errors")
        if (isinstance(enc, ast.Constant) and enc.value in ("utf-8", "utf8") and
                isinstance(err, ast.Constant) and err.value == "replace"):
            qualifying_calls.append(node)
    assert qualifying_calls, "No open() call actually has encoding='utf-8' and errors='replace'."

    expected_paths = {os.path.realpath(p) for p in data_files()}
    assert len(expected_paths) == 500, f"Expected 500 input files, found {len(expected_paths)}."
    observed = []
    real_open = builtins.open

    def tracking_open(path, *args, **kwargs):
        resolved = os.path.realpath(os.fspath(path))
        if resolved in expected_paths:
            observed.append((resolved, args, dict(kwargs)))
        return real_open(path, *args, **kwargs)

    if os.path.exists(OUTPUT_PATH):
        os.unlink(OUTPUT_PATH)

    code = compile(content, BUILD_PATH, "exec")
    namespace = {"__name__": "__main__", "__file__": BUILD_PATH}
    old_cwd = os.getcwd()
    try:
        os.chdir(PROJECT)
        with mock.patch("builtins.open", tracking_open):
            try:
                exec(code, namespace, namespace)
            except SystemExit as exc:
                assert exc.code in (None, 0), f"build.py exited unsuccessfully with status {exc.code}."
    finally:
        os.chdir(old_cwd)

    assert os.path.exists(OUTPUT_PATH), "Running build.py did not generate output.json."
    assert {item[0] for item in observed} == expected_paths, "build.py did not open every data input file."
    for path, args, kwargs in observed:
        mode = args[0] if args else kwargs.get("mode", "r")
        assert mode == "r", f"Input {path} was not opened in text read mode."
        assert kwargs.get("encoding") in ("utf-8", "utf8"), f"Input {path} was not opened with UTF-8 encoding."
        assert kwargs.get("errors") == "replace", f"Input {path} was not opened with errors='replace'."


def test_output_json():
    assert os.path.exists(OUTPUT_PATH), f"File {OUTPUT_PATH} is missing. Did you run build.py?"
    with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{OUTPUT_PATH} is not valid JSON.")

    # Preserve the original checks for the bad-file entry.
    matching_keys = [k for k in data.keys() if k.endswith("file_387.txt")]
    assert matching_keys, "output.json does not contain a key for file_387.txt."
    val = data[matching_keys[0]]
    assert "\ufffd" in val, "The value for file_387.txt does not contain the replacement character \\ufffd."

    # Derive and validate the complete output from all source files.
    expected = {}
    for path in data_files():
        key = os.path.join("data", os.path.basename(path))
        with open(path, "rb") as f:
            expected[key] = f.read().decode("utf-8", errors="replace")
    assert data == expected, "output.json does not contain the exact decoded contents of all 500 input files."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
