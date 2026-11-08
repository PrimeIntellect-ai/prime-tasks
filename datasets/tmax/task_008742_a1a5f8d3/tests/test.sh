#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tempfile
import time


def user_systemctl(*args):
    return subprocess.run(
        ["su", "-", "user", "-c", "systemctl --user " + " ".join(args)],
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_proxy_service_dependencies():
    """Verify that proxy.service has real [Unit] dependency directives."""
    path = "/home/user/.config/systemd/user/proxy.service"
    assert os.path.isfile(path), f"{path} does not exist"

    with open(path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "Requires=backend.service" in content, "proxy.service is missing 'Requires=backend.service'"
    assert "After=backend.service" in content, "proxy.service is missing 'After=backend.service'"

    section = None
    directives = {}
    for raw_line in content.splitlines():
        line = raw_line.strip()
        if not line or line.startswith(("#", ";")):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip()
            continue
        if section == "Unit" and "=" in line:
            key, value = line.split("=", 1)
            directives.setdefault(key.strip(), []).extend(value.split())

    assert "backend.service" in directives.get("Requires", []), \
        "proxy.service must require backend.service in its [Unit] section"
    assert "backend.service" in directives.get("After", []), \
        "proxy.service must start after backend.service in its [Unit] section"

    # Check the loaded unit too, so comments or an un-reloaded edit cannot pass.
    requires = user_systemctl("show", "proxy.service", "--property=Requires", "--value")
    after = user_systemctl("show", "proxy.service", "--property=After", "--value")
    assert requires.returncode == 0, requires.stderr
    assert after.returncode == 0, after.stderr
    assert "backend.service" in requires.stdout.split(), "Loaded proxy.service does not require backend.service"
    assert "backend.service" in after.stdout.split(), "Loaded proxy.service is not ordered after backend.service"


def test_binary_compiled():
    """Verify that the source compiles and the installed artifact is a current ELF binary."""
    bin_path = "/home/user/health_proxy"
    src_path = "/home/user/health_proxy.c"
    assert os.path.isfile(bin_path), f"Compiled binary {bin_path} is missing. Did you compile health_proxy.c?"
    assert os.access(bin_path, os.X_OK), f"File {bin_path} is not executable."
    assert os.path.isfile(src_path), f"Proxy source {src_path} is missing"

    with open(bin_path, "rb") as f:
        installed = f.read()
    assert installed.startswith(b"\x7fELF"), "health_proxy is not a compiled ELF executable"
    assert os.stat(bin_path).st_mtime_ns >= os.stat(src_path).st_mtime_ns, \
        "health_proxy is older than health_proxy.c; recompile the modified source"
    assert b"/home/user/logs/proxy.log" in installed, \
        "Compiled proxy does not contain the required log path"
    assert b"/home/user/proxy_access.log" not in installed, \
        "Compiled proxy still contains the obsolete log path"

    fd, rebuilt = tempfile.mkstemp(prefix="health_proxy_rebuilt_")
    os.close(fd)
    os.unlink(rebuilt)
    try:
        result = subprocess.run(
            ["gcc", src_path, "-o", rebuilt], capture_output=True, text=True, timeout=20
        )
        assert result.returncode == 0, f"health_proxy.c does not compile with gcc: {result.stderr}"
        with open(rebuilt, "rb") as f:
            rebuilt_data = f.read()
        assert rebuilt_data.startswith(b"\x7fELF")
        assert b"/home/user/logs/proxy.log" in rebuilt_data, \
            "Compiling health_proxy.c does not produce a proxy using the required log path"
        assert b"/home/user/proxy_access.log" not in rebuilt_data, \
            "health_proxy.c still compiles with the obsolete log path"
    finally:
        if os.path.exists(rebuilt):
            os.unlink(rebuilt)


def test_proxy_log_exists_and_populated():
    """Verify an agent request already populated the required log."""
    log_path = "/home/user/logs/proxy.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist. Ensure the C code was updated, compiled, and a request was made."
    assert os.path.getsize(log_path) > 0, f"Log file {log_path} is empty. Did you make a successful curl request to the proxy?"


def test_services_active():
    """Verify that both user systemd services are active."""
    for svc in ["backend.service", "proxy.service"]:
        res = user_systemctl("is-active", svc)
        status = res.stdout.strip()
        assert status == "active", f"Service {svc} is not active. Current status: '{status}'. Error output: {res.stderr.strip()}"

    pid_result = user_systemctl("show", "proxy.service", "--property=MainPID", "--value")
    assert pid_result.returncode == 0, pid_result.stderr
    assert pid_result.stdout.strip().isdigit() and int(pid_result.stdout.strip()) > 0, \
        "proxy.service has no running main process"
    pid = int(pid_result.stdout.strip())
    running_exe = os.path.realpath(f"/proc/{pid}/exe")
    assert running_exe == "/home/user/health_proxy", \
        f"proxy.service is running {running_exe}, not /home/user/health_proxy"


def test_live_proxy_http_and_logging():
    """Exercise the installed proxy and prove that this request reaches its required log."""
    log_path = "/home/user/logs/proxy.log"
    before_size = os.path.getsize(log_path)
    unique_path = f"/verifier-{os.getpid()}-{time.time_ns()}"
    response = subprocess.run(
        ["curl", "--fail", "--silent", "--show-error", "--max-time", "5",
         f"http://127.0.0.1:9090{unique_path}"],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert response.returncode == 0, f"Proxy did not serve a successful HTTP GET: {response.stderr}"
    assert "Backend reached via Proxy" in response.stdout, \
        f"Unexpected proxy response body: {response.stdout!r}"

    deadline = time.time() + 3
    while time.time() < deadline and os.path.getsize(log_path) <= before_size:
        time.sleep(0.05)
    assert os.path.getsize(log_path) > before_size, \
        "A live request did not append to /home/user/logs/proxy.log"
    with open(log_path, "rb") as f:
        f.seek(before_size)
        appended = f.read()
    assert b"Request forwarded to backend" in appended, \
        "The access log does not contain the entry produced by the verifier's request"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
