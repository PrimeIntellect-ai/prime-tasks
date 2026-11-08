#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'INDEPENDENT_EOF' > /tmp/independent_server_check.py
import asyncio
import importlib.util
import os

SERVER_PATH = "/home/user/server.py"
assert os.path.isfile(SERVER_PATH), f"Missing required file: {SERVER_PATH}"

spec = importlib.util.spec_from_file_location("submitted_server", SERVER_PATH)
assert spec is not None and spec.loader is not None, "Unable to load server.py"
server_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server_module)
assert hasattr(server_module, "start_server"), "server.py must define start_server"

async def check_server():
    srv = await asyncio.wait_for(server_module.start_server(), timeout=5)
    baseline = set(asyncio.all_tasks())
    new_pending = []

    try:
        reader, writer = await asyncio.wait_for(
            asyncio.open_connection("127.0.0.1", 8888), timeout=5
        )
        writer.write(b"GET / HTTP/1.1\r\n\r\n")
        await asyncio.wait_for(writer.drain(), timeout=5)
        await asyncio.wait_for(reader.read(100), timeout=5)
        writer.close()
        await asyncio.wait_for(writer.wait_closed(), timeout=5)

        await asyncio.sleep(0.1)

        current = asyncio.current_task()
        all_tasks = asyncio.all_tasks()
        leaked_workers = [
            task for task in all_tasks
            if task is not current
            and not task.done()
            and getattr(task.get_coro(), "__name__", "") == "background_worker"
        ]
        new_pending = [
            task for task in all_tasks
            if task is not current
            and task not in baseline
            and not task.done()
        ]

        assert not leaked_workers, "Leaked background_worker tasks detected"
        assert not new_pending, "Connection left pending background tasks: " + repr(new_pending)
    finally:
        srv.close()
        await srv.wait_closed()
        for task in new_pending:
            task.cancel()
        if new_pending:
            await asyncio.gather(*new_pending, return_exceptions=True)

asyncio.run(check_server())
INDEPENDENT_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess


def test_crash_path_extracted():
    path_file = "/home/user/crash_path.txt"
    assert os.path.isfile(path_file), f"Missing required file: {path_file}"

    with open(path_file, "r") as f:
        content = f.read().strip()

    expected_path = "/api/v1/trigger_leak_992"
    assert content == expected_path, f"Expected {path_file} to contain '{expected_path}', but got '{content}'"


def test_flag_extracted():
    flag_file = "/home/user/flag.txt"
    assert os.path.isfile(flag_file), f"Missing required file: {flag_file}"

    with open(flag_file, "r") as f:
        content = f.read().strip()

    expected_flag = "FLAG_{m3m0ry_t4sk_l34k_f0und}"
    assert content == expected_flag, f"Expected {flag_file} to contain '{expected_flag}', but got '{content}'"


def test_build_passes_without_leaks():
    test_script = "/home/user/test_build.py"
    assert os.path.isfile(test_script), f"Missing required file: {test_script}"

    result = subprocess.run(
        ["python3", test_script],
        capture_output=True,
        text=True,
        timeout=15
    )

    assert result.returncode == 0, f"Expected test_build.py to exit with code 0, but got {result.returncode}. Output: {result.stdout}\n{result.stderr}"
    assert "PASS" in result.stdout, f"Expected 'PASS' in output, but got: {result.stdout}"
    assert "FAIL" not in result.stdout, f"Expected no failures in output, but got: {result.stdout}"


def test_server_independently_has_no_leaks():
    result = subprocess.run(
        ["python3", "/tmp/independent_server_check.py"],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=15
    )
    assert result.returncode == 0, (
        "Independent server leak check failed. "
        f"Output: {result.stdout}\n{result.stderr}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
