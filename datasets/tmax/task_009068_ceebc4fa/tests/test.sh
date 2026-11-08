#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import os
import random
import re
import shutil
import stat
import subprocess
import sys
from unittest.mock import patch

RELEASE = "/home/user/release"
FIBO = os.path.join(RELEASE, "bin", "fibo")
PRIME = os.path.join(RELEASE, "bin", "prime")


def fibonacci(n):
    a, b = 0, 1
    for _ in range(n):
        a, b = b, a + b
    return a


def nth_prime(n):
    count = 0
    candidate = 1
    while count < n:
        candidate += 1
        for divisor in range(2, int(candidate ** 0.5) + 1):
            if candidate % divisor == 0:
                break
        else:
            count += 1
    return candidate


def run_binary(path, n):
    completed = subprocess.run(
        [path, str(n)], capture_output=True, text=True, timeout=10, check=True
    )
    return int(completed.stdout.strip())


def test_build_script_actually_builds_working_binaries():
    build_path = os.path.join(RELEASE, "build.py")
    assert os.path.isfile(build_path), f"File {build_path} does not exist"

    shutil.rmtree(os.path.join(RELEASE, "bin"), ignore_errors=True)
    subprocess.run(
        [sys.executable, build_path], cwd=RELEASE, timeout=120, check=True
    )

    for path in (FIBO, PRIME):
        assert os.path.isfile(path), f"Binary {path} does not exist"
        assert not os.path.islink(path), f"Binary {path} must be a regular built file"
        assert stat.S_ISREG(os.stat(path).st_mode), f"Binary {path} is not regular"
        assert os.access(path, os.X_OK), f"Binary {path} is not executable"
        with open(path, "rb") as artifact:
            assert artifact.read(4) == b"\x7fELF", f"Binary {path} is not an ELF executable"

    rng = random.SystemRandom()
    fib_inputs = {0, 1, 2, rng.randrange(8, 36), rng.randrange(8, 36)}
    prime_inputs = {1, 2, rng.randrange(8, 55), rng.randrange(8, 55)}
    for n in fib_inputs:
        assert run_binary(FIBO, n) == fibonacci(n)
    for n in prime_inputs:
        assert run_binary(PRIME, n) == nth_prime(n)


