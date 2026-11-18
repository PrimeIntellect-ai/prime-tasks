#!/bin/bash
set -u
mkdir -p /logs/verifier

cat > /tmp/verify_stack.py <<'PY'
import os
import sys
import time
import uuid
import shutil
import signal
import socket
import subprocess
from pathlib import Path

APP = Path('/home/user/app')
START = APP / 'start_all.py'

EXPECTED = {
    'db_service.py': '''import time, socket
print("DB initializing...")
time.sleep(5)
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind(('127.0.0.1', 8001))
s.listen(1)
print("DB ready on 8001")
while True:
    conn, addr = s.accept()
    conn.close()
''',
    'api_service.py': '''import socket, sys, time
try:
    s = socket.create_connection(('127.0.0.1', 8001), timeout=1)
    s.close()
except Exception:
    print("API FATAL: DB not reachable on 8001")
    sys.exit(1)

print("API connected to DB. Starting API...")
s2 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s2.bind(('127.0.0.1', 8002))
s2.listen(1)
print("API ready on 8002")
while True:
    conn, addr = s2.accept()
    conn.sendall(b"API_OK")
    conn.close()
''',
    'monitor_service.py': '''import socket, sys, time
try:
    s = socket.create_connection(('127.0.0.1', 9000), timeout=2)
    data = s.recv(1024)
    s.close()
    if b"API_OK" in data:
        with open("/home/user/app/monitor.log", "w") as f:
            f.write("STATUS: ALL_SYSTEMS_GO\\n")
        print("Monitor success.")
    else:
        sys.exit(1)
except Exception as e:
    print(f"Monitor failed: {e}")
    sys.exit(1)
'''
}

BUGGY_START = '''import subprocess, time
print("Starting all services...")
db = subprocess.Popen(["python3", "/home/user/app/db_service.py"])
api = subprocess.Popen(["python3", "/home/user/app/api_service.py"])
monitor = subprocess.Popen(["python3", "/home/user/app/monitor_service.py"])

db.wait()
'''

def fail(message):
    raise AssertionError(message)

def proc_info():
    result = {}
    for entry in Path('/proc').iterdir():
        if not entry.name.isdigit():
            continue
        try:
            raw = (entry / 'cmdline').read_bytes()
            argv = [x.decode(errors='replace') for x in raw.split(b'\0') if x]
            status = (entry / 'status').read_text(errors='replace')
            ppid = int(next(x.split()[1] for x in status.splitlines() if x.startswith('PPid:')))
            result[int(entry.name)] = (argv, ppid)
        except (OSError, StopIteration, ValueError):
            pass
    return result

def descendants(root, info):
    out = {root}
    changed = True
    while changed:
        changed = False
        for pid, (_, ppid) in info.items():
            if ppid in out and pid not in out:
                out.add(pid)
                changed = True
    return out

def kill_old_stack():
    me = os.getpid()
    for _ in range(2):
        info = proc_info()
        victims = []
        for pid, (argv, _) in info.items():
            if pid == me:
                continue
            text = ' '.join(argv)
            service = any(('/home/user/app/' + n) in text for n in
                          ('start_all.py', 'db_service.py', 'api_service.py', 'monitor_service.py'))
            tunnel = bool(argv and os.path.basename(argv[0]) == 'ssh' and '9000' in text and '8002' in text)
            if service or tunnel:
                victims.append(pid)
        for pid in victims:
            try:
                os.kill(pid, signal.SIGTERM if _ == 0 else signal.SIGKILL)
            except ProcessLookupError:
                pass
        time.sleep(0.6)

def can_connect(port, expect=None):
    try:
        with socket.create_connection(('127.0.0.1', port), timeout=0.4) as s:
            if expect is None:
                return True
            s.settimeout(1)
            return expect in s.recv(1024)
    except OSError:
        return False

def listening_inodes(port):
    answer = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[3] == '0A':
                try:
                    local_port = int(fields[1].rsplit(':', 1)[1], 16)
                except ValueError:
                    continue
                if local_port == port:
                    answer.add(fields[9])
    return answer

def pid_owns_listener(pid, port):
    wanted = listening_inodes(port)
    if not wanted:
        return False
    try:
        for fd in (Path('/proc') / str(pid) / 'fd').iterdir():
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in wanted:
                return True
    except OSError:
        return False
    return False

def marker(path, prefix):
    try:
        parts = Path(path).read_text().strip().split()
        if len(parts) == 2 and parts[0] == prefix:
            return int(parts[1])
    except (OSError, ValueError):
        pass
    return None

def valid_ssh(argv):
    if not argv or os.path.basename(argv[0]) != 'ssh':
        return False
    joined = ' '.join(argv)
    has_strict = ('StrictHostKeyChecking=no' in argv or
                  any(x == '-oStrictHostKeyChecking=no' for x in argv) or
                  ('-o' in argv and argv.index('-o') + 1 < len(argv) and
                   argv[argv.index('-o') + 1] == 'StrictHostKeyChecking=no'))
    has_key = ('-i' in argv and argv.index('-i') + 1 < len(argv) and
               argv[argv.index('-i') + 1] == '/home/user/.ssh/id_rsa')
    has_forward = any(x in argv for x in ('9000:127.0.0.1:8002',
                                          '127.0.0.1:9000:127.0.0.1:8002'))
    return ('-N' in argv and has_strict and has_key and has_forward and
            'user@127.0.0.1' in argv and '9000' in joined and '8002' in joined)

