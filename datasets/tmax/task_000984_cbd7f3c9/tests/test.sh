#!/bin/bash
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import os
import re
import secrets
import signal
import socket
import subprocess
import time
from pathlib import Path

BUILD_DIR = Path('/home/user/build_system')
BUILD_SH = BUILD_DIR / 'build.sh'
CALC_SH = BUILD_DIR / 'calc_factor.sh'
SERVER_SH = BUILD_DIR / 'server.sh'
CONFIG = Path('/app/config.png')


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, text=True, capture_output=True, **kwargs)


def read_cmdline(pid):
    try:
        data = Path(f'/proc/{pid}/cmdline').read_bytes()
        return [x.decode(errors='replace') for x in data.split(b'\0') if x]
    except (OSError, ValueError):
        return []


def listener_pids(port):
    inodes = set()
    wanted = f'{port:04X}'
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[1].rsplit(':', 1)[-1].upper() == wanted and fields[3] == '0A':
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
                match = re.fullmatch(r'socket:\[(\d+)\]', target)
                if match and match.group(1) in inodes:
                    result.add(int(proc.name))
        except OSError:
            pass
    return result


def has_expected_server_ancestor(pid, port, token, factor):
    for _ in range(12):
        args = read_cmdline(pid)
        if args and any(Path(arg).name == 'server.sh' for arg in args):
            try:
                cwd = Path(f'/proc/{pid}/cwd').resolve()
            except OSError:
                cwd = None
            if cwd == BUILD_DIR.resolve() and str(port) in args and token in args and factor in args:
                return True
        try:
            stat = Path(f'/proc/{pid}/stat').read_text()
            pid = int(stat.rsplit(')', 1)[1].split()[1])
        except (OSError, ValueError, IndexError):
            return False
        if pid <= 1:
            return False
    return False


def raw_request(port, token=None):
    lines = ['GET / HTTP/1.1']
    if token is not None:
        # handle_req.sh expects Authorization to be the first header line.
        lines.append(f'Authorization: Bearer {token}')
    lines.extend(['Connection: close', '', ''])
    payload = '\r\n'.join(lines).encode()

    with socket.create_connection(('127.0.0.1', port), timeout=5) as sock:
        sock.settimeout(5)
        sock.sendall(payload)
        chunks = []
        while True:
            try:
                chunk = sock.recv(65536)
            except socket.timeout:
                break
            if not chunk:
                break
            chunks.append(chunk)
    data = b''.join(chunks).decode(errors='replace')
    require(data.startswith('HTTP/1.1 '), f'Invalid HTTP response: {data!r}')
    status = int(data.split(None, 2)[1])
    body = re.split(r'\r?\n\r?\n', data, maxsplit=1)
    return status, body[1] if len(body) == 2 else ''


# Derive deployment values from the screenshot rather than trusting constants.
require(CONFIG.is_file(), 'Missing /app/config.png')
ocr = run(['tesseract', str(CONFIG), 'stdout']).stdout
port_match = re.search(r'PORT\s*:\s*(\d+)', ocr, re.I)
token_match = re.search(r'AUTH_TOKEN\s*:\s*([^\s]+)', ocr, re.I)
require(port_match and token_match, f'Could not extract deployment configuration via OCR: {ocr!r}')
port = int(port_match.group(1))
token = token_match.group(1).strip()

# Verify calc_factor.sh both uses bc and produces exactly six decimal places.
require(CALC_SH.is_file() and os.access(CALC_SH, os.X_OK), 'calc_factor.sh is missing or not executable')
calc_source = CALC_SH.read_text()
non_comment_calc = '\n'.join(line for line in calc_source.splitlines() if not line.lstrip().startswith('#'))
require(re.search(r'\bbc\b', non_comment_calc), 'calc_factor.sh does not use bc')
calc_result = run([str(CALC_SH)], cwd=BUILD_DIR).stdout.strip()
expected_factor = f'{(104348 * 1000000) // 33215 / 1000000:.6f}'
require(calc_result == expected_factor, f'calc_factor.sh returned {calc_result!r}, expected {expected_factor!r}')
require(re.fullmatch(r'\d+\.\d{6}', calc_result) is not None, 'Factor is not formatted to exactly six decimal places')

# The build must retain parallel jobs and a synchronization point.
require(BUILD_SH.is_file() and os.access(BUILD_SH, os.X_OK), 'build.sh is missing or not executable')
build_source = BUILD_SH.read_text()
code_lines = [line.split('#', 1)[0].rstrip() for line in build_source.splitlines()]
require(sum(bool(re.search(r'&\s*$', line)) for line in code_lines) >= 2, 'build.sh no longer launches both compilation jobs in parallel')
require(any(re.search(r'(^|[;&]\s*)wait(\s|$)', line) for line in code_lines), 'build.sh does not wait for its parallel jobs')

