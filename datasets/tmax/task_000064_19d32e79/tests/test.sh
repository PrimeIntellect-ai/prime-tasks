#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import signal
import stat
import subprocess
import tempfile
import time
import urllib.request
from pathlib import Path

HOME = Path('/home/user')
LOGS = {8081: HOME / 'metrics_8081.log', 8082: HOME / 'metrics_8082.log'}


def post(port, body, timeout=3):
    req = urllib.request.Request(
        f'http://127.0.0.1:{port}/',
        data=body.encode('utf-8'),
        headers={'Content-Type': 'application/json'},
        method='POST',
    )
    with urllib.request.urlopen(req, timeout=timeout) as response:
        assert response.status in (200, 201, 202, 204), response.status


def read_lines(path):
    with open(path, encoding='utf-8') as f:
        return [line.rstrip('\n') for line in f if line.strip()]


def listener_pids(port):
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local = fields[1]
            state = fields[3]
            if state == '0A' and int(local.rsplit(':', 1)[1], 16) == port:
                inodes.add(fields[9])
    result = set()
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / 'fd').iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    result.add(int(proc.name))
        except OSError:
            pass
    return result


def cmdline(pid):
    try:
        return Path(f'/proc/{pid}/cmdline').read_bytes().replace(b'\0', b' ').decode(errors='replace')
    except OSError:
        return ''


