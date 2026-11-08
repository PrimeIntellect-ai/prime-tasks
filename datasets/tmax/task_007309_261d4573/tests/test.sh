#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import stat
import re
import sys
import uuid
import subprocess
import importlib.util
import unittest.mock as unittest_mock
import pytest


def test_project_structure():
    assert os.path.isdir("/home/user/math_project"), "/home/user/math_project directory is missing"
    assert os.path.isdir("/home/user/math_project/src"), "/home/user/math_project/src directory is missing"
    assert os.path.isdir("/home/user/math_project/tests"), "/home/user/math_project/tests directory is missing"

    assert os.path.isfile("/home/user/math_project/src/parser.py"), "parser.py was not moved to src"
    assert os.path.isfile("/home/user/math_project/tests/test_parser.py"), "test_parser.py was not moved to tests"

    assert os.path.isfile("/home/user/math_project/src/__init__.py"), "src/__init__.py is missing"
    assert os.path.isfile("/home/user/math_project/tests/__init__.py"), "tests/__init__.py is missing"


def test_parser_fixed():
    parser_path = "/home/user/math_project/src/parser.py"
    with open(parser_path, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert re.search(r"def\s+__init__\s*\(\s*self\s*\)\s*:", content), "parser.py does not have an __init__ method"
    assert re.search(r"self\.stack\s*=\s*\[\]", content), "parser.py does not initialize self.stack in __init__"

    class_def = re.search(r"class\s+RPNParser\s*:(.*?)(?:def\s+__init__|def\s+parse_and_evaluate)", content, re.DOTALL)
    if class_def:
        assert "stack = []" not in class_def.group(1), "parser.py still has a class-level stack attribute"

    # Execute the submitted parser and verify independent per-instance state.
    name = "submitted_parser_" + uuid.uuid4().hex
    spec = importlib.util.spec_from_file_location(name, parser_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    parser_class = module.RPNParser

    p1 = parser_class()
    p2 = parser_class()
    assert p1.stack is not p2.stack, "RPNParser instances share the same stack"
    p1.stack.append(99)
    assert p2.stack == [], "changing one parser instance changes another instance"
    p1.stack.clear()

    assert p1.parse_and_evaluate("3 4 +") == 7
    assert p1.parse_and_evaluate("5 6 *") == 30, "sequential parses on one instance fail"
    assert p2.parse_and_evaluate("2 3 + 4 *") == 20


def test_test_parser_implemented():
    test_path = "/home/user/math_project/tests/test_parser.py"
    with open(test_path, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "mock_open" in content, "test_parser.py does not use mock_open"
    assert "patch" in content, "test_parser.py does not use patch"
    assert "builtins.open" in content or "'open'" in content, "test_parser.py does not patch open"
    assert "20" in content, "test_parser.py does not assert the result is 20"
    assert "2 3 + 4 *" in content, "test_parser.py does not contain the mock file content '2 3 + 4 *'"

    # Invoke test_file_read with instrumentation to verify that the required mock,
    # file read, parser call, and assertion are actually performed.
    src_dir = "/home/user/math_project/src"
    sys.path.insert(0, src_dir)
    sys.modules.pop("parser", None)
    module_name = "submitted_test_parser_" + uuid.uuid4().hex
    spec = importlib.util.spec_from_file_location(module_name, test_path)
    test_module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(test_module)

    mock_open_calls = []
    patch_calls = []
    parser_inputs = []
    parser_instances = []
    assertions = []
    created_mocks = []
    real_mock_open = unittest_mock.mock_open
    real_patch = unittest_mock.patch

    def tracked_mock_open(*args, **kwargs):
        mock_open_calls.append((args, kwargs))
        mocked = real_mock_open(*args, **kwargs)
        created_mocks.append(mocked)
        return mocked

    def tracked_patch(*args, **kwargs):
        patch_calls.append((args, kwargs))
        return real_patch(*args, **kwargs)

    class SpyParser:
        def __init__(self):
            parser_instances.append(self)

        def parse_and_evaluate(self, expression):
            parser_inputs.append(expression)
            return 20

    old_library_mock_open = unittest_mock.mock_open
    old_library_patch = unittest_mock.patch
    old_module_mock_open = getattr(test_module, "mock_open", None)
    old_module_patch = getattr(test_module, "patch", None)
    old_module_parser = test_module.RPNParser

    try:
        unittest_mock.mock_open = tracked_mock_open
        unittest_mock.patch = tracked_patch
        if hasattr(test_module, "mock_open"):
            test_module.mock_open = tracked_mock_open
        if hasattr(test_module, "patch"):
            test_module.patch = tracked_patch
        test_module.RPNParser = SpyParser

        case = test_module.TestRPNParser(methodName="test_file_read")
        case.assertEqual = lambda first, second, *args, **kwargs: assertions.append((first, second))
        case.test_file_read()
    finally:
        unittest_mock.mock_open = old_library_mock_open
        unittest_mock.patch = old_library_patch
        if old_module_mock_open is not None:
            test_module.mock_open = old_module_mock_open
        if old_module_patch is not None:
            test_module.patch = old_module_patch
        test_module.RPNParser = old_module_parser
        sys.path.remove(src_dir)

    assert mock_open_calls, "test_file_read does not call mock_open"
    assert any(
        kwargs.get("read_data") == "2 3 + 4 *" or (args and args[0] == "2 3 + 4 *")
        for args, kwargs in mock_open_calls
    ), "mock_open is not configured with '2 3 + 4 *'"
    assert any(args and args[0] == "builtins.open" for args, kwargs in patch_calls), "test_file_read does not patch builtins.open"
    assert created_mocks and any(mock.call_args and mock.call_args.args and mock.call_args.args[0] == "data.txt" for mock in created_mocks), "test_file_read does not open data.txt"
    assert any(mock().read.called for mock in created_mocks), "test_file_read does not read the mocked file"
    assert parser_instances, "test_file_read does not create a new RPNParser"
    assert parser_inputs == ["2 3 + 4 *"], "test_file_read does not pass the mocked file contents to the parser"
    assert any(first == 20 and second == 20 for first, second in assertions), "test_file_read does not assert that the parser result is 20"


def test_run_tests_sh():
    script_path = "/home/user/run_tests.sh"
    assert os.path.isfile(script_path), "run_tests.sh is missing"

    # Preserve the original script assertions.
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), "run_tests.sh is not executable"

    with open(script_path, "r") as f:
        content = f.read()

    assert "cd /home/user/math_project" in content or "cd math_project" in content, "run_tests.sh does not change directory to math_project"
    assert "PYTHONPATH=src" in content, "run_tests.sh does not export PYTHONPATH=src"
    assert "python3 -m unittest discover -s tests" in content, "run_tests.sh does not run the tests correctly"
    assert ">" in content and "test_results.log" in content, "run_tests.sh does not redirect output to test_results.log"

    # Run the submitted script with an instrumented python3. This proves that it
    # invokes unittest from the requested directory with PYTHONPATH set and sends
    # both stdout and stderr to a newly generated log.
    token = uuid.uuid4().hex
    out_token = "VERIFIER_STDOUT_" + token
    err_token = "VERIFIER_STDERR_" + token
    shim_dir = "/tmp/python-shim-" + token
    marker = "/tmp/python-marker-" + token
    rc_marker = "/tmp/python-rc-" + token
    os.mkdir(shim_dir)
    shim = os.path.join(shim_dir, "python3")
    with open(shim, "w") as f:
        f.write("#!/bin/bash\n")
        f.write('printf "%s\\n" "$PWD|$PYTHONPATH|$*" > "$VERIFIER_MARKER"\n')
        f.write('printf "%s\\n" "$VERIFIER_OUT_TOKEN"\n')
        f.write('printf "%s\\n" "$VERIFIER_ERR_TOKEN" >&2\n')
        f.write('/usr/bin/python3 "$@"\n')
        f.write('rc=$?\n')
        f.write('printf "%s\\n" "$rc" > "$VERIFIER_RC_MARKER"\n')
        f.write('exit "$rc"\n')
    os.chmod(shim, 0o755)

    log_path = "/home/user/test_results.log"
    if os.path.exists(log_path):
        os.unlink(log_path)

    env = os.environ.copy()
    env["PATH"] = shim_dir + os.pathsep + env.get("PATH", "")
    env["VERIFIER_MARKER"] = marker
    env["VERIFIER_RC_MARKER"] = rc_marker
    env["VERIFIER_OUT_TOKEN"] = out_token
    env["VERIFIER_ERR_TOKEN"] = err_token
    result = subprocess.run([script_path], cwd="/home/user", env=env, timeout=30)

    assert result.returncode == 0, "run_tests.sh returned a failure status"
    assert os.path.isfile(marker), "run_tests.sh did not execute python3"
    assert os.path.isfile(rc_marker), "the unittest command did not finish"
    assert open(rc_marker).read().strip() == "0", "the submitted unittest suite failed"

    invocation = open(marker).read().strip()
    invocation_parts = invocation.split("|", 2)
    assert invocation_parts[0] == "/home/user/math_project", "run_tests.sh did not run unittest from math_project"
    assert invocation_parts[1] == "src", "run_tests.sh did not export PYTHONPATH=src before running unittest"
    assert invocation_parts[2] == "-m unittest discover -s tests", "run_tests.sh invoked the wrong test command"

    assert os.path.isfile(log_path), "run_tests.sh did not create test_results.log"
    log_content = open(log_path).read()
    assert out_token in log_content, "run_tests.sh did not redirect standard output to test_results.log"
    assert err_token in log_content, "run_tests.sh did not redirect standard error to test_results.log"


def test_test_results_log():
    log_path = "/home/user/test_results.log"
    assert os.path.isfile(log_path), "test_results.log is missing (did you run the script?)"

    with open(log_path, "r") as f:
        content = f.read()

    assert "Ran 2 tests" in content, "test_results.log does not indicate that 2 tests ran"
    assert "OK" in content, "test_results.log does not indicate that tests passed (OK)"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
