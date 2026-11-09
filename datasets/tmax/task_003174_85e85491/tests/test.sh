#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import http.client
import os
import re
import shutil
import socket
import stat
import subprocess
import tempfile
import time

SCRIPT = "/home/user/deploy.sh"
SOURCE = "/home/user/app/server.cpp"
SOCKET_PATH = "/home/user/run/upstream.sock"
RESULT = "/home/user/test_result.log"
ACCESS_LOG = "/home/user/nginx/logs/access.log"


def processes():
    result = subprocess.run(["ps", "aux"], capture_output=True, text=True)
    return result.stdout.splitlines()


def assert_cleaned_up():
    time.sleep(1)
    entries = processes()
    nginx_running = any(("nginx" in p and "worker" in p) or ("nginx" in p and "master" in p) for p in entries)
    server_running = any("server_bin" in p and "grep" not in p for p in entries)
    assert not nginx_running, "Nginx process was not cleaned up by the trap in deploy.sh"
    assert not server_running, "server_bin process was not cleaned up by the trap in deploy.sh"


def make_wrappers(directory):
    for command in ("g++", "nginx"):
        real = shutil.which(command)
        assert real, f"Required command {command} is unavailable"
        wrapper = os.path.join(directory, command)
        with open(wrapper, "w") as f:
            f.write("#!/bin/bash\n")
            f.write(f"printf '%s\\0' \"$@\" > \"$(mktemp '{directory}/{command}.XXXXXX.args')\"\n")
            f.write(f"exec {real!r} \"$@\"\n")
        os.chmod(wrapper, 0o755)


def recorded_calls(directory, command):
    calls = []
    for name in os.listdir(directory):
        if name.startswith(command + ".") and name.endswith(".args"):
            with open(os.path.join(directory, name), "rb") as f:
                calls.append([part.decode() for part in f.read().split(b"\0") if part])
    return calls


def server_and_nginx_are_running():
    backend = False
    nginx = False
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            exe = os.path.realpath(f"/proc/{pid}/exe")
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ").decode(errors="replace")
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if exe == "/home/user/app/server_bin":
            backend = True
        if exe.endswith("/nginx") and ("nginx: master" in cmdline or "nginx: worker" in cmdline):
            nginx = True
    return backend and nginx


def probe(expected):
    conn = http.client.HTTPConnection("127.0.0.1", 8080, timeout=1)
    try:
        conn.request("GET", "/", headers={"User-Agent": "VerifierProbe/1.0"})
        response = conn.getresponse()
        body = response.read().decode()
        return response.status == 200 and body == expected
    except (OSError, http.client.HTTPException):
        return False
    finally:
        conn.close()


