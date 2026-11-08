#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import subprocess
import sys
import tempfile
import time

import pytest

APP_SERVER = "/app/eval_server.py"
APP_LOADER = "/app/load_tester.py"


def matching_pids(path):
    found = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as fh:
                args = fh.read().replace(b"\0", b" ").decode(errors="replace")
            if path in args:
                found.append(int(entry))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return found


def stop_task_processes():
    for path in (APP_LOADER, APP_SERVER):
        for pid in matching_pids(path):
            if pid != os.getpid():
                try:
                    os.kill(pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
    subprocess.run(["pkill", "-f", "redis-server"], stderr=subprocess.DEVNULL)
    time.sleep(0.4)


def sample_server_rss(current_peak):
    peak = current_peak
    for pid in matching_pids(APP_SERVER):
        try:
            with open(f"/proc/{pid}/status", encoding="utf-8") as fh:
                for line in fh:
                    if line.startswith("VmRSS:"):
                        peak = max(peak, int(line.split()[1]))
                        break
        except (FileNotFoundError, ProcessLookupError, PermissionError, ValueError):
            pass
    return peak


def command_count(info):
    total = 0
    for value in info.values():
        if isinstance(value, dict):
            total += int(value.get("calls", 0))
    return total


def test_run_services_correctness_redis_load_and_memory():
    script_path = "/home/user/run_services.sh"
    assert os.path.isfile(script_path), f"Missing script: {script_path}"

    assert os.path.isfile("/app/expression_pb2.py"), "expression_pb2.py was not generated"
    assert os.path.isfile("/app/expression_pb2_grpc.py"), "expression_pb2_grpc.py was not generated"
    sys.path.insert(0, "/app")
    import expression_pb2
    import expression_pb2_grpc
    assert "ExpressionService" in expression_pb2.DESCRIPTOR.services_by_name
    assert hasattr(expression_pb2_grpc, "ExpressionServiceStub")

    fixture_run = subprocess.run(
        [sys.executable, "-m", "pytest", "/app/tests/test_fixtures.py", "-q"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=30,
    )
    assert fixture_run.returncode == 0, fixture_run.stdout

    stop_task_processes()
    env = os.environ.copy()
    env["REDIS_HOST"] = "127.0.0.1"
    env["REDIS_PORT"] = "6379"
    env["PYTHONPATH"] = "/app" + os.pathsep + env.get("PYTHONPATH", "")

    script_log = tempfile.NamedTemporaryFile(mode="w+", delete=False)
    process = None
    peak_rss = 0
    load_tester_started = False
    load_tester_finished = False

    try:
        process = subprocess.Popen(
            ["bash", script_path],
            stdout=script_log,
            stderr=subprocess.STDOUT,
            env=env,
        )

        start = time.time()
        while time.time() - start < 60:
            peak_rss = sample_server_rss(peak_rss)
            loader_pids = matching_pids(APP_LOADER)
            if loader_pids:
                load_tester_started = True
            elif load_tester_started:
                load_tester_finished = True
                break
            time.sleep(0.05)

        assert load_tester_started, "load_tester.py was never started by the script"
        assert load_tester_finished, "load_tester.py did not finish within the timeout"
        if process.poll() is not None:
            assert process.returncode == 0, "run_services.sh exited unsuccessfully"
        assert matching_pids(APP_SERVER), "eval_server.py did not remain running"

        import redis
        cache = redis.Redis(host=env["REDIS_HOST"], port=int(env["REDIS_PORT"]), socket_timeout=3)
        deadline = time.time() + 10
        while True:
            try:
                assert cache.ping()
                break
            except Exception:
                if time.time() >= deadline:
                    raise
                time.sleep(0.1)

        cache.flushdb()
        before_commands = command_count(cache.info("commandstats"))

        client_source = r'''
import grpc
import sys
sys.path.insert(0, "/app")
import expression_pb2
import expression_pb2_grpc

channel = grpc.insecure_channel("127.0.0.1:50051")
grpc.channel_ready_future(channel).result(timeout=10)
stub = expression_pb2_grpc.ExpressionServiceStub(channel)
for i in range(50000):
    kind = i % 4
    if kind == 0:
        expr, expected = f"({i} == {i}) and ({i}%3 == {i % 3})", True
    elif kind == 1:
        expr, expected = f"({i} < {i-1}) or ({i} != {i})", False
    elif kind == 2:
        expr, expected = f"not ({i} == {i+1})", True
    else:
        expr, expected = f"({i}%5 == {(i+1) % 5})", False
    response = stub.Evaluate(expression_pb2.ExpressionRequest(expr=expr), timeout=5)
    if response.result is not expected:
        print(f"incorrect result at request {i}: {expr!r}", file=sys.stderr)
        sys.exit(1)
print("VERIFIED 50000 REQUESTS")
'''
        with open("/tmp/verifier_load_tester.py", "w", encoding="utf-8") as fh:
            fh.write(client_source)

        client = subprocess.Popen(
            [sys.executable, "/tmp/verifier_load_tester.py"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            env=env,
        )
        client_start = time.time()
        while client.poll() is None and time.time() - client_start < 180:
            peak_rss = sample_server_rss(peak_rss)
            time.sleep(0.05)
        if client.poll() is None:
            client.kill()
            output, _ = client.communicate()
            pytest.fail(f"50,000-request load test timed out\n{output}")
        output, _ = client.communicate()
        peak_rss = sample_server_rss(peak_rss)
        assert client.returncode == 0, f"Load tester failed with status {client.returncode}\n{output}"
        assert "VERIFIED 50000 REQUESTS" in output, f"Load tester did not report completion\n{output}"

        after_commands = command_count(cache.info("commandstats"))
        assert cache.dbsize() > 0, "The gRPC service did not store cached results in Redis"
        assert after_commands - before_commands >= 45000, (
            "Redis was not used for the request stream; expected cache activity for approximately "
            f"50,000 requests, observed {after_commands - before_commands} commands"
        )

        assert peak_rss > 0, "Could not measure memory of eval_server.py"
        assert peak_rss <= 50000, (
            f"Peak RSS memory of eval_server.py was {peak_rss} KB, expected <= 50000 KB"
        )
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        script_log.close()
        stop_task_processes()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
