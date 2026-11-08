#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import signal
import subprocess
import time
from pathlib import Path


def expected_csv():
    base_dir = "/home/user/mock_containers"
    expected_sizes = {}
    if os.path.isdir(base_dir):
        for container in os.listdir(base_dir):
            data_dir = os.path.join(base_dir, container, "data")
            total_size = 0
            if os.path.isdir(data_dir):
                for root, _, files in os.walk(data_dir):
                    for file in files:
                        file_path = os.path.join(root, file)
                        if os.path.isfile(file_path):
                            total_size += os.path.getsize(file_path)
            expected_sizes[container] = total_size
    return "".join(f"{c},{expected_sizes[c]}\n" for c in sorted(expected_sizes))


def assert_report_matches():
    report = Path("/home/user/capacity_report.csv")
    assert report.is_file(), "CSV report was not created"
    actual = [line.strip() for line in report.read_text().splitlines() if line.strip()]
    wanted = [line.strip() for line in expected_csv().splitlines() if line.strip()]
    assert actual == wanted, f"CSV content mismatch. Expected: {wanted}, Got: {actual}"


def kill_port_9090_listeners():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if fields[1].rsplit(":", 1)[-1].upper() == "2382" and fields[3] == "0A":
                inodes.add(fields[9])
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit() or int(proc.name) == os.getpid():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                if os.readlink(fd) in {f"socket:[{inode}]" for inode in inodes}:
                    os.kill(int(proc.name), signal.SIGKILL)
                    break
        except (OSError, PermissionError):
            pass


