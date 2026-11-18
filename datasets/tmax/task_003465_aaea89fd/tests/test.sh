#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import socket
import subprocess
import tempfile
import threading
import time
import secrets
from pathlib import Path

WRAPPER = Path('/home/user/cost_wrapper.exp')
API = Path('/home/user/cost_api.sh')
SUPERVISOR = Path('/home/user/supervisor.sh')
CALC = Path('/app/bin/calc_cost')
REPO = Path('/home/user/infra.git')
PORT = 9000


def run_reference(region, instances):
    p = subprocess.run(
        [str(CALC)], input=f'{region}\n{instances}\n',
        text=True, capture_output=True, timeout=5
    )
    assert p.returncode == 0
    m = re.search(r'Total Estimated Cost: \$(\d+)', p.stdout)
    assert m, f'Could not parse legacy calculator output: {p.stdout!r}'
    return m.group(1)


def request_daemon(region, instances, timeout=4):
    with socket.create_connection(('127.0.0.1', PORT), timeout=timeout) as s:
        s.settimeout(timeout)
        s.sendall(f'{region} {instances}\n'.encode())
        data = b''
        while b'\n' not in data:
            part = s.recv(1024)
            if not part:
                break
            data += part
    return data.decode().strip()


def listening_inodes():
    result = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local, state = fields[1], fields[3]
            if int(local.rsplit(':', 1)[1], 16) == PORT and state == '0A':
                result.add((fields[9], local.rsplit(':', 1)[0]))
    return result


def pids_for_inodes(inodes):
    wanted = {x[0] if isinstance(x, tuple) else x for x in inodes}
    found = set()
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / 'fd').iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in wanted:
                    found.add(int(proc.name))
                    break
        except OSError:
            pass
    return found


def cmdline(pid):
    try:
        return Path(f'/proc/{pid}/cmdline').read_bytes().replace(b'\0', b' ').decode(errors='replace')
    except OSError:
        return ''


def supervisor_pids():
    out = set()
    for proc in Path('/proc').iterdir():
        if proc.name.isdigit() and '/home/user/supervisor.sh' in cmdline(int(proc.name)):
            out.add(int(proc.name))
    return out


def descendants(roots):
    roots = set(roots)
    all_desc = set()
    changed = True
    while changed:
        changed = False
        for proc in Path('/proc').iterdir():
            if not proc.name.isdigit():
                continue
            pid = int(proc.name)
            try:
                fields = (proc / 'stat').read_text().split()
                ppid = int(fields[3])
            except (OSError, ValueError, IndexError):
                continue
            if ppid in roots | all_desc and pid not in all_desc:
                all_desc.add(pid)
                changed = True
    return all_desc


def wait_for_listener(timeout=6, excluded_pids=None):
    excluded_pids = excluded_pids or set()
    end = time.time() + timeout
    while time.time() < end:
        entries = listening_inodes()
        pids = pids_for_inodes(entries)
        if entries and pids and not pids.issubset(excluded_pids):
            return entries, pids
        time.sleep(0.1)
    raise AssertionError('No replacement listener appeared on 127.0.0.1:9000')


def assert_loopback_listener(entries):
    # IPv4 127.0.0.1 is represented as 0100007F in /proc/net/tcp.
    assert any(addr == '0100007F' for _, addr in entries), \
        f'Port 9000 is not bound specifically to 127.0.0.1: {entries}'


def make_git_workspace(tmpdir):
    subprocess.run(['git', 'init', '-q'], cwd=tmpdir, check=True)
    subprocess.run(['git', 'config', 'user.email', 'test@example.com'], cwd=tmpdir, check=True)
    subprocess.run(['git', 'config', 'user.name', 'Test User'], cwd=tmpdir, check=True)
    subprocess.run(['git', 'remote', 'add', 'origin', str(REPO)], cwd=tmpdir, check=True)
    branch = 'audit-' + secrets.token_hex(6)
    subprocess.run(['git', 'checkout', '-q', '-b', branch], cwd=tmpdir, check=True)
    return branch


