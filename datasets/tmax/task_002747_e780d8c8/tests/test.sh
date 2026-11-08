#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import subprocess
import tempfile
from pathlib import Path

HOME = Path('/home/user')
APP = HOME / 'app'
SOURCE = HOME / 'compliance_auditor.c'
BINARY = HOME / 'compliance_auditor'
REPORT = HOME / 'audit_trail.txt'


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, timeout=30, **kwargs)


def execute_and_read(binary):
    if REPORT.exists():
        REPORT.unlink()
    run([str(binary)], cwd=str(HOME), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert REPORT.is_file(), 'Auditor did not generate /home/user/audit_trail.txt.'
    return REPORT.read_text()


def assert_exact_report(content, token, cert_status, matches):
    expected = (
        '[AUDIT REPORT]\n'
        f'AUTH_TOKEN: {token}\n'
        f'CERT_STATUS: {cert_status}\n'
        f'IDS_MATCHES: {matches}\n'
    )
    assert content == expected, f'Unexpected audit report.\nExpected:\n{expected!r}\nGot:\n{content!r}'


def test_compliance_auditor_files_exist():
    assert SOURCE.is_file(), f'C source file {SOURCE} does not exist.'
    assert BINARY.is_file(), f'Compiled binary {BINARY} does not exist.'
    assert os.access(BINARY, os.X_OK), f'File {BINARY} is not executable.'
    assert BINARY.read_bytes()[:4] == b'\x7fELF', 'Compiled auditor is not an ELF executable.'

    source_text = SOURCE.read_text(errors='replace')
    assert re.search(r'#\s*include\s*[<\"]regex\.h[>\"]', source_text), 'C source does not include regex.h.'
    assert re.search(r'\bregcomp\s*\(', source_text), 'C source does not compile a POSIX regular expression.'
    assert re.search(r'\bregexec\s*\(', source_text), 'C source does not execute a POSIX regular expression.'


def test_audit_trail_content():
    content = execute_and_read(BINARY)

    # Preserve the original assertions while ensuring the report was produced by execution.
    assert '[AUDIT REPORT]' in content, "Missing '[AUDIT REPORT]' header."
    assert 'AUTH_TOKEN: Z79_Compliance_Req' in content, 'Incorrect or missing AUTH_TOKEN.'
    assert 'CERT_STATUS: VALID' in content, 'Incorrect or missing CERT_STATUS.'
    assert 'IDS_MATCHES: 2' in content, 'Incorrect or missing IDS_MATCHES.'
    assert_exact_report(content, 'Z79_Compliance_Req', 'VALID', 2)


def test_dynamic_elf_certificate_and_regex_behavior():
    protected = ['legacy_endpoint', 'server.crt', 'ca.crt', 'traffic.log']

    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        backup = td / 'backup'
        backup.mkdir()
        for name in protected:
            shutil.copy2(APP / name, backup / name)

        rebuilt = td / 'compliance_auditor'
        compile_result = subprocess.run(
            ['gcc', str(SOURCE), '-o', str(rebuilt), '-lelf'],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, f'C source does not compile:\n{compile_result.stderr}'
        assert rebuilt.read_bytes()[:4] == b'\x7fELF'

        try:
            nonce = secrets.token_hex(8).upper()
            token = f'DYNAMIC_TOKEN_{nonce}'
            pattern = f'^(GET|POST).*ALERT_{nonce}.*'
            endpoint_source = td / 'dynamic_endpoint.c'
            endpoint_source.write_text(
                '#include <stdio.h>\n'
                f'const char audit_data[] __attribute__((section(".audit_config"))) = '
                f'"AUTH_TOKEN={token};IDS_PATTERN={pattern}";\n'
                'int main(void) { return 0; }\n'
            )
            run(['gcc', str(endpoint_source), '-o', str(APP / 'legacy_endpoint')],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

            desired_matches = secrets.randbelow(4) + 1
            lines = [f'GET /x/ALERT_{nonce}/item{i} HTTP/1.1' for i in range(desired_matches)]
            lines += [
                f'PUT /x/ALERT_{nonce} HTTP/1.1',
                f'XGET /x/ALERT_{nonce} HTTP/1.1',
                'GET /ordinary HTTP/1.1',
                f'post /x/ALERT_{nonce} HTTP/1.1',
            ]
            secrets.SystemRandom().shuffle(lines)
            (APP / 'traffic.log').write_text('\n'.join(lines) + '\n')
            expected_matches = sum(1 for line in lines if re.search(pattern, line))

            certdir = td / 'certs'
            certdir.mkdir()
            quiet = dict(stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                 '-keyout', str(certdir / 'valid_ca.key'), '-out', str(certdir / 'valid_ca.crt'),
                 '-days', '2', '-subj', '/CN=DynamicValidCA'], **quiet)
            run(['openssl', 'req', '-newkey', 'rsa:2048', '-nodes',
                 '-keyout', str(certdir / 'server.key'), '-out', str(certdir / 'server.csr'),
                 '-subj', '/CN=dynamic.local'], **quiet)
            run(['openssl', 'x509', '-req', '-in', str(certdir / 'server.csr'),
                 '-CA', str(certdir / 'valid_ca.crt'), '-CAkey', str(certdir / 'valid_ca.key'),
                 '-CAcreateserial', '-out', str(certdir / 'server.crt'), '-days', '2'], **quiet)
            run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                 '-keyout', str(certdir / 'wrong_ca.key'), '-out', str(certdir / 'wrong_ca.crt'),
                 '-days', '2', '-subj', '/CN=UnrelatedCA'], **quiet)

            shutil.copy2(certdir / 'server.crt', APP / 'server.crt')
            shutil.copy2(certdir / 'valid_ca.crt', APP / 'ca.crt')

            # Exercise both the submitted executable and a fresh build of its submitted C source.
            for executable in (BINARY, rebuilt):
                content = execute_and_read(executable)
                assert_exact_report(content, token, 'VALID', expected_matches)

            shutil.copy2(certdir / 'wrong_ca.crt', APP / 'ca.crt')
            for executable in (BINARY, rebuilt):
                content = execute_and_read(executable)
                assert_exact_report(content, token, 'INVALID', expected_matches)
        finally:
            for name in protected:
                shutil.copy2(backup / name, APP / name)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
