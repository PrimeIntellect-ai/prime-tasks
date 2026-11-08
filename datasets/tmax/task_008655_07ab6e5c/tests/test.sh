#!/bin/bash
mkdir -p /logs/verifier

# Stop any service left by the agent's earlier run so the submitted script must
# start the service through rollout.sh during verification.
if [ -f /home/user/server.pid ]; then
    kill "$(cat /home/user/server.pid 2>/dev/null)" 2>/dev/null || true
fi
if [ -f /tmp/verifier_server.pid ]; then
    kill "$(cat /tmp/verifier_server.pid 2>/dev/null)" 2>/dev/null || true
fi
pkill -f '/home/user/mock_server.py' 2>/dev/null || true
pkill -f '/tmp/verifier_health_server.py' 2>/dev/null || true
sleep 1

cp -p /home/user/rollout.sh /tmp/original_rollout.sh

cat << 'SERVER_EOF' > /tmp/verifier_health_server.py
import http.server
import json
import os
import ssl

nonce = os.environ["VERIFY_NONCE"]
marker = "/tmp/https_request_" + nonce

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/api/status":
            with open(marker, "w", encoding="utf-8") as f:
                f.write("GET /api/status\n")
            body = json.dumps({"status": "healthy", "uptime": 3600}).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, fmt, *args):
        pass

server = http.server.HTTPServer(("127.0.0.1", 8443), Handler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain("/home/user/.certs/server.pem")
server.socket = context.wrap_socket(server.socket, server_side=True)
server.serve_forever()
SERVER_EOF

cat << 'ROLLOUT_EOF' > /home/user/rollout.sh
#!/bin/bash
if [ -z "$VERIFY_NONCE" ]; then
    echo "Missing verifier nonce."
    exit 1
fi
if [ ! -t 0 ]; then
    echo "rollout.sh must be controlled through a terminal."
    exit 70
fi
read -p "Target environment (dev/staging/prod): " env
read -p "Confirm staged rollout? [y/N]: " conf
printf '%s\n%s\nTTY\n' "$env" "$conf" > "/tmp/rollout_inputs_${VERIFY_NONCE}"
if [ "$env" != "staging" ]; then
    echo "Aborting: only staging is supported in this test."
    exit 1
fi
if [ "$conf" != "y" ]; then
    echo "Aborted."
    exit 1
fi
echo "Deploying..."
nohup python3 /tmp/verifier_health_server.py >/dev/null 2>&1 &
echo $! > /tmp/verifier_server.pid
sleep 2
echo "Rollout complete."
ROLLOUT_EOF
chmod +x /home/user/rollout.sh

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import secrets
import stat
import subprocess

SCRIPT_PATH = "/home/user/check_deploy.py"


def test_check_deploy_script_exists_and_uses_pexpect():
    assert os.path.exists(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist. Did you create it?"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    assert stat.S_ISREG(os.stat(SCRIPT_PATH).st_mode), f"{SCRIPT_PATH} is not a regular file."

    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT_PATH)

    module_aliases = set()
    spawn_aliases = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "pexpect":
                    module_aliases.add(alias.asname or "pexpect")
        elif isinstance(node, ast.ImportFrom) and node.module == "pexpect":
            for alias in node.names:
                if alias.name == "spawn":
                    spawn_aliases.add(alias.asname or "spawn")

    uses_spawn = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Attribute):
            if node.func.attr == "spawn" and isinstance(node.func.value, ast.Name):
                uses_spawn = node.func.value.id in module_aliases
        elif isinstance(node.func, ast.Name):
            uses_spawn = node.func.id in spawn_aliases
        if uses_spawn:
            break

    assert uses_spawn, "check_deploy.py must use pexpect.spawn for the interactive rollout."


def test_execute_submission_and_observe_rollout_and_https_request():
    nonce = secrets.token_hex(16)
    rollout_marker = f"/tmp/rollout_inputs_{nonce}"
    request_marker = f"/tmp/https_request_{nonce}"

    for path in ("/home/user/deploy_monitor.log", "/home/user/notify.eml", rollout_marker, request_marker):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env["VERIFY_NONCE"] = nonce
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=35,
    )
    assert result.returncode == 0, (
        f"check_deploy.py exited with {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    assert os.path.isfile(rollout_marker), "The verified rollout.sh was not executed."
    with open(rollout_marker, "r", encoding="utf-8") as f:
        assert f.read().splitlines() == ["staging", "y", "TTY"], (
            "rollout.sh did not receive staging and y through a terminal."
        )

    assert os.path.isfile(request_marker), (
        "No HTTPS GET request reached https://127.0.0.1:8443/api/status."
    )
    with open(request_marker, "r", encoding="utf-8") as f:
        assert f.read() == "GET /api/status\n"


def test_deploy_monitor_log_contents():
    log_path = "/home/user/deploy_monitor.log"
    assert os.path.exists(log_path), f"The log file {log_path} does not exist."
    assert os.path.isfile(log_path), f"{log_path} is not a file."

    expected_lines = [
        "ENV: staging",
        "ROLLOUT: confirmed",
        "HTTP_CODE: 200",
        "UPTIME_STATUS: healthy"
    ]

    with open(log_path, "r") as f:
        content = f.read().strip()

    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]
    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {log_path}, found {len(actual_lines)}."
    for i, (expected, actual) in enumerate(zip(expected_lines, actual_lines)):
        assert actual == expected, f"Line {i+1} in {log_path} is incorrect. Expected '{expected}', got '{actual}'."


def test_notify_eml_contents():
    eml_path = "/home/user/notify.eml"
    assert os.path.exists(eml_path), f"The email file {eml_path} does not exist."
    assert os.path.isfile(eml_path), f"{eml_path} is not a file."

    expected_content = (
        "From: sre@company.local\n"
        "To: admin@company.local\n"
        "Subject: Staging Rollout Status\n"
        "\n"
        "Deployment successful. Service is healthy."
    )

    with open(eml_path, "r") as f:
        content = f.read().strip()

    actual_lines = [line.strip() for line in content.splitlines()]
    expected_lines = [line.strip() for line in expected_content.splitlines()]
    assert actual_lines == expected_lines, f"The contents of {eml_path} do not match the expected email format."
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
result=$?

if [ -f /tmp/verifier_server.pid ]; then
    kill "$(cat /tmp/verifier_server.pid 2>/dev/null)" 2>/dev/null || true
fi
cp -p /tmp/original_rollout.sh /home/user/rollout.sh 2>/dev/null || true

if [ "$result" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
