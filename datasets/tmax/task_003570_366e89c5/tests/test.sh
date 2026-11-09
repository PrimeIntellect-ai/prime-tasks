#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import time
import uuid
import signal
import subprocess
import requests
import pytest

PACKAGE = "/app/microservice-gateway-1.2"
DAEMON = os.path.join(PACKAGE, "gateway_daemon")
SOURCE = os.path.join(PACKAGE, "gateway.c")


def listener_pids(port):
    output = subprocess.check_output(["ss", "-ltnpH"], text=True, stderr=subprocess.STDOUT)
    pids = set()
    for line in output.splitlines():
        fields = line.split()
        if len(fields) < 4 or not re.search(r"(?:\]:|:)%d$" % port, fields[3]):
            continue
        pids.update(int(x) for x in re.findall(r"pid=(\d+)", line))
    return pids


def wait_for_listener(port, expected_pid=None, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        pids = listener_pids(port)
        if pids and (expected_pid is None or expected_pid in pids):
            return pids
        time.sleep(0.1)
    return set()


def test_gateway_daemon_built():
    """Verify that the gateway_daemon executable was built."""
    assert os.path.isfile(DAEMON), f"Executable {DAEMON} not found. Did you fix the Makefile and compile?"
    assert os.access(DAEMON, os.X_OK), f"{DAEMON} is not executable."


def test_setup_env_script_exists_and_executable():
    """Verify setup_env.sh exists and is executable."""
    path = "/home/user/setup_env.sh"
    assert os.path.isfile(path), f"{path} does not exist."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{path} is not executable."


def test_bashrc_contains_variables():
    """Verify .bashrc contains the required environment variables."""
    path = "/home/user/.bashrc"
    assert os.path.isfile(path), f"{path} does not exist."
    with open(path, "r") as f:
        content = f.read()
    assert "GATEWAY_PORT=9000" in content, "GATEWAY_PORT=9000 not found in .bashrc"
    assert "HTTP_PORT=9001" in content, "HTTP_PORT=9001 not found in .bashrc"
    assert "GATEWAY_TOKEN=secure-micro-token" in content, "GATEWAY_TOKEN=secure-micro-token not found in .bashrc"


def test_enable_http_exp_exists():
    """Verify enable_http.exp exists."""
    path = "/home/user/enable_http.exp"
    assert os.path.isfile(path), f"{path} does not exist."


def test_ssh_tunnel_listening():
    """Verify that a process is listening on 127.0.0.1:8080."""
    try:
        output = subprocess.check_output(["ss", "-tln"], text=True)
        assert ":8080" in output, "No service is listening on port 8080. SSH tunnel might not be running."
    except subprocess.CalledProcessError:
        pytest.fail("Failed to execute ss command.")


def test_gateway_http_endpoint():
    """Verify the microservice gateway is active and fully functional via the SSH tunnel."""
    url = "http://127.0.0.1:8080/"
    headers = {"Authorization": "Bearer secure-micro-token"}
    try:
        response = requests.get(url, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the gateway at {url}: {e}")
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"
    assert "Gateway Active" in response.text, f"Expected 'Gateway Active' in response body, got: {response.text}"


def test_source_is_fixed_and_make_really_builds_daemon():
    with open(SOURCE, "r") as f:
        source = f.read()
    assert 'getenv("GATEWAY_PORT")' in source, "gateway.c does not read GATEWAY_PORT"
    assert "GETWAY_PORT" not in source, "The misspelled GETWAY_PORT remains in gateway.c"

    result = subprocess.run(
        ["make", "-B"], cwd=PACKAGE, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert result.returncode == 0, "make failed:\n" + result.stdout
    assert os.path.isfile(DAEMON) and os.access(DAEMON, os.X_OK)
    with open(DAEMON, "rb") as f:
        assert f.read(4) == b"\x7fELF", "gateway_daemon is not a compiled ELF executable"


def test_setup_env_script_is_idempotent_and_effective():
    script = "/home/user/setup_env.sh"
    env = os.environ.copy()
    env["HOME"] = "/home/user"
    for _ in range(2):
        result = subprocess.run(
            ["runuser", "-u", "user", "--", script], env=env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15
        )
        assert result.returncode == 0, "setup_env.sh failed:\n" + result.stdout

    with open("/home/user/.bashrc", "r") as f:
        content = f.read()
    required = {
        "GATEWAY_PORT": "9000",
        "HTTP_PORT": "9001",
        "GATEWAY_TOKEN": "secure-micro-token",
    }
    for key, value in required.items():
        pattern = rf"^\s*(?:export\s+)?{re.escape(key)}\s*=\s*(['\"]?){re.escape(value)}\1\s*$"
        matches = re.findall(pattern, content, flags=re.MULTILINE)
        assert len(matches) == 1, f"Expected exactly one effective {key} assignment after running setup_env.sh twice"

    command = (
        "source /home/user/.bashrc >/dev/null 2>&1; "
        "printf 'VALUES:%s:%s:%s\\n' \"$GATEWAY_PORT\" \"$HTTP_PORT\" \"$GATEWAY_TOKEN\""
    )
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "/bin/bash", "-ic", command],
        env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10
    )
    assert result.returncode == 0
    assert "VALUES:9000:9001:secure-micro-token" in result.stdout


def test_ssh_key_authorization_and_real_forwarder():
    ssh_dir = "/home/user/.ssh"
    auth_path = os.path.join(ssh_dir, "authorized_keys")
    assert os.path.isdir(ssh_dir), ".ssh directory is missing"
    assert os.path.isfile(auth_path), "authorized_keys is missing"
    user_uid = subprocess.check_output(["id", "-u", "user"], text=True).strip()
    assert str(os.stat(ssh_dir).st_uid) == user_uid, ".ssh is not owned by user"
    assert stat.S_IMODE(os.stat(ssh_dir).st_mode) & 0o022 == 0, ".ssh is group/world writable"
    assert stat.S_IMODE(os.stat(auth_path).st_mode) & 0o022 == 0, "authorized_keys is group/world writable"

    authorized = []
    with open(auth_path) as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) >= 2 and parts[0].startswith("ssh-"):
                authorized.append(tuple(parts[:2]))

    usable_private = None
    for name in os.listdir(ssh_dir):
        path = os.path.join(ssh_dir, name)
        if name.endswith(".pub") or name == "authorized_keys" or not os.path.isfile(path):
            continue
        result = subprocess.run(["ssh-keygen", "-y", "-f", path], text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        if result.returncode != 0:
            continue
        parts = result.stdout.strip().split()
        if len(parts) >= 2 and tuple(parts[:2]) in authorized:
            assert os.stat(path).st_uid == int(user_uid), f"{path} is not owned by user"
            assert stat.S_IMODE(os.stat(path).st_mode) & 0o077 == 0, f"{path} has insecure permissions"
            usable_private = path
            break
    assert usable_private, "No generated private key matches a key in authorized_keys"

    login = subprocess.run([
        "runuser", "-u", "user", "--", "ssh", "-i", usable_private,
        "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null", "-o", "ConnectTimeout=5",
        "user@127.0.0.1", "true"
    ], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10)
    assert login.returncode == 0, "Passwordless localhost SSH using the authorized key failed:\n" + login.stdout

    pids = listener_pids(8080)
    assert pids, "Nothing is listening on port 8080"
    valid = False
    details = []
    for pid in pids:
        try:
            exe = os.path.realpath(f"/proc/{pid}/exe")
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                args = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
        except OSError:
            continue
        details.append((pid, exe, args))
        if os.path.basename(exe) == "ssh" and any("8080:127.0.0.1:9001" in arg for arg in args):
            valid = True
    assert valid, f"Port 8080 is not owned by an SSH process forwarding to 127.0.0.1:9001: {details}"


def test_expect_script_activates_the_built_gateway_and_tunnel_enforces_auth():
    exp_path = "/home/user/enable_http.exp"
    with open(exp_path, "r") as f:
        exp_source = f.read()
    for marker in ("Username:", "Password:", "ENABLE HTTP"):
        assert marker in exp_source, f"Expect script does not handle {marker!r}"
    assert re.search(r"\bexpect\b", exp_source), "enable_http.exp contains no Expect interaction"
    assert re.search(r"\bspawn\b", exp_source), "enable_http.exp does not spawn a TCP client"

    # Remove any pre-existing management/backend impostors, then run the exact
    # freshly-built artifact and require that the submitted Expect script enables it.
    old_pids = listener_pids(9000) | listener_pids(9001)
    for pid in old_pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.4)
    for pid in old_pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    env = os.environ.copy()
    env.update({
        "GATEWAY_PORT": "9000",
        "HTTP_PORT": "9001",
        "GATEWAY_TOKEN": "secure-micro-token",
    })
    daemon = subprocess.Popen(
        [DAEMON], cwd=PACKAGE, env=env,
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True
    )
    assert wait_for_listener(9000, daemon.pid), "The built gateway_daemon did not listen on GATEWAY_PORT=9000"
    assert os.path.realpath(f"/proc/{daemon.pid}/exe") == os.path.realpath(DAEMON)

    exp_env = os.environ.copy()
    exp_env["HOME"] = "/home/user"
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "/usr/bin/expect", exp_path],
        env=exp_env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15
    )
    assert result.returncode == 0, "enable_http.exp failed:\n" + result.stdout
    assert daemon.poll() is None, "The tested gateway_daemon exited"
    assert wait_for_listener(9001, daemon.pid), "Expect script did not enable HTTP in the built gateway daemon"

    nonce = uuid.uuid4().hex
    bad = requests.get(
        f"http://127.0.0.1:8080/check/{nonce}",
        headers={"Authorization": f"Bearer invalid-{nonce}"}, timeout=5
    )
    assert bad.status_code == 401, f"Invalid dynamically generated token was not rejected: {bad.status_code}"

    good = requests.get(
        f"http://127.0.0.1:8080/check/{nonce}",
        headers={"Authorization": "Bearer secure-micro-token"}, timeout=5
    )
    assert good.status_code == 200
    assert "Gateway Active" in good.text
    assert daemon.pid in listener_pids(9001), "HTTP response did not come from the tested gateway process"
    assert listener_pids(8080), "SSH forwarding listener disappeared"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
