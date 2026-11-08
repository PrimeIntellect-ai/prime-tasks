#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import asyncio
import collections
import json
import os
import random
import secrets
import signal
import socket
import subprocess
import sys
import time

SERVER_PROCESS = None
BASELINE_LOG = b""
RESPONSES = []


def test_server_listening():
    """Verify that the agent left a process listening on 127.0.0.1:8765."""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        result = s.connect_ex(("127.0.0.1", 8765))
        assert result == 0, "No process is listening on 127.0.0.1:8765."
    finally:
        s.close()


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
        except (FileNotFoundError, ProcessLookupError):
            pass

    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return pids


def stop_existing_listener():
    pids = listener_pids(8765)
    for pid in pids:
        os.kill(pid, signal.SIGTERM)
    deadline = time.time() + 3
    while time.time() < deadline and listener_pids(8765):
        time.sleep(0.05)
    for pid in listener_pids(8765):
        os.kill(pid, signal.SIGKILL)
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids(8765):
        time.sleep(0.05)
    assert not listener_pids(8765), "Could not stop the existing listener for artifact testing."


def wait_for_server(proc):
    deadline = time.time() + 8
    while time.time() < deadline:
        if proc.poll() is not None:
            break
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            if s.connect_ex(("127.0.0.1", 8765)) == 0:
                return
        time.sleep(0.1)
    output = ""
    try:
        with open("/tmp/verifier_scheduler_server.out") as f:
            output = f.read()
    except OSError:
        pass
    raise AssertionError(f"server.py did not start listening on 127.0.0.1:8765. Output:\n{output}")


def make_cases():
    # Retain the original satisfiable and unsatisfiable checks.
    cases = [
        {
            "tasks": [{"id": "t1", "required_skill": "A"}, {"id": "t2", "required_skill": "A"}],
            "workers": [{"id": "w1", "skill": "A"}, {"id": "w2", "skill": "B"}, {"id": "w3", "skill": "A"}],
        },
        {
            "tasks": [{"id": "t1", "required_skill": "A"}, {"id": "t2", "required_skill": "A"}],
            "workers": [{"id": "w1", "skill": "A"}, {"id": "w2", "skill": "B"}],
        },
    ]

    rng = random.SystemRandom()
    nonce = secrets.token_hex(8)
    for case_no in range(10):
        skills = [f"skill-{nonce}-{case_no}-{i}" for i in range(rng.randint(2, 5))]
        task_counts = {skill: rng.randint(1, 4) for skill in skills}
        make_unsat = case_no % 2 == 1
        deficient = rng.choice(skills) if make_unsat else None

        tasks = []
        workers = []
        for skill in skills:
            for i in range(task_counts[skill]):
                tasks.append({"id": f"task-{nonce}-{case_no}-{skill}-{i}", "required_skill": skill})

            worker_count = task_counts[skill] + rng.randint(0, 2)
            if skill == deficient:
                worker_count = task_counts[skill] - 1
            for i in range(worker_count):
                workers.append({"id": f"worker-{nonce}-{case_no}-{skill}-{i}", "skill": skill})

        # Add workers with irrelevant skills to ensure membership and skill are checked.
        workers.append({"id": f"decoy-{nonce}-{case_no}", "skill": f"irrelevant-{nonce}-{case_no}"})
        rng.shuffle(tasks)
        rng.shuffle(workers)
        cases.append({"tasks": tasks, "workers": workers})
    return cases


def is_feasible(payload):
    needed = collections.Counter(task["required_skill"] for task in payload["tasks"])
    available = collections.Counter(worker["skill"] for worker in payload["workers"])
    return all(available[skill] >= count for skill, count in needed.items())


def validate_response(payload, response):
    assert isinstance(response, dict), f"Response is not a JSON object: {response!r}"
    if not is_feasible(payload):
        assert response == {"error": "unsatisfiable"}, f"Incorrect unsatisfiable response: {response!r}"
        return

    assert set(response) == {"assignments"}, f"Successful response has incorrect keys: {response!r}"
    assignments = response["assignments"]
    assert isinstance(assignments, list), f"assignments is not a list: {response!r}"
    assert len(assignments) == len(payload["tasks"]), "Not every task was assigned exactly once."

    tasks = {task["id"]: task for task in payload["tasks"]}
    workers = {worker["id"]: worker for worker in payload["workers"]}
    seen_tasks = set()
    seen_workers = set()
    for assignment in assignments:
        assert isinstance(assignment, dict), f"Assignment is not an object: {assignment!r}"
        assert set(assignment) == {"task_id", "worker_id"}, f"Malformed assignment: {assignment!r}"
        task_id = assignment["task_id"]
        worker_id = assignment["worker_id"]
        assert task_id in tasks, f"Unknown task ID in assignment: {task_id!r}"
        assert worker_id in workers, f"Unknown worker ID in assignment: {worker_id!r}"
        assert task_id not in seen_tasks, f"Task assigned more than once: {task_id!r}"
        assert worker_id not in seen_workers, f"Worker assigned more than once: {worker_id!r}"
        assert workers[worker_id]["skill"] == tasks[task_id]["required_skill"], (
            f"Worker {worker_id!r} lacks the required skill for task {task_id!r}."
        )
        seen_tasks.add(task_id)
        seen_workers.add(worker_id)

    assert seen_tasks == set(tasks), "The assignment does not cover exactly the submitted tasks."


