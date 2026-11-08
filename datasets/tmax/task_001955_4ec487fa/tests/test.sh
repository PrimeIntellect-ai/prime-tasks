#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import socket
import subprocess
import tempfile
import threading
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

REPO = "/home/user/uptime_repo.git"
HOOK = os.path.join(REPO, "hooks/post-receive")
CONFIG_DIR = "/home/user/uptime_config"
ENDPOINTS = os.path.join(CONFIG_DIR, "endpoints.txt")
MONITOR = "/home/user/monitor_bin"
RESULTS = "/home/user/uptime_results.log"
CLIENT = "/home/user/uptime_client"
SRC = "/home/user/monitor_src"


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, text=True, capture_output=True, **kwargs)


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_original_final_state_and_git_history():
    assert os.path.isdir(REPO), f"Bare repository directory {REPO} does not exist."
    config_path = os.path.join(REPO, "config")
    assert os.path.isfile(config_path), f"Git config file not found in {REPO}."
    with open(config_path, "r") as f:
        assert "bare = true" in f.read().lower(), f"Repository at {REPO} is not a bare Git repository."
    assert run(["git", "--git-dir", REPO, "rev-parse", "--is-bare-repository"]).stdout.strip() == "true"

    assert os.path.isfile(HOOK), f"post-receive hook does not exist at {HOOK}."
    assert os.access(HOOK, os.X_OK), f"post-receive hook at {HOOK} is not executable."

    assert os.path.isdir(CONFIG_DIR), f"Configuration directory {CONFIG_DIR} does not exist."
    assert os.path.isfile(ENDPOINTS), f"endpoints.txt does not exist in {CONFIG_DIR}."
    with open(ENDPOINTS, "r") as f:
        content = f.read()
    assert "http://127.0.0.1:8080/health" in content, "endpoints.txt is missing the 8080 URL."
    assert "http://127.0.0.1:8081/health" in content, "endpoints.txt is missing the 8081 URL."

    assert os.path.isfile(MONITOR), f"Monitor binary does not exist at {MONITOR}."
    assert os.access(MONITOR, os.X_OK), f"Monitor binary at {MONITOR} is not executable."
    with open(MONITOR, "rb") as f:
        assert f.read(4) == b"\x7fELF", "monitor_bin is not a compiled ELF executable."

    assert os.path.isdir(SRC), f"Rust project directory {SRC} does not exist."
    assert os.path.isfile(os.path.join(SRC, "Cargo.toml")), "Rust project is missing Cargo.toml."
    assert os.path.isfile(os.path.join(SRC, "src", "main.rs")), "Rust project is missing src/main.rs."

    assert os.path.isfile(RESULTS), f"Results log file does not exist at {RESULTS}."
    lines = read_nonempty_lines(RESULTS)
    expected_8080 = "http://127.0.0.1:8080/health is UP"
    expected_8081 = "http://127.0.0.1:8081/health is DOWN"
    assert expected_8080 in lines, f"Expected '{expected_8080}' in {RESULTS}."
    assert expected_8081 in lines, f"Expected '{expected_8081}' in {RESULTS}."

    assert os.path.isdir(os.path.join(CLIENT, ".git")), f"Client clone {CLIENT} is missing."
    subjects = run(["git", "-C", CLIENT, "log", "--format=%s", "--all"]).stdout.splitlines()
    assert "Add endpoints" in subjects, "Client history does not contain the required 'Add endpoints' commit."
    original_tree = run(["git", "--git-dir", REPO, "show", "master:endpoints.txt"]).stdout
    assert "http://127.0.0.1:8080/health" in original_tree
    assert "http://127.0.0.1:8081/health" in original_tree


