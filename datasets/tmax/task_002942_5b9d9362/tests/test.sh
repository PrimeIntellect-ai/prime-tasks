#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import stat
import subprocess
import uuid

SCRIPT_PATH = '/home/user/process_intercepts.sh'
INTERCEPTS_DIR = '/home/user/intercepts'
REDACTED_DIR = '/home/user/vuln_redacted'


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."


def test_script_uses_unshare():
    with open(SCRIPT_PATH, 'r') as f:
        content = f.read()
    assert re.search(r'unshare\s+-n\s+openssl', content), \
        "Script does not appear to use 'unshare -n openssl' for network isolation."


def key_bits(path):
    result = subprocess.run(
        ['/usr/bin/openssl', 'pkey', '-in', path, '-text', '-noout'],
        capture_output=True, text=True
    )
    assert result.returncode == 0, f"Could not inspect verifier fixture {path}: {result.stderr}"
    match = re.search(r'Private-Key:\s*\((\d+) bit', result.stdout + result.stderr)
    assert match, f"Could not determine key size for {path}"
    return int(match.group(1))


def redacted_copy(source):
    pattern = re.compile(
        rb'(-----BEGIN (?:RSA )?PRIVATE KEY-----\r?\n).*?'
        rb'(\r?\n-----END (?:RSA )?PRIVATE KEY-----)',
        re.DOTALL,
    )
    result, count = pattern.subn(rb'\1[REDACTED]\2', source)
    assert count >= 1, "Fixture did not contain a supported private-key block"
    return result


def make_fresh_corpus():
    shutil.rmtree(INTERCEPTS_DIR, ignore_errors=True)
    shutil.rmtree(REDACTED_DIR, ignore_errors=True)
    os.makedirs(INTERCEPTS_DIR)
    os.makedirs(REDACTED_DIR)

    # Runtime-random names prevent fixed filename solutions. Key sizes are later
    # recomputed from these files rather than trusted from this list.
    for bits in (2048, 1024, 2048, 1024):
        name = f"capture_{uuid.uuid4().hex}.pem"
        path = os.path.join(INTERCEPTS_DIR, name)
        result = subprocess.run([
            '/usr/bin/openssl', 'req', '-x509', '-nodes', '-days', '2',
            '-newkey', f'rsa:{bits}', '-keyout', path, '-out', path,
            '-subj', f'/CN={uuid.uuid4().hex}'
        ], capture_output=True, text=True)
        assert result.returncode == 0, result.stderr


def test_execution_dynamic_selection_isolation_and_exact_redaction():
    make_fresh_corpus()

    expected = {}
    for name in os.listdir(INTERCEPTS_DIR):
        path = os.path.join(INTERCEPTS_DIR, name)
        if name.endswith('.pem') and key_bits(path) == 1024:
            with open(path, 'rb') as f:
                expected[name] = redacted_copy(f.read())

    assert expected, "Verifier corpus unexpectedly has no weak keys"

    # Interpose unshare during execution. This both permits network namespace
    # isolation in restricted containers and records actual `unshare -n openssl`
    # invocations, so a comment containing that text is insufficient.
    unshare_path = shutil.which('unshare')
    assert unshare_path, "unshare is unavailable"
    real_unshare = unshare_path + '.verifier-real-' + uuid.uuid4().hex
    log_path = '/tmp/unshare-openssl-' + uuid.uuid4().hex + '.log'
    os.rename(unshare_path, real_unshare)
    wrapper = f'''#!/bin/bash
if [ "$1" = "-n" ]; then
    shift
    [ "$1" = "--" ] && shift
    if [ "$(basename -- "$1")" = "openssl" ]; then
        echo isolated >> {log_path!r}
        exec "$@"
    fi
fi
exec {real_unshare!r} "$@"
'''
    try:
        with open(unshare_path, 'w') as f:
            f.write(wrapper)
        os.chmod(unshare_path, 0o755)
        result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True)
    finally:
        if os.path.exists(unshare_path):
            os.remove(unshare_path)
        os.rename(real_unshare, unshare_path)

    assert result.returncode == 0, f"Script failed to execute. stderr: {result.stderr}"

    isolated_calls = 0
    if os.path.exists(log_path):
        with open(log_path) as f:
            isolated_calls = sum(1 for line in f if line.strip() == 'isolated')
        os.remove(log_path)
    pem_count = sum(name.endswith('.pem') for name in os.listdir(INTERCEPTS_DIR))
    assert isolated_calls >= pem_count, \
        "The script did not actually inspect every PEM through 'unshare -n openssl'."

    actual_names = set(os.listdir(REDACTED_DIR))
    assert actual_names == set(expected), \
        f"Expected dynamically identified weak files {set(expected)}, got {actual_names}."

    cert_pattern = re.compile(
        rb'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----', re.DOTALL
    )
    key_pattern = re.compile(
        rb'(-----BEGIN (?:RSA )?PRIVATE KEY-----)\r?\n(.*?)\r?\n'
        rb'(-----END (?:RSA )?PRIVATE KEY-----)', re.DOTALL
    )

    for name, expected_bytes in expected.items():
        out_path = os.path.join(REDACTED_DIR, name)
        assert os.path.isfile(out_path), f"{out_path} is missing."
        with open(out_path, 'rb') as f:
            actual = f.read()
        with open(os.path.join(INTERCEPTS_DIR, name), 'rb') as f:
            source = f.read()

        assert cert_pattern.findall(actual) == cert_pattern.findall(source), \
            f"Certificate block was not copied unchanged in {name}."
        match = key_pattern.search(actual)
        assert match is not None, f"Private key block missing or malformed in {name}."
        assert match.group(2).strip() == b'[REDACTED]', \
            f"Private key material was not properly redacted in {name}."
        assert actual == expected_bytes, \
            f"{name} differs from the source beyond the required key-body redaction."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
