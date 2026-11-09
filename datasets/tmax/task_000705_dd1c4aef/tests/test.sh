#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import asyncio
import importlib.util
import json
import os
import subprocess

REPO_DIR = "/home/user/async_service"
SERVER_PATH = os.path.join(REPO_DIR, "server.py")


def test_config_recovered():
    config_path = os.path.join(REPO_DIR, "config.json")
    assert os.path.isfile(config_path), "config.json was not recovered to /home/user/async_service/config.json"
    with open(config_path, "r") as f:
        try:
            config = json.load(f)
        except json.JSONDecodeError:
            assert False, "config.json is not valid JSON"
    assert "SECRET_KEY" in config, "config.json does not contain SECRET_KEY"
    assert config["SECRET_KEY"] == "sk_prod_99x2b_a1z", "SECRET_KEY value is incorrect in config.json"


def test_resolution_report_exists_and_valid():
    report_path = "/home/user/resolution_report.json"
    assert os.path.isfile(report_path), "resolution_report.json is missing"

    with open(report_path, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            assert False, "resolution_report.json is not valid JSON"

    assert "secret_key" in report, "resolution_report.json missing 'secret_key'"
    assert report["secret_key"] == "sk_prod_99x2b_a1z", "Incorrect secret_key in resolution_report.json"

    assert "fixed_files" in report, "resolution_report.json missing 'fixed_files'"
    assert "server.py" in report["fixed_files"], "server.py not listed in fixed_files"

    assert "culprit_commit" in report, "resolution_report.json missing 'culprit_commit'"

    try:
        output = subprocess.check_output(
            ["git", "log", "--grep=Feature: add heavy background processing per request", "--format=%H"],
            cwd=REPO_DIR,
            text=True,
        ).strip()
        expected_commit = output.splitlines()[0] if output else ""
    except Exception:
        expected_commit = ""

    assert expected_commit != "", "Could not find culprit commit in git history"
    assert report["culprit_commit"] == expected_commit, (
        f"Incorrect culprit_commit in resolution_report.json. Expected {expected_commit}"
    )


def _is_create_task_call(node):
    return (
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr == "create_task"
    )


def test_server_py_fixed_and_assert_added():
    assert os.path.isfile(SERVER_PATH), "server.py is missing"

    with open(SERVER_PATH, "r") as f:
        content = f.read()

    # Retain the original source-level assertions.
    assert "cancel()" in content, "server.py does not appear to call cancel() on the background task"
    assert "assert" in content, "server.py does not contain an assert statement to validate the fix"

    try:
        tree = ast.parse(content)
    except SyntaxError:
        assert False, "server.py has invalid Python syntax"

    has_assert = any(isinstance(node, ast.Assert) for node in ast.walk(tree))
    assert has_assert, "No assert statement found in server.py AST"

    handlers = [
        node for node in ast.walk(tree)
        if isinstance(node, (ast.AsyncFunctionDef, ast.FunctionDef)) and node.name == "handle_client"
    ]
    assert handlers, "server.py does not define handle_client"
    handler = handlers[0]

    created_task_names = set()
    for node in ast.walk(handler):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            value = node.value
            if _is_create_task_call(value):
                targets = node.targets if isinstance(node, ast.Assign) else [node.target]
                for target in targets:
                    created_task_names.update(
                        child.id for child in ast.walk(target) if isinstance(child, ast.Name)
                    )

    relevant_assert = False
    for assertion in (node for node in ast.walk(handler) if isinstance(node, ast.Assert)):
        names = {node.id for node in ast.walk(assertion.test) if isinstance(node, ast.Name)}
        attrs = {node.attr for node in ast.walk(assertion.test) if isinstance(node, ast.Attribute)}
        calls = {
            node.func.id
            for node in ast.walk(assertion.test)
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
        }
        task_reference = bool(names & created_task_names) or any(
            marker in name.lower()
            for name in names
            for marker in ("task", "active", "background")
        )
        completion_check = bool(attrs & {"done", "cancelled", "all_tasks"}) or bool(
            calls & {"len", "sum", "all", "any"}
        )
        if task_reference and completion_check:
            relevant_assert = True
            break

    assert relevant_assert, (
        "handle_client must contain a nontrivial assertion checking that its background task "
        "is done/cancelled or that its active-task count is zero"
    )


def _load_server_module():
    old_cwd = os.getcwd()
    try:
        os.chdir(REPO_DIR)
        spec = importlib.util.spec_from_file_location("submitted_server", SERVER_PATH)
        assert spec is not None and spec.loader is not None, "Could not load server.py"
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module
    finally:
        os.chdir(old_cwd)


class ImmediateReader:
    def __init__(self, data):
        self.data = data

    async def read(self, _size):
        return self.data


class BlockingReader:
    async def read(self, _size):
        await asyncio.Event().wait()


class FakeWriter:
    def __init__(self):
        self.closed = False
        self.writes = []

    def get_extra_info(self, _name):
        return ("127.0.0.1", 12345)

    def write(self, data):
        self.writes.append(data)

    async def drain(self):
        return None

    def close(self):
        self.closed = True

    async def wait_closed(self):
        return None


async def _live_new_tasks(baseline):
    await asyncio.sleep(0)
    await asyncio.sleep(0)
    current = asyncio.current_task()
    return [
        task for task in asyncio.all_tasks()
        if task is not current and task not in baseline and not task.done()
    ]


async def _cleanup(tasks):
    for task in tasks:
        task.cancel()
    if tasks:
        await asyncio.gather(*tasks, return_exceptions=True)


async def _exercise_disconnects(module):
    # EOF is the ordinary immediate-disconnect path that originally leaked.
    writer = FakeWriter()
    baseline = set(asyncio.all_tasks())
    await asyncio.wait_for(module.handle_client(ImmediateReader(b""), writer), timeout=2)
    leaked = await _live_new_tasks(baseline)
    try:
        assert writer.closed, "handle_client did not close the writer after EOF"
        assert not leaked, "A background task remained active after an immediate client disconnect"
    finally:
        await _cleanup(leaked)

    # Also exercise a completed request; its per-connection task must be gone.
    writer = FakeWriter()
    baseline = set(asyncio.all_tasks())
    await asyncio.wait_for(module.handle_client(ImmediateReader(b"hello"), writer), timeout=2)
    leaked = await _live_new_tasks(baseline)
    try:
        assert writer.closed, "handle_client did not close the writer after a request"
        assert not leaked, "A background task remained active after a completed request"
    finally:
        await _cleanup(leaked)

    # Exercise cancellation while the handler is blocked reading from the client.
    writer = FakeWriter()
    baseline = set(asyncio.all_tasks())
    handler_task = asyncio.create_task(module.handle_client(BlockingReader(), writer))
    await asyncio.sleep(0)
    await asyncio.sleep(0)
    handler_task.cancel()
    try:
        await asyncio.wait_for(handler_task, timeout=2)
    except asyncio.CancelledError:
        pass
    leaked = await _live_new_tasks(baseline)
    try:
        assert writer.closed, "handle_client did not close the writer when cancelled"
        assert not leaked, "A background task remained active after handler cancellation"
    finally:
        await _cleanup(leaked)


def test_server_behavior_has_no_orphaned_connection_tasks():
    module = _load_server_module()
    assert asyncio.iscoroutinefunction(module.handle_client), "handle_client must be asynchronous"
    asyncio.run(_exercise_disconnects(module))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
