#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import http.server
import json
import os
import re
import shutil
import socketserver
import stat
import subprocess
import tempfile
import threading
import time
import urllib.request

import pytest


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def test_wrk_binary_compiled():
    wrk_path = "/app/wrk/wrk"
    assert os.path.isfile(wrk_path), f"wrk binary not found at {wrk_path}. Did you compile it?"
    assert os.access(wrk_path, os.X_OK), f"wrk binary at {wrk_path} is not executable."

    # Rebuild from the vendored source so an executable script or prebuilt impostor
    # cannot satisfy the check. A successful link also verifies the Makefile fix.
    clean = run(["make", "clean"], cwd="/app/wrk", timeout=30)
    assert clean.returncode == 0, f"make clean failed:\n{clean.stdout}\n{clean.stderr}"
    build = run(["make", "-j2"], cwd="/app/wrk", timeout=120)
    assert build.returncode == 0, f"wrk did not compile from source:\n{build.stdout}\n{build.stderr}"
    assert os.path.isfile(wrk_path) and os.access(wrk_path, os.X_OK)
    with open(wrk_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The rebuilt wrk artifact is not an ELF executable."


def test_wrk_generates_real_load():
    counter = {"requests": 0}
    lock = threading.Lock()

    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def do_GET(self):
            with lock:
                counter["requests"] += 1
            body = b"verifier-response"
            self.send_response(200)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
        daemon_threads = True

    server = Server(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    port = server.server_address[1]
    started = time.monotonic()
    try:
        result = run(
            ["/app/wrk/wrk", "-t1", "-c2", "-d2s", f"http://127.0.0.1:{port}/derived"],
            timeout=12,
        )
    finally:
        elapsed = time.monotonic() - started
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)

    assert result.returncode == 0, f"wrk failed against verifier server:\n{result.stdout}\n{result.stderr}"
    total_match = re.search(r"\b(\d+) requests in\s+([0-9.]+)([sm])", result.stdout)
    rate_match = re.search(r"Requests/sec:\s+([0-9.]+)", result.stdout)
    assert total_match and rate_match, f"Normal wrk statistics were not produced:\n{result.stdout}"
    reported_total = int(total_match.group(1))
    reported_rate = float(rate_match.group(1))
    observed = counter["requests"]
    assert observed >= 20, f"The verifier server observed only {observed} requests; wrk did not generate a real load."
    assert reported_total <= observed, "wrk reported more completed requests than the verifier server received."
    assert observed - reported_total <= max(20, int(observed * 0.10)), "wrk request totals do not match observed traffic."
    assert reported_rate <= (observed / max(elapsed, 0.1)) * 1.75, "The printed Requests/sec is not supported by observed traffic."


def test_git_repo_and_hook():
    repo_path = "/home/user/git/api.git"
    assert os.path.isdir(repo_path), f"Bare git repository not found at {repo_path}."
    result = run(["git", "rev-parse", "--is-bare-repository"], cwd=repo_path)
    assert result.returncode == 0 and result.stdout.strip() == "true", f"{repo_path} is not a valid bare Git repository."

    hook_path = os.path.join(repo_path, "hooks", "post-receive")
    assert os.path.isfile(hook_path), f"post-receive hook not found at {hook_path}."
    st = os.stat(hook_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"post-receive hook at {hook_path} is not executable."
    with open(hook_path, "rb") as f:
        first_line = f.readline().decode("utf-8", "replace").strip()
    assert "bash" in first_line, "The post-receive hook must be a Bash hook."
    syntax = run(["bash", "-n", hook_path])
    assert syntax.returncode == 0, f"The post-receive Bash hook has invalid syntax: {syntax.stderr}"


def test_git_pushed():
    repo_path = "/home/user/git/api.git"
    result = run(["git", "log", "-1"], cwd=repo_path)
    assert result.returncode == 0, "No commits found in the bare repository. Did you push your changes?"
    compose = run(["git", "show", "HEAD:docker-compose.yml"], cwd=repo_path)
    assert compose.returncode == 0, "The pushed commit does not contain docker-compose.yml."


def test_post_receive_really_checks_out_and_runs_compose():
    repo_path = "/home/user/git/api.git"
    deploy_path = "/home/user/deploy"
    token = f"verifier-{os.getpid()}-{time.time_ns()}"
    marker_name = ".verifier-push-marker"
    log_path = f"/tmp/docker-hook-{os.getpid()}.log"
    real_docker = f"/usr/bin/docker.verifier-real-{os.getpid()}"
    docker_path = "/usr/bin/docker"

    assert os.path.exists(docker_path), "Docker CLI is unavailable."
    work = tempfile.mkdtemp(prefix="hook-push-")
    moved = False
    try:
        clone = run(["git", "clone", repo_path, work], timeout=30)
        assert clone.returncode == 0, f"Could not clone the submitted bare repository: {clone.stderr}"
        branch = run(["git", "symbolic-ref", "--short", "HEAD"], cwd=work)
        assert branch.returncode == 0, "The pushed repository has no checked-out branch."
        branch_name = branch.stdout.strip()
        with open(os.path.join(work, marker_name), "w") as f:
            f.write(token + "\n")
        run(["git", "config", "user.email", "verifier@localhost"], cwd=work)
        run(["git", "config", "user.name", "Verifier"], cwd=work)
        assert run(["git", "add", marker_name], cwd=work).returncode == 0
        commit = run(["git", "commit", "-m", "Verifier hook exercise"], cwd=work)
        assert commit.returncode == 0, f"Could not create verifier push: {commit.stderr}"

        open(log_path, "w").close()
        os.chmod(log_path, 0o666)
        os.rename(docker_path, real_docker)
        moved = True
        with open(docker_path, "w") as f:
            f.write("#!/bin/bash\n")
            f.write(f"printf '%s\\t%s\\n' \"$PWD\" \"$*\" >> {log_path!r}\n")
            f.write(f"exec {real_docker!r} \"$@\"\n")
        os.chmod(docker_path, 0o755)

        pushed = run(["git", "push", "origin", f"HEAD:{branch_name}"], cwd=work, timeout=180)
        assert pushed.returncode == 0, f"Push did not successfully execute the post-receive hook:\n{pushed.stdout}\n{pushed.stderr}"
    finally:
        if moved:
            try:
                if os.path.lexists(docker_path):
                    os.unlink(docker_path)
            finally:
                os.rename(real_docker, docker_path)
        shutil.rmtree(work, ignore_errors=True)

    marker_path = os.path.join(deploy_path, marker_name)
    assert os.path.isfile(marker_path), "A newly pushed file was not checked out into /home/user/deploy."
    with open(marker_path) as f:
        assert f.read().strip() == token, "The deployment directory was not updated to the latest pushed commit."

    with open(log_path) as f:
        calls = [line.rstrip("\n").split("\t", 1) for line in f if "\t" in line]
    matching = []
    for cwd, args in calls:
        words = args.split()
        if cwd == deploy_path and len(words) >= 2 and words[0:2] == ["compose", "up"]:
            matching.append(words)
    assert matching, "The hook did not run 'docker compose up' inside /home/user/deploy."
    assert any("-d" in words and "--build" in words for words in matching), "The hook did not run Docker Compose with both -d and --build."

    committed = run(["git", "show", "HEAD:docker-compose.yml"], cwd=repo_path)
    assert committed.returncode == 0
    with open(os.path.join(deploy_path, "docker-compose.yml")) as f:
        assert f.read() == committed.stdout, "The deployed docker-compose.yml is not the latest pushed version."


def compose_container(service):
    ids = run(["docker", "ps", "-q", "--filter", f"label=com.docker.compose.service={service}"])
    assert ids.returncode == 0, ids.stderr
    for cid in ids.stdout.split():
        inspected = run(["docker", "inspect", cid])
        if inspected.returncode != 0:
            continue
        data = json.loads(inspected.stdout)[0]
        labels = data.get("Config", {}).get("Labels", {}) or {}
        if labels.get("com.docker.compose.project.working_dir") == "/home/user/deploy":
            assert data.get("State", {}).get("Running"), f"Compose service {service} is not running."
            return data
    pytest.fail(f"No running Docker Compose container for service {service} from /home/user/deploy was found.")


def test_docker_compose_and_tunnel():
    api = compose_container("api")
    nginx = compose_container("nginx")
    api_networks = set(api["NetworkSettings"]["Networks"])
    nginx_networks = set(nginx["NetworkSettings"]["Networks"])
    assert api_networks & nginx_networks, "The api and nginx Compose services still do not share a Docker network."

    ports = nginx["NetworkSettings"].get("Ports", {}).get("80/tcp") or []
    assert any(str(p.get("HostPort")) == "9090" for p in ports), "The Compose nginx container does not publish host port 9090."

    try:
        resp = urllib.request.urlopen("http://127.0.0.1:9090", timeout=3)
        assert resp.status == 200, f"Expected HTTP 200 from Nginx, got {resp.status}"
        body = resp.read().decode("utf-8")
        assert "OK" in body, "Expected 'OK' in response body from Nginx"
    except Exception as e:
        pytest.fail(f"Failed to access Nginx directly on port 9090. Is Docker Compose running and networks fixed? Error: {e}")

    listener_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                if fields[3] == "0A" and int(fields[1].split(":")[1], 16) == 8080:
                    listener_inodes.add(fields[9])
    assert listener_inodes, "No process is listening on local tunnel port 8080."

    ssh_listener = False
    for proc in glob.glob("/proc/[0-9]*"):
        try:
            with open(os.path.join(proc, "cmdline"), "rb") as f:
                argv = [x.decode("utf-8", "replace") for x in f.read().split(b"\0") if x]
            if not argv or os.path.basename(argv[0]) != "ssh":
                continue
            joined = " ".join(argv)
            if "-L" not in joined or "8080:" not in joined or ":9090" not in joined:
                continue
            for fd in glob.glob(os.path.join(proc, "fd", "*")):
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in listener_inodes:
                    ssh_listener = True
                    break
        except (OSError, IndexError):
            continue
        if ssh_listener:
            break
    assert ssh_listener, "Port 8080 is not owned by a background ssh -L tunnel to port 9090."

    try:
        resp = urllib.request.urlopen("http://127.0.0.1:8080", timeout=3)
        assert resp.status == 200, f"Expected HTTP 200 via SSH tunnel, got {resp.status}"
        body = resp.read().decode("utf-8")
        assert "OK" in body, "Expected 'OK' in response body via SSH tunnel"
    except Exception as e:
        pytest.fail(f"Failed to access API via SSH tunnel on port 8080. Is the tunnel running? Error: {e}")


def test_wrk_throughput():
    wrk_path = "/app/wrk/wrk"
    cmd = [wrk_path, "-t1", "-c10", "-d5s", "http://127.0.0.1:8080"]
    try:
        result = run(cmd, timeout=15)
    except subprocess.TimeoutExpired:
        pytest.fail("wrk load test timed out after 15 seconds.")

    assert result.returncode == 0, f"wrk failed to run. Stderr: {result.stderr}\nStdout: {result.stdout}"
    match = re.search(r"Requests/sec:\s+([0-9.]+)", result.stdout)
    assert match is not None, f"Could not parse 'Requests/sec' from wrk output:\n{result.stdout}"
    req_per_sec = float(match.group(1))
    threshold = 500.0
    assert req_per_sec >= threshold, f"Throughput metric failed: {req_per_sec} Requests/sec is strictly less than the required threshold of {threshold} Requests/sec."
    assert not re.search(r"Socket errors:", result.stdout), f"wrk reported socket errors:\n{result.stdout}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
