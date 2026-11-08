#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import socket
import stat
import subprocess
import threading
import time
import urllib.request

APP_SOURCE = "/home/user/app/disk_monitor.c"
APP_EXECUTABLE = "/home/user/app/disk_monitor"
BACKEND_SOCKET = "/home/user/app/backend.sock"
NGINX_CONFIG = "/home/user/nginx/nginx.conf"
NGINX_PREFIX = "/home/user/nginx"
SCRIPT = "/home/user/check_capacity.sh"
LOG = "/home/user/capacity.log"


def fetch(url, timeout=2):
    with urllib.request.urlopen(url, timeout=timeout) as response:
        return response.read().decode("utf-8")


def wait_for_url(url, timeout=5):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            return fetch(url)
        except Exception as exc:
            last_error = exc
            time.sleep(0.1)
    raise AssertionError(f"Timed out waiting for {url}: {last_error}")


def wait_for_unix_socket(path, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            if stat.S_ISSOCK(os.stat(path).st_mode):
                return
        except FileNotFoundError:
            pass
        time.sleep(0.05)
    raise AssertionError(f"{path} was not created as a UNIX socket")


def unix_http_get(path):
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(2)
    try:
        client.connect(path)
        client.sendall(b"GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
        chunks = []
        while True:
            data = client.recv(4096)
            if not data:
                break
            chunks.append(data)
        return b"".join(chunks).decode("utf-8", errors="replace")
    finally:
        client.close()


def stop_nginx():
    subprocess.run(["pkill", "-TERM", "-x", "nginx"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)
    time.sleep(0.5)
    subprocess.run(["pkill", "-KILL", "-x", "nginx"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)
    try:
        os.unlink("/home/user/nginx/nginx.pid")
    except FileNotFoundError:
        pass


def stop_disk_monitors():
    subprocess.run(["pkill", "-TERM", "-x", "disk_monitor"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-TERM", "-x", "disk_monitor_rebuilt"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)
    time.sleep(0.2)
    subprocess.run(["pkill", "-KILL", "-x", "disk_monitor"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-KILL", "-x", "disk_monitor_rebuilt"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)


def remove_backend_socket():
    try:
        os.unlink(BACKEND_SOCKET)
    except FileNotFoundError:
        pass


def exact_executable_is_running(path):
    expected = os.path.realpath(path)
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            if os.path.realpath(f"/proc/{entry}/exe") == expected:
                return True
        except (FileNotFoundError, PermissionError, OSError):
            pass
    return False


def correctly_configured_nginx_is_running():
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            exe = os.path.realpath(f"/proc/{entry}/exe")
            if os.path.basename(exe) != "nginx":
                continue
            raw = open(f"/proc/{entry}/cmdline", "rb").read()
            args = [x.decode(errors="replace") for x in raw.split(b"\0") if x]
            if ("-c" in args and NGINX_CONFIG in args and
                    "-p" in args and NGINX_PREFIX in args):
                return True
        except (FileNotFoundError, PermissionError, OSError):
            pass
    return False


class OneShotTCPServer:
    def __init__(self, body):
        self.body = body.encode()
        self.error = None
        self.ready = threading.Event()
        self.thread = threading.Thread(target=self._run, daemon=True)

    def _run(self):
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            server.bind(("127.0.0.1", 8080))
            server.listen(1)
            server.settimeout(5)
            self.ready.set()
            client, _ = server.accept()
            with client:
                client.settimeout(2)
                client.recv(4096)
                response = (b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n" +
                            f"Content-Length: {len(self.body)}\r\nConnection: close\r\n\r\n".encode() +
                            self.body)
                client.sendall(response)
        except Exception as exc:
            self.error = exc
            self.ready.set()
        finally:
            server.close()

    def start(self):
        self.thread.start()
        assert self.ready.wait(2), "Temporary server did not start"
        assert self.error is None, f"Temporary server failed: {self.error}"

    def join(self):
        self.thread.join(5)
        assert not self.thread.is_alive(), "Temporary forwarding test server did not finish"
        assert self.error is None, f"Temporary server failed: {self.error}"


class UnixHTTPServer:
    def __init__(self, percentage):
        self.body = f"RESOURCE_USAGE: {percentage}%\n".encode()
        self.stop_event = threading.Event()
        self.ready = threading.Event()
        self.error = None
        self.thread = threading.Thread(target=self._run, daemon=True)

    def _run(self):
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            remove_backend_socket()
            server.bind(BACKEND_SOCKET)
            server.listen(8)
            server.settimeout(0.2)
            self.ready.set()
            while not self.stop_event.is_set():
                try:
                    client, _ = server.accept()
                except socket.timeout:
                    continue
                with client:
                    client.settimeout(2)
                    try:
                        client.recv(4096)
                    except socket.timeout:
                        pass
                    response = (b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n" +
                                f"Content-Length: {len(self.body)}\r\nConnection: close\r\n\r\n".encode() +
                                self.body)
                    client.sendall(response)
        except Exception as exc:
            self.error = exc
            self.ready.set()
        finally:
            server.close()

    def start(self):
        self.thread.start()
        assert self.ready.wait(2), "Temporary UNIX backend did not start"
        assert self.error is None, f"Temporary UNIX backend failed: {self.error}"

    def stop(self):
        self.stop_event.set()
        self.thread.join(3)
        assert not self.thread.is_alive(), "Temporary UNIX backend did not stop"
        assert self.error is None, f"Temporary UNIX backend failed: {self.error}"
        remove_backend_socket()


def test_disk_monitor_running():
    assert os.path.exists(APP_EXECUTABLE), f"{APP_EXECUTABLE} executable does not exist"

    # Preserve the original process check.
    res = subprocess.run(["pgrep", "-f", "disk_monitor"], stdout=subprocess.PIPE)
    assert res.returncode == 0, "disk_monitor process is not running"

    assert os.access(APP_EXECUTABLE, os.X_OK), f"{APP_EXECUTABLE} is not executable"
    with open(APP_EXECUTABLE, "rb") as executable:
        assert executable.read(4) == b"\x7fELF", "disk_monitor is not a compiled ELF executable"
    assert exact_executable_is_running(APP_EXECUTABLE), \
        "The process running is not the submitted /home/user/app/disk_monitor executable"


def test_nginx_running():
    res = subprocess.run(["pgrep", "-f", "nginx"], stdout=subprocess.PIPE)
    assert res.returncode == 0, "nginx process is not running"
    assert correctly_configured_nginx_is_running(), \
        "Nginx was not started with the required configuration and prefix"


def test_port_forwarding_and_app_response():
    try:
        res = fetch("http://127.0.0.1:9090/")
    except Exception as exc:
        assert False, ("Failed to connect to http://127.0.0.1:9090/ or read response: "
                       f"{exc}. Ensure port forwarding is set up and the C app is bound "
                       "to the correct socket.")
    assert "RESOURCE_USAGE:" in res, \
        f"Expected 'RESOURCE_USAGE:' in response, but got: {res}"


def test_check_capacity_script():
    assert os.path.exists(SCRIPT), f"{SCRIPT} does not exist"
    assert os.access(SCRIPT, os.X_OK), f"{SCRIPT} is not executable"


def test_capacity_log():
    assert os.path.exists(LOG), f"{LOG} does not exist. Did you run the check_capacity.sh script?"
    with open(LOG, "r") as log_file:
        content = log_file.read()
    match = re.search(r"\[LOG\] Usage is \d+%", content)
    assert match is not None, \
        f"Correct log entry format not found in {LOG}. Content was: {content}"


def test_complete_deployment_and_script_behavior():
    assert os.path.isfile(APP_SOURCE), f"{APP_SOURCE} does not exist"

    rebuilt = "/tmp/disk_monitor_rebuilt"
    compile_result = subprocess.run(
        ["gcc", APP_SOURCE, "-o", rebuilt], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert compile_result.returncode == 0, \
        f"disk_monitor.c does not compile: {compile_result.stderr}"

    # Stop Nginx and put an unpredictable response on 8080. A request through
    # 9090 must reach it, proving 9090 actually forwards to 127.0.0.1:8080.
    stop_nginx()
    nonce = "FORWARD_CHECK_" + secrets.token_hex(16)
    forward_target = OneShotTCPServer(nonce)
    forward_target.start()
    forwarded = wait_for_url("http://127.0.0.1:9090/", timeout=3)
    forward_target.join()
    assert forwarded == nonce, \
        "Port 9090 did not forward the request and response to 127.0.0.1:8080"

    # Compile and execute the submitted source independently. It must create
    # and serve HTTP on the exact UNIX socket required by Nginx.
    stop_disk_monitors()
    remove_backend_socket()
    rebuilt_process = subprocess.Popen([rebuilt], stdout=subprocess.DEVNULL,
                                         stderr=subprocess.PIPE)
    try:
        wait_for_unix_socket(BACKEND_SOCKET)
        rebuilt_response = unix_http_get(BACKEND_SOCKET)
        assert re.search(r"RESOURCE_USAGE:\s*\d+%", rebuilt_response), \
            f"Recompiled source returned an invalid response: {rebuilt_response}"
    finally:
        rebuilt_process.terminate()
        try:
            rebuilt_process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            rebuilt_process.kill()
            rebuilt_process.wait(timeout=2)
        remove_backend_socket()

    # Execute the named submitted artifact itself and verify that it owns the
    # required socket and serves the backend response.
    app_process = subprocess.Popen([APP_EXECUTABLE], stdout=subprocess.DEVNULL,
                                   stderr=subprocess.PIPE)
    fake_backend = None
    restored_process = None
    try:
        wait_for_unix_socket(BACKEND_SOCKET)
        assert exact_executable_is_running(APP_EXECUTABLE), \
            "The named disk_monitor executable did not remain running"
        app_response = unix_http_get(BACKEND_SOCKET)
        marker = re.search(r"RESOURCE_USAGE:\s*(\d+)%", app_response)
        assert marker, f"Named disk_monitor returned an invalid response: {app_response}"

        # Start Nginx ourselves with exactly the required invocation, then
        # verify both its direct endpoint and the forwarded endpoint reach the
        # submitted UNIX-socket backend.
        config_test = subprocess.run(
            ["nginx", "-t", "-c", NGINX_CONFIG, "-p", NGINX_PREFIX],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        assert config_test.returncode == 0, \
            f"Required Nginx configuration is invalid: {config_test.stderr}"
        start_result = subprocess.run(
            ["nginx", "-c", NGINX_CONFIG, "-p", NGINX_PREFIX],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        assert start_result.returncode == 0, \
            f"Nginx failed to start with the required command: {start_result.stderr}"

        direct = wait_for_url("http://127.0.0.1:8080/")
        proxied = wait_for_url("http://127.0.0.1:9090/")
        assert direct == proxied, \
            "Port 9090 response does not match the response served through Nginx on 8080"
        assert re.search(r"RESOURCE_USAGE:\s*\d+%", direct), \
            f"Nginx did not return the disk_monitor response: {direct}"

        # Replace only the UNIX backend with an unpredictable percentage and
        # execute the submitted script. This checks that the script really
        # obtains and parses the live deployment value instead of fabricating a log.
        app_process.terminate()
        try:
            app_process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            app_process.kill()
            app_process.wait(timeout=2)
        remove_backend_socket()

        percentage = secrets.choice([n for n in range(1, 100) if n != 88])
        fake_backend = UnixHTTPServer(percentage)
        fake_backend.start()
        challenged = wait_for_url("http://127.0.0.1:9090/")
        assert re.search(rf"RESOURCE_USAGE:\s*{percentage}%", challenged), \
            "The Nginx/forwarding chain did not reach the UNIX backend"

        sentinel = b"[VERIFIER SENTINEL]\n"
        with open(LOG, "wb") as log_file:
            log_file.write(sentinel)
        script_result = subprocess.run(
            [SCRIPT], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=10
        )
        assert script_result.returncode == 0, \
            f"check_capacity.sh failed when executed: {script_result.stderr}"
        with open(LOG, "rb") as log_file:
            after = log_file.read()
        assert after.startswith(sentinel), \
            "check_capacity.sh did not append to the existing capacity.log"
        appended = after[len(sentinel):].decode("utf-8", errors="replace")
        assert appended == f"[LOG] Usage is {percentage}%\n", \
            ("check_capacity.sh did not append exactly the live backend value; "
             f"appended content was: {appended!r}")
    finally:
        if fake_backend is not None:
            fake_backend.stop()
        if app_process.poll() is None:
            app_process.terminate()
            try:
                app_process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                app_process.kill()
                app_process.wait(timeout=2)
        remove_backend_socket()
        # Leave the required backend running after verification.
        restored_process = subprocess.Popen([APP_EXECUTABLE], stdout=subprocess.DEVNULL,
                                            stderr=subprocess.DEVNULL)
        wait_for_unix_socket(BACKEND_SOCKET)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