async def exercise(cases):
    try:
        import websockets
    except ImportError as exc:
        raise AssertionError("websockets library is not installed in the environment.") from exc

    results = []
    async with websockets.connect("ws://127.0.0.1:8765", open_timeout=5) as ws:
        for payload in cases:
            await ws.send(json.dumps(payload))
            raw = await asyncio.wait_for(ws.recv(), timeout=5)
            assert isinstance(raw, str), f"Server returned a non-text WebSocket message: {raw!r}"
            try:
                response = json.loads(raw)
            except json.JSONDecodeError as exc:
                raise AssertionError(f"Response is not valid JSON: {raw!r}") from exc
            validate_response(payload, response)
            results.append(response)
    return results


def test_websocket_logic_and_constraints():
    """Restart the submitted artifact and exercise derived satisfiable and unsatisfiable inputs."""
    global SERVER_PROCESS, BASELINE_LOG, RESPONSES
    server_path = "/home/user/scheduler-pr/server.py"
    assert os.path.isfile(server_path), f"Required server artifact does not exist: {server_path}"

    stop_existing_listener()
    output = open("/tmp/verifier_scheduler_server.out", "w")
    SERVER_PROCESS = subprocess.Popen(
        [sys.executable, server_path],
        cwd="/home/user/scheduler-pr",
        stdout=output,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    wait_for_server(SERVER_PROCESS)

    # Seed a marker so overwriting the log cannot pass as appending.
    log_path = "/home/user/scheduler_log.jsonl"
    marker = {"verifier_marker": secrets.token_hex(16)}
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    with open(log_path, "ab+") as f:
        f.seek(0, os.SEEK_END)
        if f.tell() > 0:
            f.seek(-1, os.SEEK_END)
            if f.read(1) != b"\n":
                f.seek(0, os.SEEK_END)
                f.write(b"\n")
        f.seek(0, os.SEEK_END)
        f.write((json.dumps(marker) + "\n").encode())
        f.flush()
    with open(log_path, "rb") as f:
        BASELINE_LOG = f.read()

    cases = make_cases()
    RESPONSES = asyncio.run(exercise(cases))
    assert len(RESPONSES) == len(cases)


def test_scheduler_log_file():
    """Verify every tested response was appended as its own JSON line."""
    log_path = "/home/user/scheduler_log.jsonl"
    assert os.path.exists(log_path), f"Log file {log_path} does not exist. Did you append to it?"

    deadline = time.time() + 3
    data = b""
    expected_total_lines = len(BASELINE_LOG.splitlines()) + len(RESPONSES)
    while time.time() < deadline:
        with open(log_path, "rb") as f:
            data = f.read()
        if len(data.splitlines()) >= expected_total_lines:
            break
        time.sleep(0.05)

    assert data.startswith(BASELINE_LOG), "The existing scheduler log was overwritten instead of appended to."
    suffix = data[len(BASELINE_LOG):]
    assert suffix.endswith(b"\n"), "The final logged response is not terminated by a newline."
    raw_lines = suffix.splitlines()
    assert len(raw_lines) == len(RESPONSES), (
        f"Expected exactly {len(RESPONSES)} appended response lines, found {len(raw_lines)}."
    )

    logged = []
    for line in raw_lines:
        assert line.strip(), "The response log contains an empty appended line."
        try:
            value = json.loads(line)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"Log file contains an invalid JSON line: {line!r}") from exc
        assert isinstance(value, dict), f"Logged response is not a JSON object: {value!r}"
        logged.append(value)

    assert logged == RESPONSES, "Logged responses do not exactly match the responses sent to clients."

    lines = [line.strip() for line in data.decode().splitlines() if line.strip()]
    assert len(lines) >= 2, f"Log file should contain at least 2 JSON lines after testing, found {len(lines)}."
    log1 = json.loads(lines[-2])
    log2 = json.loads(lines[-1])
    assert "assignments" in log1 or "error" in log1, "Second-to-last log entry missing expected keys."
    assert "assignments" in log2 or "error" in log2, "Last log entry missing expected keys."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
