#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import hashlib
import os
import secrets
import stat
import subprocess
import tempfile


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def openssl_der(cmd):
    result = subprocess.run(cmd, capture_output=True)
    assert result.returncode == 0, result.stderr.decode(errors='replace')
    return result.stdout


def test_pki_certificates():
    """Verify certificate identity, key size, lifetime, and key matching."""
    pki_dir = '/home/user/pki'
    crt_file = os.path.join(pki_dir, 'server.crt')
    key_file = os.path.join(pki_dir, 'server.key')

    assert os.path.isdir(pki_dir), f"Directory {pki_dir} does not exist."
    assert os.path.isfile(crt_file), f"Certificate {crt_file} does not exist."
    assert os.path.isfile(key_file), f"Private key {key_file} does not exist."

    result = run(['openssl', 'x509', '-in', crt_file, '-noout', '-text'])
    assert result.returncode == 0, f"Failed to parse certificate {crt_file}."
    assert "CN = localhost" in result.stdout or "CN=localhost" in result.stdout, "Certificate does not have CN=localhost."
    assert 'Public-Key: (2048 bit)' in result.stdout, "Certificate does not contain a 2048-bit RSA public key."

    result_key = run(['openssl', 'rsa', '-in', key_file, '-check', '-noout'])
    assert result_key.returncode == 0, f"Private key {key_file} is invalid."
    key_text = run(['openssl', 'rsa', '-in', key_file, '-noout', '-text'])
    assert key_text.returncode == 0
    assert 'Private-Key: (2048 bit' in key_text.stdout, "Private key is not 2048-bit RSA."

    dates = run(['openssl', 'x509', '-in', crt_file, '-noout', '-startdate', '-enddate'])
    assert dates.returncode == 0
    values = dict(line.strip().split('=', 1) for line in dates.stdout.splitlines() if '=' in line)
    not_before = datetime.datetime.strptime(values['notBefore'], '%b %d %H:%M:%S %Y %Z').replace(tzinfo=datetime.timezone.utc)
    not_after = datetime.datetime.strptime(values['notAfter'], '%b %d %H:%M:%S %Y %Z').replace(tzinfo=datetime.timezone.utc)
    lifetime = (not_after - not_before).total_seconds()
    assert abs(lifetime - 365 * 24 * 60 * 60) <= 5, "Certificate is not valid for 365 days."
    now = datetime.datetime.now(datetime.timezone.utc)
    assert not_before <= now <= not_after, "Certificate is not currently valid."

    cert_pub = openssl_der(['openssl', 'x509', '-in', crt_file, '-pubkey', '-noout'])
    cert_pub_der = subprocess.run(
        ['openssl', 'pkey', '-pubin', '-outform', 'DER'], input=cert_pub, capture_output=True
    )
    assert cert_pub_der.returncode == 0
    key_pub_der = openssl_der(['openssl', 'pkey', '-in', key_file, '-pubout', '-outform', 'DER'])
    assert hashlib.sha256(cert_pub_der.stdout).digest() == hashlib.sha256(key_pub_der).digest(), \
        "Certificate and private key do not match."

    verified = run(['openssl', 'verify', '-CAfile', crt_file, crt_file])
    assert verified.returncode == 0, "Certificate is not a valid self-signed certificate."


def assert_server_behavior(binary):
    nonce = secrets.token_hex(24)
    cases = [
        (f'{nonce}|sig:VALID_MAC', 0),
        (f'{nonce}|sig:none', 1),
        (f'{nonce}|sig:{secrets.token_hex(20)}', 1),
        (f'{nonce}|sig:VALID_MAC{secrets.token_hex(8)}', 1),
        (f'{nonce}|sig:VALID_MAC|extra:{secrets.token_hex(8)}', 1),
        (f'{nonce}|sig:none|extra:{secrets.token_hex(8)}', 1),
        (secrets.token_hex(32), 1),
    ]
    for token, expected in cases:
        result = run([binary, token], timeout=5)
        assert result.returncode == expected, f"Incorrect validation result for randomized token {token!r}."


