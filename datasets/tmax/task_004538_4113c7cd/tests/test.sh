#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import subprocess
import tempfile
import textwrap
import uuid

import pytest

EVIL_DIR = "/app/corpora/evil"
CLEAN_DIR = "/app/corpora/clean"
SANITIZER_SCRIPT = "/home/user/sanitizer.py"
REQUESTER_SCRIPT = "/home/user/requester.py"


def run_sanitizer(filepath):
    return subprocess.run(
        ["python3", SANITIZER_SCRIPT, filepath],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )


def assert_classification(filepath, expected_code, expected_output):
    result = run_sanitizer(filepath)
    assert result.returncode == expected_code, (
        f"Wrong exit code for {filepath}: expected {expected_code}, got "
        f"{result.returncode}. stderr={result.stderr!r}"
    )
    assert result.stdout.strip() == expected_output, (
        f"Wrong output for {filepath}: expected {expected_output!r}, "
        f"got {result.stdout!r}"
    )


def test_sanitizer_exists():
    assert os.path.isfile(SANITIZER_SCRIPT), f"Sanitizer script missing at {SANITIZER_SCRIPT}"


def test_requester_exists():
    assert os.path.isfile(REQUESTER_SCRIPT), f"Requester script missing at {REQUESTER_SCRIPT}"


def test_requester_uses_asyncio():
    with open(REQUESTER_SCRIPT, "r") as f:
        source = f.read()

    tree = ast.parse(source)
    uses_asyncio = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "asyncio":
                    uses_asyncio = True
        elif isinstance(node, ast.ImportFrom):
            if node.module == "asyncio":
                uses_asyncio = True

    assert uses_asyncio, "The requester.py script must use asyncio to replicate the concurrency pattern."


def test_sanitizer_evil_corpus():
    if not os.path.isfile(SANITIZER_SCRIPT):
        pytest.fail(f"Cannot test evil corpus: {SANITIZER_SCRIPT} does not exist.")

    evil_files = [os.path.join(EVIL_DIR, f) for f in os.listdir(EVIL_DIR) if f.endswith(".json")]
    assert evil_files, f"No JSON files found in {EVIL_DIR}"

    bypassed = []
    for filepath in evil_files:
        result = run_sanitizer(filepath)
        if result.returncode != 1 or result.stdout.strip() != "EVIL":
            bypassed.append(os.path.basename(filepath))

    if bypassed:
        pytest.fail(
            f"{len(bypassed)} of {len(evil_files)} evil requests had the wrong status/output: "
            f"{', '.join(bypassed)}"
        )


def test_sanitizer_clean_corpus():
    if not os.path.isfile(SANITIZER_SCRIPT):
        pytest.fail(f"Cannot test clean corpus: {SANITIZER_SCRIPT} does not exist.")

    clean_files = [os.path.join(CLEAN_DIR, f) for f in os.listdir(CLEAN_DIR) if f.endswith(".json")]
    assert clean_files, f"No JSON files found in {CLEAN_DIR}"

    modified = []
    for filepath in clean_files:
        result = run_sanitizer(filepath)
        if result.returncode != 0 or result.stdout.strip() != "CLEAN":
            modified.append(os.path.basename(filepath))

    if modified:
        pytest.fail(
            f"{len(modified)} of {len(clean_files)} clean requests had the wrong status/output: "
            f"{', '.join(modified)}"
        )