# Rebuild repeatedly from clean outputs and inspect each object. This exercises the
# formerly racing region rather than accepting pre-created artifacts.
for iteration in range(40):
    for name in ('a.o', 'b.o', 'server_bin'):
        try:
            (BUILD_DIR / name).unlink()
        except FileNotFoundError:
            pass
    result = subprocess.run([str(BUILD_SH)], cwd=BUILD_DIR, text=True, capture_output=True, timeout=20)
    require(result.returncode == 0, f'build.sh failed on stress iteration {iteration}:\n{result.stdout}\n{result.stderr}')
    for name in ('a.o', 'b.o', 'server_bin'):
        require((BUILD_DIR / name).is_file(), f'build.sh did not create {name}')
    a_symbols = run(['nm', str(BUILD_DIR / 'a.o')]).stdout
    b_symbols = run(['nm', str(BUILD_DIR / 'b.o')]).stdout
    require(re.search(r'\bpart_a$', a_symbols, re.M) is not None and re.search(r'\bpart_b$', a_symbols, re.M) is None,
            f'a.o has incorrect symbols on iteration {iteration}')
    require(re.search(r'\bpart_b$', b_symbols, re.M) is not None and re.search(r'\bpart_a$', b_symbols, re.M) is None,
            f'b.o has incorrect symbols on iteration {iteration}')

require(os.access(BUILD_DIR / 'server_bin', os.X_OK), 'server_bin is not executable')
require(run([str(BUILD_DIR / 'server_bin')], cwd=BUILD_DIR).stdout.strip() == 'OK', 'Generated server_bin does not run correctly')
require(SERVER_SH.is_file() and os.access(SERVER_SH, os.X_OK), 'server.sh is missing or not executable after the build')

# Preserve the original live-service assertions, using values obtained from OCR and
# the calculation rather than embedding them in the verifier.
status, body = raw_request(port, token)
require(status == 200, f'Expected HTTP 200 for the configured token, got {status}')
require(expected_factor in body, f'Expected {expected_factor!r} in response body, got {body!r}')
status, body = raw_request(port, 'INVALID-TOKEN')
require(status == 401, f'Expected HTTP 401 for an invalid token, got {status}')

# Ensure the listener is actually socat launched through the required server.sh with
# the extracted port/token/factor, rather than an unrelated hard-coded HTTP server.
provenance_ok = False
for pid in listener_pids(port):
    cmd = read_cmdline(pid)
    if any('socat' in Path(arg).name for arg in cmd) and has_expected_server_ancestor(pid, port, token, expected_factor):
        provenance_ok = True
        break
require(provenance_ok, 'Port listener was not launched by server.sh with the extracted configuration and calculated factor')

# Independently execute server.sh on unpredictable inputs so a server hard-coded only
# for the public deployment request cannot pass.
probe_socket = socket.socket()
probe_socket.bind(('127.0.0.1', 0))
probe_port = probe_socket.getsockname()[1]
probe_socket.close()
probe_token = 'VERIFY-' + secrets.token_hex(16)
probe_factor = 'FACTOR-' + secrets.token_hex(12)
proc = subprocess.Popen(
    [str(SERVER_SH), str(probe_port), probe_token, probe_factor],
    cwd=BUILD_DIR,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.PIPE,
    text=True,
    start_new_session=True,
)
try:
    deadline = time.time() + 5
    while time.time() < deadline:
        if proc.poll() is not None:
            err = proc.stderr.read() if proc.stderr else ''
            raise AssertionError(f'server.sh exited during dynamic probe: {err}')
        try:
            probe_status, probe_body = raw_request(probe_port, probe_token)
            break
        except (OSError, AssertionError):
            time.sleep(0.1)
    else:
        raise AssertionError('Dynamically launched server.sh did not begin listening')

    require(probe_status == 200, f'Dynamic valid-token probe returned {probe_status}')
    require(probe_factor in probe_body, f'Dynamic factor {probe_factor!r} was not returned: {probe_body!r}')
    for invalid in ('INVALID-' + secrets.token_hex(8), probe_token + '-WRONG'):
        bad_status, _ = raw_request(probe_port, invalid)
        require(bad_status == 401, f'Dynamic invalid-token probe returned {bad_status}')
finally:
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait(timeout=3)
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
