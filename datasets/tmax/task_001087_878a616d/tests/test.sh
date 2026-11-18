#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ipaddress
import os
import pathlib
import random
import shutil
import signal
import subprocess
import tempfile
import time
import uuid

import pytest

BARE_REPO = "/home/user/router_deploy.git"
DEPLOY_DIR = "/home/user/deployed_router"
RAW_ROUTES = "/home/user/raw_routes.txt"
PID_FILE = "/home/user/daemon.pid"


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, **kwargs)


def expected_routes():
    with open(RAW_ROUTES, "r") as f:
        networks = [ipaddress.IPv4Network(line.strip(), strict=False)
                    for line in f if line.strip()]
    return list(ipaddress.collapse_addresses(networks))


def wait_for(predicate, timeout=15):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            if predicate():
                return
        except Exception as exc:
            last_error = exc
        time.sleep(0.2)
    if last_error:
        raise last_error
    raise AssertionError("Timed out waiting for deployment")


@pytest.fixture(scope="session", autouse=True)
def exercise_git_deployment_pipeline():
    assert os.path.isdir(BARE_REPO), f"Bare repository {BARE_REPO} is missing"
    assert run(["git", "--git-dir", BARE_REPO, "rev-parse", "--is-bare-repository"]).stdout.strip() == "true"
    run(["git", "--git-dir", BARE_REPO, "rev-parse", "--verify", "refs/heads/main"])

    hook = os.path.join(BARE_REPO, "hooks", "post-receive")
    assert os.path.isfile(hook), "post-receive hook is missing"
    assert os.access(hook, os.X_OK), "post-receive hook is not executable"

    # optimizer.go must already be part of the submitted main-branch history.
    optimizer_source = run([
        "git", "--git-dir", BARE_REPO, "show", "refs/heads/main:optimizer.go"
    ]).stdout
    assert "package main" in optimizer_source, "Committed optimizer.go is not a Go main package"
    run(["git", "--git-dir", BARE_REPO, "log", "-1", "--format=%H", "--", "optimizer.go"])

    assert os.path.isfile("/home/user/start_daemon.sh"), "start_daemon.sh is missing"
    assert os.access("/home/user/start_daemon.sh", os.X_OK), "start_daemon.sh is not executable"

    # Use verifier-generated data so a prewritten routes.conf cannot pass.
    nonce = os.urandom(2)
    second_a = nonce[0]
    second_b = nonce[1]
    raw = [f"172.{second_a}.{i}.0/24" for i in range(256)]
    raw += [
        f"10.{second_b}.0.0/24", f"10.{second_b}.1.0/24",
        f"10.{second_b}.2.0/24", f"10.{second_b}.3.0/24",
        f"10.{second_b}.0.0/25", f"10.{second_b}.0.0/24",
        f"100.{second_a}.8.0/24", f"100.{second_a}.9.0/24",
        "198.18.0.0/25", "198.18.0.128/25",
        "203.0.113.0/25",
    ]
    random.SystemRandom().shuffle(raw)
    with open(RAW_ROUTES, "w") as f:
        f.write("\n".join(raw) + "\n")
    truth = expected_routes()

    # Independently compile and execute the committed Go source against that data.
    os.makedirs(DEPLOY_DIR, exist_ok=True)
    conf = os.path.join(DEPLOY_DIR, "routes.conf")
    if os.path.exists(conf):
        os.remove(conf)
    with tempfile.TemporaryDirectory() as build_dir:
        source_path = os.path.join(build_dir, "optimizer.go")
        binary_path = os.path.join(build_dir, "optimizer")
        with open(source_path, "w") as f:
            f.write(optimizer_source)
        run(["go", "build", "-o", binary_path, source_path])
        run([binary_path], cwd=DEPLOY_DIR)
    assert os.path.isfile(conf), "Committed optimizer did not generate routes.conf"
    with open(conf) as f:
        generated = [ipaddress.IPv4Network(x.strip(), strict=False)
                     for x in f if x.strip()]
    assert list(ipaddress.collapse_addresses(generated)) == truth
    assert len(generated) <= len(truth)

    # Stop the prior daemon so only a fresh post-receive deployment can satisfy tests.
    if os.path.isfile(PID_FILE):
        try:
            old_pid = int(pathlib.Path(PID_FILE).read_text().strip())
            cmdline_path = f"/proc/{old_pid}/cmdline"
            if os.path.isfile(cmdline_path) and b"router_daemon" in pathlib.Path(cmdline_path).read_bytes():
                os.kill(old_pid, signal.SIGTERM)
                for _ in range(30):
                    if not os.path.exists(f"/proc/{old_pid}"):
                        break
                    time.sleep(0.1)
        except (ValueError, ProcessLookupError, PermissionError):
            pass
    for path in (PID_FILE, conf):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    # Push a unique committed token to main. Its appearance in the work tree,
    # regenerated routes, and a new daemon jointly demonstrate hook-triggered deployment.
    token = uuid.uuid4().hex
    token_name = ".verifier-deploy-token"
    token_path = os.path.join(DEPLOY_DIR, token_name)
    try:
        os.remove(token_path)
    except FileNotFoundError:
        pass

    with tempfile.TemporaryDirectory() as clone_dir:
        run(["git", "clone", "-b", "main", BARE_REPO, clone_dir])
        run(["git", "config", "user.name", "Verifier"], cwd=clone_dir)
        run(["git", "config", "user.email", "verifier@localhost"], cwd=clone_dir)
        pathlib.Path(clone_dir, token_name).write_text(token + "\n")
        run(["git", "add", token_name], cwd=clone_dir)
        run(["git", "commit", "-m", "verifier deployment trigger"], cwd=clone_dir)
        pushed_commit = run(["git", "rev-parse", "HEAD"], cwd=clone_dir).stdout.strip()
        run(["git", "push", "origin", "HEAD:main"], cwd=clone_dir)

    assert run(["git", "--git-dir", BARE_REPO, "rev-parse", "refs/heads/main"]).stdout.strip() == pushed_commit

    def deployment_complete():
        if not os.path.isfile(token_path) or pathlib.Path(token_path).read_text().strip() != token:
            return False
        if not os.path.isfile(conf) or not os.path.isfile(PID_FILE):
            return False
        pid_text = pathlib.Path(PID_FILE).read_text().strip()
        return pid_text.isdigit() and os.path.isdir(f"/proc/{pid_text}")

    wait_for(deployment_complete)

    deployed_source = pathlib.Path(DEPLOY_DIR, "optimizer.go")
    assert deployed_source.is_file(), "Hook did not check out optimizer.go to deployed_router"
    assert deployed_source.read_text() == optimizer_source, "Deployed optimizer.go does not match main"


