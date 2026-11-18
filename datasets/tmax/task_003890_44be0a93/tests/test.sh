#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_final_state.py
import http.client
import math
import os
import re
import signal
import socket
import stat
import subprocess
import time


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def proc_info():
    result = []
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        pid = int(name)
        try:
            exe = os.path.realpath(f'/proc/{pid}/exe')
            with open(f'/proc/{pid}/cmdline', 'rb') as f:
                cmdline = f.read().replace(b'\0', b' ').decode(errors='replace')
            result.append((pid, exe, cmdline))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return result


def gunicorn_pids():
    return [pid for pid, exe, cmd in proc_info()
            if re.search(r'(^|[ /])gunicorn(?:[ .:/]|$)', cmd)]


def nginx_pids():
    return [(pid, cmd) for pid, exe, cmd in proc_info()
            if os.path.basename(exe) == 'nginx']


def qemu_pids_for_socket():
    return [pid for pid, exe, cmd in proc_info()
            if os.path.basename(exe).startswith('qemu-system-')
            and 'unix:/app/run/qemu.sock' in cmd]


def identity(pid):
    uid = gid = None
    groups = []
    with open(f'/proc/{pid}/status') as f:
        for line in f:
            if line.startswith('Uid:'):
                uid = int(line.split()[1])
            elif line.startswith('Gid:'):
                gid = int(line.split()[1])
            elif line.startswith('Groups:'):
                groups = [int(x) for x in line.split()[1:]]
    require(uid is not None and gid is not None, 'Could not determine Gunicorn credentials')
    if gid not in groups:
        groups.append(gid)
    return uid, gid, groups


def run_as(cmd, uid, gid, groups, **kwargs):
    def demote():
        os.setgroups(groups)
        os.setgid(gid)
        os.setuid(uid)
    return subprocess.run(cmd, preexec_fn=demote, **kwargs)


def socket_inode(path):
    try:
        with open('/proc/net/unix') as f:
            for line in f:
                fields = line.split()
                if len(fields) >= 8 and fields[-1] == path:
                    return fields[6]
    except FileNotFoundError:
        pass
    return None


def process_holds_inode(pid, inode):
    try:
        for fd in os.listdir(f'/proc/{pid}/fd'):
            try:
                if os.readlink(f'/proc/{pid}/fd/{fd}') == f'socket:[{inode}]':
                    return True
            except (FileNotFoundError, PermissionError):
                pass
    except (FileNotFoundError, PermissionError):
        return False
    return False


def wait_for_qemu(timeout=15):
    deadline = time.monotonic() + timeout
    last = 'QEMU did not create its socket'
    while time.monotonic() < deadline:
        pids = qemu_pids_for_socket()
        if pids and os.path.exists('/app/run/qemu.sock'):
            try:
                require(stat.S_ISSOCK(os.stat('/app/run/qemu.sock').st_mode),
                        '/app/run/qemu.sock is not a UNIX socket')
                inode = socket_inode('/app/run/qemu.sock')
                if inode and any(process_holds_inode(pid, inode) for pid in pids):
                    return pids
                last = 'The QEMU process does not own /app/run/qemu.sock'
            except (FileNotFoundError, AssertionError) as exc:
                last = str(exc)
        time.sleep(0.2)
    raise AssertionError(last)


def check_endpoint_once():
    conn = http.client.HTTPConnection('127.0.0.1', 8080, timeout=2)
    try:
        conn.request('GET', '/api/status')
        response = conn.getresponse()
        body = response.read()
        require(response.status == 200,
                f'/api/status returned HTTP {response.status}, not 200')
        require(body.strip() == b'OK',
                f'/api/status returned unexpected body: {body!r}')
    finally:
        conn.close()


# Required artifacts must exist and retain their intended roles.
require(os.path.isfile('/app/nginx/nginx.conf'), 'Missing /app/nginx/nginx.conf')
require(os.path.isfile('/app/api/gunicorn.conf.py'), 'Missing /app/api/gunicorn.conf.py')
require(os.path.isfile('/app/start_vm.sh'), 'Missing /app/start_vm.sh')
require(os.access('/app/start_vm.sh', os.X_OK), '/app/start_vm.sh is not executable')

with open('/app/nginx/nginx.conf') as f:
    nginx_config = f.read()