def load_server():
    path = os.path.join(RELEASE, "server.py")
    assert os.path.isfile(path), f"File {path} does not exist"
    spec = importlib.util.spec_from_file_location("submitted_release_server", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_server_endpoints_use_subprocess_and_return_required_json():
    module = load_server()
    assert hasattr(module, "app"), "server.py must expose a Flask app named app"
    client = module.app.test_client()

    expected = {
        (FIBO, "10"): b"55\n",
        (PRIME, "5"): b"11\n",
    }
    seen = []

    def fake_run(*args, **kwargs):
        assert args, "subprocess.run must receive a command"
        command = args[0]
        assert isinstance(command, (list, tuple)), "binary command must be an argument list"
        assert len(command) == 2, f"unexpected binary command: {command!r}"
        key = (os.path.abspath(os.fspath(command[0])), str(command[1]))
        assert key in expected, f"unexpected binary command: {command!r}"
        assert kwargs.get("capture_output") is True or kwargs.get("stdout") == subprocess.PIPE, \
            "server must capture binary stdout"
        seen.append(key)
        return subprocess.CompletedProcess(command, 0, stdout=expected[key], stderr=b"")

    with patch("subprocess.run", side_effect=fake_run) as mocked_run:
        fib_response = client.get("/api/fibo/10")
        prime_response = client.get("/api/prime/5")

    assert fib_response.status_code == 200
    assert fib_response.get_json() == {"algorithm": "fibonacci", "n": 10, "result": 55}
    assert prime_response.status_code == 200
    assert prime_response.get_json() == {"algorithm": "prime", "n": 5, "result": 11}
    assert mocked_run.call_count == 2
    assert seen == [(FIBO, "10"), (PRIME, "5")]


def _decorator_is_fixture(decorator):
    if isinstance(decorator, ast.Call):
        decorator = decorator.func
    return (
        isinstance(decorator, ast.Name) and decorator.id == "fixture"
    ) or (
        isinstance(decorator, ast.Attribute) and decorator.attr == "fixture"
    )


def _contains_patch_of_subprocess_run(function):
    for node in ast.walk(function):
        if not isinstance(node, ast.Call):
            continue
        is_patch = (
            isinstance(node.func, ast.Name) and node.func.id == "patch"
        ) or (
            isinstance(node.func, ast.Attribute) and node.func.attr == "patch"
        )
        if is_patch and node.args and isinstance(node.args[0], ast.Constant):
            target = node.args[0].value
            if isinstance(target, str) and target.endswith("subprocess.run"):
                return True
    return False


def _test_references_mock_assertion(function, mock_names):
    for node in ast.walk(function):
        if isinstance(node, ast.Assert):
            if any(isinstance(child, ast.Name) and child.id in mock_names for child in ast.walk(node.test)):
                return True
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
            if node.func.attr.startswith("assert_"):
                if any(isinstance(child, ast.Name) and child.id in mock_names for child in ast.walk(node.func.value)):
                    return True
    return False


def test_submitted_mock_suite_structure_and_execution():
    path = os.path.join(RELEASE, "test_server.py")
    assert os.path.isfile(path), f"File {path} does not exist"
    with open(path, "r", encoding="utf-8") as source_file:
        source = source_file.read()
    tree = ast.parse(source, filename=path)

    imports_unittest_mock = any(
        isinstance(node, ast.ImportFrom) and node.module == "unittest.mock"
        or isinstance(node, ast.Import) and any(alias.name == "unittest.mock" for alias in node.names)
        or isinstance(node, ast.ImportFrom) and node.module == "unittest" and any(alias.name == "mock" for alias in node.names)
        for node in tree.body
    )
    assert imports_unittest_mock, "test_server.py must use unittest.mock.patch"

    fixtures = {
        node.name: node
        for node in tree.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        and any(_decorator_is_fixture(dec) for dec in node.decorator_list)
        and _contains_patch_of_subprocess_run(node)
    }
    assert fixtures, "a pytest fixture must patch subprocess.run"

    tests = {
        node.name: node
        for node in tree.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        and node.name in {"test_fibo_endpoint", "test_prime_endpoint"}
    }
    assert set(tests) == {"test_fibo_endpoint", "test_prime_endpoint"}, \
        "both required endpoint tests must be defined"

    requirements = {
        "test_fibo_endpoint": ("/api/fibo/10", "fibonacci", 55),
        "test_prime_endpoint": ("/api/prime/5", "prime", 11),
    }
    for name, function in tests.items():
        argument_names = {arg.arg for arg in function.args.args}
        used_mock_fixtures = argument_names.intersection(fixtures)
        assert used_mock_fixtures, f"{name} must use the subprocess mock fixture"
        constants = {
            node.value for node in ast.walk(function)
            if isinstance(node, ast.Constant) and isinstance(node.value, (str, int))
        }
        endpoint, algorithm, result = requirements[name]
        assert endpoint in constants, f"{name} must request {endpoint}"
        assert algorithm in constants and result in constants, f"{name} must assert the required JSON result"
        assert _test_references_mock_assertion(function, used_mock_fixtures), \
            f"{name} must verify how the subprocess mock was called"

    byte_constants = {
        node.value for node in ast.walk(tree)
        if isinstance(node, ast.Constant) and isinstance(node.value, bytes)
    }
    assert b"55\n" in byte_constants and b"11\n" in byte_constants, \
        "the fixture must provide the specified byte stdout values"

    backups = {}
    marker = os.path.join(RELEASE, ".binary_was_called_during_mock_tests")
    if os.path.exists(marker):
        os.remove(marker)
    try:
        for binary in (FIBO, PRIME):
            backup = binary + ".verifier-backup"
            shutil.copy2(binary, backup)
            backups[binary] = backup
            with open(binary, "w", encoding="utf-8") as wrapper:
                wrapper.write("#!/bin/sh\necho called >> %s\nexit 97\n" % marker)
            os.chmod(binary, 0o755)

        results_path = os.path.join(RELEASE, "test_results.txt")
        with open(results_path, "w", encoding="utf-8") as output:
            completed = subprocess.run(
                [sys.executable, "-m", "pytest", path, "-v"],
                cwd=RELEASE,
                stdout=output,
                timeout=120,
            )
        assert completed.returncode == 0, "the submitted pytest suite did not pass"
        assert not os.path.exists(marker), "the submitted tests called a real binary instead of mocking subprocess.run"
    finally:
        for binary, backup in backups.items():
            if os.path.exists(backup):
                os.replace(backup, binary)
        if os.path.exists(marker):
            os.remove(marker)


def test_binaries_exist_and_executable():
    fibo_path = "/home/user/release/bin/fibo"
    prime_path = "/home/user/release/bin/prime"

    assert os.path.isfile(fibo_path), f"Binary {fibo_path} does not exist"
    assert os.access(fibo_path, os.X_OK), f"Binary {fibo_path} is not executable"

    assert os.path.isfile(prime_path), f"Binary {prime_path} does not exist"
    assert os.access(prime_path, os.X_OK), f"Binary {prime_path} is not executable"


def test_build_script_exists():
    path = "/home/user/release/build.py"
    assert os.path.isfile(path), f"File {path} does not exist"


def test_server_script_exists():
    path = "/home/user/release/server.py"
    assert os.path.isfile(path), f"File {path} does not exist"


def test_test_server_script_exists_and_uses_mock():
    path = "/home/user/release/test_server.py"
    assert os.path.isfile(path), f"File {path} does not exist"

    with open(path, "r") as f:
        content = f.read()

    assert "patch" in content, "The test_server.py script does not use 'patch'"
    assert "subprocess.run" in content, "The test_server.py script does not mock 'subprocess.run'"


def test_test_results_exist_and_passed():
    path = "/home/user/release/test_results.txt"
    assert os.path.isfile(path), f"File {path} does not exist"

    with open(path, "r") as f:
        content = f.read()

    # Check that tests passed. Pytest outputs something like "2 passed" or "100%"
    assert "failed" not in content.lower() or "0 failed" in content.lower(), "test_results.txt indicates test failures"
    assert "passed" in content.lower(), "test_results.txt does not indicate passing tests"
    assert re.search(r"\b2 passed\b", content.lower()), "exactly the two required tests must pass"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
