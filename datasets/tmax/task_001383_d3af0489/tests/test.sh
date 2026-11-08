#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import signal
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid


def wait_for_port(port, listening=True, timeout=15):
    deadline = time.time() + timeout
    while time.time() < deadline:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            present = s.connect_ex(("127.0.0.1", port)) == 0
        if present == listening:
            return
        time.sleep(0.1)
    raise AssertionError(f"port {port} did not reach listening={listening}")


def raw_get(path):
    with socket.create_connection(("127.0.0.1", 8181), timeout=3) as s:
        s.settimeout(3)
        request = f"GET {path} HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
        s.sendall(request.encode("ascii"))
        chunks = []
        while True:
            try:
                chunk = s.recv(4096)
            except socket.timeout:
                raise AssertionError("netmon did not close the HTTP response")
            if not chunk:
                break
            chunks.append(chunk)
    return b"".join(chunks)


def listening_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].split(":")[-1] == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    result = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    result.add(int(entry))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return result


def stop_port_9090():
    pids = listening_pids(9090)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 5
    while time.time() < deadline and listening_pids(9090):
        time.sleep(0.1)
    for pid in listening_pids(9090):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    wait_for_port(9090, listening=False, timeout=5)


def process_start(pid):
    with open(f"/proc/{pid}/stat") as f:
        return f.read().split()[21]


