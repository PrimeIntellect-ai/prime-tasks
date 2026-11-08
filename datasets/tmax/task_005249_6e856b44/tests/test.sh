#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import signal
import socket
import subprocess
import tarfile
import tempfile
import time
import uuid
from pathlib import Path

REPO = Path("/home/user/app_repo")
PATCH = Path("/home/user/fix.patch")
PORTS = {8000, 8001, 8002}


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, capture_output=True, **kwargs)


def kill_port_owners():
    socket_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            try:
                port = int(fields[1].rsplit(":", 1)[1], 16)
                inode = fields[9]
            except (IndexError, ValueError):
                continue
            if port in PORTS:
                socket_inodes.add(inode)

    if not socket_inodes:
        return

    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit() or int(proc.name) == os.getpid():
            continue
        fd_dir = proc / "fd"
        try:
            for fd in fd_dir.iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in socket_inodes:
                    try:
                        os.kill(int(proc.name), signal.SIGKILL)
                    except (ProcessLookupError, PermissionError):
                        pass
                    break
        except (OSError, PermissionError):
            pass
    time.sleep(0.15)


def port_open(port):
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=0.15):
            return True
    except OSError:
        return False


def wait_for_ports(processes):
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        assert all(p.poll() is None for p in processes), "A required service exited during startup"
        if all(port_open(p) for p in PORTS):
            return
        time.sleep(0.05)
    assert False, "The router, worker, and logger did not all listen on ports 8000-8002"


def expected_body_from_known_good_revision():
    root = run(["git", "-C", str(REPO), "rev-list", "--max-parents=0", "HEAD"], check=True).stdout.strip()
    source = run(["git", "-C", str(REPO), "show", f"{root}:processing_worker.sh"], check=True).stdout
    match = re.search(r"\\r\\n\\r\\n([^'\"\r\n]+)", source)
    assert match, "Could not derive the expected worker response from the known-good revision"
    return match.group(1).strip()


def check_endpoint(expected, attempts=5):
    times = []
    for i in range(attempts):
        payload = "verification_payload_" + uuid.uuid4().hex
        try:
            result = subprocess.run(
                ["curl", "--http0.9", "-sS", "-w", "\n%{time_total}",
                 f"http://localhost:8000/process?data={payload}"],
                capture_output=True, text=True, check=True, timeout=5
            )
        except subprocess.TimeoutExpired:
            assert False, f"Request {i+1} timed out after 5 seconds. The performance regression was not fixed."
        except subprocess.CalledProcessError as e:
            assert False, f"curl command failed. Is the service running? Error: {e.stderr}"

        try:
            body, timing = result.stdout.rsplit("\n", 1)
            time_total = float(timing.strip())
        except (ValueError, TypeError):
            assert False, f"Failed to parse curl output: {result.stdout!r}"

        assert body.strip() == expected, (
            f"Incorrect /process response: expected {expected!r}, got {body.strip()!r}"
        )
        times.append(time_total)

    avg_time = sum(times) / len(times)
    assert avg_time <= 0.5, (
        f"Average response time {avg_time:.3f}s exceeds threshold of 0.5s. Times: {times}"
    )


def test_fix_patch_exists():
    assert PATCH.exists(), f"Patch file {PATCH} does not exist."
    assert PATCH.is_file(), f"{PATCH} is not a file."
    assert PATCH.stat().st_size > 0, f"Patch file {PATCH} is empty."


def test_performance_regression_fixed():
    expected = expected_body_from_known_good_revision()

    numstat = run(["git", "-C", str(REPO), "apply", "--numstat", str(PATCH)])
    assert numstat.returncode == 0, f"fix.patch is not a valid Git patch:\n{numstat.stderr}"
    touched = {line.split("\t", 2)[-1].strip() for line in numstat.stdout.splitlines() if line.strip()}
    assert "processing_worker.sh" in touched, "fix.patch does not repair processing_worker.sh"
    assert "router_config.env" in touched, "fix.patch does not reconfigure router_config.env"

    reverse = run(["git", "-C", str(REPO), "apply", "--reverse", "--check", str(PATCH)])
    assert reverse.returncode == 0, (
        "fix.patch has not been applied to the current working tree, or does not describe its fix:\n"
        + reverse.stderr
    )

    patched_dir = Path(tempfile.mkdtemp(prefix="verified_patch_"))
    archive = Path(tempfile.mktemp(prefix="head_", suffix=".tar"))
    processes = []
    try:
        with archive.open("wb") as out:
            archived = subprocess.run(["git", "-C", str(REPO), "archive", "HEAD"], stdout=out, stderr=subprocess.PIPE)
        assert archived.returncode == 0, archived.stderr.decode(errors="replace")
        with tarfile.open(archive) as tf:
            tf.extractall(patched_dir)

        applied = run(["git", "-C", str(patched_dir), "apply", "--check", str(PATCH)])
        assert applied.returncode == 0, f"fix.patch cannot be applied to a clean HEAD:\n{applied.stderr}"
        run(["git", "-C", str(patched_dir), "apply", str(PATCH)], check=True)

        config = (patched_dir / "router_config.env").read_text()
        assert re.search(r"(?m)^\s*WORKER_TIMEOUT\s*=\s*200\s*$", config), (
            "router_config.env was not restored to the known-good worker timeout"
        )

        kill_port_owners()
        log_dir = patched_dir / "verification_logs"
        log_dir.mkdir()
        for script, name in (("router_service.sh", "router"),
                             ("processing_worker.sh", "worker"),
                             ("logging_service.sh", "logger")):
            log = open(log_dir / f"{name}.log", "w")
            processes.append(subprocess.Popen(
                ["bash", str(patched_dir / script)], cwd=patched_dir,
                stdout=log, stderr=subprocess.STDOUT, start_new_session=True
            ))
        wait_for_ports(processes)
        check_endpoint(expected, attempts=5)
    finally:
        for process in processes:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        kill_port_owners()
        archive.unlink(missing_ok=True)
        shutil.rmtree(patched_dir, ignore_errors=True)

    # Also verify and leave running the services from the actual repaired repository.
    started = run(["bash", str(REPO / "start_all.sh")], cwd=REPO)
    assert started.returncode == 0, f"start_all.sh failed:\n{started.stderr}"
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline and not all(port_open(p) for p in PORTS):
        time.sleep(0.05)
    assert all(port_open(p) for p in PORTS), "The repaired repository's services are not all running"

    pids = [int(x) for x in Path("/tmp/pids").read_text().split()]
    assert len(pids) == 3 and all(Path(f"/proc/{pid}").exists() for pid in pids), (
        "start_all.sh did not leave all three repository services running"
    )
    check_endpoint(expected, attempts=1)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