def run_deploy(expected):
    os.makedirs("/home/user/run", exist_ok=True)
    try:
        os.unlink(SOCKET_PATH)
    except FileNotFoundError:
        pass
    with open(SOCKET_PATH, "w") as f:
        f.write("stale socket placeholder")

    for path in (RESULT, "/home/user/app/server_bin", ACCESS_LOG):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    with tempfile.TemporaryDirectory() as wrapper_dir:
        make_wrappers(wrapper_dir)
        env = os.environ.copy()
        env["PATH"] = wrapper_dir + os.pathsep + env.get("PATH", "")

        started = time.monotonic()
        proc = subprocess.Popen(
            ["bash", "-x", SCRIPT],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
        )

        observed_real_stack = False
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline and proc.poll() is None:
            try:
                socket_ok = stat.S_ISSOCK(os.stat(SOCKET_PATH).st_mode)
            except FileNotFoundError:
                socket_ok = False
            if socket_ok and server_and_nginx_are_running() and probe(expected):
                observed_real_stack = True
                break
            time.sleep(0.1)

        try:
            stdout, stderr = proc.communicate(timeout=max(1, deadline - time.monotonic()))
        except subprocess.TimeoutExpired:
            proc.kill()
            stdout, stderr = proc.communicate()
            raise AssertionError(f"Deploy script timed out.\nSTDOUT:\n{stdout}\nSTDERR:\n{stderr}")

        assert proc.returncode == 0, (
            f"Deploy script failed with exit code {proc.returncode}.\n"
            f"STDOUT:\n{stdout}\nSTDERR:\n{stderr}"
        )
        assert observed_real_stack, (
            "The deployed server_bin and Nginx were not simultaneously observed serving "
            "the expected response through http://127.0.0.1:8080/"
        )

        gpp_calls = recorded_calls(wrapper_dir, "g++")
        assert [SOURCE, "-o", "/home/user/app/server_bin"] in gpp_calls, (
            "deploy.sh did not invoke g++ /home/user/app/server.cpp "
            "-o /home/user/app/server_bin"
        )
        nginx_calls = recorded_calls(wrapper_dir, "nginx")
        assert ["-p", "/home/user/nginx", "-c", "/home/user/nginx/nginx.conf"] in nginx_calls, (
            "deploy.sh did not start Nginx with the required -p and -c arguments"
        )

        assert re.search(r"(?m)^\s*set\s+-[^\n#]*e", open(SCRIPT).read()), "deploy.sh must use set -e"
        assert re.search(r"(?m)^\s*trap\b.*\bEXIT\b", open(SCRIPT).read()), (
            "deploy.sh must install an EXIT trap for cleanup"
        )
        assert re.search(r"(?m)^\+\s+rm\b[^\n]*?/home/user/run/upstream\.sock", stderr), (
            "deploy.sh did not remove the old upstream socket before startup"
        )
        assert re.search(r"(?m)^\+\s+sleep\s+[2-9][0-9]*(?:\.\d+)?\s*$", stderr), (
            "deploy.sh must wait a few seconds for the services to start"
        )
        assert re.search(r"(?m)^\+\s+trap\b.*\bEXIT\b", stderr), (
            "The cleanup trap was not actually installed during execution"
        )
        assert time.monotonic() - started >= 2, "deploy.sh did not wait for service startup"

    assert os.path.isfile(RESULT), f"Log file {RESULT} was not created by the deploy script"
    with open(RESULT) as f:
        assert f.read().strip() == expected, f"Expected log content {expected!r}"

    assert os.path.isfile(ACCESS_LOG), "Nginx access log was not created"
    with open(ACCESS_LOG, errors="replace") as f:
        access_lines = f.readlines()
    assert any("GET / HTTP/" in line and "VerifierProbe/1.0" not in line for line in access_lines), (
        "No HTTP GET made by deploy.sh was observed in the Nginx access log"
    )

    assert_cleaned_up()


def test_server_cpp_fixed():
    assert os.path.isfile(SOURCE), f"File {SOURCE} is missing"
    with open(SOURCE) as f:
        content = f.read()
    assert SOCKET_PATH in content, (
        "The socket path in server.cpp was not updated to /home/user/run/upstream.sock"
    )


def test_deploy_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f"Deploy script {SCRIPT} is missing"
    assert os.access(SCRIPT, os.X_OK), f"Deploy script {SCRIPT} is not executable"


def test_deploy_script_execution_and_cleanup():
    run_deploy("Hello from C++!")


def test_deploy_rebuilds_and_serves_current_source():
    expected = "RL9a4c2e7b1d6f0"
    assert len(expected) == 15
    with open(SOURCE) as f:
        original = f.read()

    replacement = r'''#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <cstring>

int main() {
    const char* path = "/home/user/run/upstream.sock";
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return 1;
    sockaddr_un address{};
    address.sun_family = AF_UNIX;
    std::strncpy(address.sun_path, path, sizeof(address.sun_path) - 1);
    unlink(path);
    if (bind(fd, reinterpret_cast<sockaddr*>(&address), sizeof(address)) < 0) return 2;
    if (listen(fd, 3) < 0) return 3;
    while (true) {
        int client = accept(fd, nullptr, nullptr);
        if (client < 0) continue;
        const char* response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 15\r\nConnection: close\r\n\r\nRL9a4c2e7b1d6f0";
        write(client, response, std::strlen(response));
        close(client);
    }
}
'''
    try:
        with open(SOURCE, "w") as f:
            f.write(replacement)
        run_deploy(expected)
    finally:
        with open(SOURCE, "w") as f:
            f.write(original)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
