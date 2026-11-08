#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import socket
import stat
import subprocess
import tempfile
import urllib.request
import uuid

import pytest

SRC = "/app/src"
DEPLOY = "/app/deploy"


def parse_closure(deps_path, start="app.py"):
    graph = {}
    with open(deps_path, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line:
                continue
            assert ":" in line, f"Malformed dependency line: {raw!r}"
            name, values = line.split(":", 1)
            graph[name.strip()] = [x.strip() for x in values.split(",") if x.strip()]

    seen = set()
    pending = [start]
    while pending:
        name = pending.pop()
        if name in seen:
            continue
        seen.add(name)
        pending.extend(graph.get(name, []))
    return seen


def assert_exact_bundle(expected):
    assert os.path.isdir(DEPLOY), f"Deployment directory {DEPLOY} does not exist."
    actual = set(os.listdir(DEPLOY))
    assert actual == expected, f"Expected exactly {sorted(expected)}, found {sorted(actual)}"
    for name in expected:
        source = os.path.join(SRC, name)
        deployed = os.path.join(DEPLOY, name)
        assert os.path.isfile(source), f"Required source file is missing: {source}"
        assert os.path.isfile(deployed), f"Required deployed file is missing: {deployed}"
        with open(source, "rb") as sf, open(deployed, "rb") as df:
            assert df.read() == sf.read(), f"Deployed file differs from its source: {name}"


def listening_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r", encoding="ascii") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A":
                        local_port = int(fields[1].rsplit(":", 1)[1], 16)
                        if local_port == port:
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode("utf-8", "replace")
    except OSError:
        return ""


def test_service_flow():
    """Verify that Nginx, Flask, and Redis are correctly integrated and responding."""
    url = "http://127.0.0.1:8080/health"
    try:
        resp = urllib.request.urlopen(url, timeout=5)
        status = resp.status
        body = resp.read().decode('utf-8')
    except Exception as e:
        pytest.fail(f"Service flow failed when trying to reach {url}: {e}")

    assert status == 200, f"Expected HTTP 200 from {url}, got {status}"
    assert body == "OK", f"Expected response body 'OK', got '{body}'"


def test_bundle_size():
    """Measure the total size of files in the deploy directory and assert it is below the threshold."""
    deploy_dir = "/app/deploy"
    assert os.path.isdir(deploy_dir), f"Deployment directory {deploy_dir} does not exist."

    total_size = sum(
        os.path.getsize(os.path.join(deploy_dir, f))
        for f in os.listdir(deploy_dir)
        if os.path.isfile(os.path.join(deploy_dir, f))
    )

    threshold = 4096
    assert total_size < threshold, (
        f"Bundle size exceeds the allowed threshold. "
        f"Measured: {total_size} bytes, Threshold: {threshold} bytes."
    )


def test_deploy_status_log():
    """Check that the deploy_status.log file exists and contains the READY indicator."""
    log_path = "/home/user/deploy_status.log"
    assert os.path.isfile(log_path), f"Log file {log_path} is missing."

    with open(log_path, 'r') as f:
        content = f.read()

    assert "READY" in content, f"Expected the word 'READY' in {log_path}, but it was not found."


def test_required_artifacts_and_exact_initial_bundle():
    script = "/home/user/bundle.sh"
    config = "/home/user/nginx.conf"
    for path in (script, config):
        assert os.path.exists(path), f"Required artifact is missing: {path}"
        assert not os.path.islink(path), f"Required artifact must not be a symlink: {path}"
        assert stat.S_ISREG(os.stat(path).st_mode), f"Required artifact is not a regular file: {path}"

    expected = parse_closure(os.path.join(SRC, "deps.txt"))
    assert_exact_bundle(expected)


def test_real_stack_is_listening():
    nginx_pids = listening_pids(8080)
    assert nginx_pids, "Nothing is listening on port 8080"
    assert all("nginx" in cmdline(pid).lower() for pid in nginx_pids), (
        f"Port 8080 is not owned exclusively by Nginx: {[cmdline(p) for p in nginx_pids]}"
    )
    assert all(os.stat(f"/proc/{pid}").st_uid != 0 for pid in nginx_pids), (
        "Nginx listening processes must run as a non-root user"
    )
    assert any("/home/user/nginx.conf" in cmdline(pid) for pid in nginx_pids), (
        "The running Nginx instance was not started with /home/user/nginx.conf"
    )

    flask_pids = listening_pids(5000)
    assert flask_pids, "Nothing is listening on Flask port 5000"
    assert any(
        "python" in cmdline(pid).lower() and "/app/deploy/app.py" in cmdline(pid)
        for pid in flask_pids
    ), f"Port 5000 is not served by python3 /app/deploy/app.py: {[cmdline(p) for p in flask_pids]}"

    redis_pids = listening_pids(6379)
    assert redis_pids, "Nothing is listening on Redis port 6379"
    assert any("redis-server" in cmdline(pid).lower() for pid in redis_pids), (
        f"Port 6379 is not served by Redis: {[cmdline(p) for p in redis_pids]}"
    )


def test_bundle_script_performs_dependency_graph_traversal():
    script = "/home/user/bundle.sh"
    token = uuid.uuid4().hex
    first = f"probe_{token}.py"
    second = f"leaf_{token}.py"
    unused = f"unused_{token}.py"
    created = [first, second, unused]
    deps_path = os.path.join(SRC, "deps.txt")

    with open(deps_path, "rb") as f:
        original_deps = f.read()

    backup_parent = tempfile.mkdtemp(prefix="deploy_backup_")
    backup_deploy = os.path.join(backup_parent, "deploy")
    shutil.copytree(DEPLOY, backup_deploy)

    try:
        with open(os.path.join(SRC, first), "w", encoding="utf-8") as f:
            f.write(f"# traversal probe {token}\n")
        with open(os.path.join(SRC, second), "w", encoding="utf-8") as f:
            f.write(f"# transitive leaf {token}\n")
        with open(os.path.join(SRC, unused), "w", encoding="utf-8") as f:
            f.write(f"# must not be copied {token}\n")

        text = original_deps.decode("utf-8")
        lines = text.splitlines()
        for i, line in enumerate(lines):
            if line.split(":", 1)[0].strip() == "app.py":
                left, right = line.split(":", 1)
                existing = right.strip()
                lines[i] = f"{left}: {existing + ', ' if existing else ''}{first}"
                break
        else:
            pytest.fail("deps.txt does not define app.py")
        lines.extend([f"{first}: {second}", f"{second}:", f"{unused}:"])
        with open(deps_path, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")

        with open(os.path.join(DEPLOY, unused), "w", encoding="utf-8") as f:
            f.write("stale decoy that the bundler must remove\n")

        result = subprocess.run(
            ["runuser", "-u", "user", "--", "bash", script],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, f"bundle.sh failed when executed:\n{result.stdout}"

        expected = parse_closure(deps_path)
        assert first in expected and second in expected and unused not in expected
        assert_exact_bundle(expected)
    finally:
        with open(deps_path, "wb") as f:
            f.write(original_deps)
        for name in created:
            try:
                os.remove(os.path.join(SRC, name))
            except FileNotFoundError:
                pass
        if os.path.exists(DEPLOY):
            shutil.rmtree(DEPLOY)
        shutil.copytree(backup_deploy, DEPLOY)
        shutil.rmtree(backup_parent, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
