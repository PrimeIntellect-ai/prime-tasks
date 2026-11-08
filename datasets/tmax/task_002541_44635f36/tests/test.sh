#!/bin/bash
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

WORKDIR=$(mktemp -d /tmp/task-verifier.XXXXXX) || exit 1
chmod 700 "$WORKDIR"
MAIN_PID=""
DECOY_PID=""
cleanup() {
    [ -n "$DECOY_PID" ] && kill "$DECOY_PID" 2>/dev/null || true
    [ -n "$MAIN_PID" ] && kill "$MAIN_PID" 2>/dev/null || true
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

# Stop any copy of the setup service left running by the agent. The verifier
# supplies its own instrumented service so it can prove that test_auth.sh sent
# the required request.
USER_UID=$(id -u user)
for pid in $(ps -eo pid=,uid= | awk -v uid="$USER_UID" '$2 == uid {print $1}'); do
    kill -KILL "$pid" 2>/dev/null || true
done
sleep 0.2

cat > "$WORKDIR/auth_server.py" <<'PY_EOF'
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os

marker = os.environ['AUTH_MARKER']
expected = b'{"username": "admin", "password": "password123"}'

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        try:
            length = int(self.headers.get('Content-Length', '-1'))
        except ValueError:
            length = -1
        body = self.rfile.read(length) if length >= 0 else b''
        content_type = self.headers.get('Content-Type', '').strip().lower()
        valid = self.path == '/admin' and content_type == 'application/json' and body == expected
        self.send_response(200 if valid else 401)
        self.end_headers()
        if valid:
            with open(marker, 'w', encoding='utf-8') as f:
                f.write('valid-request-received\n')
    def log_message(self, fmt, *args):
        pass

ThreadingHTTPServer(('127.0.0.1', 8065), Handler).serve_forever()
PY_EOF

AUTH_MARKER="$WORKDIR/auth_request.marker" python3 "$WORKDIR/auth_server.py" >"$WORKDIR/auth_server.log" 2>&1 &
MAIN_PID=$!
for _ in $(seq 1 50); do
    kill -0 "$MAIN_PID" 2>/dev/null || exit 1
    nc -z 127.0.0.1 8065 2>/dev/null && break
    sleep 0.1
done
nc -z 127.0.0.1 8065 2>/dev/null || exit 1

# Add a temporary second listener at an unpredictable port. A real scanner must
# find both it and the rogue service; a script that merely echoes 8065 will fail.
DECOY_PORT=$(python3 - <<'PY_EOF'
import random, socket
ports = [p for p in range(8000, 8101) if p != 8065]
random.SystemRandom().shuffle(ports)
for port in ports:
    s = socket.socket()
    try:
        s.bind(('127.0.0.1', port))
    except OSError:
        s.close()
        continue
    s.close()
    print(port)
    break
else:
    raise SystemExit(1)
PY_EOF
) || exit 1
python3 -m http.server "$DECOY_PORT" --bind 127.0.0.1 >"$WORKDIR/decoy.log" 2>&1 &
DECOY_PID=$!
for _ in $(seq 1 50); do
    kill -0 "$DECOY_PID" 2>/dev/null || exit 1
    nc -z 127.0.0.1 "$DECOY_PORT" 2>/dev/null && break
    sleep 0.1
done
nc -z 127.0.0.1 "$DECOY_PORT" 2>/dev/null || exit 1
printf '%s\n' "$DECOY_PORT" > "$WORKDIR/decoy_port"

for script in /home/user/audit_ports.sh /home/user/test_auth.sh /home/user/block_ip.sh; do
    [ -f "$script" ] || exit 1
    bash -n "$script" || exit 1
done

rm -f /home/user/active_ports.log
if ! timeout 30s runuser -u user -- bash /home/user/audit_ports.sh; then
    exit 1
fi

# The decoy was only for auditing. Leave the actual rogue service as the sole
# active target before exercising the authentication script.
kill "$DECOY_PID" 2>/dev/null || true
wait "$DECOY_PID" 2>/dev/null || true
DECOY_PID=""

rm -f /home/user/auth_status.txt "$WORKDIR/auth_request.marker"
if ! timeout 30s runuser -u user -- bash /home/user/test_auth.sh; then
    exit 1
fi

# Reset the ACL, then execute the submitted remediation script rather than
# trusting state that may have been fabricated before verification.
printf 'allow all\n' > /home/user/app/acl.conf
chown user:user /home/user/app/acl.conf
chmod 644 /home/user/app/acl.conf
if ! timeout 30s runuser -u user -- bash /home/user/block_ip.sh; then
    exit 1
fi

cat > "$WORKDIR/test_final_state.py" <<'PY_EOF'
import hashlib
import os
import re
import stat

WORKDIR = os.environ['VERIFIER_WORKDIR']


def assert_regular_script(path):
    assert os.path.isfile(path), f"Script {path} does not exist."
    mode = os.lstat(path).st_mode
    assert stat.S_ISREG(mode), f"Script {path} is not a regular file."


def test_task1_audit_ports():
    script_path = '/home/user/audit_ports.sh'
    log_path = '/home/user/active_ports.log'

    assert_regular_script(script_path)
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."

    with open(log_path, 'r', encoding='utf-8') as f:
        content = f.read().strip()

    assert '8065' in content, f"Expected port 8065 in {log_path}, but found: {content}"
    lines = content.splitlines() if content else []
    assert all(re.fullmatch(r'[0-9]+', line) for line in lines), \
        f"{log_path} must contain only one numeric port per line: {content!r}"
    with open(os.path.join(WORKDIR, 'decoy_port'), encoding='utf-8') as f:
        decoy = f.read().strip()
    assert len(lines) == len(set(lines)), f"Duplicate ports found in {log_path}: {lines}"
    assert set(lines) == {'8065', decoy}, \
        f"Scanner did not report exactly the active test ports: expected 8065 and {decoy}, found {lines}"


def test_task2_file_integrity():
    log_path = '/home/user/modified_files.txt'
    baseline_path = '/home/user/baseline.sha256'

    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."
    assert os.path.isfile(baseline_path), f"Baseline {baseline_path} does not exist."

    with open(log_path, 'r', encoding='utf-8') as f:
        content = f.read().strip()

    assert 'app/public/app.js' in content or '/home/user/app/public/app.js' in content, \
        f"Expected modified file path (app.js) in {log_path}, but found: {content}"

    expected = []
    with open(baseline_path, 'r', encoding='utf-8') as f:
        for raw_line in f:
            raw_line = raw_line.rstrip('\n')
            if not raw_line:
                continue
            parts = raw_line.split(None, 1)
            assert len(parts) == 2 and re.fullmatch(r'[0-9a-fA-F]{64}', parts[0]), \
                f"Malformed baseline line: {raw_line!r}"
            recorded, name = parts
            name = name.lstrip('*')
            path = name if os.path.isabs(name) else os.path.join('/home/user', name)
            path = os.path.abspath(path)
            try:
                with open(path, 'rb') as target:
                    actual = hashlib.sha256(target.read()).hexdigest()
            except OSError:
                actual = None
            if actual != recorded.lower():
                expected.append(path)

    actual_lines = content.splitlines() if content else []
    assert all(os.path.isabs(line) for line in actual_lines), \
        f"Every modified-file entry must be an absolute path: {actual_lines}"
    assert len(actual_lines) == len(set(actual_lines)), \
        f"Duplicate entries found in {log_path}: {actual_lines}"
    assert set(actual_lines) == set(expected), \
        f"Integrity results do not match the supplied baseline: expected {expected}, found {actual_lines}"


def test_task3_auth_flow():
    script_path = '/home/user/test_auth.sh'
    log_path = '/home/user/auth_status.txt'

    assert_regular_script(script_path)
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."

    with open(script_path, 'r', encoding='utf-8', errors='replace') as f:
        script = f.read()
    assert re.search(r'(?<![A-Za-z0-9_])curl(?![A-Za-z0-9_])', script), \
        f"{script_path} must use curl as instructed."

    with open(log_path, 'r', encoding='utf-8') as f:
        content = f.read().strip()

    assert '200' == content, f"Expected HTTP status 200 in {log_path}, but found: {content}"
    marker = os.path.join(WORKDIR, 'auth_request.marker')
    assert os.path.isfile(marker), \
        "The executed authentication script did not send the required POST request to the service."


def test_task4_network_policy():
    script_path = '/home/user/block_ip.sh'
    acl_path = '/home/user/app/acl.conf'

    assert_regular_script(script_path)
    assert os.path.isfile(acl_path), f"ACL file {acl_path} does not exist."

    with open(acl_path, 'r', encoding='utf-8') as f:
        lines = f.read().strip().split('\n')

    assert len(lines) > 0, f"ACL file {acl_path} is empty."
    assert lines[-1].strip() == 'deny 10.10.50.15', \
        f"Expected the last line of {acl_path} to be 'deny 10.10.50.15', but found: '{lines[-1]}'"
    assert lines == ['allow all', 'deny 10.10.50.15'], \
        f"The executed script must append exactly one deny rule, but found: {lines}"

    st = os.stat(acl_path)
    permissions = stat.S_IMODE(st.st_mode)
    assert permissions == 0o444, \
        f"Expected permissions 444 for {acl_path}, but found {oct(permissions)}"
PY_EOF

if VERIFIER_WORKDIR="$WORKDIR" python3 -m pytest "$WORKDIR/test_final_state.py" -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