def test_end_to_end_artifacts_and_real_post():
    analyzer_cpp = Path("/home/user/analyzer.cpp")
    submit_script = Path("/home/user/submit_metrics.sh")
    assert analyzer_cpp.is_file(), f"C++ analyzer source missing: {analyzer_cpp}"
    assert submit_script.is_file(), f"Automation script missing: {submit_script}"
    assert os.access(submit_script, os.X_OK), f"Automation script is not executable: {submit_script}"

    script_text = submit_script.read_text(errors="replace")
    assert "g++" in script_text, "submit_metrics.sh does not invoke g++"
    assert "curl" in script_text, "submit_metrics.sh does not invoke curl"

    nonce = secrets.token_hex(6)
    dynamic_container = Path(f"/home/user/mock_containers/verifier_{nonce}")
    nested = dynamic_container / "data" / "nested"
    nested.mkdir(parents=True)
    (nested / "payload.bin").write_bytes(os.urandom(1237))
    (dynamic_container / "ignored.bin").write_bytes(os.urandom(411))
    alpha_extra = Path(f"/home/user/mock_containers/alpha/data/dynamic_{nonce}.bin")
    alpha_extra.write_bytes(os.urandom(719))
    Path(f"/home/user/mock_containers/alpha/meta/ignored_{nonce}.bin").write_bytes(os.urandom(997))

    verifier_binary = f"/tmp/verifier_analyzer_{nonce}"
    subprocess.run(
        ["g++", "-std=c++17", str(analyzer_cpp), "-o", verifier_binary],
        check=True,
        timeout=30,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    Path("/home/user/capacity_report.csv").unlink(missing_ok=True)
    subprocess.run([verifier_binary], check=True, timeout=20)
    assert_report_matches()

    expected_body = expected_csv()
    dynamic_token = f"verify_{secrets.token_hex(16)}"
    auth_path = Path("/home/user/.config/reporter/auth.conf")
    assert auth_path.is_file(), f"Auth file missing: {auth_path}"
    original_auth = auth_path.read_text()
    auth_path.write_text(f"# Client authentication config\nTOKEN={dynamic_token}\n")

    observation = f"/tmp/upload_observed_{nonce}.json"
    ready = f"/tmp/upload_ready_{nonce}"
    server_code = r'''
from http.server import BaseHTTPRequestHandler, HTTPServer
import json, os
expected_body = os.environ["VERIFY_BODY"]
expected_token = os.environ["VERIFY_TOKEN"]
observation = os.environ["VERIFY_OBSERVATION"]
ready = os.environ["VERIFY_READY"]
class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length).decode("utf-8")
        token = self.headers.get("X-Auth-Token")
        valid = self.path == "/upload" and token == expected_token and body.strip() == expected_body.strip()
        with open(observation, "w") as f:
            json.dump({"path": self.path, "token": token, "body": body, "valid": valid}, f)
        if valid:
            with open("/home/user/server_success.flag", "w") as f:
                f.write("SUCCESS")
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"Metrics accepted")
        else:
            self.send_response(403 if token != expected_token else 400)
            self.end_headers()
    def log_message(self, *args):
        pass
server = HTTPServer(("127.0.0.1", 9090), Handler)
open(ready, "w").close()
server.timeout = 30
server.handle_request()
'''
    env = os.environ.copy()
    env.update({
        "VERIFY_BODY": expected_body,
        "VERIFY_TOKEN": dynamic_token,
        "VERIFY_OBSERVATION": observation,
        "VERIFY_READY": ready,
    })

    server = None
    try:
        kill_port_9090_listeners()
        Path("/home/user/capacity_report.csv").unlink(missing_ok=True)
        Path("/home/user/analyzer").unlink(missing_ok=True)
        Path("/home/user/server_success.flag").unlink(missing_ok=True)
        Path(observation).unlink(missing_ok=True)
        Path(ready).unlink(missing_ok=True)

        server = subprocess.Popen(["python3", "-c", server_code], env=env)
        deadline = time.time() + 5
        while time.time() < deadline and not Path(ready).exists():
            assert server.poll() is None, "Verification reporting service failed to start"
            time.sleep(0.05)
        assert Path(ready).exists(), "Verification reporting service did not become ready"

        result = subprocess.run(
            [str(submit_script)],
            cwd="/home/user",
            timeout=45,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert result.returncode == 0, (
            f"submit_metrics.sh exited {result.returncode}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        server.wait(timeout=5)

        assert Path("/home/user/analyzer").is_file(), "submit_metrics.sh did not create /home/user/analyzer"
        assert os.access("/home/user/analyzer", os.X_OK), "/home/user/analyzer is not executable"
        assert_report_matches()
        assert Path(observation).is_file(), "No POST request reached the reporting service"
        request = json.loads(Path(observation).read_text())
        assert request["valid"], f"Invalid upload received: {request}"
    finally:
        auth_path.write_text(original_auth)
        if server is not None and server.poll() is None:
            server.kill()
            server.wait()


def test_auth_conf_updated():
    auth_file = "/home/user/.config/reporter/auth.conf"
    assert os.path.isfile(auth_file), f"Auth file missing: {auth_file}"

    with open(auth_file, "r") as f:
        content = f.read()

    server_script = "/home/user/reporting_service.py"
    assert os.path.isfile(server_script), f"Reporting service script missing: {server_script}"

    with open(server_script, "r") as f:
        server_content = f.read()

    match = re.search(r'EXPECTED_TOKEN\s*=\s*["\']([^"\']+)["\']', server_content)
    assert match is not None, "Could not find EXPECTED_TOKEN in reporting_service.py"
    expected_token = match.group(1)
    assert expected_token == "secr3t_c4pacity_77", "reporting_service.py was improperly modified"
    assert expected_token in content, f"auth.conf does not contain the correct token. Expected to find: {expected_token}"


def test_csv_content():
    csv_file = "/home/user/capacity_report.csv"
    assert os.path.isfile(csv_file), f"CSV report missing: {csv_file}"
    expected_lines = [line.strip() for line in expected_csv().splitlines() if line.strip()]
    with open(csv_file, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    assert actual_lines == expected_lines, f"CSV content mismatch. Expected: {expected_lines}, Got: {actual_lines}"


def test_server_success_flag():
    flag_file = "/home/user/server_success.flag"
    assert os.path.isfile(flag_file), "server_success.flag was not created by a verified POST"
    with open(flag_file, "r") as f:
        content = f.read().strip()
    assert content == "SUCCESS", f"server_success.flag contains '{content}', expected 'SUCCESS'"


def test_scripts_exist():
    analyzer_cpp = "/home/user/analyzer.cpp"
    assert os.path.isfile(analyzer_cpp), f"C++ analyzer source missing: {analyzer_cpp}"
    submit_script = "/home/user/submit_metrics.sh"
    assert os.path.isfile(submit_script), f"Automation script missing: {submit_script}"
    assert os.access(submit_script, os.X_OK), f"Automation script is not executable: {submit_script}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