def test_complete_deployment_and_behavior():
    project = "/home/user/src/network_monitor"
    registry = "/home/user/registry.git"
    hook = f"{registry}/hooks/post-receive"
    deploy = "/home/user/deploy"

    assert os.path.isdir(project), "Rust project directory does not exist at /home/user/src/network_monitor"
    assert os.path.isfile(f"{project}/Cargo.toml"), "Cargo.toml not found in the Rust project"

    assert os.path.isdir(registry), "Bare git repository does not exist at /home/user/registry.git"
    assert os.path.isfile(f"{registry}/config"), "Git config not found in bare repository"
    assert subprocess.check_output(["git", "--git-dir", registry, "rev-parse", "--is-bare-repository"], text=True).strip() == "true"

    assert os.path.isfile(hook), f"post-receive hook not found at {hook}"
    assert os.access(hook, os.X_OK), "post-receive hook is not executable"
    with open(hook) as f:
        content = f.read()
    assert "df -k" in content, "Hook does not contain 'df -k'"
    assert "50000" in content, "Hook does not check for 50000 KB disk space"
    assert "cargo build" in content and "--release" in content, "Hook does not contain 'cargo build --release'"
    assert "netmon" in content, "Hook does not contain references to netmon"
    assert "/home/user/netmon.log" in content, "Hook does not redirect output to /home/user/netmon.log"

    assert os.path.isdir(deploy), "Deploy directory does not exist at /home/user/deploy"
    assert os.path.isfile(f"{deploy}/Cargo.toml"), "Checked out code missing in deploy directory"

    status_path = "/home/user/final_status.txt"
    assert os.path.isfile(status_path), f"{status_path} does not exist"
    with open(status_path) as f:
        final_status = f.read().strip()
    assert final_status == "UP", f"final_status.txt contains '{final_status}', expected 'UP'"

    output = subprocess.check_output(["pgrep", "-f", "netmon"], text=True)
    assert output.strip(), "netmon process is not running"
    wait_for_port(9090, listening=True, timeout=3)
    wait_for_port(8181, listening=True, timeout=3)

    req = urllib.request.Request("http://127.0.0.1:8181/")
    try:
        with urllib.request.urlopen(req, timeout=2) as response:
            assert response.status == 200, f"Expected HTTP 200, got {response.status}"
            assert response.read().decode().strip() == "UP"
    except urllib.error.URLError as exc:
        raise AssertionError(f"Failed to connect or received error from netmon: {exc}")

    # Exercise the quota rejection path with a controlled df result.
    fakebin = tempfile.mkdtemp(prefix="quota-tools-")
    fake_df = os.path.join(fakebin, "df")
    with open(fake_df, "w") as f:
        f.write("#!/bin/sh\nprintf 'Filesystem 1024-blocks Used Available Capacity Mounted on\\n'\nprintf 'fake 100000 60000 40000 60%% /home/user\\n'\n")
    os.chmod(fake_df, 0o755)
    head = subprocess.check_output(["git", "--git-dir", registry, "rev-parse", "refs/heads/master"], text=True).strip()
    quota_env = os.environ.copy()
    quota_env["PATH"] = fakebin + os.pathsep + quota_env["PATH"]
    quota = subprocess.run(
        [hook], input=f"{head} {head} refs/heads/master\n", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=quota_env, timeout=20
    )
    assert quota.returncode == 1, "Hook did not exit 1 when df reported less than 50000 KB available"
    assert quota.stdout.strip(), "Hook did not print an error for insufficient disk space"

    # Make and push a unique, harmless source change. This executes the real hook
    # and lets the verifier observe checkout, release build, and process restart.
    with tempfile.TemporaryDirectory(prefix="deploy-push-") as clone:
        subprocess.run(["git", "clone", registry, clone], check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        subprocess.run(["git", "-C", clone, "checkout", "master"], check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        subprocess.run(["git", "-C", clone, "config", "user.email", "verifier@localhost"], check=True)
        subprocess.run(["git", "-C", clone, "config", "user.name", "Deployment Verifier"], check=True)

        metadata = json.loads(subprocess.check_output(["cargo", "metadata", "--no-deps", "--format-version", "1"], cwd=clone, text=True))
        targets = [t for p in metadata["packages"] for t in p["targets"] if t["name"] == "netmon" and "bin" in t["kind"]]
        assert targets, "Cargo project does not define a netmon binary"
        source = targets[0]["src_path"]
        token = "verifier-deploy-" + uuid.uuid4().hex
        with open(source, "a") as f:
            f.write(f"\n// {token}\n")
        relative_source = os.path.relpath(source, clone)
        subprocess.run(["git", "-C", clone, "add", relative_source], check=True)
        subprocess.run(["git", "-C", clone, "commit", "-m", token], check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        new_commit = subprocess.check_output(["git", "-C", clone, "rev-parse", "HEAD"], text=True).strip()

        old_pids = listening_pids(8181)
        assert old_pids, "No process was listening on 8181 before deployment"
        old_identity = {pid: process_start(pid) for pid in old_pids}
        push_started = time.time()
        pushed = subprocess.run(
            ["git", "-C", clone, "push", "origin", "HEAD:master"],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=120
        )
        assert pushed.returncode == 0, f"Push did not successfully execute post-receive hook:\n{pushed.stdout}"

    assert subprocess.check_output(["git", "--git-dir", registry, "rev-parse", "refs/heads/master"], text=True).strip() == new_commit
    deployed_source = os.path.join(deploy, relative_source)
    assert os.path.isfile(deployed_source), "Hook did not check out the incoming source into /home/user/deploy"
    with open(deployed_source) as f:
        assert token in f.read(), "Deployed checkout is not the commit that was pushed"

    binary = f"{deploy}/target/release/netmon"
    assert os.path.isfile(binary) and os.access(binary, os.X_OK), "Hook did not produce the release netmon binary"
    assert os.stat(binary).st_mtime >= push_started - 2, "Release binary was not rebuilt by the push"

    wait_for_port(8181, listening=True, timeout=15)
    new_pids = listening_pids(8181)
    assert new_pids, "Deployed netmon did not listen on port 8181"
    for pid, start in old_identity.items():
        if os.path.exists(f"/proc/{pid}"):
            assert process_start(pid) != start or pid not in new_pids, "The old netmon process was not restarted"

    deployed_pid = next(iter(new_pids))
    assert os.path.samefile(f"/proc/{deployed_pid}/exe", binary), "Port 8181 is not served by the newly built deploy binary"
    assert os.path.realpath(f"/proc/{deployed_pid}/fd/1") == "/home/user/netmon.log", "netmon stdout is not redirected to /home/user/netmon.log"
    assert os.path.realpath(f"/proc/{deployed_pid}/fd/2") == "/home/user/netmon.log", "netmon stderr is not redirected to /home/user/netmon.log"

    # Test both outcomes using backend state controlled by the verifier.
    assert raw_get("/up-" + uuid.uuid4().hex) == b"HTTP/1.1 200 OK\r\n\r\nUP"
    stop_port_9090()
    assert raw_get("/down-" + uuid.uuid4().hex) == b"HTTP/1.1 503 Service Unavailable\r\n\r\nDOWN"

    backend = subprocess.Popen(
        ["python3", "-m", "http.server", "9090", "--bind", "127.0.0.1"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True
    )
    wait_for_port(9090, listening=True, timeout=10)
    assert raw_get("/up-again-" + uuid.uuid4().hex) == b"HTTP/1.1 200 OK\r\n\r\nUP"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