def test_sanitizer_unseen_requests_and_exact_boundaries():
    token = uuid.uuid4().hex
    cases = [
        ({"method": "POST", "path": "/auth/login", "headers": {}, "body": {"username": f"admin_{token}"}}, 1, "EVIL"),
        ({"method": "GET", "path": "/auth/login", "headers": {"X-Test": token}, "body": {"username": "admin_"}}, 1, "EVIL"),
        ({"method": "POST", "path": "/auth/login", "headers": {}, "body": {"username": f"user_{token}"}}, 0, "CLEAN"),
        ({"method": "POST", "path": "/auth/login", "headers": {}, "body": {"username": "admin"}}, 0, "CLEAN"),
        ({"method": "POST", "path": "/auth/login", "headers": {}, "body": {"username": f"xadmin_{token}"}}, 0, "CLEAN"),
        ({"method": "POST", "path": "/auth/login/", "headers": {}, "body": {"username": f"admin_{token}"}}, 0, "CLEAN"),
        ({"method": "POST", "path": "/api/auth/login", "headers": {}, "body": {"username": f"admin_{token}"}}, 0, "CLEAN"),
        ({"method": "POST", "path": "/auth/Login", "headers": {}, "body": {"username": f"admin_{token}"}}, 0, "CLEAN"),
        ({"method": "POST", "path": "/auth/login", "headers": {}, "body": {"other": f"admin_{token}"}}, 0, "CLEAN"),
    ]

    with tempfile.TemporaryDirectory(prefix="gateway_requests_") as directory:
        for index, (request, expected_code, expected_output) in enumerate(cases):
            filepath = os.path.join(directory, f"request_{index}_{token}.json")
            with open(filepath, "w") as f:
                json.dump(request, f)
            assert_classification(filepath, expected_code, expected_output)


def test_requester_processes_files_with_actual_async_concurrency():
    with tempfile.TemporaryDirectory(prefix="requester_input_") as input_dir, tempfile.TemporaryDirectory(prefix="async_trace_") as trace_dir:
        nested = os.path.join(input_dir, "nested")
        os.makedirs(nested)
        expected_paths = []
        for index in range(6):
            parent = nested if index % 2 else input_dir
            path = os.path.join(parent, f"request_{index}_{uuid.uuid4().hex}.json")
            with open(path, "w") as f:
                json.dump({"index": index}, f)
            expected_paths.append(path)

        marker = os.path.join(trace_dir, "asyncio_trace.json")
        sitecustomize = textwrap.dedent(
            """
            import atexit
            import asyncio
            import json
            import os

            _created = []
            _concurrent = False
            _original_create_task = asyncio.BaseEventLoop.create_task

            def _tracked_create_task(self, coro, *args, **kwargs):
                global _concurrent
                try:
                    current = asyncio.current_task(loop=self)
                except Exception:
                    current = None
                try:
                    pending_others = [
                        task for task in asyncio.all_tasks(self)
                        if not task.done() and task is not current
                    ]
                    if pending_others:
                        _concurrent = True
                except Exception:
                    pass

                code = getattr(coro, "cr_code", None)
                _created.append(getattr(code, "co_qualname", type(coro).__name__))
                return _original_create_task(self, coro, *args, **kwargs)

            asyncio.BaseEventLoop.create_task = _tracked_create_task

            def _write_trace():
                marker = os.environ.get("ASYNC_TRACE_MARKER")
                if marker:
                    with open(marker, "w") as f:
                        json.dump({"created": _created, "concurrent": _concurrent}, f)

            atexit.register(_write_trace)
            """
        )
        with open(os.path.join(trace_dir, "sitecustomize.py"), "w") as f:
            f.write(sitecustomize)

        env = os.environ.copy()
        env["ASYNC_TRACE_MARKER"] = marker
        old_pythonpath = env.get("PYTHONPATH")
        env["PYTHONPATH"] = trace_dir if not old_pythonpath else trace_dir + os.pathsep + old_pythonpath

        result = subprocess.run(
            ["python3", REQUESTER_SCRIPT, input_dir],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
            timeout=15,
        )
        assert result.returncode == 0, f"requester.py failed: {result.stderr!r}"

        output_lines = result.stdout.splitlines()
        for path in expected_paths:
            matching_lines = [line for line in output_lines if path in line]
            assert len(matching_lines) == 1, (
                f"Expected requester.py to print processed path {path!r} exactly once; "
                f"stdout was {result.stdout!r}"
            )

        assert os.path.isfile(marker), "requester.py did not initialize and run an asyncio event loop"
        with open(marker, "r") as f:
            trace = json.load(f)
        assert trace.get("created"), "requester.py did not create asyncio tasks"
        assert trace.get("concurrent") is True, (
            "requester.py did not schedule multiple tasks concurrently; files must not be processed sequentially"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
