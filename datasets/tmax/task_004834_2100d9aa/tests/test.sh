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
import time
import subprocess
import requests
import pytest

CONF = "/home/user/supervisor.conf"
TOKEN = "k8s-mock-alpha-99x2"


def cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode(errors="replace").strip()
    except OSError:
        return ""


def executable(pid):
    try:
        return os.path.realpath(f"/proc/{pid}/exe")
    except OSError:
        return ""


def has_supervisord_ancestor(pid):
    seen = set()
    while pid > 1 and pid not in seen:
        seen.add(pid)
        try:
            with open(f"/proc/{pid}/stat") as f:
                fields = f.read().split()
            pid = int(fields[3])
        except (OSError, ValueError, IndexError):
            return False
        if "supervisord" in cmdline(pid):
            return True
    return False


def listening_socket_inodes(port, expected_addr):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                rows = f.readlines()[1:]
        except OSError:
            continue
        for row in rows:
            fields = row.split()
            local = fields[1]
            state = fields[3]
            addr_hex, port_hex = local.split(":")
            if state != "0A" or int(port_hex, 16) != port:
                continue
            if table.endswith("tcp"):
                addr = {
                    "0100007F": "127.0.0.1",
                    "00000000": "0.0.0.0",
                }.get(addr_hex, addr_hex)
            else:
                addr = "::" if int(addr_hex, 16) == 0 else addr_hex
            if addr == expected_addr:
                inodes.add(fields[9])
    return inodes


def listener_pids(port, expected_addr):
    inodes = listening_socket_inodes(port, expected_addr)
    owners = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            fds = os.listdir(fd_dir)
        except OSError:
            continue
        for fd in fds:
            try:
                target = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            match = re.fullmatch(r"socket:\[(\d+)\]", target)
            if match and match.group(1) in inodes:
                owners.add(int(name))
                break
    return owners


def assert_stack_processes():
    op1 = listener_pids(8081, "127.0.0.1")
    op2 = listener_pids(8082, "127.0.0.1")
    proxy = listener_pids(9090, "127.0.0.1")
    tunnel = listener_pids(8000, "0.0.0.0")

    assert op1, "Nothing is listening on 127.0.0.1:8081"
    assert op2, "Nothing is listening on 127.0.0.1:8082"
    assert proxy, "Nothing is listening on 127.0.0.1:9090"
    assert tunnel, "Nothing is listening on 0.0.0.0:8000"

    for pid, port in [(p, 8081) for p in op1] + [(p, 8082) for p in op2]:
        assert executable(pid) == "/app/operator-core", (
            f"Port {port} is not owned by /app/operator-core: pid={pid}, cmd={cmdline(pid)}"
        )
        command = cmdline(pid)
        assert str(port) in command and "--port" in command, command
        assert has_supervisord_ancestor(pid), f"operator on port {port} is not supervised"

    for pid in proxy:
        command = cmdline(pid)
        assert "python" in os.path.basename(executable(pid)).lower(), command
        assert "/home/user/proxy.py" in command, command
        assert has_supervisord_ancestor(pid), "proxy.py is not supervised"

    for pid in tunnel:
        command = cmdline(pid)
        assert os.path.basename(executable(pid)) == "ssh", command
        assert "8000" in command and "9090" in command and "127.0.0.1" in command, command
        assert has_supervisord_ancestor(pid), "SSH tunnel is not supervised"

    return proxy


def test_supervisor_conf_exists():
    """Check that the supervisor configuration file was created at the correct location."""
    assert os.path.exists(CONF), f"The supervisor configuration file {CONF} does not exist."
    assert os.path.isfile(CONF), f"The path {CONF} is not a file."
    text = open(CONF, errors="replace").read()
    for name in ("operator-1", "operator-2", "proxy", "tunnel"):
        assert re.search(rf"(?m)^\s*\[program:{re.escape(name)}\]\s*$", text), (
            f"Missing [program:{name}] in {CONF}"
        )


def test_required_processes_and_auth_injection():
    """Verify that the real supervised backends, proxy, and SSH listener are present."""
    assert_stack_processes()

    expected = {}
    for port in (8081, 8082):
        url = f"http://127.0.0.1:{port}/api/v1/manifests"
        unauth = requests.get(url, timeout=3)
        assert unauth.status_code == 401, f"Backend {port} accepted an unauthenticated request"
        wrong = requests.get(url, headers={"X-K8s-Mock-Auth": "wrong-token"}, timeout=3)
        assert wrong.status_code == 401, f"Backend {port} accepted an incorrect token"
        good = requests.get(url, headers={"X-K8s-Mock-Auth": TOKEN}, timeout=3)
        assert good.status_code == 200
        expected[f"port-{port}"] = good.json()

    # The proxy must replace an external bad credential with the discovered credential.
    proxied = requests.get(
        "http://127.0.0.1:9090/api/v1/manifests",
        headers={"X-K8s-Mock-Auth": "wrong-token"},
        timeout=3,
    )
    assert proxied.status_code == 200, "Proxy did not inject/replace the backend authentication header"
    body = proxied.json()
    assert body.get("backend") in expected
    assert body == expected[body["backend"]], "Proxy response does not match the real backend response"


def test_api_load_balancing():
    """Test the complete SSH-tunnel, proxy, authentication, and backend path."""
    url = "http://127.0.0.1:8000/api/v1/manifests"
    expected = {}
    for port in (8081, 8082):
        response = requests.get(
            f"http://127.0.0.1:{port}/api/v1/manifests",
            headers={"X-K8s-Mock-Auth": TOKEN},
            timeout=3,
        )
        assert response.status_code == 200
        expected[f"port-{port}"] = response.json()

    backends_seen = set()
    for _ in range(10):
        try:
            resp = requests.get(url, timeout=3)
            assert resp.status_code == 200, f"Expected HTTP 200 OK, got {resp.status_code}. Response body: {resp.text}"
            try:
                data = resp.json()
            except ValueError:
                pytest.fail(f"Response was not valid JSON: {resp.text}")
            backend = data.get("backend")
            assert backend is not None, f"Response JSON missing 'backend' field: {data}"
            assert backend in expected, f"Unknown backend reported: {backend}"
            assert data == expected[backend], "Tunnel response does not match the real operator backend"
            backends_seen.add(backend)
        except requests.RequestException as e:
            pytest.fail(f"Request to {url} failed: {e}")

    assert "port-8081" in backends_seen, "After 10 requests, did not receive any response from backend port-8081. Load balancing might not be working."
    assert "port-8082" in backends_seen, "After 10 requests, did not receive any response from backend port-8082. Load balancing might not be working."


def test_process_supervision():
    """Test that killing proxy.py causes supervisord to restart the real proxy."""
    old_proxy_pids = listener_pids(9090, "127.0.0.1")
    assert old_proxy_pids

    # Preserve the original restart test while ensuring the killed process is the port owner.
    subprocess.run(["pkill", "-9", "-f", "proxy.py"])
    time.sleep(5)

    new_proxy_pids = listener_pids(9090, "127.0.0.1")
    assert new_proxy_pids, "supervisord did not restore the proxy listener"
    assert new_proxy_pids.isdisjoint(old_proxy_pids), "The proxy listener was not restarted"
    assert_stack_processes()

    url = "http://127.0.0.1:8000/api/v1/manifests"
    try:
        resp = requests.get(url, timeout=5)
        assert resp.status_code == 200, f"Service did not recover after proxy was killed. Expected 200 OK, got {resp.status_code}."
    except requests.RequestException as e:
        pytest.fail(f"Service did not recover after proxy was killed. Request failed: {e}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
