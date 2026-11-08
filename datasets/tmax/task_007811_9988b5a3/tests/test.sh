#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import json
import os
import shutil
import stat
import subprocess
import sys
import tarfile

PACKAGE_SH = "/home/user/package.sh"
PROJECT = "/home/user/log_processor"
TEST_DIR = PROJECT + "/tests"
VENV = "/home/user/venv"
TARBALL = "/home/user/log_processor.tar.gz"
PLUGIN = "/tmp/verifier_plugin.py"


def test_package_sh_exists_and_executable():
    assert os.path.isfile(PACKAGE_SH), f"{PACKAGE_SH} is missing"
    st = os.stat(PACKAGE_SH)
    assert bool(st.st_mode & stat.S_IXUSR), f"{PACKAGE_SH} is not executable"


def test_parser_refactored_and_behaves_per_instance():
    parser_path = PROJECT + "/parser.py"
    assert os.path.isfile(parser_path), f"{parser_path} is missing"

    with open(parser_path, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source)

    classes = [node.name for node in ast.walk(tree) if isinstance(node, ast.ClassDef)]
    assert "LogParser" in classes, "LogParser class not found in parser.py"

    # Preserve the original check for the two module-level assignments.
    for node in tree.body:
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name):
                    assert target.id not in ("CURRENT_STATE", "PARSED_DATA"), \
                        f"Global variable {target.id} found in parser.py"

    module_functions = {
        node.name for node in tree.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
    }
    assert "parse_line" not in module_functions, "parse_line must be encapsulated in LogParser"

    cls = next(node for node in tree.body if isinstance(node, ast.ClassDef) and node.name == "LogParser")
    methods = {
        node.name for node in cls.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
    }
    assert "__init__" in methods, "LogParser must define __init__"
    assert "parse_line" in methods, "LogParser must define parse_line"

    spec = importlib.util.spec_from_file_location("submitted_log_parser", parser_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert not hasattr(module, "CURRENT_STATE"), "CURRENT_STATE must not remain module state"
    assert not hasattr(module, "PARSED_DATA"), "PARSED_DATA must not remain module state"

    LogParser = module.LogParser
    first = LogParser()
    second = LogParser()
    assert first.current_state == "IDLE"
    assert first.parsed_data == []
    assert second.current_state == "IDLE"
    assert second.parsed_data == []
    assert first.parsed_data is not second.parsed_data, "instances must not share parsed_data"

    first.parse_line("  START  ")
    first.parse_line("DATA: 100")
    first.parse_line("DATA: hello")
    assert first.current_state == "ACTIVE"
    assert first.parsed_data == ["100", "hello"]
    assert second.current_state == "IDLE"
    assert second.parsed_data == [], "state leaked between LogParser instances"

    second.parse_line("DATA: ignored")
    assert second.parsed_data == [], "DATA must be ignored while IDLE"
    first.parse_line("STOP")
    assert first.current_state == "IDLE"
    assert first.parsed_data == ["100", "hello"]
    first.parse_line("DATA: ignored-after-stop")
    assert first.parsed_data == ["100", "hello"]


def _constructor_name(call):
    if not isinstance(call, ast.Call):
        return None
    if isinstance(call.func, ast.Name):
        return call.func.id
    if isinstance(call.func, ast.Attribute):
        return call.func.attr
    return None


def _check_updated_test(path):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    # Preserve the original assertion.
    assert "LogParser" in content, f"LogParser not used in {os.path.basename(path)}"

    tree = ast.parse(content)
    assert not any(
        isinstance(node, (ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == "LogParser"
        for node in tree.body
    ), f"{path} must use the parser's LogParser, not define a replacement"

    imports_parser = False
    for node in tree.body:
        if isinstance(node, ast.ImportFrom) and node.module in ("log_processor.parser", "log_processor"):
            imports_parser = True
        if isinstance(node, ast.Import):
            if any(alias.name in ("log_processor.parser", "log_processor") for alias in node.names):
                imports_parser = True
    assert imports_parser, f"{path} does not import LogParser or its parser module"

    tests = [
        node for node in tree.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name.startswith("test_")
    ]
    assert tests, f"No tests found in {path}"
    for fn in tests:
        instance_names = set()
        for node in ast.walk(fn):
            if isinstance(node, ast.Assign) and _constructor_name(node.value) == "LogParser":
                for target in node.targets:
                    if isinstance(target, ast.Name):
                        instance_names.add(target.id)
            elif isinstance(node, ast.AnnAssign) and _constructor_name(node.value) == "LogParser":
                if isinstance(node.target, ast.Name):
                    instance_names.add(node.target.id)
        assert instance_names, f"{fn.name} in {path} must create a fresh LogParser instance"
        used = any(
            isinstance(node, ast.Call)
            and isinstance(node.func, ast.Attribute)
            and node.func.attr == "parse_line"
            and isinstance(node.func.value, ast.Name)
            and node.func.value.id in instance_names
            for node in ast.walk(fn)
        )
        assert used, f"{fn.name} in {path} must call parse_line on its LogParser instance"


def test_test_files_updated():
    _check_updated_test(TEST_DIR + "/test_start.py")
    _check_updated_test(TEST_DIR + "/test_stop.py")


def _write_pytest_probe():
    with open(PLUGIN, "w", encoding="utf-8") as f:
        f.write(r'''
import json
import os
import sys
import pytest


def pytest_sessionfinish(session, exitstatus):
    mode = os.environ.get("VERIFIER_PYTEST_MODE", "success")
    data = {
        "args": list(session.config.invocation_params.args),
        "cwd": os.getcwd(),
        "executable": sys.executable,
        "prefix": sys.prefix,
        "pytest_file": pytest.__file__,
    }
    with open("/tmp/pytest_seen_" + mode + ".json", "w", encoding="utf-8") as out:
        json.dump(data, out)
    if mode == "fail":
        session.exitstatus = pytest.ExitCode.TESTS_FAILED
''')


def _run_package(mode):
    marker = f"/tmp/pytest_seen_{mode}.json"
    if os.path.exists(marker):
        os.unlink(marker)
    env = os.environ.copy()
    env["PYTHONPATH"] = "/tmp" + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    env["PYTEST_ADDOPTS"] = (env.get("PYTEST_ADDOPTS", "") + " -p verifier_plugin").strip()
    env["VERIFIER_PYTEST_MODE"] = mode
    result = subprocess.run([PACKAGE_SH], capture_output=True, text=True, env=env, timeout=300)
    assert os.path.isfile(marker), (
        f"{PACKAGE_SH} did not run pytest; output:\n{result.stdout}\n{result.stderr}"
    )
    with open(marker, "r", encoding="utf-8") as f:
        probe = json.load(f)
    return result, probe


def _assert_pytest_target(probe):
    cwd = os.path.realpath(probe["cwd"])
    targets = []
    for arg in probe["args"]:
        if isinstance(arg, str) and arg and not arg.startswith("-"):
            targets.append(os.path.realpath(arg if os.path.isabs(arg) else os.path.join(cwd, arg)))
    assert os.path.realpath(TEST_DIR) == cwd or os.path.realpath(TEST_DIR) in targets, \
        f"pytest was not run on {TEST_DIR}: cwd={cwd}, args={probe['args']}"
    assert os.path.realpath(probe["prefix"]) == os.path.realpath(VENV), \
        "pytest was not run from the requested virtual environment"
    assert os.path.realpath(probe["executable"]).startswith(os.path.realpath(VENV) + os.sep)


def test_package_sh_execution_and_failure_handling():
    _write_pytest_probe()
    shutil.rmtree(VENV, ignore_errors=True)
    if os.path.exists(TARBALL):
        os.unlink(TARBALL)

    failed, fail_probe = _run_package("fail")
    _assert_pytest_target(fail_probe)
    assert failed.returncode != 0, "package.sh must return non-zero when pytest fails"
    assert not os.path.exists(TARBALL), "package.sh created the tarball despite failed tests"

    succeeded, success_probe = _run_package("success")
    _assert_pytest_target(success_probe)
    assert succeeded.returncode == 0, \
        f"{PACKAGE_SH} failed with output:\n{succeeded.stdout}\n{succeeded.stderr}"


def test_venv_and_pytest_installed():
    pytest_path = VENV + "/bin/pytest"
    assert os.path.isfile(pytest_path), f"{pytest_path} is missing. Did the script install pytest in the venv?"
    assert os.access(pytest_path, os.X_OK), f"{pytest_path} is not executable"
    python = VENV + "/bin/python"
    result = subprocess.run(
        [python, "-c", "import os,sys,pytest; print(os.path.realpath(sys.prefix)); print(os.path.realpath(pytest.__file__))"],
        capture_output=True, text=True
    )
    assert result.returncode == 0, f"pytest is not importable in the venv: {result.stderr}"
    lines = result.stdout.strip().splitlines()
    assert os.path.realpath(lines[0]) == os.path.realpath(VENV)
    assert os.path.realpath(lines[1]).startswith(os.path.realpath(VENV) + os.sep), \
        "pytest was not installed inside /home/user/venv"


def test_tarball_created_and_contains_project():
    assert os.path.isfile(TARBALL), f"{TARBALL} is missing. Did the script create the tarball?"
    required = [
        "log_processor/parser.py",
        "log_processor/__init__.py",
        "log_processor/tests/test_start.py",
        "log_processor/tests/test_stop.py",
    ]
    with tarfile.open(TARBALL, "r:gz") as archive:
        members = archive.getmembers()
        normalized = {}
        for member in members:
            name = member.name
            assert not os.path.isabs(name), f"unsafe absolute tar member: {name}"
            clean = os.path.normpath(name).lstrip("./")
            assert clean != ".." and not clean.startswith("../"), f"unsafe tar member: {name}"
            normalized[clean] = member
        for rel in required:
            assert rel in normalized, f"tarball is missing {rel}"
            member = normalized[rel]
            assert member.isfile(), f"{rel} is not a regular file in the tarball"
            archived = archive.extractfile(member).read()
            with open(os.path.join("/home/user", rel), "rb") as current:
                assert archived == current.read(), f"tarball contains a stale or altered {rel}"


def test_submitted_tests_really_pass_in_venv():
    result = subprocess.run(
        [VENV + "/bin/python", "-m", "pytest", TEST_DIR, "-q"],
        capture_output=True, text=True, timeout=120
    )
    assert result.returncode == 0, f"submitted tests fail:\n{result.stdout}\n{result.stderr}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