def main():
    if not START.exists() or not START.is_file() or START.is_symlink():
        fail('start_all.py must be a regular file')
    submitted = START.read_text()
    if submitted == BUGGY_START:
        fail('start_all.py was not rewritten')
    subprocess.run([sys.executable, '-m', 'py_compile', str(START)], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)

    for name, expected in EXPECTED.items():
        if (APP / name).read_text() != expected:
            fail(f'{name} was modified')

    subprocess.run(['service', 'ssh', 'start'], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    kill_old_stack()
    try:
        (APP / 'monitor.log').unlink()
    except FileNotFoundError:
        pass

    work = Path('/tmp') / ('stack_verify_' + uuid.uuid4().hex)
    work.mkdir(mode=0o700)
    backups = {}
    marks = {n: work / (n + '.mark') for n in ('db', 'api', 'monitor')}
    for name in EXPECTED:
        src = APP / name
        backup = work / name
        shutil.copyfile(src, backup)
        backups[name] = backup

    wrappers = {
        'db_service.py': f'''import os
open({str(marks['db'])!r}, 'w').write('START ' + str(os.getpid()))
os.execv('/usr/bin/python3', ['python3', {str(backups['db_service.py'])!r}])
''',
        'api_service.py': f'''import os, socket
try:
    s = socket.create_connection(('127.0.0.1', 8001), timeout=1)
    s.close()
except Exception:
    open({str(marks['api'])!r}, 'w').write('FAIL ' + str(os.getpid()))
    raise
open({str(marks['api'])!r}, 'w').write('OK ' + str(os.getpid()))
os.execv('/usr/bin/python3', ['python3', {str(backups['api_service.py'])!r}])
''',
        'monitor_service.py': f'''import os, socket
try:
    s = socket.create_connection(('127.0.0.1', 9000), timeout=2)
    data = s.recv(1024)
    s.close()
    assert b'API_OK' in data
except Exception:
    open({str(marks['monitor'])!r}, 'w').write('FAIL ' + str(os.getpid()))
    raise
open({str(marks['monitor'])!r}, 'w').write('OK ' + str(os.getpid()))
os.execv('/usr/bin/python3', ['python3', {str(backups['monitor_service.py'])!r}])
'''
    }

    manager = None
    success = False
    try:
        for name, body in wrappers.items():
            (APP / name).write_text(body)

        manager = subprocess.Popen([sys.executable, str(START)], cwd=str(APP),
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        deadline = time.time() + 30
        while time.time() < deadline:
            if manager.poll() is not None:
                fail(f'start_all.py exited early with status {manager.returncode}')
            if (marker(marks['db'], 'START') is not None and
                marker(marks['api'], 'OK') is not None and
                marker(marks['monitor'], 'OK') is not None and
                (APP / 'monitor.log').exists()):
                break
            time.sleep(0.05)
        else:
            fail('the submitted manager did not bring up the instrumented stack in time')

        dbpid = marker(marks['db'], 'START')
        apipid = marker(marks['api'], 'OK')
        if marker(marks['monitor'], 'OK') is None:
            fail('monitor_service.py was not started after a functional tunnel was ready')
        if not can_connect(8001):
            fail('database port 8001 is not accepting connections')
        if not can_connect(8002, b'API_OK'):
            fail('API port 8002 is not functional')

        info = proc_info()
        family = descendants(manager.pid, info)
        if dbpid not in family or apipid not in family:
            fail('database and API were not launched by start_all.py')
        if not pid_owns_listener(dbpid, 8001):
            fail('the launched database process does not own port 8001')
        if not pid_owns_listener(apipid, 8002):
            fail('the launched API process does not own port 8002')

        ssh_candidates = [(pid, argv) for pid, (argv, _) in info.items()
                          if pid in family and valid_ssh(argv)]
        if not ssh_candidates:
            fail('required SSH tunnel process forwarding 9000 to 8002 is not running')
        if not any(pid_owns_listener(pid, 9000) for pid, _ in ssh_candidates):
            fail('port 9000 is not owned by the required SSH process')
        if not can_connect(9000, b'API_OK'):
            fail('the SSH tunnel on port 9000 does not reach the API')

        content = (APP / 'monitor.log').read_text().strip()
        if content != 'STATUS: ALL_SYSTEMS_GO':
            fail("monitor.log does not contain exactly 'STATUS: ALL_SYSTEMS_GO'")
        time.sleep(0.5)
        if manager.poll() is not None:
            fail('start_all.py did not remain alive with its subprocesses')
        success = True
    finally:
        for name, expected in EXPECTED.items():
            (APP / name).write_text(expected)
        if not success and manager is not None and manager.poll() is None:
            try:
                os.kill(manager.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        shutil.rmtree(work, ignore_errors=True)

if __name__ == '__main__':
    main()
PY

if python3 /tmp/verify_stack.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
