#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_deployer_behavior.py
import json
import os
import signal
import subprocess
import time
import uuid

WORKER = "/home/user/worker.sh"
LOG_DIR = "/home/user/logs"
LOG = os.path.join(LOG_DIR, "deploy.log")
BAK = LOG + ".bak"
MANIFEST = "/home/user/manifest.json"
SOURCE = "/home/user/deployer.go"
BINARY = "/tmp/deployer-under-test"


def worker_processes():
    found = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            raw = open(f"/proc/{name}/cmdline", "rb").read()
            args = [part.decode(errors="replace") for part in raw.split(b"\0") if part]
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue
        if WORKER in args:
            found.append((int(name), args))
    return found


def stop_all_workers():
    pids = [pid for pid, _ in worker_processes()]
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline:
        remaining = [pid for pid, _ in worker_processes() if pid in pids]
        if not remaining:
            return
        time.sleep(0.05)
    for pid, _ in worker_processes():
        if pid in pids:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def wait_for(predicate, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(0.05)
    return False


def read_text(path):
    with open(path, "r") as f:
        return f.read()


def test_compiled_deployer_performs_staged_rollout():
    assert os.path.isfile(SOURCE), "/home/user/deployer.go does not exist. You must write the Go program."

    stop_all_workers()
    os.makedirs(LOG_DIR, exist_ok=True)
    for path in (LOG, BAK):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    token = uuid.uuid4().hex
    target = f"v9.{token}.0"
    event_log = f"/tmp/deployer-events-{token}"

    instrumented_worker = r'''#!/bin/bash
ID=$1
VERSION=$2
trap 'printf "TERM %s %s %s %s\n" "$ID" "$VERSION" "$$" "$(date +%s%N)" >> "$EVENT_LOG"; exit 0' TERM
printf "START %s %s %s %s\n" "$ID" "$VERSION" "$$" "$(date +%s%N)" >> "$EVENT_LOG"
echo "[$(date -Iseconds)] WORKER $ID STARTED VERSION $VERSION" >> /home/user/logs/deploy.log
echo "PADDING LOG ENTRY TO ENSURE IT EXCEEDS ONE HUNDRED BYTES FOR THE INITIAL STARTUP SEQUENCE. THIS IS PADDING." >> /home/user/logs/deploy.log
while true; do
    sleep 0.1
 done
'''
    with open(WORKER, "w") as f:
        f.write(instrumented_worker)
    os.chmod(WORKER, 0o755)

    with open(MANIFEST, "w") as f:
        json.dump({"target_version": target}, f, indent=3)
        f.write("\n")

    env = os.environ.copy()
    env["EVENT_LOG"] = event_log
    initial = []
    try:
        for worker_id in (1, 2, 3):
            initial.append(subprocess.Popen(
                [WORKER, str(worker_id), "v1.0.0"],
                env=env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            ))

        assert wait_for(lambda: os.path.isfile(LOG) and read_text(LOG).count("VERSION v1.0.0") >= 3), \
            "Failed to establish the three initial v1.0.0 workers."
        assert os.path.getsize(LOG) > 100, "The controlled initial deployment log was not larger than 100 bytes."

        with open(BAK, "w") as f:
            f.write("STALE BACKUP MUST BE OVERWRITTEN\n")

        build = subprocess.run(
            ["go", "build", "-o", BINARY, SOURCE],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=30,
        )
        assert build.returncode == 0, f"deployer.go does not compile successfully:\n{build.stdout}"

        started_at = time.time()
        run = subprocess.run(
            [BINARY],
            cwd="/home/user",
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=15,
        )
        elapsed = time.time() - started_at
        assert run.returncode == 0, f"The compiled deployer exited unsuccessfully:\n{run.stdout}"

        assert os.path.isfile(BAK), "Log rotation failed: /home/user/logs/deploy.log.bak does not exist."
        backup = read_text(BAK)
        assert "VERSION v1.0.0" in backup, "The backup log file does not contain the initial v1.0.0 entries."
        assert "PADDING" in backup, "The backup log file does not contain the initial padding."
        assert "STALE BACKUP MUST BE OVERWRITTEN" not in backup, "Log rotation did not overwrite the existing backup."

        assert os.path.isfile(LOG), "/home/user/logs/deploy.log does not exist."
        new_log = read_text(LOG)
        for worker_id in (1, 2, 3):
            expected = f"WORKER {worker_id} STARTED VERSION {target}"
            assert expected in new_log, f"New log file is missing start message for worker {worker_id}: {expected}"
        assert "VERSION v1.0.0" not in new_log, "The new log file still contains v1.0.0 entries. Log rotation may not have been performed correctly."

        processes = worker_processes()
        for worker_id in (1, 2, 3):
            old = [pid for pid, args in processes if str(worker_id) in args and "v1.0.0" in args]
            assert not old, f"Old process 'worker.sh {worker_id} v1.0.0' is still running."
            new = [pid for pid, args in processes if str(worker_id) in args and target in args]
            assert new, f"New process 'worker.sh {worker_id} {target}' is not running."

        events = [line.split() for line in read_text(event_log).splitlines() if line.strip()]
        old_pids = {str(worker_id): str(proc.pid) for worker_id, proc in zip((1, 2, 3), initial)}
        for worker_id in (1, 2, 3):
            wid = str(worker_id)
            term = [e for e in events if len(e) == 5 and e[0] == "TERM" and e[1] == wid and e[2] == "v1.0.0" and e[3] == old_pids[wid]]
            start = [e for e in events if len(e) == 5 and e[0] == "START" and e[1] == wid and e[2] == target]
            assert term, f"Worker {worker_id} was not gracefully terminated with SIGTERM."
            assert start, f"Worker {worker_id} was not started using the manifest target version."
            assert int(term[0][4]) <= int(start[0][4]), f"Worker {worker_id} was replaced before its old process handled SIGTERM."

        starts = [e for e in events if len(e) == 5 and e[0] == "START" and e[2] == target]
        starts.sort(key=lambda e: int(e[4]))
        assert [e[1] for e in starts] == ["1", "2", "3"], "Workers were not rolled out sequentially in ID order."
        gaps = [(int(starts[i + 1][4]) - int(starts[i][4])) / 1_000_000_000 for i in range(2)]
        for index, gap in enumerate(gaps, start=1):
            assert 0.80 <= gap <= 1.80, f"Rollout gap after worker {index} was {gap:.3f}s instead of one second."
        assert elapsed >= 1.6, "The deployer returned too quickly to have staged both one-second rollout intervals."
    finally:
        stop_all_workers()
        for proc in initial:
            if proc.poll() is None:
                proc.kill()
PYTEST_EOF

if python3 -m pytest /tmp/test_deployer_behavior.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
