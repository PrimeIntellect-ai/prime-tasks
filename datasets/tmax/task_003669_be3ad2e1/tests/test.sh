#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import os
import re
import ssl
import stat
import time
import socket
import signal
import secrets
import shutil
import subprocess
import tempfile
from pathlib import Path

TLS_DIR = Path('/home/user/tls_web')
CERT = TLS_DIR / 'cert.pem'
KEY = TLS_DIR / 'key.pem'
INDEX = TLS_DIR / 'index.html'
BARE = Path('/home/user/monitor.git')
SRC = Path('/home/user/monitor_src')
DEPLOY = Path('/home/user/monitor_deploy')
HOOK = BARE / 'hooks/post-receive'
LOG = Path('/home/user/hook_output.log')
PORT_HEX = format(8443, '04X')

def run(cmd, **kwargs):
    kwargs.setdefault('text', True)
    kwargs.setdefault('stdout', subprocess.PIPE)
    kwargs.setdefault('stderr', subprocess.PIPE)
    kwargs.setdefault('timeout', 20)
    p = subprocess.run(cmd, **kwargs)
    if p.returncode != 0:
        raise AssertionError(f"Command failed ({p.returncode}): {cmd}\nstdout: {p.stdout}\nstderr: {p.stderr}")
    return p

def listener_pids():
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].split(':')[-1].upper() == PORT_HEX and fields[3] == '0A':
                inodes.add(fields[9])
    pids = set()
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / 'fd').iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                m = re.fullmatch(r'socket:\[(\d+)\]', target)
                if m and m.group(1) in inodes:
                    pids.add(int(proc.name))
        except OSError:
            pass
    return pids

def kill_listeners():
    for sig in (signal.SIGTERM, signal.SIGKILL):
        pids = listener_pids()
        if not pids:
            return
        for pid in pids:
            if pid != os.getpid():
                try:
                    os.kill(pid, sig)
                except ProcessLookupError:
                    pass
        time.sleep(0.5)
    assert not listener_pids(), 'Could not stop the process listening on port 8443'

