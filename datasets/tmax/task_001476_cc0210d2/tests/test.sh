#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import asyncio
import os
import re
import secrets
import subprocess
import sys
import tempfile

PROJECT = "/home/user/data_ingester"
RUNNER = os.path.join(PROJECT, "run_processor.py")
LOG_PATH = "/home/user/success.log"
MAGIC = b"\xBA\xAD\xF0\x0D"


def run_processor(input_dir, timeout=8):
    if os.path.exists(LOG_PATH):
        os.unlink(LOG_PATH)
    try:
        result = subprocess.run(
            [sys.executable, RUNNER, input_dir],
            cwd=PROJECT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as exc:
        raise AssertionError(f"Processor hung for input directory {input_dir}") from exc
    assert result.returncode == 0, (
        f"Processor exited with {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(LOG_PATH), "Processor completed without creating success.log"
    with open(LOG_PATH, "r") as f:
        content = f.read().strip()
    match = re.fullmatch(r"Success:\s*(\d+),\s*Failed:\s*(\d+)", content)
    assert match, f"Unexpected success.log content: {content!r}"
    return int(match.group(1)), int(match.group(2))


def expected_counts(input_dir):
    success = failed = 0
    for filename in os.listdir(input_dir):
        path = os.path.join(input_dir, filename)
        if not os.path.isfile(path):
            continue
        with open(path, "rb") as f:
            for line in f:
                if MAGIC in line:
                    failed += 1
                else:
                    success += 1
    return success, failed


def test_setup_py_fixed():
    setup_path = "/home/user/data_ingester/setup.py"
    assert os.path.isfile(setup_path), f"{setup_path} is missing."

    with open(setup_path, "r") as f:
        content = f.read()

    try:
        ast.parse(content)
    except SyntaxError as e:
        assert False, f"setup.py still contains a syntax error: {e}"

    assert "'asyncio'" in content or '"asyncio"' in content, "asyncio missing from setup.py"
    assert "'logging'" in content or '"logging"' in content, "logging missing from setup.py"
    assert "asyncio'logging" not in content.replace(" ", "").replace("\n", ""), "Comma is still missing between asyncio and logging."

    result = subprocess.run(
        [sys.executable, "-m", "pip", "install", "--no-deps", "--force-reinstall", "-e", "."],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Editable installation failed.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    imported = subprocess.run(
        [sys.executable, "-c", "import ingester"],
        cwd="/tmp",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert imported.returncode == 0, f"Installed package cannot be imported: {imported.stderr}"


def test_minimized_crash_bin():
    crash_path = "/home/user/minimized_crash.bin"
    assert os.path.isfile(crash_path), f"The file {crash_path} was not created."

    with open(crash_path, "rb") as f:
        content = f.read()

    assert MAGIC in content, "minimized_crash.bin does not contain the correct magic bytes."
    assert len(content) <= 16, "minimized_crash.bin is not properly minimized. It should contain only the minimal byte sequence."
    assert content == MAGIC, "minimized_crash.bin is not the exact minimum failure-inducing byte sequence."

    sys.path.insert(0, PROJECT)
    from ingester.parser import parse_record

    try:
        parse_record(content)
    except ValueError:
        pass
    else:
        assert False, "The minimized input does not reproduce the parser error."

    for i in range(len(content)):
        candidate = content[:i] + content[i + 1:]
        try:
            parse_record(candidate)
        except Exception as exc:
            assert False, f"A smaller candidate still triggers a parser error: {candidate!r}: {exc}"


def test_async_worker_fixed():
    worker_path = "/home/user/data_ingester/ingester/async_worker.py"
    assert os.path.isfile(worker_path), f"{worker_path} is missing."

    with open(worker_path, "r") as f:
        content = f.read()

    tree = ast.parse(content)

    class TaskDoneChecker(ast.NodeVisitor):
        def __init__(self):
            self.safe = False

        def visit_Try(self, node):
            finally_has_task_done = False
            for stmt in node.finalbody:
                if self._contains_task_done(stmt):
                    finally_has_task_done = True

            except_has_task_done = False
            for handler in node.handlers:
                for stmt in handler.body:
                    if self._contains_task_done(stmt):
                        except_has_task_done = True

            try_has_task_done = False
            for stmt in node.body:
                if self._contains_task_done(stmt):
                    try_has_task_done = True

            if finally_has_task_done or (try_has_task_done and except_has_task_done):
                self.safe = True

            self.generic_visit(node)

        def _contains_task_done(self, node):
            found = False
            for child in ast.walk(node):
                if isinstance(child, ast.Call):
                    if isinstance(child.func, ast.Attribute) and child.func.attr == "task_done":
                        found = True
            return found

    checker = TaskDoneChecker()
    checker.visit(tree)
    assert checker.safe, "async_worker.py does not properly call queue.task_done() for both success and exception paths."

    sys.path.insert(0, PROJECT)
    from ingester.async_worker import worker

    async def exercise_worker():
        queue = asyncio.Queue()
        stats = {"success": 0, "failed": 0}
        task = asyncio.create_task(worker("verification-worker", queue, stats))
        queue.put_nowait(b"valid-" + secrets.token_bytes(8))
        queue.put_nowait(b"bad-" + MAGIC + b"-record")
        try:
            await asyncio.wait_for(queue.join(), timeout=3)
        finally:
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)
        return stats

    stats = asyncio.run(exercise_worker())
    assert stats == {"success": 1, "failed": 1}, f"Worker produced incorrect statistics: {stats}"


def test_processor_handles_derived_inputs_without_hanging():
    with tempfile.TemporaryDirectory(prefix="ingester-verifier-") as input_dir:
        records = []
        for _ in range(4 + secrets.randbelow(5)):
            records.append(b"valid-" + secrets.token_hex(12).encode())
        for _ in range(2 + secrets.randbelow(4)):
            records.append(
                b"corrupt-" + secrets.token_hex(5).encode() + MAGIC + secrets.token_hex(5).encode()
            )

        # Spread records across randomly named files so the verifier does not trust
        # a pre-created report or only exercise the known fixture layout.
        for index, record in enumerate(records):
            path = os.path.join(input_dir, secrets.token_hex(8) + ".bin")
            with open(path, "wb") as f:
                f.write(record + b"\n")

        expected = expected_counts(input_dir)
        actual = run_processor(input_dir)
        assert actual == expected, f"Processor reported {actual}; expected {expected}"


def test_success_log():
    input_dir = "/home/user/inputs"
    expected = expected_counts(input_dir)
    actual = run_processor(input_dir)
    assert actual == expected, f"Processor reported {actual} for supplied inputs; expected {expected}"

    log_path = "/home/user/success.log"
    assert os.path.isfile(log_path), f"The file {log_path} was not created. Did the processor run successfully?"

    with open(log_path, "r") as f:
        content = f.read().strip()

    match = re.match(r"Success:\s*(\d+),\s*Failed:\s*(\d+)", content)
    assert match, f"success.log content '{content}' does not match expected format 'Success: X, Failed: Y'."

    success_count = int(match.group(1))
    failed_count = int(match.group(2))

    assert success_count > 0, "Expected at least one successful record."
    assert failed_count > 0, "Expected at least one failed record (the malformed one)."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