def test_routes_conf_metric():
    raw_routes_path = RAW_ROUTES
    conf_path = os.path.join(DEPLOY_DIR, "routes.conf")

    assert os.path.isfile(raw_routes_path), f"Raw routes file {raw_routes_path} is missing."
    assert os.path.isfile(conf_path), f"Compiled routes file {conf_path} is missing."

    with open(raw_routes_path, "r") as f:
        raw_lines = [line.strip() for line in f if line.strip()]
    networks = [ipaddress.IPv4Network(cidr, strict=False) for cidr in raw_lines]
    collapsed = list(ipaddress.collapse_addresses(networks))
    optimal_count = len(collapsed)

    with open(conf_path, "r") as f:
        agent_lines = [line.strip() for line in f if line.strip()]
    agent_count = len(agent_lines)

    assert agent_count <= optimal_count, (
        f"Metric threshold failed: Agent produced {agent_count} routes, "
        f"but optimal aggregation is {optimal_count} routes."
    )

    agent_networks = [ipaddress.IPv4Network(cidr, strict=False) for cidr in agent_lines]
    agent_collapsed = list(ipaddress.collapse_addresses(agent_networks))
    assert set(agent_collapsed) == set(collapsed), "Agent's aggregated routes do not cover the exact same IP space as the raw routes."


def test_daemon_running():
    assert os.path.isfile(PID_FILE), f"PID file {PID_FILE} is missing."
    pid_str = pathlib.Path(PID_FILE).read_text().strip()
    assert pid_str.isdigit(), f"PID file does not contain a valid integer: {pid_str}"
    pid = int(pid_str)
    assert os.path.isdir(f"/proc/{pid}"), f"Process with PID {pid} is not running."

    with open(f"/proc/{pid}/cmdline", "rb") as f:
        cmdline = f.read().replace(b"\x00", b" ").decode("utf-8")
    assert "router_daemon" in cmdline, f"Process {pid} is not the router_daemon. Cmdline: {cmdline}"

    assert os.stat(f"/proc/{pid}/ns/net").st_ino != os.stat("/proc/self/ns/net").st_ino, "Daemon is not in an isolated network namespace"
    assert os.stat(f"/proc/{pid}/ns/user").st_ino != os.stat("/proc/self/ns/user").st_ino, "Daemon is not in an isolated user namespace"


def test_daemon_network_namespace():
    pid = pathlib.Path(PID_FILE).read_text().strip()
    try:
        out = subprocess.check_output(["nsenter", "-t", pid, "-n", "ip", "addr", "show", "dummy0"], stderr=subprocess.STDOUT)
        out_str = out.decode("utf-8")
        assert "10.99.0.1/24" in out_str, "dummy0 interface does not have the expected IP 10.99.0.1/24 in the daemon's namespace."
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to inspect dummy0 in daemon's network namespace: {e.output.decode('utf-8')}")

    try:
        out = subprocess.check_output(["nsenter", "-t", pid, "-n", "ip", "route", "show"], stderr=subprocess.STDOUT)
        out_str = out.decode("utf-8")
        assert "192.168.100.0/24" in out_str, "Route to 192.168.100.0/24 is missing in the daemon's namespace."
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to inspect routes in daemon's network namespace: {e.output.decode('utf-8')}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
