#!/bin/bash
set +e
mkdir -p /logs/verifier

backup="/tmp/start_legacy_vm.sh.verifier.$$"
marker="/tmp/legacy_vm_started.verifier.$$"

cleanup() {
    if [ -e "$backup" ]; then
        cp -a "$backup" /app/start_legacy_vm.sh >/dev/null 2>&1 || true
        rm -f "$backup"
    fi
    rm -f "$marker"
}

run_verification() {
    [ -f /home/user/run_stack.sh ] || return 1
    [ -x /home/user/run_stack.sh ] || return 1
    [ -f /app/start_legacy_vm.sh ] || return 1

    # Stop any pre-existing implementations so the submitted integration script
    # must actually bring up the complete stack during verification.
    python3 - <<'PY' || return 1
import os, signal, time

ports = {8000, 8001, 9090}

def listener_inodes():
    result = set()
    for path in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(path) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == '0A':
                        port = int(fields[1].split(':')[1], 16)
                        if port in ports:
                            result.add(fields[9])
        except FileNotFoundError:
            pass
    return result

def owners(inodes):
    found = set()
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        fd_dir = f'/proc/{entry}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f'{fd_dir}/{fd}')
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    found.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            pass
    return found

for sig in (signal.SIGTERM, signal.SIGKILL):
    pids = owners(listener_inodes())
    if not pids:
        break
    for pid in pids:
        try:
            os.kill(pid, sig)
        except ProcessLookupError:
            pass
    time.sleep(1)
if listener_inodes():
    raise SystemExit('Could not clear required listening ports')
PY

    # Instrument the required legacy launcher with a fresh runtime marker. The
    # wrapper executes the unmodified launcher after recording invocation.
    cp -a /app/start_legacy_vm.sh "$backup" || return 1
    rm -f "$marker"
    cat > /app/start_legacy_vm.sh <<EOF
#!/bin/bash
printf 'invoked\n' > '$marker'
exec '$backup' "\$@"
EOF
    chmod 755 /app/start_legacy_vm.sh || return 1

    timeout --kill-after=5s 120s runuser -u user -- env \
        HOME=/home/user USER=user LOGNAME=user \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        /home/user/run_stack.sh || return 1

    [ -s "$marker" ] || return 1

    # The requested copied Rust project must exist and compile as the user.
    [ -f /home/user/router/Cargo.toml ] || return 1
    [ -f /home/user/router/src/main.rs ] || return 1
    timeout --kill-after=5s 120s runuser -u user -- env \
        HOME=/home/user USER=user LOGNAME=user \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        cargo build --manifest-path /home/user/router/Cargo.toml || return 1

    cat > /tmp/test_final_state.py <<'TEST_EOF'
import hashlib
import os
import secrets
import signal
import socket
import stat
import threading
import time

import requests

USER_UID = os.stat('/home/user').st_uid


def listener_pids(port):
    inodes = set()
    for path in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(path) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if (len(fields) > 9 and fields[3] == '0A' and
                            int(fields[1].split(':')[1], 16) == port):
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        try:
            for fd in os.listdir(f'/proc/{entry}/fd'):
                try:
                    target = os.readlink(f'/proc/{entry}/fd/{fd}')
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    pids.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            pass
    return pids


def proc_uid(pid):
    with open(f'/proc/{pid}/status') as f:
        for line in f:
            if line.startswith('Uid:'):
                return int(line.split()[1])
    raise AssertionError(f'No UID for process {pid}')


def file_hash(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(131072), b''):
            h.update(chunk)
    return h.digest()


def recv_line(sock):
    data = bytearray()
    while not data.endswith(b'\n'):
        chunk = sock.recv(1)
        if not chunk:
            break
        data.extend(chunk)
    return bytes(data)


def test_run_stack_script_exists_and_executable():
    script_path = '/home/user/run_stack.sh'
    assert os.path.isfile(script_path), f'Missing script: {script_path}'
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f'Script is not executable: {script_path}'


def test_stack_processes_are_live_non_root_and_router_is_built_rust_artifact():
    p8000 = listener_pids(8000)
    p8001 = listener_pids(8001)
    p9090 = listener_pids(9090)
    assert len(p8000) == 1, f'Expected one HTTP listener, found {p8000}'
    assert len(p8001) == 1, f'Expected one proxy listener, found {p8001}'
    assert len(p9090) >= 1, 'Legacy service is not listening on port 9090'
    assert p8000 == p8001, 'HTTP and TCP services are not the submitted router process'

    router_pid = next(iter(p8000))
    assert proc_uid(router_pid) == USER_UID, 'Router is not running as user'
    assert all(proc_uid(pid) == USER_UID for pid in p9090), 'Legacy service is running as root'

    with open(f'/proc/{router_pid}/environ', 'rb') as f:
        env = dict(item.split(b'=', 1) for item in f.read().split(b'\0') if b'=' in item)
    assert env.get(b'TZ') == b'Asia/Tokyo', f'Router TZ is {env.get(b"TZ")!r}'
    assert env.get(b'LANG') == b'C.UTF-8', f'Router LANG is {env.get(b"LANG")!r}'

    running_exe = f'/proc/{router_pid}/exe'
    with open(running_exe, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'Router process is not a compiled executable'
    candidates = [
        '/home/user/router/target/debug/router',
        '/home/user/router/target/release/router',
    ]
    candidate_hashes = [file_hash(p) for p in candidates if os.path.isfile(p)]
    assert candidate_hashes, 'Cargo did not produce a router binary'
    assert file_hash(running_exe) in candidate_hashes, 'Listening process is not a binary built from the submitted Rust project'


def test_http_info_endpoint():
    url = 'http://127.0.0.1:8000/info'
    try:
        response = requests.get(url, timeout=2)
    except requests.exceptions.RequestException as e:
        assert False, f'Failed to connect to HTTP service at {url}: {e}'

    assert response.status_code == 200, f'Expected HTTP 200 OK, got {response.status_code}'

    try:
        data = response.json()
    except ValueError:
        assert False, f'Response is not valid JSON: {response.text}'

    expected_tz = 'Asia/Tokyo'
    expected_target = '127.0.0.1:9090'
    assert data.get('tz') == expected_tz, f"Expected tz '{expected_tz}', got '{data.get('tz')}'"
    assert data.get('legacy_target') == expected_target, f"Expected legacy_target '{expected_target}', got '{data.get('legacy_target')}'"


def test_tcp_proxy_auth_success():
    host = '127.0.0.1'
    port = 8001
    try:
        s = socket.create_connection((host, port), timeout=2)
    except Exception as e:
        assert False, f'Failed to connect to TCP proxy at {host}:{port}: {e}'

    try:
        s.sendall(b'AUTH: v2migrate\nHelloLegacy\n')
        response = s.recv(1024)
    except Exception as e:
        s.close()
        assert False, f'Error communicating with TCP proxy: {e}'
    s.close()

    response_str = response.decode('utf-8', errors='replace')
    assert 'LEGACY_OS_ACK: HelloLegacy' in response_str, f"Expected 'LEGACY_OS_ACK: HelloLegacy' in response, got: '{response_str}'"


def test_tcp_proxy_auth_failure():
    host = '127.0.0.1'
    port = 8001
    try:
        s = socket.create_connection((host, port), timeout=2)
    except Exception as e:
        assert False, f'Failed to connect to TCP proxy at {host}:{port}: {e}'

    try:
        s.sendall(b'AUTH: badtoken\nHello\n')
        response = s.recv(1024)
    except Exception:
        response = b''
    s.close()
    assert response == b'', f'Expected connection to be dropped with no response, but got: {response}'


def test_dynamic_bidirectional_proxy_and_auth_stripping():
    # Replace the predictable mock backend only after preserving the original
    # fixed live-service assertion above. Its random challenge cannot be
    # precomputed or hardcoded by the submission.
    old_pids = listener_pids(9090)
    for pid in old_pids:
        os.kill(pid, signal.SIGTERM)
    deadline = time.time() + 3
    while listener_pids(9090) and time.time() < deadline:
        time.sleep(0.05)
    for pid in listener_pids(9090):
        os.kill(pid, signal.SIGKILL)
    time.sleep(0.1)

    secret = secrets.token_bytes(32)
    banner = b'VM-BANNER-' + secrets.token_hex(18).encode() + b'\n'
    payload = b'probe-' + secrets.token_hex(40).encode() + b'\n'
    ready = threading.Event()
    failure = []

    def backend():
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as srv:
                srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                srv.bind(('127.0.0.1', 9090))
                srv.listen(1)
                ready.set()
                srv.settimeout(5)
                conn, _ = srv.accept()
                with conn:
                    conn.settimeout(5)
                    conn.sendall(banner[:7])
                    time.sleep(0.03)
                    conn.sendall(banner[7:])
                    received = recv_line(conn)
                    digest = hashlib.sha256(secret + received).hexdigest().encode()
                    conn.sendall(b'RESULT:' + digest + b'\n')
        except Exception as exc:
            failure.append(repr(exc))
            ready.set()

    thread = threading.Thread(target=backend, daemon=True)
    thread.start()
    assert ready.wait(2), 'Dynamic backend did not start'
    assert not failure, failure

    with socket.create_connection(('127.0.0.1', 8001), timeout=3) as client:
        client.settimeout(3)
        # Fragment the authentication line to require proper first-line parsing.
        client.sendall(b'AUTH: v2')
        time.sleep(0.02)
        client.sendall(b'migrate\n')
        assert recv_line(client) == banner, 'Unsolicited backend bytes were not proxied to the client'
        client.sendall(payload[:11])
        time.sleep(0.02)
        client.sendall(payload[11:])
        response = recv_line(client)

    thread.join(3)
    assert not thread.is_alive(), 'Dynamic backend did not receive proxied client data'
    assert not failure, failure
    expected = b'RESULT:' + hashlib.sha256(secret + payload).hexdigest().encode() + b'\n'
    assert response == expected, f'Proxy did not relay the randomized backend response: {response!r}'


def test_randomized_invalid_auth_is_dropped_without_backend_contact():
    bad = b'AUTH: ' + secrets.token_hex(20).encode() + b'\n'
    with socket.create_connection(('127.0.0.1', 8001), timeout=2) as s:
        s.settimeout(2)
        s.sendall(bad + b'should-not-pass\n')
        try:
            response = s.recv(1024)
        except (ConnectionResetError, socket.timeout):
            response = b''
    assert response == b'', f'Invalid randomized authentication produced data: {response!r}'
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
}

if run_verification; then
    result=1
else
    result=0
fi
cleanup
echo "$result" > /logs/verifier/reward.txt
exit 0
