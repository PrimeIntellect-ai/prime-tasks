#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import queue
import secrets
import signal
import socket
import subprocess
import time

import pytest
import requests


def _tcp_rows():
    rows = []
    with open('/proc/net/tcp', 'r') as f:
        next(f)
        for line in f:
            fields = line.split()
            local_ip, local_port = fields[1].split(':')
            remote_ip, remote_port = fields[2].split(':')
            rows.append({
                'local_ip': local_ip,
                'local_port': int(local_port, 16),
                'remote_ip': remote_ip,
                'remote_port': int(remote_port, 16),
                'state': fields[3],
                'inode': fields[9],
            })
    return rows


def _inode_owners(inode):
    owners = set()
    needle = 'socket:[%s]' % inode
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        fd_dir = '/proc/%s/fd' % name
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(os.path.join(fd_dir, fd)) == needle:
                        owners.add(int(name))
                        break
                except OSError:
                    pass
        except OSError:
            pass
    return owners


def _listener(port):
    for row in _tcp_rows():
        if row['state'] == '0A' and row['local_port'] == port:
            return row, _inode_owners(row['inode'])
    return None, set()


def _wait_for_port(port, present=True, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        row, owners = _listener(port)
        if bool(row) == present:
            return row, owners
        time.sleep(0.05)
    return _listener(port)


def _cmdline(pid):
    try:
        with open('/proc/%d/cmdline' % pid, 'rb') as f:
            return f.read().replace(b'\0', b' ').decode(errors='replace')
    except OSError:
        return ''


def test_api_gateway_processes_large_integers_correctly():
    """
    Retains the original end-to-end assertion for the originally tested value.
    """
    url = "http://127.0.0.1:8080/process"
    large_tx_id = 12345678901234567
    payload = {"tx_id": large_tx_id, "amount": 100.0}

    try:
        response = requests.post(url, json=payload, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("Failed to connect to the API Gateway on 127.0.0.1:8080. Are the services running?")
    except requests.exceptions.Timeout:
        pytest.fail("Request to API Gateway timed out. The services might be deadlocked or crashed.")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response, but got: {response.text}")

    assert data.get("status") == "success", f"Expected status 'success', got {data.get('status')}"
    assert "processed_id" in data, "Response JSON is missing 'processed_id' field"
    assert data["processed_id"] == large_tx_id, (
        f"Precision loss or corruption detected. Expected processed_id {large_tx_id}, "
        f"but got {data['processed_id']}."
    )


def test_worker_contains_type_assertion():
    """Retains the original source assertion check."""
    worker_path = "/app/src/worker.py"
    assert os.path.isfile(worker_path), f"File not found: {worker_path}"
    with open(worker_path, "r") as f:
        content = f.read()

    has_assertion = "assert type(" in content and "is int" in content
    has_isinstance = "assert isinstance(" in content and "int" in content
    assert has_assertion or has_isinstance, (
        "worker.py is missing the required strict assertion to validate that the "
        "deserialized transaction ID is exactly of type int."
    )


def test_all_three_services_are_listening_on_required_interfaces():
    expected = {7070: '/app/src/db.py', 9090: '/app/src/worker.py', 8080: '/app/src/gateway.py'}
    seen = set()
    for port, script in expected.items():
        row, owners = _listener(port)
        assert row is not None, f"No service is listening on TCP port {port}"
        assert row['local_ip'] == '0100007F', f"Port {port} is not bound to 127.0.0.1"
        matching = {pid for pid in owners if script in _cmdline(pid)}
        assert matching, f"The expected service {script} does not own listening port {port}"
        seen.update(matching)
    assert len(seen) == 3, "Database, worker, and gateway must be three running services"


def _statement_lists(node):
    for field in ('body', 'orelse', 'finalbody'):
        value = getattr(node, field, None)
        if isinstance(value, list):
            yield value
            for statement in value:
                yield from _statement_lists(statement)
    handlers = getattr(node, 'handlers', None)
    if handlers:
        for handler in handlers:
            yield handler.body
            for statement in handler.body:
                yield from _statement_lists(statement)


def _assigned_names(target):
    if isinstance(target, ast.Name):
        return [target.id]
    if isinstance(target, (ast.Tuple, ast.List)):
        result = []
        for item in target.elts:
            result.extend(_assigned_names(item))
        return result
    return []


def _contains_unpack(node):
    for child in ast.walk(node):
        if isinstance(child, ast.Call) and isinstance(child.func, ast.Attribute):
            if isinstance(child.func.value, ast.Name) and child.func.value.id == 'struct' and child.func.attr == 'unpack':
                return True
    return False


def _is_exact_type_assert(node, variable):
    for child in ast.walk(node.test):
        if not isinstance(child, ast.Compare) or len(child.ops) != 1:
            continue
        left = child.left
        right = child.comparators[0]
        if (isinstance(child.ops[0], ast.Is) and isinstance(left, ast.Call)
                and isinstance(left.func, ast.Name) and left.func.id == 'type'
                and len(left.args) == 1 and isinstance(left.args[0], ast.Name)
                and left.args[0].id == variable and isinstance(right, ast.Name)
                and right.id == 'int'):
            return True
    return False


def _assertions_accept(assertions, variable, value):
    env = {'type': type, 'int': int, variable: value}
    try:
        for assertion in assertions:
            expression = ast.Expression(body=assertion.test)
            ast.fix_missing_locations(expression)
            if not bool(eval(compile(expression, '<worker assertion>', 'eval'), {'__builtins__': {}}, env)):
                return False
        return True
    except Exception:
        return False


def test_worker_has_immediate_strict_type_and_64_bit_bound_assertions():
    path = '/app/src/worker.py'
    with open(path, 'r') as f:
        tree = ast.parse(f.read(), filename=path)

    candidates = []
    for statements in _statement_lists(tree):
        for index, statement in enumerate(statements):
            if not isinstance(statement, (ast.Assign, ast.AnnAssign)) or not _contains_unpack(statement):
                continue
            targets = statement.targets if isinstance(statement, ast.Assign) else [statement.target]
            names = []
            for target in targets:
                names.extend(_assigned_names(target))
            following = []
            for later in statements[index + 1:]:
                if isinstance(later, ast.Assert):
                    following.append(later)
                else:
                    break
            for name in names:
                candidates.append((name, following))

    assert candidates, "worker.py must deserialize the transaction ID with struct.unpack"
    for variable, assertions in candidates:
        if not assertions or not any(_is_exact_type_assert(a, variable) for a in assertions):
            continue
        bound_assertions = [a for a in assertions if not _is_exact_type_assert(a, variable)]
        if not bound_assertions:
            continue
        references_variable = any(
            isinstance(n, ast.Name) and n.id == variable
            for assertion in bound_assertions for n in ast.walk(assertion.test)
        )
        has_comparison = any(
            isinstance(n, ast.Compare)
            for assertion in bound_assertions for n in ast.walk(assertion.test)
        )
        if not (references_variable and has_comparison):
            continue

        signed64 = (
            _assertions_accept(assertions, variable, -(1 << 63))
            and _assertions_accept(assertions, variable, (1 << 63) - 1)
            and not _assertions_accept(assertions, variable, -(1 << 63) - 1)
            and not _assertions_accept(assertions, variable, 1 << 63)
        )
        unsigned64 = (
            _assertions_accept(assertions, variable, 0)
            and _assertions_accept(assertions, variable, (1 << 64) - 1)
            and not _assertions_accept(assertions, variable, -1)
            and not _assertions_accept(assertions, variable, 1 << 64)
        )
        if signed64 or unsigned64:
            return

    pytest.fail(
        "Immediately after struct.unpack, worker.py must assert type(transaction_id) is int "
        "and assert valid signed or unsigned 64-bit bounds"
    )


class ProbeDatabase:
    def __init__(self, count):
        self.events = queue.Queue()
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(('127.0.0.1', 7070))
        self.sock.listen(5)
        self.sock.settimeout(8)
        self.thread = __import__('threading').Thread(target=self._run, args=(count,), daemon=True)
        self.thread.start()

    def _run(self, count):
        try:
            for _ in range(count):
                conn, peer = self.sock.accept()
                with conn:
                    conn.settimeout(5)
                    data = conn.recv(4096)
                    owners = set()
                    for row in _tcp_rows():
                        if (row['state'] == '01' and row['local_port'] == peer[1]
                                and row['remote_port'] == 7070):
                            owners.update(_inode_owners(row['inode']))
                    self.events.put((data, owners))
                    conn.sendall(b'{"status": "saved"}')
        except Exception as exc:
            self.events.put(exc)

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass
        self.thread.join(timeout=1)


def test_random_transactions_traverse_gateway_worker_and_database():
    db_row, db_owners = _listener(7070)
    worker_row, worker_owners = _listener(9090)
    assert db_row and db_owners, "Database service is not running"
    assert worker_row and worker_owners, "Worker service is not running"
    worker_pids = {pid for pid in worker_owners if '/app/src/worker.py' in _cmdline(pid)}
    assert worker_pids, "worker.py does not own port 9090"

    # Values are generated only after the agent has finished, preventing a fixed-answer gateway.
    tx_ids = []
    while len(tx_ids) < 4:
        value = (1 << 53) + secrets.randbelow((1 << 63) - (1 << 53))
        if value not in tx_ids:
            tx_ids.append(value)

    probe = None
    restarted = None
    try:
        for pid in db_owners:
            os.kill(pid, signal.SIGTERM)
        row, _ = _wait_for_port(7070, present=False, timeout=5)
        assert row is None, "Could not temporarily stop the database service"

        probe = ProbeDatabase(len(tx_ids))
        for tx_id in tx_ids:
            response = requests.post(
                'http://127.0.0.1:8080/process',
                json={'tx_id': tx_id, 'amount': 250.50},
                timeout=8,
            )
            assert response.status_code == 200, response.text
            data = response.json()
            assert data.get('status') == 'success'
            assert data.get('processed_id') == tx_id

            event = probe.events.get(timeout=6)
            if isinstance(event, Exception):
                raise event
            db_payload, client_owners = event
            assert db_payload.decode().strip() == str(tx_id), (
                f"Database received {db_payload!r}, expected exact transaction ID {tx_id}"
            )
            assert client_owners & worker_pids, (
                "The database connection was not made by the running worker service"
            )
    finally:
        if probe is not None:
            probe.close()
        restarted = subprocess.Popen(
            ['python3', '/app/src/db.py'],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        row, owners = _wait_for_port(7070, present=True, timeout=5)
        assert row is not None and any('/app/src/db.py' in _cmdline(pid) for pid in owners), (
            "Database service was not restored after verification"
        )


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
