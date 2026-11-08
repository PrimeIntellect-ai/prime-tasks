#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import random
import resource
import signal
import struct
import subprocess
import sys
import time
import urllib.request

ROOT = "/home/user/mobile_build"
EXPECTED = {"ARCH": "arm64", "OPT": "O3", "LTO": "true"}


def read_env(path):
    env_vars = {}
    with open(path, "r") as f:
        content = f.read().strip().split("\n")
    for line in content:
        if "=" in line:
            k, v = line.split("=", 1)
            env_vars[k.strip()] = v.strip()
    return env_vars


def test_01_api_is_running():
    with urllib.request.urlopen("http://127.0.0.1:8080/constraints", timeout=3) as response:
        assert response.status == 200
        data = json.loads(response.read().decode())
    assert "variables" in data and "rules" in data, "The local REST API is not serving constraints."


def test_02_build_env_exists_and_correct():
    env_path = os.path.join(ROOT, "build.env")
    assert os.path.isfile(env_path), f"File {env_path} does not exist. Did orchestrator.py run successfully?"
    env_vars = read_env(env_path)
    assert env_vars.get("ARCH") == "arm64", "build.env does not contain the correct ARCH value."
    assert env_vars.get("OPT") == "O3", "build.env does not contain the correct OPT value."
    assert env_vars.get("LTO") == "true", "build.env does not contain the correct LTO value."


def test_03_libmobile_so_exists():
    so_path = os.path.join(ROOT, "libmobile.so")
    assert os.path.isfile(so_path), f"File {so_path} does not exist. Did you run 'make'?"


def test_04_success_log_exists():
    log_path = os.path.join(ROOT, "success.log")
    assert os.path.isfile(log_path), f"File {log_path} does not exist. Did report.py send the correct POST request?"
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert content == "SUCCESS", f"Expected success.log to contain 'SUCCESS', but found '{content}'"


def kill_port_8080_listeners():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].split(":")[-1].upper() == "1F90" and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == os.getpid():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    os.kill(int(pid), signal.SIGTERM)
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass

    deadline = time.time() + 3
    while time.time() < deadline:
        try:
            urllib.request.urlopen("http://127.0.0.1:8080/constraints", timeout=0.2)
        except Exception:
            return
        time.sleep(0.1)
    raise AssertionError("Could not stop the existing API server for isolated verification.")