def commit_and_push(tmpdir, branch, line, should_accept):
    Path(tmpdir, 'deployment.conf').write_text(line + '\n')
    subprocess.run(['git', 'add', 'deployment.conf'], cwd=tmpdir, check=True)
    subprocess.run(['git', 'commit', '-q', '-m', 'audit deployment'], cwd=tmpdir, check=True)
    result = subprocess.run(
        ['git', 'push', 'origin', f'HEAD:refs/heads/{branch}'],
        cwd=tmpdir, text=True, capture_output=True
    )
    if should_accept:
        assert result.returncode == 0, f'Git push should have succeeded, but failed: {result.stderr}'
    else:
        assert result.returncode != 0, 'Git push should have been rejected for exceeding budget'
        assert 'FinOps: Budget exceeded' in result.stderr, \
            f'Expected rejection message not found in stderr: {result.stderr}'
        subprocess.run(['git', 'reset', '--hard', '-q', 'HEAD^'], cwd=tmpdir, check=True)
    return result


class ControlledServer:
    def __init__(self, answers):
        self.answers = answers
        self.received = []
        self.error = None
        self.ready = threading.Event()
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self._run, daemon=True)

    def _run(self):
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            srv.bind(('127.0.0.1', PORT))
            srv.listen(10)
            srv.settimeout(0.2)
            self.ready.set()
            while not self.stop.is_set():
                try:
                    conn, _ = srv.accept()
                except socket.timeout:
                    continue
                with conn:
                    conn.settimeout(2)
                    data = b''
                    while b'\n' not in data:
                        part = conn.recv(1024)
                        if not part:
                            break
                        data += part
                    line = data.decode().strip()
                    self.received.append(line)
                    value = self.answers.get(line, '9999')
                    conn.sendall((value + '\n').encode())
        except Exception as exc:
            self.error = exc
            self.ready.set()
        finally:
            srv.close()

    def start(self):
        self.thread.start()
        assert self.ready.wait(3), 'Controlled TCP server did not start'
        assert self.error is None, f'Controlled TCP server failed: {self.error}'

    def close(self):
        self.stop.set()
        self.thread.join(3)
        assert self.error is None, f'Controlled TCP server failed: {self.error}'