def wait_port(up=True, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(('127.0.0.1', 8443), timeout=0.3):
                if up:
                    return
        except OSError:
            if not up:
                return
        time.sleep(0.1)
    raise AssertionError(f"Port 8443 did not become {'available' if up else 'closed'}")

def https_get():
    context = ssl._create_unverified_context()
    with socket.create_connection(('127.0.0.1', 8443), timeout=4) as raw:
        with context.wrap_socket(raw, server_hostname='127.0.0.1') as conn:
            request = b'GET /index.html HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n'
            conn.sendall(request)
            data = b''
            while True:
                chunk = conn.recv(65536)
                if not chunk:
                    break
                data += chunk
    head, sep, body = data.partition(b'\r\n\r\n')
    assert sep, f'HTTPS server returned a malformed HTTP response: {data!r}'
    status = int(head.splitlines()[0].split()[1])
    return status, body

def peer_der():
    context = ssl._create_unverified_context()
    with socket.create_connection(('127.0.0.1', 8443), timeout=4) as raw:
        with context.wrap_socket(raw, server_hostname='127.0.0.1') as conn:
            return conn.getpeercert(binary_form=True)

def assert_elf_and_curl(path):
    assert path.is_file(), f'Compiled binary {path} does not exist.'
    st = path.stat()
    assert bool(st.st_mode & stat.S_IXUSR), f'Compiled binary {path} is not executable.'
    assert path.read_bytes()[:4] == b'\x7fELF', f'{path} is not a compiled ELF executable.'
    linked = run(['ldd', str(path)]).stdout.lower()
    assert 'libcurl' in linked, f'{path} is not linked against libcurl.'

def checker_output(path, expected):
    p = subprocess.run([str(path)], cwd=str(DEPLOY), text=True, stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, timeout=12)
    assert p.returncode == 0, f'{path} failed: {p.stderr}'
    assert p.stdout == f'STATUS: {expected}\n', f'Unexpected checker output: {p.stdout!r}'

restored_server = None
server_was_replaced = False
controlled = None
work = Path(tempfile.mkdtemp(prefix='verifier-monitor-'))
try:
    # Preserve and strengthen the original file/executable assertions.
    assert CERT.is_file(), f'Certificate file {CERT} does not exist.'
    assert KEY.is_file(), f'Key file {KEY} does not exist.'
    assert INDEX.is_file(), f'Index file {INDEX} does not exist.'
    assert INDEX.stat().st_size == 0, f'{INDEX} is not empty.'
    assert HOOK.is_file(), f'Git hook {HOOK} does not exist.'
    assert bool(HOOK.stat().st_mode & stat.S_IXUSR), f'Git hook {HOOK} is not executable.'
    assert (DEPLOY / 'checker.c').is_file(), f'Deployed source {DEPLOY / "checker.c"} does not exist.'
    assert_elf_and_curl(DEPLOY / 'checker')
    assert LOG.is_file(), f'Log file {LOG} does not exist.'
    original_log = LOG.read_text()
    assert 'STATUS: 200' in original_log, f"Log file {LOG} does not contain 'STATUS: 200'."

    # Validate that the key and certificate are real, matching, and self-signed.
    run(['openssl', 'x509', '-in', str(CERT), '-noout'])
    run(['openssl', 'pkey', '-in', str(KEY), '-noout'])
    cert_pub = run(['openssl', 'x509', '-in', str(CERT), '-pubkey', '-noout']).stdout
    key_pub = run(['openssl', 'pkey', '-in', str(KEY), '-pubout']).stdout
    assert cert_pub == key_pub, 'cert.pem and key.pem do not form a matching key pair.'
    run(['openssl', 'verify', '-CAfile', str(CERT), str(CERT)])
    subject = run(['openssl', 'x509', '-in', str(CERT), '-noout', '-subject', '-nameopt', 'RFC2253']).stdout.strip()
    issuer = run(['openssl', 'x509', '-in', str(CERT), '-noout', '-issuer', '-nameopt', 'RFC2253']).stdout.strip()
    assert subject.removeprefix('subject=') == issuer.removeprefix('issuer='), 'Certificate is not self-signed.'

    # Exercise the agent's running TLS server and ensure it presents this certificate.
    wait_port(True)
    assert peer_der() == ssl.PEM_cert_to_DER_cert(CERT.read_text()), 'Port 8443 is not serving cert.pem.'
    status, body = https_get()
    assert status == 200, f'HTTPS server returned status {status}, not 200.'
    assert body == b'', f'HTTPS index response was not empty: {body!r}'

    # Validate the actual Git history and that the committed source was deployed.
    git_env = os.environ.copy()
    git_env['GIT_CONFIG_GLOBAL'] = str(work / 'gitconfig')
    run(['git', 'config', '--global', '--add', 'safe.directory', '*'], env=git_env)
    assert run(['git', '--git-dir', str(BARE), 'rev-parse', '--is-bare-repository'], env=git_env).stdout.strip() == 'true'
    bare_head = run(['git', '--git-dir', str(BARE), 'rev-parse', 'refs/heads/master'], env=git_env).stdout.strip()
    src_head = run(['git', '-C', str(SRC), 'rev-parse', 'HEAD'], env=git_env).stdout.strip()
    assert src_head == bare_head, 'monitor_src HEAD was not pushed to the bare repository master branch.'
    committed = subprocess.run(['git', '--git-dir', str(BARE), 'show', 'master:checker.c'],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20).stdout
    assert committed, 'checker.c is not committed on master.'
    assert committed == (SRC / 'checker.c').read_bytes(), 'monitor_src/checker.c differs from the pushed commit.'
    assert committed == (DEPLOY / 'checker.c').read_bytes(), 'The pushed checker.c was not checked out into monitor_deploy.'
    source_text = committed.decode('utf-8', errors='replace')
    for token in ('https://127.0.0.1:8443/index.html', 'CURLOPT_SSL_VERIFYPEER', 'CURLINFO_RESPONSE_CODE'):
        assert token in source_text, f'checker.c does not contain required libcurl operation {token!r}.'

    # Independently compile the submitted source with libcurl.
    independent = work / 'checker-independent'
    run(['gcc', str(SRC / 'checker.c'), '-o', str(independent), '-lcurl'])
    assert_elf_and_curl(independent)
    checker_output(independent, 200)
    checker_output(DEPLOY / 'checker', 200)

    # Replace the server temporarily with a self-signed HTTPS responder whose status
    # is selected only after the submission, rejecting hardcoded STATUS: 200 output.
    kill_listeners()
    server_was_replaced = True
    status_file = work / 'status'
    status_server = work / 'status_server.py'
    status_server.write_text('''import http.server, ssl, sys\nstatus_file, cert, key = sys.argv[1:]\nclass H(http.server.BaseHTTPRequestHandler):\n    def do_GET(self):\n        self.send_response(int(open(status_file).read()))\n        self.send_header("Content-Length", "0")\n        self.end_headers()\n    def log_message(self, *args): pass\ns = http.server.ThreadingHTTPServer(("127.0.0.1", 8443), H)\nc = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)\nc.load_cert_chain(cert, key)\ns.socket = c.wrap_socket(s.socket, server_side=True)\ns.serve_forever()\n''')
    choices = [201, 202, 418, 429, 503]
    first = secrets.choice(choices)
    second = secrets.choice([x for x in choices if x != first])
    status_file.write_text(str(first))
    controlled = subprocess.Popen(['python3', str(status_server), str(status_file), str(CERT), str(KEY)],
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    wait_port(True)
    checker_output(independent, first)
    checker_output(DEPLOY / 'checker', first)
    status_file.write_text(str(second))
    checker_output(independent, second)
    checker_output(DEPLOY / 'checker', second)

    # Make a fresh push containing a uniquely marked, valid libcurl checker. This
    # directly exercises checkout, gcc -lcurl, execution, and log redirection by the hook.
    hook_status = secrets.choice([x for x in choices if x not in (first, second)])
    status_file.write_text(str(hook_status))
    clone = work / 'hook-clone'
    run(['git', 'clone', str(BARE), str(clone)], env=git_env)
    run(['git', '-C', str(clone), 'config', 'user.email', 'verifier@local'], env=git_env)
    run(['git', '-C', str(clone), 'config', 'user.name', 'Verifier'], env=git_env)
    marker = 'VERIFIER_BUILD_' + secrets.token_hex(12)
    generated = f'''#include <curl/curl.h>\n#include <stdio.h>\nvolatile const char verifier_marker[] = "{marker}";\nstatic size_t discard(void *p, size_t s, size_t n, void *u) {{ (void)p; (void)u; return s*n; }}\nint main(void) {{\n  CURL *c; long code = 0;\n  if (curl_global_init(CURL_GLOBAL_DEFAULT) != CURLE_OK) return 2;\n  c = curl_easy_init(); if (!c) return 3;\n  curl_easy_setopt(c, CURLOPT_URL, "https://127.0.0.1:8443/index.html");\n  curl_easy_setopt(c, CURLOPT_SSL_VERIFYPEER, 0L);\n  curl_easy_setopt(c, CURLOPT_WRITEFUNCTION, discard);\n  if (curl_easy_perform(c) != CURLE_OK) return 4;\n  if (curl_easy_getinfo(c, CURLINFO_RESPONSE_CODE, &code) != CURLE_OK) return 5;\n  printf("STATUS: %ld\\n", code);\n  curl_easy_cleanup(c); curl_global_cleanup(); return 0;\n}}\n'''
    (clone / 'checker.c').write_text(generated)
    (clone / 'verifier_nonce').write_text(marker + '\n')
    run(['git', '-C', str(clone), 'add', 'checker.c', 'verifier_nonce'], env=git_env)
    run(['git', '-C', str(clone), 'commit', '-m', 'Verifier hook exercise'], env=git_env)
    run(['git', '-C', str(clone), 'push', 'origin', 'master'], env=git_env, timeout=30)

    assert (DEPLOY / 'checker.c').read_text() == generated, 'post-receive did not check out the newly pushed checker.c.'
    assert_elf_and_curl(DEPLOY / 'checker')
    assert marker.encode() in (DEPLOY / 'checker').read_bytes(), 'Deployed checker was not compiled from the pushed source.'
    checker_output(DEPLOY / 'checker', hook_status)
    assert LOG.read_text() == f'STATUS: {hook_status}\n', 'Hook did not execute checker and redirect its exact output to hook_output.log.'
finally:
    if controlled is not None:
        controlled.terminate()
        try:
            controlled.wait(timeout=3)
        except subprocess.TimeoutExpired:
            controlled.kill()
    if server_was_replaced and CERT.is_file() and KEY.is_file():
        kill_listeners()
        restore_script = work / 'restore_https.py'
        restore_script.write_text('''import http.server, ssl, os\nos.chdir("/home/user/tls_web")\ns=http.server.ThreadingHTTPServer(("127.0.0.1",8443),http.server.SimpleHTTPRequestHandler)\nc=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)\nc.load_cert_chain("cert.pem","key.pem")\ns.socket=c.wrap_socket(s.socket,server_side=True)\ns.serve_forever()\n''')
        restored_server = subprocess.Popen(['python3', str(restore_script)], stdout=subprocess.DEVNULL,
                                           stderr=subprocess.DEVNULL, start_new_session=True)
        try:
            wait_port(True, timeout=5)
        except Exception:
            pass
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