def test_server_binary_behavior():
    """Verify both the submitted executable and patched source implement strict validation."""
    binary = '/home/user/server'
    source = '/home/user/server.cpp'
    assert os.path.isfile(binary), f"Compiled binary {binary} does not exist."
    assert os.access(binary, os.X_OK), f"Binary {binary} is not executable."
    assert os.path.isfile(source), f"Patched source {source} does not exist."
    with open(binary, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "Compiled server is not an ELF binary."

    res_bypass = run([binary, 'admin|sig:none'])
    assert res_bypass.returncode == 1, "Server still accepts 'admin|sig:none' (vulnerability not patched)."
    res_valid = run([binary, 'admin|sig:VALID_MAC'])
    assert res_valid.returncode == 0, "Server rejects valid token 'admin|sig:VALID_MAC'."
    assert_server_behavior(binary)

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, 'server')
        compiled = run(['g++', source, '-o', rebuilt], timeout=30)
        assert compiled.returncode == 0, f"Patched server.cpp does not compile: {compiled.stderr}"
        assert_server_behavior(rebuilt)


def test_sandbox_script():
    """Verify and execute the sandbox launcher with a recording bwrap shim."""
    script = '/home/user/run_secure.sh'
    assert os.path.isfile(script), f"Script {script} does not exist."
    assert os.access(script, os.X_OK), f"Script {script} is not executable."

    with open(script, 'r') as f:
        content = f.read()

    assert 'bwrap' in content, "Script does not use 'bwrap'."
    assert '--unshare-net' in content, "Script does not isolate network (--unshare-net)."
    assert '--ro-bind / /' in content, "Script does not mount root as read-only (--ro-bind / /)."
    assert '/home/user/server' in content, "Script does not execute /home/user/server."
    assert '--ro-bind /home/user/pki /home/user/pki' in content, \
        "Script does not bind mount /home/user/pki read-only."

    syntax = run(['bash', '-n', script])
    assert syntax.returncode == 0, f"Sandbox script has invalid shell syntax: {syntax.stderr}"

    with tempfile.TemporaryDirectory() as td:
        log = os.path.join(td, 'args')
        shim = os.path.join(td, 'bwrap')
        with open(shim, 'w') as f:
            f.write('#!/bin/sh\n: > "$BWRAP_LOG"\nfor arg in "$@"; do printf "%s\\n" "$arg" >> "$BWRAP_LOG"; done\nexit 0\n')
        os.chmod(shim, 0o755)
        env = os.environ.copy()
        env['PATH'] = td + os.pathsep + env.get('PATH', '')
        env['BWRAP_LOG'] = log
        invoked = run([script], env=env, timeout=10)
        assert invoked.returncode == 0, f"Sandbox launcher failed when bwrap was invoked: {invoked.stderr}"
        assert os.path.isfile(log), "Sandbox launcher did not execute bwrap."
        with open(log) as f:
            args = [line.rstrip('\n') for line in f]

    assert '--unshare-net' in args, "Executed bwrap command does not isolate the network."
    assert any(args[i:i+3] == ['--ro-bind', '/', '/'] for i in range(len(args) - 2)), \
        "Executed bwrap command does not mount root read-only."
    assert any(args[i:i+3] == ['--ro-bind', '/home/user/pki', '/home/user/pki'] for i in range(len(args) - 2)), \
        "Executed bwrap command does not bind mount the PKI directory read-only."
    assert '/home/user/server' in args, "Executed bwrap command does not launch /home/user/server."


def test_suid_audit():
    """Verify that the audit exactly reports the SUID files currently present."""
    audit_file = '/home/user/suid_audit.txt'
    assert os.path.isfile(audit_file), f"Audit file {audit_file} does not exist."

    with open(audit_file, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 1, f"Audit file should contain exactly 1 line, found {len(lines)}."
    assert lines[0] == '/home/user/test_env/fake_sudo', f"Audit file contains incorrect SUID file path: {lines[0]}."

    discovered = []
    for root, _, files in os.walk('/home/user/test_env'):
        for name in files:
            path = os.path.abspath(os.path.join(root, name))
            if os.stat(path, follow_symlinks=False).st_mode & stat.S_ISUID:
                discovered.append(path)
    assert sorted(lines) == sorted(discovered), "Audit does not exactly match the SUID files in test_env."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
