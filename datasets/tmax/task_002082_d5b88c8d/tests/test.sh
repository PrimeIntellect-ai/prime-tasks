#!/bin/bash
set -e
mkdir -p /logs/verifier

backup="/tmp/legacy_cert_gen.verifier.$$"
mv /app/legacy_cert_gen "$backup"
cleanup() {
    rm -f /app/legacy_cert_gen
    if [ -f "$backup" ]; then
        mv "$backup" /app/legacy_cert_gen
    fi
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import socket
import subprocess
import tempfile
import threading
import uuid
from pathlib import Path

SCRIPT = '/home/user/policy_enforcer.sh'
GENERATOR = '/app/legacy_cert_gen'


def test_policy_enforcer_script_exists_and_executable():
    """Check if the agent created the policy enforcer script and made it executable."""
    assert os.path.isfile(SCRIPT), f"Agent script {SCRIPT} is missing."
    assert os.access(SCRIPT, os.X_OK), f"Agent script {SCRIPT} is not executable."


def test_policy_enforcer_accuracy():
    """Retain the original setup-provided accuracy assertion."""
    eval_script = '/eval/test_accuracy.py'
    assert os.path.isfile(eval_script), f"Evaluation script {eval_script} is missing."

    result = subprocess.run(['python3', eval_script], capture_output=True, text=True)
    accuracy_match = re.search(r'(?i)accuracy.*?([0-9]*\.?[0-9]+)', result.stdout)
    if accuracy_match:
        accuracy = float(accuracy_match.group(1))
        assert accuracy >= 0.98, f"Accuracy {accuracy} is below the threshold of 0.98. Output: {result.stdout}"
    else:
        assert result.returncode == 0, f"Accuracy test failed. Output: {result.stdout}\nError: {result.stderr}"


def make_cert(directory, name, kind='rsa', bits=2048, digest='sha256', days=45):
    cert = directory / f'{name}.crt'
    key = directory / f'{name}.key'
    if kind == 'rsa':
        cmd = [
            'openssl', 'req', '-x509', '-newkey', f'rsa:{bits}', '-nodes',
            '-subj', f'/CN={name}.internal', f'-{digest}', '-days', str(days),
            '-keyout', str(key), '-out', str(cert),
        ]
    else:
        cmd = [
            'openssl', 'req', '-x509', '-newkey', 'ec',
            '-pkeyopt', 'ec_paramgen_curve:prime256v1', '-nodes',
            '-subj', f'/CN={name}.internal', f'-{digest}', '-days', str(days),
            '-keyout', str(key), '-out', str(cert),
        ]
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return cert.read_text(), key.read_text()


def install_generator(cert=None, key=None, exit_code=0, malformed=False,
                      isolation_bad_cert=None, canary=None, port=None):
    if malformed:
        cert = '-----BEGIN CERTIFICATE-----\nnot-a-certificate\n-----END CERTIFICATE-----\n'
        key = '-----BEGIN PRIVATE KEY-----\ninvalid\n-----END PRIVATE KEY-----\n'

    cert = cert or ''
    key = key or ''
    bad = isolation_bad_cert or cert

    source = f'''\n#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <arpa/inet.h>

static const char CERT_OK[] = {json.dumps(cert)};
static const char CERT_BAD[] = {json.dumps(bad)};
static const char KEY_DATA[] = {json.dumps(key)};

int main(int argc, char **argv) {{
    int breached = 0;
'''
    if canary is not None:
        source += f'''\n    FILE *probe = fopen({json.dumps(canary)}, "r");
    if (probe) {{ breached = 1; fclose(probe); }}
'''
    if port is not None:
        source += f'''\n    alarm(3);
    int s = socket(AF_INET, SOCK_STREAM, 0);
    if (s >= 0) {{
        struct sockaddr_in a;
        a.sin_family = AF_INET;
        a.sin_port = htons({port});
        a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        if (connect(s, (struct sockaddr *)&a, sizeof(a)) == 0) breached = 1;
        close(s);
    }}
    alarm(0);
'''
    if exit_code:
        source += f'    return {exit_code};\n}}\n'
    else:
        source += '''
    FILE *c = fopen("cert.pem", "w");
    if (!c) return 20;
    fputs(breached ? CERT_BAD : CERT_OK, c);
    fclose(c);
    FILE *k = fopen("key.pem", "w");
    if (!k) return 21;
    fputs(KEY_DATA, k);
    fclose(k);
    return 0;
}
'''

    with tempfile.TemporaryDirectory() as td:
        src = Path(td) / 'gen.c'
        out = Path(td) / 'legacy_cert_gen'
        src.write_text(source)
        subprocess.run(['gcc', '-static', '-O2', '-s', '-o', str(out), str(src)], check=True)
        os.chmod(out, 0o755)
        os.replace(out, GENERATOR)


def invoke(domain, expected_code, expected_line, require_cleanup=False):
    with tempfile.TemporaryDirectory() as cwd:
        result = subprocess.run(
            [SCRIPT, domain], cwd=cwd, capture_output=True, text=True, timeout=20
        )
        assert result.returncode == expected_code, (
            f'Unexpected exit code for {domain}: {result.returncode}\n'
            f'stdout={result.stdout!r}\nstderr={result.stderr!r}'
        )
        assert result.stdout.strip() == expected_line, (
            f'Unexpected stdout for {domain}: {result.stdout!r}; stderr={result.stderr!r}'
        )
        if require_cleanup:
            assert not (Path(cwd) / 'cert.pem').exists(), 'cert.pem was not deleted after failure'
            assert not (Path(cwd) / 'key.pem').exists(), 'key.pem was not deleted after failure'


def test_policy_enforcer_behavior_and_isolation():
    token = uuid.uuid4().hex
    with tempfile.TemporaryDirectory() as fixture_dir_name:
        fixture_dir = Path(fixture_dir_name)
        valid256 = make_cert(fixture_dir, 'valid256', digest='sha256', days=31)
        valid512 = make_cert(fixture_dir, 'valid512', digest='sha512', days=397)
        weak_key = make_cert(fixture_dir, 'weakkey', bits=1024, digest='sha256', days=45)
        ec_key = make_cert(fixture_dir, 'eckey', kind='ec', digest='sha256', days=45)
        sha1 = make_cert(fixture_dir, 'sha1', digest='sha1', days=45)
        too_short = make_cert(fixture_dir, 'short', digest='sha256', days=29)
        too_long = make_cert(fixture_dir, 'long', digest='sha256', days=398)
        isolated_valid = make_cert(fixture_dir, 'isolated', digest='sha256', days=45)

        install_generator(*valid256)
        invoke(f'valid-a-{token}.internal', 0, f'PASS: valid-a-{token}.internal')

        install_generator(*valid512)
        invoke(f'valid-b-{token}.internal', 0, f'PASS: valid-b-{token}.internal')

        for label, fixture in [
            ('weak-rsa', weak_key),
            ('ec', ec_key),
            ('sha1', sha1),
            ('short', too_short),
            ('long', too_long),
        ]:
            install_generator(*fixture)
            domain = f'{label}-{token}.internal'
            invoke(domain, 1, f'FAIL: {domain}', require_cleanup=True)

        install_generator(malformed=True)
        domain = f'malformed-{token}.internal'
        invoke(domain, 1, f'FAIL: {domain}', require_cleanup=True)

        install_generator(exit_code=7)
        domain = f'crash-{token}.internal'
        invoke(domain, 1, f'FAIL: {domain}', require_cleanup=True)

        canary = f'/policy_isolation_canary_{token}'
        Path(canary).write_text('outside data must not be readable')
        listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind(('127.0.0.1', 0))
        listener.listen(5)
        listener.settimeout(10)
        port = listener.getsockname()[1]

        def accept_once():
            try:
                conn, _ = listener.accept()
                conn.close()
            except (OSError, socket.timeout):
                pass

        thread = threading.Thread(target=accept_once, daemon=True)
        thread.start()
        try:
            install_generator(
                *isolated_valid,
                isolation_bad_cert=sha1[0],
                canary=canary,
                port=port,
            )
            domain = f'isolation-{token}.internal'
            invoke(domain, 0, f'PASS: {domain}')
        finally:
            listener.close()
            thread.join(timeout=1)
            Path(canary).unlink(missing_ok=True)

        install_generator(*valid256)
        with tempfile.TemporaryDirectory() as cwd:
            no_arg = subprocess.run([SCRIPT], cwd=cwd, capture_output=True, text=True, timeout=20)
            assert no_arg.returncode != 0, 'The script accepted zero arguments'
            two_args = subprocess.run(
                [SCRIPT, f'one-{token}.internal', f'two-{token}.internal'],
                cwd=cwd, capture_output=True, text=True, timeout=20
            )
            assert two_args.returncode != 0, 'The script accepted more than one argument'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
