#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import secrets
import shutil
import stat
import subprocess
import tempfile


def get_expected_ips():
    log_path = '/home/user/access.log'
    if not os.path.exists(log_path):
        return []

    malicious_ips = set()
    with open(log_path, 'r') as f:
        for line in f:
            if 'UNION SELECT' in line:
                parts = line.split()
                if parts:
                    malicious_ips.add(parts[0])

    return sorted(list(malicious_ips))


def get_expected_ports():
    cert_dir = '/home/user/certs'
    expired_ports = []

    for cert_path in glob.glob(os.path.join(cert_dir, 'port_*.pem')):
        filename = os.path.basename(cert_path)
        port_str = filename.replace('port_', '').replace('.pem', '')
        try:
            port_num = int(port_str)
        except ValueError:
            continue

        result = subprocess.run(
            ['openssl', 'x509', '-checkend', '0', '-noout', '-in', cert_path],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        if result.returncode != 0:
            expired_ports.append(port_num)

    return sorted(expired_ports)


def expected_content():
    lines = ['#!/bin/bash', '# IP Blocklist']
    for ip in get_expected_ips():
        lines.append(f'iptables -A INPUT -s {ip} -j DROP')
    lines.append('# Port Blocklist')
    for port in get_expected_ports():
        lines.append(f'iptables -A INPUT -p tcp --dport {port} -j DROP')
    return '\n'.join(lines) + '\n'


def test_enforce_sh_exists_and_executable():
    script_path = '/home/user/enforce.sh'
    assert os.path.isfile(script_path), f"File {script_path} does not exist."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {script_path} is not executable."


def test_enforce_sh_content():
    script_path = '/home/user/enforce.sh'
    assert os.path.isfile(script_path), f"File {script_path} does not exist."

    expected = expected_content()
    with open(script_path, 'r') as f:
        actual_content = f.read()

    assert actual_content.strip() == expected.strip(), (
        f"Content of {script_path} does not match expected output.\n"
        f"Expected:\n{expected.strip()}\n"
        f"Actual:\n{actual_content.strip()}"
    )


def build_rust_binary(project):
    cargo_toml = os.path.join(project, 'Cargo.toml')
    assert os.path.isfile(cargo_toml), 'Cargo.toml is missing from the Rust project.'
    assert glob.glob(os.path.join(project, 'src', '**', '*.rs'), recursive=True), (
        'The Rust project contains no Rust source files under src/.'
    )

    metadata = subprocess.run(
        ['cargo', 'metadata', '--format-version', '1', '--no-deps'],
        cwd=project, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=120
    )
    assert metadata.returncode == 0, f'Invalid Cargo project:\n{metadata.stderr}'
    packages = json.loads(metadata.stdout).get('packages', [])
    assert any('bin' in target.get('kind', []) for p in packages for target in p.get('targets', [])), (
        'The Cargo project has no Rust binary target.'
    )

    build = subprocess.run(
        ['cargo', 'build', '--message-format=json'],
        cwd=project, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=180
    )
    assert build.returncode == 0, f'Rust project failed to build:\n{build.stderr}'

    executables = []
    for line in build.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        if message.get('reason') == 'compiler-artifact':
            target = message.get('target', {})
            executable = message.get('executable')
            if executable and 'bin' in target.get('kind', []):
                executables.append(executable)

    assert executables, 'Cargo did not produce a Rust binary executable.'
    binary = executables[0]
    assert os.path.isfile(binary) and os.access(binary, os.X_OK)
    return binary


def test_compiled_rust_program_generates_policy_from_inputs():
    project = '/home/user/policy_builder'
    binary = build_rust_binary(project)

    access_path = '/home/user/access.log'
    cert_dir = '/home/user/certs'
    enforce_path = '/home/user/enforce.sh'

    cert_files = glob.glob(os.path.join(cert_dir, 'port_*.pem'))
    expired = []
    valid = []
    for path in cert_files:
        result = subprocess.run(
            ['openssl', 'x509', '-checkend', '0', '-noout', '-in', path],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        (valid if result.returncode == 0 else expired).append(path)
    assert expired and valid, 'Test fixture must contain both expired and valid certificates.'

    access_data = open(access_path, 'rb').read()
    access_mode = stat.S_IMODE(os.stat(access_path).st_mode)
    enforce_data = open(enforce_path, 'rb').read()
    enforce_mode = stat.S_IMODE(os.stat(enforce_path).st_mode)
    backup_cert_dir = tempfile.mkdtemp(prefix='certs-backup-', dir='/home/user')
    os.rmdir(backup_cert_dir)
    os.rename(cert_dir, backup_cert_dir)

    try:
        os.mkdir(cert_dir)
        ports = set()
        while len(ports) < 4:
            ports.add(10000 + secrets.randbelow(50000))
        p1, p2, p3, p4 = list(ports)
        shutil.copy2(expired[0], os.path.join(cert_dir, f'port_{p1}.pem'))
        shutil.copy2(expired[0], os.path.join(cert_dir, f'port_{p2}.pem'))
        shutil.copy2(valid[0], os.path.join(cert_dir, f'port_{p3}.pem'))
        shutil.copy2(valid[0], os.path.join(cert_dir, f'port_{p4}.pem'))

        ip1 = f'198.51.100.{1 + secrets.randbelow(200)}'
        ip2 = f'203.0.113.{1 + secrets.randbelow(200)}'
        with open(access_path, 'w') as f:
            f.write(f'{ip2} - - "GET /?q=UNION SELECT secret" 403 0\n')
            f.write('192.0.2.10 - - "GET /normal" 200 1\n')
            f.write(f'{ip1} - - "POST / UNION SELECT data" 403 0\n')
            f.write(f'{ip2} - - "GET /again UNION SELECT data" 403 0\n')

        if os.path.lexists(enforce_path):
            os.unlink(enforce_path)

        run = subprocess.run(
            [binary], cwd=project, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120
        )
        assert run.returncode == 0, (
            f'Compiled Rust program failed when executed:\nstdout:\n{run.stdout}\nstderr:\n{run.stderr}'
        )
        assert os.path.isfile(enforce_path), 'The compiled Rust program did not create /home/user/enforce.sh.'

        expected = expected_content()
        with open(enforce_path, 'r') as f:
            actual = f.read()
        assert actual.strip() == expected.strip(), (
            'The compiled Rust program did not generate the policy for the runtime test inputs.\n'
            f'Expected:\n{expected.strip()}\nActual:\n{actual.strip()}'
        )
    finally:
        if os.path.lexists(cert_dir):
            shutil.rmtree(cert_dir)
        os.rename(backup_cert_dir, cert_dir)
        with open(access_path, 'wb') as f:
            f.write(access_data)
        os.chmod(access_path, access_mode)
        if os.path.lexists(enforce_path):
            os.unlink(enforce_path)
        with open(enforce_path, 'wb') as f:
            f.write(enforce_data)
        os.chmod(enforce_path, enforce_mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
