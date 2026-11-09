#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import signal
import socket
import stat
import subprocess
import time

BASE = "/home/user/ws_api_test"


def test_00_files_exist():
    """Verify that all required implementation files have been created."""
    required_files = [
        f"{BASE}/server.js",
        f"{BASE}/test.py",
        f"{BASE}/run_tests.sh",
    ]
    for file_path in required_files:
        assert os.path.isfile(file_path), f"Required file missing: {file_path}"


def test_01_runner_executable():
    """Verify that the bash runner script is executable."""
    runner_path = f"{BASE}/run_tests.sh"
    assert os.path.isfile(runner_path), f"Runner script missing: {runner_path}"
    st = os.stat(runner_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Runner script is not executable: {runner_path}"


def test_02_implementation_uses_required_tools():
    """Inspect the submitted implementations for the required languages and libraries."""
    server_path = f"{BASE}/server.js"
    client_path = f"{BASE}/test.py"
    runner_path = f"{BASE}/run_tests.sh"

    server = open(server_path, encoding="utf-8").read()
    assert re.search(r"(?:require\s*\(\s*['\"]ws['\"]|from\s+['\"]ws['\"])", server), \
        "server.js must use the ws package"
    assert re.search(r"(?:require\s*\(\s*['\"]semver['\"]|from\s+['\"]semver['\"])", server), \
        "server.js must use the semver package"

    client_source = open(client_path, encoding="utf-8").read()
    tree = ast.parse(client_source, filename=client_path)
    imported = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported.update(alias.name.split('.')[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imported.add(node.module.split('.')[0])
    assert "websockets" in imported, "test.py must import and use the websockets library"
    assert imported.intersection({"random", "secrets", "hypothesis"}), \
        "test.py must use a random/property-based test-case generator"

    runner = open(runner_path, encoding="utf-8").read()
    subprocess.run(["bash", "-n", runner_path], check=True)
    assert re.search(r"npm\s+(?:install|i)\b[^\n]*(?:\bws\b[^\n]*\bsemver\b|\bsemver\b[^\n]*\bws\b)", runner), \
        "run_tests.sh must install ws and semver"
    assert re.search(r"(?:python3?|[^\s/]+/python)\s+-m\s+venv|python3?-m\s+venv", runner), \
        "run_tests.sh must create a Python virtual environment"
    assert "websockets" in runner and ("packaging" in runner or "semver" in runner), \
        "run_tests.sh must install the required Python packages"
    assert re.search(r"(?:node\s+[^\n]*server\.js|server\.js[^\n]*&)", runner), \
        "run_tests.sh must start server.js"
    assert re.search(r"(?:python3?|python|[^\s/]+/python)\s+[^\n]*test\.py", runner), \
        "run_tests.sh must execute test.py"
    assert re.search(r"\b(?:kill|trap)\b", runner), \
        "run_tests.sh must clean up the background server"


def test_03_execute_runner():
    """Run the submitted orchestration script and require it to create a new report."""
    report = f"{BASE}/test_report.log"
    if os.path.exists(report):
        os.remove(report)

    # Do not let a server left behind by the agent make a broken runner appear to work.
    subprocess.run(["pkill", "-f", f"node.*{BASE}/server.js"], check=False)
    subprocess.run(["pkill", "-f", "node.*server.js"], check=False)
    time.sleep(0.3)

    result = subprocess.run(
        [f"{BASE}/run_tests.sh"],
        cwd=BASE,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=300,
    )
    assert result.returncode == 0, f"run_tests.sh failed:\n{result.stdout[-5000:]}"
    assert os.path.isfile(report), "run_tests.sh did not generate test_report.log"
    assert os.path.getsize(report) > 0, "run_tests.sh generated an empty test_report.log"

    time.sleep(0.3)
    leftover = subprocess.run(
        ["pgrep", "-f", f"node.*{BASE}/server.js"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    assert leftover.returncode != 0, "run_tests.sh left its Node.js server running"


def is_valid_semver(v):
    pattern = r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-zA-Z0-9-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-zA-Z0-9-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$'
    return re.match(pattern, v) is not None


def is_greater_than_2_0_0(v):
    try:
        from packaging.version import Version, InvalidVersion
        try:
            return Version(v) > Version("2.0.0")
        except InvalidVersion:
            return None
    except ImportError:
        match = re.match(r'^(\d+)\.(\d+)\.(\d+)', v)
        if not match:
            return None
        major, minor, patch = map(int, match.groups())
        if major > 2:
            return True
        if major == 2 and minor > 0:
            return True
        if major == 2 and minor == 0 and patch > 0:
            return True
        return False


def test_04_log_correctness():
    """Verify that the newly generated report has exactly 13 correctly classified entries."""
    log_path = f"{BASE}/test_report.log"
    assert os.path.isfile(log_path), f"Required file missing: {log_path}"

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 13, f"Expected exactly 13 test cases in log, found {len(lines)}"

    success_count = 0
    rejected_count = 0
    error_count = 0

    for line in lines:
        parts = line.split(',')
        assert len(parts) == 2, f"Invalid log format (expected 'version,status'): {line}"

        version, status = parts[0], parts[1]
        is_valid = is_valid_semver(version)

        if status == "success":
            success_count += 1
            assert is_valid, f"Expected valid semver > 2.0.0 for success, got invalid: {version}"
            gt_2 = is_greater_than_2_0_0(version)
            assert gt_2 is not False, f"Version {version} is not > 2.0.0 but got 'success'"
        elif status == "rejected":
            rejected_count += 1
            assert is_valid, f"Expected valid semver <= 2.0.0 for rejected, got invalid: {version}"
            gt_2 = is_greater_than_2_0_0(version)
            assert gt_2 is not True, f"Version {version} is > 2.0.0 but got 'rejected'"
        elif status == "error":
            error_count += 1
            assert not is_valid, f"Expected invalid semver for 'error', got valid: {version}"
        else:
            assert False, f"Unknown status '{status}' in log for version {version}"

    assert success_count == 5, f"Expected 5 'success' entries, found {success_count}"
    assert rejected_count == 5, f"Expected 5 'rejected' entries, found {rejected_count}"
    assert error_count == 3, f"Expected 3 'error' entries, found {error_count}"


def test_05_server_live_behavior():
    """Start the submitted server and independently exercise hidden semantic-version cases."""
    probe_path = "/tmp/ws_hidden_probe.js"
    probe = r'''
const WebSocket = require('/home/user/ws_api_test/node_modules/ws');

const cases = [
  [{action: 'update', version: '2.0.1'}, 'success'],
  [{action: 'update', version: '2.0.1-alpha.7'}, 'success'],
  [{action: 'update', version: '7.4.3+build.19'}, 'success'],
  [{action: 'update', version: '2.0.0'}, 'rejected'],
  [{action: 'update', version: '2.0.0-rc.1'}, 'rejected'],
  [{action: 'update', version: '0.0.0'}, 'rejected'],
  [{action: 'update', version: '01.2.3'}, 'error'],
  [{action: 'update', version: '2.0.0.1'}, 'error'],
  [{action: 'update', version: 'not-a-version'}, 'error'],
  [{action: 'update', version: 2001}, 'error'],
  [{action: 'update'}, 'error']
];

function connect() {
  return new Promise((resolve, reject) => {
    let attempts = 0;
    const tryOnce = () => {
      const ws = new WebSocket('ws://localhost:8765');
      ws.once('open', () => resolve(ws));
      ws.once('error', err => {
        ws.close();
        if (++attempts < 30) setTimeout(tryOnce, 100);
        else reject(err);
      });
    };
    tryOnce();
  });
}

function exchange(ws, payload) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('response timeout')), 3000);
    ws.once('message', data => {
      clearTimeout(timer);
      try { resolve(JSON.parse(data.toString())); } catch (e) { reject(e); }
    });
    ws.send(JSON.stringify(payload));
  });
}

(async () => {
  const ws = await connect();
  for (const [payload, expected] of cases) {
    const answer = await exchange(ws, payload);
    if (!answer || Object.keys(answer).length !== 1 || answer.status !== expected) {
      throw new Error(`For ${JSON.stringify(payload)}, expected ${expected}, got ${JSON.stringify(answer)}`);
    }
  }
  ws.close();
})().catch(err => { console.error(err.stack || err); process.exit(1); });
'''
    with open(probe_path, "w", encoding="utf-8") as f:
        f.write(probe)

    server = subprocess.Popen(
        ["node", f"{BASE}/server.js"],
        cwd=BASE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        start_new_session=True,
    )
    try:
        result = subprocess.run(
            ["node", probe_path],
            cwd=BASE,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=20,
        )
        server_output = ""
        if server.poll() is not None and server.stdout:
            server_output = server.stdout.read()
        assert result.returncode == 0, \
            f"server failed independent WebSocket checks:\n{result.stdout}\n{server_output}"
        assert server.poll() is None, "server exited while handling the hidden requests"
    finally:
        if server.poll() is None:
            os.killpg(server.pid, signal.SIGTERM)
            try:
                server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(server.pid, signal.SIGKILL)
                server.wait(timeout=5)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