def test_monitor_and_post_receive_pipeline_are_functional():
    token = uuid.uuid4().hex
    requests_seen = []
    statuses = {
        f"/up-{token}": 200,
        f"/down-{token}": 503,
        f"/pipeline-up-{token}": 200,
        f"/pipeline-down-{token}": 418,
    }

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            requests_seen.append(self.path)
            code = statuses.get(self.path, 404)
            self.send_response(code)
            self.end_headers()
            self.wfile.write(b"test")

        def log_message(self, fmt, *args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    port = server.server_address[1]
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    dead_socket = socket.socket()
    dead_socket.bind(("127.0.0.1", 0))
    dead_port = dead_socket.getsockname()[1]
    dead_socket.close()

    try:
        # Exercise the submitted executable directly on unpredictable URLs and
        # derive expected answers from this verifier's server behavior.
        direct_urls = [
            f"http://127.0.0.1:{port}/up-{token}",
            f"http://127.0.0.1:{port}/down-{token}",
            f"http://127.0.0.1:{dead_port}/failed-{token}",
        ]
        os.makedirs(CONFIG_DIR, exist_ok=True)
        with open(ENDPOINTS, "w") as f:
            f.write("\n".join(direct_urls) + "\n")
        with open(RESULTS, "w"):
            pass

        subprocess.run([MONITOR], check=True, timeout=30)
        assert read_nonempty_lines(RESULTS) == [
            f"{direct_urls[0]} is UP",
            f"{direct_urls[1]} is DOWN",
            f"{direct_urls[2]} is DOWN",
        ]
        assert f"/up-{token}" in requests_seen, "Monitor did not issue the expected HTTP GET for the 200 endpoint."
        assert f"/down-{token}" in requests_seen, "Monitor did not issue the expected HTTP GET for the non-200 endpoint."

        # Push a new unpredictable configuration. A temporary wrapper records
        # that post-receive invokes the executable at the exact required path,
        # then delegates to the original compiled monitor.
        pipeline_urls = [
            f"http://127.0.0.1:{port}/pipeline-up-{token}",
            f"http://127.0.0.1:{port}/pipeline-down-{token}",
        ]
        pipeline_content = "\n".join(pipeline_urls) + "\n"

        run(["git", "-C", CLIENT, "checkout", "master"])
        run(["git", "-C", CLIENT, "config", "user.name", "Verifier"])
        run(["git", "-C", CLIENT, "config", "user.email", "verifier@example.invalid"])
        with open(os.path.join(CLIENT, "endpoints.txt"), "w") as f:
            f.write(pipeline_content)
        run(["git", "-C", CLIENT, "add", "endpoints.txt"])
        run(["git", "-C", CLIENT, "commit", "-m", f"Verifier pipeline test {token}"])

        marker = os.path.join(tempfile.gettempdir(), f"monitor-invoked-{token}")
        backup = os.path.join(tempfile.gettempdir(), f"monitor-bin-{token}")
        shutil.copy2(MONITOR, backup)
        try:
            with open(MONITOR, "w") as f:
                f.write("#!/bin/sh\n")
                f.write(f"printf invoked > '{marker}'\n")
                f.write(f"exec '{backup}' \"$@\"\n")
            os.chmod(MONITOR, 0o755)
            if os.path.exists(ENDPOINTS):
                os.unlink(ENDPOINTS)
            with open(RESULTS, "w"):
                pass
            run(["git", "-C", CLIENT, "push", "origin", "master"], timeout=45)
        finally:
            os.replace(backup, MONITOR)

        assert os.path.isfile(marker), "post-receive did not execute /home/user/monitor_bin."
        with open(ENDPOINTS, "r") as f:
            assert f.read() == pipeline_content, "post-receive did not check out the pushed master configuration."
        pushed_content = run(["git", "--git-dir", REPO, "show", "master:endpoints.txt"]).stdout
        assert pushed_content == pipeline_content, "Bare repository master does not contain the pushed configuration."
        assert read_nonempty_lines(RESULTS) == [
            f"{pipeline_urls[0]} is UP",
            f"{pipeline_urls[1]} is DOWN",
        ], "The push-triggered monitor results are incorrect."
        assert f"/pipeline-up-{token}" in requests_seen
        assert f"/pipeline-down-{token}" in requests_seen
        with open(MONITOR, "rb") as f:
            assert f.read(4) == b"\x7fELF", "Compiled monitor was not restored after pipeline test."
    finally:
        server.shutdown()
        server.server_close()

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
