#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import shutil
import subprocess
import tempfile
import time
import urllib.request
import uuid

import pytest
from datetime import datetime, timedelta

REPO = "/home/user/nginx-repo"
BARE = "/home/user/nginx.git"
ACTIVE_CONFIG = "/home/user/nginx/nginx.conf"
PID_FILE = "/home/user/nginx/nginx.pid"
HOOK = "/home/user/nginx.git/hooks/post-receive"


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def git(*args, cwd=None):
    proc = run(["git", *args], cwd=cwd)
    assert proc.returncode == 0, (
        f"git {' '.join(args)} failed:\nstdout: {proc.stdout}\nstderr: {proc.stderr}"
    )
    return proc.stdout.strip()


def nginx_workers(master_pid):
    workers = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            with open(f"/proc/{name}/status", "r") as f:
                status = f.read()
            match = re.search(r"^PPid:\s+(\d+)$", status, re.MULTILINE)
            if match and int(match.group(1)) == master_pid:
                workers.add(int(name))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return workers


def fetch_ping():
    with urllib.request.urlopen("http://127.0.0.1:8080/ping", timeout=3) as response:
        return response.status, response.read()


def test_git_commit_configuration_and_live_route():
    assert os.path.isdir(os.path.join(REPO, ".git")), "Working clone is missing or is not a Git repository."
    assert os.path.isdir(BARE), "Bare Git repository is missing."

    origin = git("remote", "get-url", "origin", cwd=REPO)
    assert os.path.realpath(os.path.join(REPO, origin)) == os.path.realpath(BARE), (
        f"The working clone's origin is {origin}, not {BARE}."
    )

    clone_head = git("rev-parse", "HEAD", cwd=REPO)
    bare_head = git("--git-dir", BARE, "rev-parse", "refs/heads/master")
    assert clone_head == bare_head, "The committed nginx.conf change was not pushed to origin/master."

    commit_count = int(git("rev-list", "--count", "HEAD", cwd=REPO))
    assert commit_count >= 2, "No new commit was made after the initial nginx configuration commit."

    committed_config = subprocess.run(
        ["git", "-C", REPO, "show", "HEAD:nginx.conf"], capture_output=True
    )
    assert committed_config.returncode == 0, "nginx.conf is not committed at HEAD."
    committed_bytes = committed_config.stdout

    assert os.path.isfile(ACTIVE_CONFIG), f"Active configuration {ACTIVE_CONFIG} is missing."
    with open(ACTIVE_CONFIG, "rb") as f:
        active_bytes = f.read()
    assert active_bytes == committed_bytes, (
        "The active nginx.conf is not the nginx.conf from the pushed commit."
    )

    config_text = committed_bytes.decode("utf-8")
    ping_location = re.search(
        r"location\s+(?:=\s*)?/ping\s*\{(?P<body>[^{}]*)\}",
        config_text,
        re.DOTALL,
    )
    assert ping_location, "The committed configuration has no location for /ping."
    assert re.search(
        r"proxy_pass\s+http://127\.0\.0\.1:8081/ping\s*;",
        ping_location.group("body"),
    ), "The /ping location does not proxy to http://127.0.0.1:8081/ping."

    syntax = run(["/usr/sbin/nginx", "-t", "-c", ACTIVE_CONFIG])
    assert syntax.returncode == 0, f"Active Nginx configuration is invalid:\n{syntax.stderr}"

    status, body = fetch_ping()
    assert status == 200, f"Nginx /ping returned HTTP {status}, not 200."
    assert body == b"OK", f"Nginx /ping returned unexpected body {body!r}."


def test_health_log_up():
    log_file = "/home/user/logs/health.log"
    assert os.path.exists(log_file), f"Log file {log_file} does not exist."
    with open(log_file, "r") as f:
        lines = f.readlines()

    recent_lines = lines[-15:]
    up_count = sum(1 for line in recent_lines if "| UP |" in line)
    assert up_count > 0, (
        "No recent 'UP' entries found in health.log. "
        "This indicates Nginx is not routing /ping to the backend correctly, "
        "or the git hook failed to reload Nginx."
    )

    # Require a fresh, well-formed UP record produced after verification began,
    # rather than trusting only content that could have been appended beforehand.
    initial_size = os.path.getsize(log_file)
    fresh = ""
    deadline = time.time() + 6
    while time.time() < deadline:
        with open(log_file, "r") as f:
            f.seek(initial_size)
            fresh = f.read()
        if any(re.fullmatch(r"\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \| UP \| \d+", line)
               for line in fresh.splitlines()):
            break
        time.sleep(0.25)
    else:
        pytest.fail("The running health checker did not append a fresh UP record.")