def wait_listening(port, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if listener_pids(port):
            return
        time.sleep(0.05)
    raise AssertionError(f'Nothing listening on port {port}')


def git(*args, cwd=None, env=None):
    result = subprocess.run(['git', *args], cwd=cwd, env=env, text=True,
                            capture_output=True, timeout=15)
    assert result.returncode == 0, result.stderr or result.stdout
    return result.stdout.strip()


def additions(repo, commit):
    out = git('show', '--numstat', '--format=', commit, cwd=repo)
    total = 0
    for line in out.splitlines():
        fields = line.split('\t', 2)
        if fields and fields[0].isdigit():
            total += int(fields[0])
    return total


def main():
    # Preserve the original final-state assertions.
    summary = HOME / 'dashboard-summary.txt'
    assert summary.is_file(), f'File {summary} does not exist.'
    assert summary.read_text().strip() == 'TOTAL_ALICE=20'

    for path in LOGS.values():
        assert path.is_file(), f'Log file {path} does not exist.'
    lines1 = read_lines(LOGS[8081])
    lines2 = read_lines(LOGS[8082])
    total_lines = len(lines1) + len(lines2)
    assert total_lines >= 3, f'Expected at least 3 log entries, found {total_lines}.'
    if total_lines == 3:
        assert sorted((len(lines1), len(lines2))) == [1, 2]

    alice_lines = 0
    bob_lines = 0
    for line in lines1 + lines2:
        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            continue
        if data.get('author') == 'Alice':
            alice_lines += data.get('lines_added', 0)
        elif data.get('author') == 'Bob':
            bob_lines += data.get('lines_added', 0)
    assert alice_lines >= 20, alice_lines
    assert bob_lines >= 10, bob_lines

    repo = HOME / 'telemetry.git'
    assert repo.is_dir()
    result = subprocess.run(
        ['git', '-C', str(repo), 'log', '--format=%an', '--shortstat', 'master'],
        capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, result.stderr
    original_alice = original_bob = 0
    author = None
    for raw in result.stdout.splitlines():
        line = raw.strip()
        if line in ('Alice', 'Bob'):
            author = line
        elif 'insertion' in line:
            for part in line.split(','):
                if 'insertion' in part:
                    number = int(part.strip().split()[0])
                    if author == 'Alice':
                        original_alice += number
                    elif author == 'Bob':
                        original_bob += number
    assert original_alice >= 20, original_alice
    assert original_bob >= 10, original_bob

    # Required artifacts must be real files, and the hook must be executable.
    backend = HOME / 'backend.py'
    lb = HOME / 'lb.py'
    hook = repo / 'hooks/post-receive'
    for path in (backend, lb, hook):
        assert path.is_file() and not path.is_symlink(), f'Missing regular file: {path}'
    assert hook.stat().st_mode & 0o111, 'post-receive hook is not executable'

    # Confirm the requested scripts are actually running as three distinct listeners.
    p8080 = listener_pids(8080)
    p8081 = listener_pids(8081)
    p8082 = listener_pids(8082)
    assert p8080 and p8081 and p8082, 'Ports 8080, 8081, and 8082 must all be listening'
    assert any('/home/user/lb.py' in cmdline(pid) for pid in p8080)
    assert any('/home/user/backend.py' in cmdline(pid) for pid in p8081)
    assert any('/home/user/backend.py' in cmdline(pid) for pid in p8082)
    assert p8081.isdisjoint(p8082), 'The two backend instances must be distinct processes'

    # Exercise each backend directly and require the exact raw request body in its own log.
    token = secrets.token_hex(12)
    for port in (8081, 8082):
        before = read_lines(LOGS[port])
        body = f'{{"probe":"backend-{port}-{token}","value":{port}}}'
        post(port, body)
        deadline = time.time() + 3
        while time.time() < deadline and len(read_lines(LOGS[port])) <= len(before):
            time.sleep(0.05)
        after = read_lines(LOGS[port])
        assert len(after) == len(before) + 1
        assert after[-1] == body, f'Backend {port} did not append the raw JSON body'

    # Preserve and strengthen the original live load-balancer assertion.
    before = {port: read_lines(path) for port, path in LOGS.items()}
    live_body = json.dumps({'author': 'TestUser', 'lines_added': 999})
    post(8080, live_body)
    deadline = time.time() + 3
    while time.time() < deadline:
        deltas = {p: read_lines(LOGS[p])[len(before[p]):] for p in LOGS}
        if sum(map(len, deltas.values())):
            break
        time.sleep(0.05)
    assert sum(map(len, deltas.values())) == 1
    assert sum(line == live_body for values in deltas.values() for line in values) == 1

    # Replace the backend listeners with independent recording servers. This lets us
    # observe forwarded headers and exact destination order rather than trusting logs.
    backend_pids = p8081 | p8082
    for pid in backend_pids:
        os.kill(pid, signal.SIGTERM)
    deadline = time.time() + 5
    while time.time() < deadline and (listener_pids(8081) or listener_pids(8082)):
        time.sleep(0.05)
    assert not listener_pids(8081) and not listener_pids(8082)

    probe_dir = Path(tempfile.mkdtemp(prefix='lb-probes-'))
    probe_script = probe_dir / 'probe.py'
    probe_script.write_text(r'''import http.server, json, os, sys, time
port = int(sys.argv[1]); output = sys.argv[2]
class Server(http.server.ThreadingHTTPServer):
    allow_reuse_address = True
class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', '0'))).decode('utf-8')
        record = {'time': time.time_ns(), 'port': port, 'body': body,
                  'forwarded': self.headers.get('X-Forwarded-By')}
        with open(output, 'a', encoding='utf-8') as f:
            f.write(json.dumps(record) + '\n'); f.flush(); os.fsync(f.fileno())
        self.send_response(204); self.end_headers()
    def log_message(self, *args): pass
Server(('127.0.0.1', port), Handler).serve_forever()
''')
    probes = []
    try:
        for port in (8081, 8082):
            probes.append(subprocess.Popen(
                ['python3', str(probe_script), str(port), str(probe_dir / f'{port}.jsonl')],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
        wait_listening(8081)
        wait_listening(8082)

        # Push two newly generated commits. Git invokes the submitted hook itself;
        # expected insertion counts are independently derived from the resulting commits.
        work = Path(tempfile.mkdtemp(prefix='hook-check-'))
        clone = work / 'clone'
        git('clone', str(repo), str(clone))
        git('checkout', 'master', cwd=clone)
        suffix = secrets.token_hex(8)
        authors = [f'VerifierA_{suffix}', f'VerifierB_{suffix}']
        commit_ids = []
        data_file = clone / f'verifier_{suffix}.txt'
        for index, author_name in enumerate(authors):
            count = 4 + secrets.randbelow(8)
            mode = 'w' if index == 0 else 'a'
            with open(data_file, mode, encoding='utf-8') as f:
                for i in range(count):
                    f.write(f'{suffix}-{index}-{i}\n')
            git('add', data_file.name, cwd=clone)
            env = os.environ.copy()
            env.update({
                'GIT_AUTHOR_NAME': author_name,
                'GIT_AUTHOR_EMAIL': f'{suffix}-{index}@example.invalid',
                'GIT_COMMITTER_NAME': 'Verifier',
                'GIT_COMMITTER_EMAIL': 'verifier@example.invalid',
            })
            git('commit', '-m', f'verifier {suffix} {index}', cwd=clone, env=env)
            commit_ids.append(git('rev-parse', 'HEAD', cwd=clone))
        expected_hook_bodies = [
            f'{{"author": "{name}", "lines_added": {additions(clone, oid)}}}'
            for name, oid in zip(authors, commit_ids)
        ]
        git('push', 'origin', 'master', cwd=clone)

        # Additional unpredictable requests establish strict alternation over both targets.
        rr_bodies = []
        for i in range(6):
            body = json.dumps({'rr_token': suffix, 'sequence': i}, separators=(',', ':'))
            rr_bodies.append(body)
            post(8080, body)

        wanted = set(expected_hook_bodies + rr_bodies)
        deadline = time.time() + 5
        records = []
        while time.time() < deadline:
            records = []
            for port in (8081, 8082):
                path = probe_dir / f'{port}.jsonl'
                if path.exists():
                    records.extend(json.loads(line) for line in path.read_text().splitlines() if line)
            selected = sorted((r for r in records if r['body'] in wanted), key=lambda r: r['time'])
            if len(selected) >= len(wanted):
                break
            time.sleep(0.05)

        assert len(selected) == len(wanted), 'Hook or load balancer failed to forward every probe'
        assert {r['body'] for r in selected} == wanted
        assert all(r['forwarded'] == 'ObservabilityLB' for r in selected), \
            'X-Forwarded-By: ObservabilityLB was not injected'
        ports = [r['port'] for r in selected]
        assert all(a != b for a, b in zip(ports, ports[1:])), \
            f'Forwarding was not strict round-robin: {ports}'
        assert ports.count(8081) == ports.count(8082) == len(ports) // 2
    finally:
        for process in probes:
            process.terminate()
        for process in probes:
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
        shutil.rmtree(probe_dir, ignore_errors=True)


if __name__ == '__main__':
    main()
PY

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