def test_complete_pipeline():
    # Required artifacts and permissions.
    for path, label in ((WRAPPER, 'Wrapper'), (API, 'Cost daemon'), (SUPERVISOR, 'Supervisor')):
        assert path.is_file(), f'{label} script missing at {path}'
        assert os.access(path, os.X_OK), f'{label} script is not executable'
    assert REPO.is_dir(), f'Git repo missing at {REPO}'
    hook = REPO / 'hooks/pre-receive'
    assert hook.is_file(), f'pre-receive hook missing at {hook}'
    assert os.access(hook, os.X_OK), 'pre-receive hook is not executable'

    # Preserve the original fixed wrapper assertion and add unpredictable cases.
    fixed = subprocess.run([str(WRAPPER), 'eu-west', '5'], capture_output=True, text=True, timeout=5)
    assert fixed.returncode == 0, 'Wrapper script failed to execute'
    assert fixed.stdout.strip() == '100', f"Expected wrapper to output '100', got {fixed.stdout.strip()}"
    assert re.fullmatch(r'\d+\n?', fixed.stdout), 'Wrapper printed text other than the numerical cost'

    cases = [('us-east', secrets.randbelow(45) + 2), ('eu-west', secrets.randbelow(35) + 2)]
    cases += [(secrets.choice(('us-east', 'eu-west')), secrets.randbelow(80) + 3) for _ in range(3)]
    for region, count in cases:
        expected = run_reference(region, count)
        result = subprocess.run([str(WRAPPER), region, str(count)], capture_output=True, text=True, timeout=5)
        assert result.returncode == 0
        assert result.stdout.strip() == expected
        assert re.fullmatch(r'\d+\n?', result.stdout), f'Wrapper emitted extra output: {result.stdout!r}'
    assert subprocess.run([str(WRAPPER), 'us-east'], capture_output=True, timeout=5).returncode != 0
    assert subprocess.run([str(WRAPPER), 'us-east', '2', 'extra'], capture_output=True, timeout=5).returncode != 0

    # Replace the calculator briefly with an unpredictable interactive implementation.
    # This proves the wrapper actually executes and interacts with /app/bin/calc_cost.
    calc_bytes, calc_mode = CALC.read_bytes(), CALC.stat().st_mode
    probe_log = Path('/tmp/calc_probe_' + secrets.token_hex(5))
    token = str(secrets.randbelow(800000) + 100000)
    probe = f'''#!/usr/bin/env python3
import sys
with open({str(probe_log)!r}, 'a') as f: f.write('started\\n')
print('Welcome to FinOps Calculator V2.')
print('Enter Region (us-east, eu-west): ', end='', flush=True)
r=sys.stdin.readline().strip()
print('Enter Number of Instances: ', end='', flush=True)
n=sys.stdin.readline().strip()
with open({str(probe_log)!r}, 'a') as f: f.write(r+' '+n+'\\n')
print('Total Estimated Cost: ${token}')
'''
    try:
        CALC.write_text(probe)
        CALC.chmod(0o755)
        r = secrets.choice(('us-east', 'eu-west'))
        n = str(secrets.randbelow(90) + 1)
        probed = subprocess.run([str(WRAPPER), r, n], capture_output=True, text=True, timeout=5)
        assert probed.returncode == 0 and probed.stdout.strip() == token
        assert f'{r} {n}' in probe_log.read_text(), 'Wrapper did not invoke the legacy calculator with the supplied inputs'
    finally:
        CALC.write_bytes(calc_bytes)
        CALC.chmod(calc_mode & 0o7777)
        probe_log.unlink(missing_ok=True)

    entries = listening_inodes()
    assert entries, 'Nothing is listening on port 9000'
    assert_loopback_listener(entries)
    listener_pids = pids_for_inodes(entries)
    assert listener_pids, 'Could not identify the process listening on port 9000'
    listener_commands = ' '.join(cmdline(p) for p in listener_pids)
    assert re.search(r'(^|[ /])(socat|nc)( |$)', listener_commands), \
        f'The TCP listener is not socat or nc: {listener_commands}'

    # Preserve the fixed daemon assertion and add derived random requests.
    assert request_daemon('us-east', 12) == '120', "Expected daemon to return '120'"
    for region, count in cases:
        assert request_daemon(region, count) == run_reference(region, count)

    # Replace the wrapper briefly. A daemon that hardcodes the pricing formula instead
    # of passing each request to cost_wrapper.exp cannot pass this check.
    wrapper_bytes, wrapper_mode = WRAPPER.read_bytes(), WRAPPER.stat().st_mode
    wrapper_log = Path('/tmp/wrapper_probe_' + secrets.token_hex(5))
    daemon_cases = []
    for _ in range(3):
        daemon_cases.append((secrets.choice(('us-east', 'eu-west')), secrets.randbelow(200) + 101,
                             str(secrets.randbelow(800000) + 100000)))
    mapping = {(r, str(n)): value for r, n, value in daemon_cases}
    probe_script = f'''#!/usr/bin/env python3
import sys
m={mapping!r}
with open({str(wrapper_log)!r}, 'a') as f: f.write(repr(sys.argv[1:])+'\\n')
if len(sys.argv) != 3 or (sys.argv[1],sys.argv[2]) not in m: sys.exit(2)
print(m[(sys.argv[1],sys.argv[2])])
'''
    try:
        WRAPPER.write_text(probe_script)
        WRAPPER.chmod(0o755)
        for region, count, value in daemon_cases:
            assert request_daemon(region, count) == value
        logged = wrapper_log.read_text()
        for region, count, _ in daemon_cases:
            assert region in logged and str(count) in logged
    finally:
        WRAPPER.write_bytes(wrapper_bytes)
        WRAPPER.chmod(wrapper_mode & 0o7777)
        wrapper_log.unlink(missing_ok=True)

    # Supervision must be real: verify a running supervisor, kill the actual socket
    # owner without swallowing errors, then require a different listener to appear.
    supervisors = supervisor_pids()
    assert supervisors, 'supervisor.sh is not running in the background'
    old_entries = listening_inodes()
    old_pids = pids_for_inodes(old_entries)
    assert old_pids, 'No daemon listener was available to kill'
    for pid in old_pids:
        os.kill(pid, signal.SIGKILL)
    end = time.time() + 2
    while time.time() < end and any(Path(f'/proc/{p}').exists() for p in old_pids):
        time.sleep(0.05)
    assert not any(Path(f'/proc/{p}').exists() for p in old_pids), 'The original listener was not killed'
    new_entries, new_pids = wait_for_listener(7, old_pids)
    assert_loopback_listener(new_entries)
    assert new_pids != old_pids, 'Supervisor did not create a replacement daemon'
    assert supervisor_pids(), 'supervisor.sh terminated instead of monitoring the daemon'
    time.sleep(0.2)
    assert request_daemon('eu-west', 10) == '200', 'Daemon did not recover after being killed'

    # Exercise the real hook over multiple unpredictable, oracle-derived prices.
    subprocess.run(['git', 'config', '--global', '--add', 'safe.directory', '*'], check=True)
    with tempfile.TemporaryDirectory() as tmpdir:
        branch = make_git_workspace(tmpdir)
        commit_and_push(tmpdir, branch, 'eu-west 10', True)       # original acceptance
        commit_and_push(tmpdir, branch, 'us-east 100', False)     # original rejection
        random_policy_cases = [
            ('us-east', secrets.randbelow(49) + 1),
            ('eu-west', secrets.randbelow(24) + 1),
            ('us-east', secrets.randbelow(70) + 51),
            ('eu-west', secrets.randbelow(70) + 26),
        ]
        secrets.SystemRandom().shuffle(random_policy_cases)
        for region, count in random_policy_cases:
            cost = int(run_reference(region, count))
            commit_and_push(tmpdir, branch, f'{region} {count}', cost <= 500)

    # Stop the genuine supervisor temporarily and substitute a controlled TCP oracle.
    # Inputs are chosen so their returned costs contradict the legacy formula, proving
    # the hook extracts deployment.conf, contacts port 9000, and trusts its response.
    supervisors = supervisor_pids()
    assert supervisors
    controlled = None
    try:
        for pid in supervisors:
            os.kill(pid, signal.SIGSTOP)
        victims = descendants(supervisors) | pids_for_inodes(listening_inodes())
        victims -= supervisors
        for pid in victims:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        end = time.time() + 4
        while listening_inodes() and time.time() < end:
            time.sleep(0.05)
        assert not listening_inodes(), 'The supervised daemon could not be stopped for hook isolation'

        accept_line = f'eu-west {secrets.randbelow(40) + 60}'  # genuinely over budget
        reject_line = f'us-east {secrets.randbelow(20) + 1}'   # genuinely under budget
        controlled = ControlledServer({accept_line: '499', reject_line: '501'})
        controlled.start()
        with tempfile.TemporaryDirectory() as tmpdir:
            branch = make_git_workspace(tmpdir)
            commit_and_push(tmpdir, branch, accept_line, True)
            commit_and_push(tmpdir, branch, reject_line, False)
        assert accept_line in controlled.received, 'Hook did not send accepted deployment.conf contents to TCP daemon'
        assert reject_line in controlled.received, 'Hook did not send rejected deployment.conf contents to TCP daemon'
    finally:
        if controlled is not None:
            controlled.close()
        for pid in supervisors:
            try:
                os.kill(pid, signal.SIGCONT)
            except ProcessLookupError:
                pass

    wait_for_listener(7)
    assert request_daemon('us-east', 12) == '120'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