def test_git_hook():
    assert os.path.exists(HOOK), f"Git hook {HOOK} does not exist."
    assert os.access(HOOK, os.X_OK), f"Git hook {HOOK} is not executable."

    original_head = git("--git-dir", BARE, "rev-parse", "refs/heads/master")
    original_config = subprocess.run(
        ["git", "--git-dir", BARE, "show", f"{original_head}:nginx.conf"],
        capture_output=True,
    )
    assert original_config.returncode == 0
    original_bytes = original_config.stdout

    with open(PID_FILE, "r") as f:
        master_pid = int(f.read().strip())
    assert os.path.exists(f"/proc/{master_pid}"), "Nginx PID file does not name a running process."
    old_workers = nginx_workers(master_pid)
    assert old_workers, "Could not identify a running Nginx worker before testing the hook."

    temp_clone = tempfile.mkdtemp(prefix="hook-test-", dir="/home/user")
    os.chown(temp_clone, 1000, 1000)
    marker = f"# verifier-hook-marker-{uuid.uuid4().hex}\n".encode()
    test_bytes = original_bytes.rstrip(b"\n") + b"\n" + marker

    pushed = False
    try:
        clone = run(["runuser", "-u", "user", "--", "git", "clone", BARE, temp_clone])
        assert clone.returncode == 0, f"Could not clone bare repository as user:\n{clone.stderr}"
        git("config", "user.email", "verifier@example.com", cwd=temp_clone)
        git("config", "user.name", "Verifier", cwd=temp_clone)
        with open(os.path.join(temp_clone, "nginx.conf"), "wb") as f:
            f.write(test_bytes)
        os.chown(os.path.join(temp_clone, "nginx.conf"), 1000, 1000)
        git("add", "nginx.conf", cwd=temp_clone)
        git("commit", "-m", "Verifier hook deployment probe", cwd=temp_clone)

        push = run([
            "runuser", "-u", "user", "--", "git", "-C", temp_clone,
            "push", "origin", "HEAD:refs/heads/master",
        ])
        assert push.returncode == 0, f"Push invoking post-receive failed:\n{push.stderr}"
        pushed = True

        deployed = False
        reloaded = False
        deadline = time.time() + 6
        while time.time() < deadline:
            try:
                with open(ACTIVE_CONFIG, "rb") as f:
                    deployed = f.read() == test_bytes
            except FileNotFoundError:
                deployed = False
            current_workers = nginx_workers(master_pid)
            reloaded = bool(current_workers) and current_workers != old_workers
            if deployed and reloaded:
                break
            time.sleep(0.2)

        assert deployed, (
            "Pushing a new nginx.conf did not cause post-receive to check it out "
            "to /home/user/nginx/nginx.conf."
        )
        assert os.path.exists(f"/proc/{master_pid}"), "Nginx master exited instead of reloading gracefully."
        assert reloaded, (
            "Nginx workers did not reload after the push; the hook did not send "
            "the required reload signal using nginx.pid."
        )
        status, body = fetch_ping()
        assert status == 200 and body == b"OK", "The hook deployment broke the /ping route."
    finally:
        if pushed:
            run([
                "runuser", "-u", "user", "--", "git", "-C", temp_clone,
                "push", "--force", "origin",
                f"{original_head}:refs/heads/master",
            ])
            deadline = time.time() + 5
            while time.time() < deadline:
                try:
                    with open(ACTIVE_CONFIG, "rb") as f:
                        if f.read() == original_bytes:
                            break
                except FileNotFoundError:
                    pass
                time.sleep(0.2)
        shutil.rmtree(temp_clone, ignore_errors=True)


def generate_log_file(path, num_lines):
    with open(path, 'w') as f:
        dt = datetime(2023, 10, 4, 12, 0, 0)
        for _ in range(num_lines):
            dt += timedelta(seconds=random.randint(1, 10))
            dt_str = dt.strftime("%Y-%m-%d %H:%M:%S")
            if random.choice([True, False]):
                status = "UP"
                latency = random.randint(0, 5000)
            else:
                status = "DOWN"
                latency = -1
            f.write(f"{dt_str} | {status} | {latency}\n")


def test_parser_fuzz_equivalence():
    agent_parser = "/home/user/parser"
    oracle_parser = "/app/oracle_parser"

    assert os.path.exists(agent_parser), f"Parser executable missing at {agent_parser}"
    assert os.path.isfile(agent_parser), f"Parser at {agent_parser} is not a regular file"
    assert os.access(agent_parser, os.X_OK), f"Parser at {agent_parser} is not executable"

    with open(agent_parser, "rb") as f:
        agent_source = f.read()
    with open(oracle_parser, "rb") as f:
        oracle_source = f.read()
    assert agent_source != oracle_source, "Submitted parser is byte-identical to the reference implementation."

    random.seed(42)

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(100):
            num_lines = random.randint(10, 500)
            log_path = os.path.join(tmpdir, f"test_{i}.log")
            generate_log_file(log_path, num_lines)

            oracle_proc = subprocess.run([oracle_parser, log_path], capture_output=True)
            agent_proc = subprocess.run([agent_parser, log_path], capture_output=True)

            assert agent_proc.returncode == oracle_proc.returncode, (
                f"Return code mismatch on input {log_path}. "
                f"Oracle: {oracle_proc.returncode}, Agent: {agent_proc.returncode}"
            )

            if agent_proc.stdout != oracle_proc.stdout:
                with open(log_path, 'r') as f:
                    sample_input = f.read()
                pytest.fail(
                    f"Output mismatch on input {log_path}.\n"
                    f"Input sample (first 100 chars): {sample_input[:100]}...\n"
                    f"Oracle output (hex): {oracle_proc.stdout.hex()}\n"
                    f"Agent output (hex): {agent_proc.stdout.hex()}"
                )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