def test_05_execute_required_artifacts():
    report_path = os.path.join(ROOT, "report.py")
    orchestrator_path = os.path.join(ROOT, "orchestrator.py")
    assert os.path.isfile(report_path), "report.py does not exist."
    assert os.path.isfile(orchestrator_path), "orchestrator.py does not exist."

    # Rebuild rather than trusting a file named libmobile.so, then validate and load it.
    so_path = os.path.join(ROOT, "libmobile.so")
    if os.path.lexists(so_path):
        os.unlink(so_path)
    built = subprocess.run(["make"], cwd=ROOT, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, text=True, timeout=30)
    assert built.returncode == 0, "make failed:\n" + built.stdout
    assert os.path.isfile(so_path), "make did not produce libmobile.so."
    with open(so_path, "rb") as f:
        header = f.read(20)
    assert header[:4] == b"\x7fELF", "libmobile.so is not an ELF binary."
    endian = "<" if header[5] == 1 else ">"
    assert struct.unpack(endian + "H", header[16:18])[0] == 3, "libmobile.so is not a shared object."
    ctypes.CDLL(so_path)

    kill_port_8080_listeners()

    arch = ["arm32", "arm64", "x86"]
    opt = ["O1", "O2", "O3"]
    lto = ["true", "false"]
    while True:
        target = {"ARCH": random.choice(arch), "OPT": random.choice(opt), "LTO": random.choice(lto)}
        if target != EXPECTED:
            break
    domains = {}
    for key, values in (("ARCH", arch), ("OPT", opt), ("LTO", lto)):
        others = [v for v in values if v != target[key]]
        random.shuffle(others)
        domains[key] = others + [target[key]]
    rules = []
    for key, values in domains.items():
        for value in values[:-1]:
            rules.append({"if": {key: value}, "then": {key: target[key]}})

    config_path = "/tmp/verifier_api_config.json"
    capture_path = "/tmp/verifier_report_capture.json"
    with open(config_path, "w") as f:
        json.dump({"variables": domains, "rules": rules}, f)
    if os.path.exists(capture_path):
        os.unlink(capture_path)

    server_source = r'''
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
CONFIG = "/tmp/verifier_api_config.json"
CAPTURE = "/tmp/verifier_report_capture.json"
EXPECTED = {"ARCH": "arm64", "OPT": "O3", "LTO": "true"}
class Server(HTTPServer):
    allow_reuse_address = True
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass
    def do_GET(self):
        if self.path != "/constraints":
            self.send_response(404); self.end_headers(); return
        with open(CONFIG) as f:
            payload = json.load(f)
        body = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def do_POST(self):
        if self.path != "/report":
            self.send_response(404); self.end_headers(); return
        length = int(self.headers.get("Content-Length", "0"))
        try:
            payload = json.loads(self.rfile.read(length).decode())
        except Exception:
            self.send_response(400); self.end_headers(); return
        with open(CAPTURE, "w") as f:
            json.dump(payload, f)
        if payload == EXPECTED:
            with open("/home/user/mobile_build/success.log", "w") as f:
                f.write("SUCCESS")
            self.send_response(200)
        else:
            self.send_response(400)
        self.end_headers()
Server(("127.0.0.1", 8080), Handler).serve_forever()
'''
    server_file = "/tmp/verifier_api.py"
    with open(server_file, "w") as f:
        f.write(server_source)
    server = subprocess.Popen([sys.executable, server_file], stdout=subprocess.DEVNULL,
                              stderr=subprocess.PIPE, text=True)
    try:
        deadline = time.time() + 5
        while time.time() < deadline:
            if server.poll() is not None:
                raise AssertionError("Verification API failed to start: " + server.stderr.read())
            try:
                urllib.request.urlopen("http://127.0.0.1:8080/constraints", timeout=0.2)
                break
            except Exception:
                time.sleep(0.1)
        else:
            raise AssertionError("Verification API did not start.")

        # report.py must itself issue the correct POST; a pre-created log is not accepted.
        success_path = os.path.join(ROOT, "success.log")
        if os.path.exists(success_path):
            os.unlink(success_path)
        reported = subprocess.run([sys.executable, report_path], cwd=ROOT,
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                  text=True, timeout=15)
        assert reported.returncode == 0, "report.py failed:\n" + reported.stdout
        assert os.path.isfile(capture_path), "report.py did not POST to /report."
        with open(capture_path) as f:
            assert json.load(f) == EXPECTED, "report.py sent an incorrect JSON payload."
        assert os.path.isfile(success_path), "The report POST did not produce success.log."
        with open(success_path) as f:
            assert f.read().strip() == "SUCCESS"

        # Exercise the solver with a verifier-generated constraint set whose sole
        # solution is last in the search order. The 100 MiB address-space cap catches
        # the original per-state 10 MiB leak and rejects hardcoded build.env output.
        env_path = os.path.join(ROOT, "build.env")
        if os.path.exists(env_path):
            os.unlink(env_path)

        def limit_memory():
            cap = 100 * 1024 * 1024
            resource.setrlimit(resource.RLIMIT_AS, (cap, cap))

        solved = subprocess.run([sys.executable, orchestrator_path], cwd=ROOT,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, timeout=30, preexec_fn=limit_memory)
        assert solved.returncode == 0, "orchestrator.py failed under the 100MB limit:\n" + solved.stdout
        assert os.path.isfile(env_path), "orchestrator.py did not generate build.env."
        assert read_env(env_path) == target, "orchestrator.py did not solve the supplied constraints."
    finally:
        server.terminate()
        try:
            server.wait(timeout=3)
        except subprocess.TimeoutExpired:
            server.kill()
            server.wait()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