require('proxy_pass' in nginx_config and '/app/run/api.sock' in nginx_config,
        'Nginx configuration does not proxy to the Gunicorn API socket')

# The real Nginx and Gunicorn services must be running.
nginx = nginx_pids()
require(nginx, 'No real nginx process is running')
require(any('/app/nginx/nginx.conf' in cmd for _, cmd in nginx),
        'Running nginx was not started with /app/nginx/nginx.conf')
gpids = gunicorn_pids()
require(gpids, 'No Gunicorn process is running')
api_uid, api_gid, api_groups = identity(gpids[0])
check_endpoint_once()

# Test start_vm.sh itself from a clean state, rather than trusting an already
# running process that may have been launched by some other command.
for pid, exe, cmd in proc_info():
    if os.path.basename(exe).startswith('qemu-system-'):
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
time.sleep(1)
for pid, exe, cmd in proc_info():
    if os.path.basename(exe).startswith('qemu-system-'):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
try:
    os.unlink('/app/run/qemu.sock')
except FileNotFoundError:
    pass

try:
    vm_start = run_as(['/app/start_vm.sh'], api_uid, api_gid, api_groups,
                      stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                      text=True, timeout=10)
except subprocess.TimeoutExpired:
    raise AssertionError('/app/start_vm.sh did not return after launching QEMU')
require(vm_start.returncode == 0,
        f'/app/start_vm.sh failed:\nstdout: {vm_start.stdout}\nstderr: {vm_start.stderr}')
qemu_pids = wait_for_qemu()

# Verify the API process identity has read/write permission and can establish
# and write through the actual QEMU-owned serial socket.
st = os.stat('/app/run/qemu.sock')
if api_uid == st.st_uid:
    permission_bits = (st.st_mode >> 6) & 7
elif st.st_gid in api_groups:
    permission_bits = (st.st_mode >> 3) & 7
else:
    permission_bits = st.st_mode & 7
require(permission_bits & 4 and permission_bits & 2,
        'Gunicorn identity lacks read/write permission on /app/run/qemu.sock')

probe = r'''import socket
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(3)
s.connect('/app/run/qemu.sock')
s.sendall(b'\r\n')
s.close()
'''
probe_result = run_as(['python3', '-c', probe], api_uid, api_gid, api_groups,
                      stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                      text=True, timeout=5)
require(probe_result.returncode == 0,
        'Gunicorn identity could not communicate with the QEMU serial socket: '
        + probe_result.stderr)

# Preserve the original required check of the provided benchmark and its
# self-reported throughput.
try:
    result = subprocess.run(['python3', '/app/benchmark.py'], capture_output=True,
                            text=True, timeout=60)
except subprocess.TimeoutExpired:
    raise AssertionError('Benchmark script timed out after 60 seconds')
require(result.returncode == 0,
        f'Benchmark script failed with return code {result.returncode}.\n'
        f'stdout: {result.stdout}\nstderr: {result.stderr}')
match = re.search(r'Throughput:\s*([\d\.]+)\s*req/s', result.stdout)
require(match is not None,
        f'Could not find throughput metric in benchmark output.\nstdout: {result.stdout}')
throughput = float(match.group(1))
require(math.isfinite(throughput) and throughput >= 300.0,
        f'Throughput {throughput} req/s is less than 300.0 req/s')

# Independently generate requests so replacing benchmark.py with a fabricated
# print statement cannot pass. Only correct 200/OK responses are counted.
duration = 2.0
start = time.monotonic()
successes = 0
errors = 0
while time.monotonic() - start < duration:
    conn = http.client.HTTPConnection('127.0.0.1', 8080, timeout=1)
    try:
        conn.request('GET', '/api/status')
        response = conn.getresponse()
        body = response.read()
        if response.status == 200 and body.strip() == b'OK':
            successes += 1
        else:
            errors += 1
    except Exception:
        errors += 1
    finally:
        conn.close()
independent_throughput = successes / duration
require(errors == 0, f'Independent load test observed {errors} failed responses')
require(independent_throughput >= 300.0,
        f'Independent throughput {independent_throughput:.1f} req/s is below 300.0 req/s')
PY_EOF

python3 /tmp/verify_final_state.py
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
