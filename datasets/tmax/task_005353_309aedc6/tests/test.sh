#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import shlex
import socket
import ssl
import stat
import subprocess
import tempfile
import urllib.request
import uuid


def run_checked(args, **kwargs):
    return subprocess.run(args, check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, **kwargs)


def test_compilation():
    setup_bin = '/home/user/bin/setup'
    assert os.path.isfile(setup_bin), f"Compiled binary {setup_bin} does not exist."
    st = os.stat(setup_bin)
    assert bool(st.st_mode & stat.S_IXUSR), f"Binary {setup_bin} is not executable."

    with open(setup_bin, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"{setup_bin} is not a compiled ELF executable."

    token = uuid.uuid4().hex
    username = f'verify_{token}'
    password = f'pw_{token}_X9'
    with tempfile.TemporaryDirectory() as td:
        output_db = os.path.join(td, 'users.db')
        proc = subprocess.run(
            [setup_bin, output_db],
            input=f'9922\n{username}\n{password}\n',
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert proc.returncode == 0, f"Compiled setup program failed: {proc.stderr}"
        assert 'Enter admin pin: ' in proc.stdout
        assert 'Enter new username: ' in proc.stdout
        assert 'Enter new password: ' in proc.stdout
        assert 'Database created successfully.' in proc.stdout
        assert os.path.isfile(output_db), "Compiled setup program did not create its requested database."
        with open(output_db, 'r') as f:
            assert f.read() == f'USER:{username}|PASS:{password}\n', \
                "Compiled setup program did not process derived credentials correctly."


def test_directories_and_symlink():
    dirs = [
        '/home/user/deploy/webroot',
        '/home/user/deploy/certs',
        '/home/user/shared_assets'
    ]
    for d in dirs:
        assert os.path.isdir(d), f"Directory {d} does not exist."

    symlink = '/home/user/deploy/webroot/assets'
    assert os.path.islink(symlink), f"{symlink} is not a symlink."
    assert os.readlink(symlink) == '/home/user/shared_assets', \
        f"Symlink {symlink} does not point to /home/user/shared_assets."

    test_file = '/home/user/shared_assets/test.txt'
    assert os.path.isfile(test_file), f"Test file {test_file} does not exist."
    with open(test_file, 'r') as f:
        content = f.read().strip()
    assert content == 'Assets working', f"Test file content is incorrect: {content}"


def test_expect_script_and_db():
    expect_script = '/home/user/bin/run_setup.exp'
    setup_bin = '/home/user/bin/setup'
    db_file = '/home/user/deploy/users.db'
    assert os.path.isfile(expect_script), f"Expect script {expect_script} does not exist."

    suffix = uuid.uuid4().hex
    real_bin = f'/tmp/setup.real.{suffix}'
    marker = f'/tmp/setup.marker.{suffix}'
    previous_db = None
    if os.path.isfile(db_file):
        with open(db_file, 'rb') as f:
            previous_db = f.read()

    os.replace(setup_bin, real_bin)
    wrapper = '#!/bin/sh\nprintf \'%s\\n\' "$@" > ' + shlex.quote(marker) + \
              '\nexec ' + shlex.quote(real_bin) + ' "$@"\n'
    try:
        with open(setup_bin, 'w') as f:
            f.write(wrapper)
        os.chmod(setup_bin, 0o755)
        if os.path.exists(db_file):
            os.unlink(db_file)

        proc = subprocess.run(
            ['expect', expect_script],
            cwd='/home/user',
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert proc.returncode == 0, \
            f"Expect script failed when executed:\nstdout: {proc.stdout}\nstderr: {proc.stderr}"
        assert os.path.isfile(marker), \
            "Expect script did not launch /home/user/bin/setup."
        with open(marker, 'r') as f:
            invoked_args = f.read().splitlines()
        assert invoked_args == [db_file], \
            f"Expect script invoked setup with incorrect arguments: {invoked_args}"
        assert os.path.isfile(db_file), \
            "Running the Expect script did not generate the database."
        with open(db_file, 'r') as f:
            content = f.read()
        assert content == 'USER:app_admin|PASS:SecureDeploy2024\n', \
            "Database generated through Expect has incorrect contents."
    finally:
        if os.path.lexists(setup_bin):
            os.unlink(setup_bin)
        os.replace(real_bin, setup_bin)
        if os.path.exists(marker):
            os.unlink(marker)
        if not os.path.isfile(db_file) and previous_db is not None:
            with open(db_file, 'wb') as f:
                f.write(previous_db)


def test_tls_certs():
    cert_file = '/home/user/deploy/certs/cert.pem'
    key_file = '/home/user/deploy/certs/key.pem'
    assert os.path.isfile(cert_file), f"Certificate file {cert_file} does not exist."
    assert os.path.isfile(key_file), f"Key file {key_file} does not exist."

    run_checked(['openssl', 'x509', '-in', cert_file, '-noout'])
    run_checked(['openssl', 'rsa', '-in', key_file, '-check', '-noout'])
    run_checked(['openssl', 'verify', '-CAfile', cert_file, cert_file])

    subject = run_checked([
        'openssl', 'x509', '-in', cert_file, '-noout',
        '-subject', '-nameopt', 'RFC2253'
    ]).stdout.decode()
    assert 'CN=localhost' in subject, f"Certificate subject is not for localhost: {subject}"

    key_text = run_checked([
        'openssl', 'rsa', '-in', key_file, '-text', '-noout'
    ]).stdout.decode()
    assert '2048 bit' in key_text, "Private key is not a 2048-bit RSA key."

    cert_pub_pem = run_checked([
        'openssl', 'x509', '-in', cert_file, '-pubkey', '-noout'
    ]).stdout
    cert_pub_der = run_checked(
        ['openssl', 'pkey', '-pubin', '-outform', 'DER'], input=cert_pub_pem
    ).stdout
    key_pub_der = run_checked([
        'openssl', 'pkey', '-in', key_file, '-pubout', '-outform', 'DER'
    ]).stdout
    assert cert_pub_der == key_pub_der, "Certificate and private key do not match."


def test_web_server():
    url = 'https://localhost:8443/assets/test.txt'
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    try:
        req = urllib.request.urlopen(url, context=ctx, timeout=5)
        content = req.read().decode('utf-8').strip()
        assert 'Assets working' in content, \
            "Web server did not return the expected content from the symlinked directory."
    except Exception as e:
        assert False, f"Failed to connect to the web server or retrieve the file: {e}"

    cert_file = '/home/user/deploy/certs/cert.pem'
    with open(cert_file, 'r') as f:
        expected_der = ssl.PEM_cert_to_DER_cert(f.read())
    with socket.create_connection(('localhost', 8443), timeout=5) as raw:
        with ctx.wrap_socket(raw, server_hostname='localhost') as tls_sock:
            served_der = tls_sock.getpeercert(binary_form=True)
    assert hashlib.sha256(served_der).digest() == hashlib.sha256(expected_der).digest(), \
        "The HTTPS server is not using /home/user/deploy/certs/cert.pem."

    matching_processes = []
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        try:
            with open(f'/proc/{entry}/cmdline', 'rb') as f:
                argv = [p for p in f.read().split(b'\0') if p]
            if not argv:
                continue
            executable = os.path.basename(argv[0].decode(errors='ignore'))
            if executable == 'openssl' and b's_server' in argv and b'-WWW' in argv \
                    and any(b'8443' in arg for arg in argv):
                cwd = os.path.realpath(f'/proc/{entry}/cwd')
                matching_processes.append((entry, cwd))
        except (FileNotFoundError, PermissionError, OSError):
            pass

    assert matching_processes, \
        "No background openssl s_server -WWW process serving port 8443 was found."
    assert any(cwd == '/home/user/deploy/webroot' for _, cwd in matching_processes), \
        "The openssl s_server process is not serving from /home/user/deploy/webroot."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
