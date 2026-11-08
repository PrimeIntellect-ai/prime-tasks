#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import os
import subprocess
import sys
import tempfile
import uuid


def load_service(path):
    spec = importlib.util.spec_from_file_location("flaky_service", path)
    flaky_service = importlib.util.module_from_spec(spec)
    sys.modules["flaky_service"] = flaky_service
    spec.loader.exec_module(flaky_service)
    return flaky_service


def handler_names(node):
    if isinstance(node, ast.Name):
        return {node.id}
    if isinstance(node, ast.Attribute):
        return {node.attr}
    if isinstance(node, ast.Tuple):
        names = set()
        for element in node.elts:
            names.update(handler_names(element))
        return names
    return set()


def test_flaky_service_fixed():
    path = "/home/user/flaky_service.py"
    assert os.path.exists(path), f"File {path} does not exist."
    assert os.path.isfile(path), f"File {path} is not a regular file."

    with open(path, "r", encoding="utf-8") as source_file:
        tree = ast.parse(source_file.read(), filename=path)

    read_cache_nodes = [
        node for node in tree.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        and node.name == "read_cache"
    ]
    assert read_cache_nodes, "read_cache() is missing."
    assert any(
        "FileNotFoundError" in handler_names(handler.type)
        for node in ast.walk(read_cache_nodes[0])
        if isinstance(node, ast.Try)
        for handler in node.handlers
    ), "read_cache() must catch FileNotFoundError inside the function."

    flaky_service = load_service(path)

    # Preserve successful-file behavior: return the actual contents when present.
    expected = "cache-data-" + uuid.uuid4().hex
    with tempfile.NamedTemporaryFile(mode="w", delete=False, encoding="utf-8") as cache_file:
        cache_file.write(expected)
        existing_path = cache_file.name
    try:
        flaky_service.get_cache_file = lambda: existing_path
        assert flaky_service.read_cache() == expected, \
            "read_cache() must still return the contents of an existing cache file."
    finally:
        os.unlink(existing_path)

    # Exercise several independently generated missing paths.
    for _ in range(5):
        missing_path = os.path.join(tempfile.gettempdir(), "missing-cache-" + uuid.uuid4().hex)
        flaky_service.get_cache_file = lambda p=missing_path: p
        try:
            result = flaky_service.read_cache()
        except FileNotFoundError:
            raise AssertionError("read_cache() still raises FileNotFoundError. It should be caught.")
        except Exception as exc:
            raise AssertionError(f"read_cache() raised an unexpected exception: {exc}")
        assert result == "cache miss", \
            f"read_cache() should return 'cache miss', but returned {result!r}"


def test_script_runs_repeatedly_without_crashing(tmp_path):
    path = "/home/user/flaky_service.py"

    # Force every main() iteration down the cache-reading branch, with a missing file.
    sitecustomize = tmp_path / "sitecustomize.py"
    sitecustomize.write_text(
        "import random\n"
        "random.seed = lambda *args, **kwargs: None\n"
        "random.random = lambda: 0.0\n"
        "random.randint = lambda a, b: 987\n",
        encoding="utf-8",
    )
    forced_missing = "/tmp/syscache_987.tmp"
    if os.path.exists(forced_missing):
        os.unlink(forced_missing)

    env = os.environ.copy()
    old_pythonpath = env.get("PYTHONPATH")
    env["PYTHONPATH"] = str(tmp_path) + (os.pathsep + old_pythonpath if old_pythonpath else "")

    for run_number in range(5):
        completed = subprocess.run(
            ["python3", path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
            env=env,
        )
        combined = completed.stdout + completed.stderr
        assert completed.returncode == 0, \
            f"Execution {run_number + 1} crashed with exit code {completed.returncode}:\n{combined}"
        assert "Traceback" not in combined, \
            f"Execution {run_number + 1} produced a traceback:\n{combined}"


def test_syscall_txt_content():
    path = "/home/user/syscall.txt"
    assert os.path.exists(path), f"File {path} does not exist. You need to create it."

    with open(path, "r", encoding="utf-8") as syscall_file:
        content = syscall_file.read().strip()

    assert "openat" in content.lower(), \
        f"The file {path} does not contain the correct system call name. Found: {content}"
    assert content == "openat", \
        f"The file {path} must contain only the exact system call name 'openat'. Found: {content!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
