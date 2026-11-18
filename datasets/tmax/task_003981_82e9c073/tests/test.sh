#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import signal
import stat
import subprocess
import time
import pytest

MAGIC = 170


def expected_output(data):
    return bytes(b if 48 <= b <= 57 else b ^ MAGIC for b in data)


def run_processor(path, data):
    try:
        proc = subprocess.run(
            [path],
            input=data,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=2,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Processor {path} timed out")
    assert proc.returncode == 0, f"Processor {path} exited with {proc.returncode}: {proc.stderr!r}"
    return proc.stdout


def test_env_sh():
    env_path = "/home/user/env.sh"
    assert os.path.isfile(env_path), f"{env_path} does not exist"
    with open(env_path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "TZ" in content and "Europe/Berlin" in content, f"{env_path} does not contain the correct TZ export"
    assert "export " in content, f"{env_path} does not export the variable"

    proc = subprocess.run(
        ["/bin/bash", "-c", 'source /home/user/env.sh && printf "%s" "$TZ" && export -p | grep -q "declare -x TZ="'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env={"HOME": "/home/user", "PATH": "/usr/bin:/bin"},
        timeout=2,
    )
    assert proc.returncode == 0, f"env.sh could not be sourced or did not export TZ: {proc.stderr!r}"
    assert proc.stdout == b"Europe/Berlin", f"env.sh sets TZ incorrectly: {proc.stdout!r}"


def test_route_conf():
    route_path = "/home/user/route.conf"
    assert os.path.isfile(route_path), f"{route_path} does not exist"
    with open(route_path, "r") as f:
        content = f.read().strip()

    expected = "default via 192.168.1.1 dev eth1"
    assert content == expected, f"{route_path} content mismatch. Expected: '{expected}', Got: '{content}'"


def test_processor_source_and_fuzz_equivalence():
    source_path = "/home/user/processor.c"
    agent_path = "/home/user/processor"
    rebuilt_path = "/tmp/processor_from_source"

    assert os.path.isfile(source_path), f"C source {source_path} is missing"
    assert stat.S_ISREG(os.lstat(source_path).st_mode), f"{source_path} is not a regular file"
    assert os.path.isfile(agent_path), f"Agent executable {agent_path} is missing"
    assert os.access(agent_path, os.X_OK), f"Agent executable {agent_path} is not executable"
    with open(agent_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{agent_path} is not a compiled executable"

    build = subprocess.run(
        ["gcc", "-O2", "-std=c11", source_path, "-o", rebuilt_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert build.returncode == 0, f"processor.c does not compile: {build.stderr.decode(errors='replace')}"

    cases = [
        b"",
        bytes(range(256)),
        b"0123456789",
        b"abcXYZ\x00\xff09",
    ]
    random.seed(42)
    for _ in range(500):
        length = random.randint(1, 4096)
        cases.append(bytes(random.randint(0, 255) for _ in range(length)))

    for i, input_data in enumerate(cases):
        expected = expected_output(input_data)
        for path in (agent_path, rebuilt_path):
            actual = run_processor(path, input_data)
            assert actual == expected, (
                f"Output mismatch for {path} on case {i}.\n"
                f"Input length: {len(input_data)}\n"
                f"Expected output length: {len(expected)}\n"
                f"Actual output length: {len(actual)}\n"
                f"Expected output (first 20 bytes): {expected[:20]!r}\n"
                f"Actual output (first 20 bytes): {actual[:20]!r}"
            )


def write_fifo_when_ready(path, data, timeout=3):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            fd = os.open(path, os.O_WRONLY | os.O_NONBLOCK)
        except OSError:
            time.sleep(0.02)
            continue
        try:
            os.write(fd, data)
        finally:
            os.close(fd)
        return
    pytest.fail("Supervisor did not provide a reader for sensor_data")


def wait_for_log(path, expected, timeout=3):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with open(path, "rb") as f:
                actual = f.read()
        except FileNotFoundError:
            actual = b""
        if actual == expected:
            return
        if len(actual) > len(expected) or not expected.startswith(actual):
            pytest.fail(f"processed.log contains unexpected data: {actual!r}")
        time.sleep(0.02)
    pytest.fail(f"processed.log did not reach expected content {expected!r}")


def test_supervisor_sh():
    supervisor_path = "/home/user/supervisor.sh"
    fifo_path = "/home/user/sensor_data"
    log_path = "/home/user/processed.log"

    assert os.path.isfile(supervisor_path), f"{supervisor_path} does not exist"
    assert os.access(supervisor_path, os.X_OK), f"{supervisor_path} is not executable"

    with open(supervisor_path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "env.sh" in content, "supervisor.sh does not source env.sh"
    assert "mkfifo" in content or "mknod" in content, "supervisor.sh does not create a named pipe"
    assert "sensor_data" in content, "supervisor.sh does not reference sensor_data"
    assert "while" in content or "until" in content, "supervisor.sh does not contain a loop"
    assert "processor" in content, "supervisor.sh does not run the processor"
    assert "processed.log" in content, "supervisor.sh does not append to processed.log"

    for path in (fifo_path, log_path):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    proc = subprocess.Popen(
        [supervisor_path],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )
    try:
        deadline = time.time() + 3
        while time.time() < deadline:
            if proc.poll() is not None:
                pytest.fail(f"supervisor.sh terminated early: {proc.stderr.read()!r}")
            try:
                if stat.S_ISFIFO(os.stat(fifo_path).st_mode):
                    break
            except FileNotFoundError:
                pass
            time.sleep(0.02)
        else:
            pytest.fail("supervisor.sh did not create sensor_data as a named pipe")

        first = b"A1\x00z"
        second = b"9\xffB2"
        write_fifo_when_ready(fifo_path, first)
        wait_for_log(log_path, expected_output(first))

        # Closing the first writer gives the processor EOF. A second successful
        # write verifies that the supervisor restarted it and appends output.
        write_fifo_when_ready(fifo_path, second)
        wait_for_log(log_path, expected_output(first) + expected_output(second))
        assert proc.poll() is None, "supervisor.sh stopped instead of continuing its loop"
    finally:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.wait(timeout=2)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
