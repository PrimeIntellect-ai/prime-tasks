#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib
import importlib.machinery
import importlib.metadata
import json
import os
import random
import runpy
import string
import subprocess
import sys
import types

import pytest
from packaging.requirements import Requirement
from packaging.version import Version

ROOT = "/home/user/waf_pipeline"


def test_parser_c_fixed():
    file_path = os.path.join(ROOT, "parser.c")
    assert os.path.isfile(file_path), f"{file_path} is missing."
    with open(file_path, "r") as f:
        content = f.read()
    assert "strcpy(buffer, input);" not in content, "parser.c still contains the strcpy vulnerability."
    assert (
        "strncpy" in content
        or "snprintf" in content
        or "strlcpy" in content
        or 'PyArg_ParseTuple(args, "s#", &input, &length)' in content
    ), "parser.c does not seem to use a safe string copy function."


def test_setup_py_exists_and_builds_extension():
    setup_path = os.path.join(ROOT, "setup.py")
    assert os.path.isfile(setup_path), f"{setup_path} is missing. setup.py was not created."

    built = subprocess.run(
        [sys.executable, "setup.py", "build_ext", "--inplace", "--force"],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert built.returncode == 0, f"setup.py could not build the extension:\n{built.stdout}"

    installed = subprocess.run(
        [sys.executable, "-m", "pip", "install", "-e", ".", "--no-deps"],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert installed.returncode == 0, f"pip install -e . failed:\n{installed.stdout}"


def test_requirements_conflict_resolved_and_installed():
    path = os.path.join(ROOT, "requirements.txt")
    assert os.path.isfile(path), f"{path} is missing."
    requirements = []
    with open(path, encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if line and not line.startswith("#"):
                requirements.append(Requirement(line))

    by_name = {r.name.lower(): r for r in requirements}
    assert "flask" in by_name, "Flask is missing from requirements.txt."
    assert "werkzeug" in by_name, "Werkzeug is missing from requirements.txt."
    assert Version("2.0.0") in by_name["werkzeug"].specifier, (
        "Werkzeug must be upgraded to a constraint compatible with version 2.0.0."
    )
    assert Version("1.0.1") not in by_name["werkzeug"].specifier, (
        "The incompatible Werkzeug 1.0.1 constraint remains."
    )

    for req in requirements:
        try:
            installed = Version(importlib.metadata.version(req.name))
        except importlib.metadata.PackageNotFoundError:
            pytest.fail(f"Required dependency {req.name} is not installed.")
        assert installed in req.specifier, (
            f"Installed {req.name} {installed} does not satisfy {req.specifier}."
        )


def test_waf_parser_importable_and_correct():
    sys.path.insert(0, ROOT)
    importlib.invalidate_caches()
    sys.modules.pop("waf_parser", None)
    try:
        waf_parser = importlib.import_module("waf_parser")
    except ImportError as e:
        pytest.fail(f"Could not import waf_parser. Ensure it was compiled and installed. Error: {e}")

    assert hasattr(waf_parser, "extract_payload"), "waf_parser is missing the extract_payload function."
    origin = getattr(waf_parser, "__file__", "") or ""
    assert any(origin.endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES), (
        f"waf_parser must be the compiled C extension, not a Python substitute: {origin}"
    )

    rng = random.Random(os.urandom(16))
    alphabet = string.ascii_letters + string.digits + " /?='<>;-_"
    for length in [0, 1, 17, 127, 254, 255]:
        value = "".join(rng.choice(alphabet) for _ in range(length))
        result = waf_parser.extract_payload(value)
        assert isinstance(result, str), "extract_payload should return a string."
        assert result == value, f"extract_payload corrupted a valid {length}-byte input."

    for length in [256, 300, 1024]:
        value = "".join(rng.choice(alphabet) for _ in range(length))
        result = waf_parser.extract_payload(value)
        assert isinstance(result, str), "extract_payload should return a string for oversized input."
        assert value.startswith(result), "Oversized input must be copied safely without inventing data."

    large_string = "A" * 300
    try:
        result = waf_parser.extract_payload(large_string)
        assert isinstance(result, str), "extract_payload should return a string."
    except Exception as e:
        pytest.fail(f"extract_payload raised an exception on large input: {e}")


def test_run_waf_has_custom_trie():
    path = os.path.join(ROOT, "run_waf.py")
    assert os.path.isfile(path), f"{path} is missing."
    with open(path, encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=path)

    trie_classes = [n for n in ast.walk(tree) if isinstance(n, ast.ClassDef) and n.name == "Trie"]
    assert trie_classes, "run_waf.py must define a custom Trie class."

    instantiated_names = set()
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            value = node.value
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            if isinstance(value, ast.Call) and isinstance(value.func, ast.Name) and value.func.id == "Trie":
                for target in targets:
                    if isinstance(target, ast.Name):
                        instantiated_names.add(target.id)
    assert instantiated_names, "The custom Trie class is defined but never instantiated."

    used = False
    for node in ast.walk(tree):
        if (
            isinstance(node, ast.Call)
            and isinstance(node.func, ast.Attribute)
            and isinstance(node.func.value, ast.Name)
            and node.func.value.id in instantiated_names
        ):
            used = True
            break
    assert used, "The instantiated Trie is never used to insert or search signatures."


def test_original_waf_execution_and_blocked_log_correct():
    run_path = os.path.join(ROOT, "run_waf.py")
    assert os.path.isfile(run_path), f"{run_path} is missing."
    completed = subprocess.run(
        [sys.executable, run_path],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert completed.returncode == 0, f"run_waf.py failed on the supplied inputs:\n{completed.stdout}"

    file_path = os.path.join(ROOT, "blocked.log")
    assert os.path.isfile(file_path), f"{file_path} is missing. WAF script might not have produced output."
    with open(file_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "[BLOCKED] admin'-- IN GET /login?user=admin'-- HTTP/1.1",
        "[BLOCKED] <script> IN POST /submit?data=<script>alert(1)</script> HTTP/1.1",
        "[BLOCKED] DROP TABLE IN GET /api/data?query=SELECT * FROM users; DROP TABLE users; HTTP/1.1",
        "[BLOCKED] /etc/passwd IN GET /home?file=../../../../etc/passwd HTTP/1.1",
    ]
    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} blocked payloads, but found {len(lines)}."
    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch.\nExpected: {expected}\nActual: {actual}"


def test_waf_executes_parser_and_handles_unseen_data():
    rules_path = os.path.join(ROOT, "rules.json")
    payloads_path = os.path.join(ROOT, "payloads.txt")
    blocked_path = os.path.join(ROOT, "blocked.log")
    run_path = os.path.join(ROOT, "run_waf.py")

    originals = {}
    for path in [rules_path, payloads_path, blocked_path]:
        originals[path] = open(path, "rb").read() if os.path.exists(path) else None

    token = os.urandom(10).hex()
    rules = [f"sigA_{token}", f"sigB_{token}", f"sigC_{token}"]
    payloads = [f"RAW_{i}_{token}" for i in range(6)]
    extracted = {
        payloads[0]: payloads[0],
        payloads[1]: payloads[1] + "::" + rules[2],
        payloads[2]: payloads[2],
        payloads[3]: rules[0] + "::" + payloads[3],
        payloads[4]: payloads[4] + "::" + rules[1],
        payloads[5]: payloads[5],
    }
    expected = [
        f"[BLOCKED] {rules[2]} IN {payloads[1]}",
        f"[BLOCKED] {rules[0]} IN {payloads[3]}",
        f"[BLOCKED] {rules[1]} IN {payloads[4]}",
    ]

    fake = types.ModuleType("waf_parser")
    calls = []

    def extract_payload(value):
        calls.append(value)
        key = value.rstrip("\r\n")
        assert key in extracted, f"Parser received an unexpected value: {value!r}"
        return extracted[key]

    fake.extract_payload = extract_payload
    previous_module = sys.modules.get("waf_parser")
    old_cwd = os.getcwd()
    old_argv = sys.argv[:]
    try:
        with open(rules_path, "w", encoding="utf-8") as f:
            json.dump(rules, f)
        with open(payloads_path, "w", encoding="utf-8") as f:
            f.write("\n".join(payloads) + "\n")
        if os.path.exists(blocked_path):
            os.remove(blocked_path)

        sys.modules["waf_parser"] = fake
        os.chdir(ROOT)
        sys.argv = [run_path]
        try:
            runpy.run_path(run_path, run_name="__main__")
        except SystemExit as exc:
            assert exc.code in (None, 0), f"run_waf.py exited with status {exc.code}"

        assert len(calls) == len(payloads), (
            f"extract_payload must be called once for every payload; got {len(calls)} calls for {len(payloads)} lines."
        )
        assert [value.rstrip("\r\n") for value in calls] == payloads, (
            "Payloads were not passed to extract_payload in input order."
        )
        assert os.path.isfile(blocked_path), "run_waf.py did not create blocked.log for unseen inputs."
        with open(blocked_path, encoding="utf-8") as f:
            actual = [line.strip() for line in f if line.strip()]
        assert actual == expected, f"Incorrect WAF output for unseen rules/payloads.\nExpected: {expected}\nActual: {actual}"
    finally:
        os.chdir(old_cwd)
        sys.argv = old_argv
        if previous_module is None:
            sys.modules.pop("waf_parser", None)
        else:
            sys.modules["waf_parser"] = previous_module
        for path, data in originals.items():
            if data is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
