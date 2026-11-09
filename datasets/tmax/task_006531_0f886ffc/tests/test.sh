#!/bin/bash
mkdir -p /logs/verifier
printf '0\n' > /logs/verifier/reward.txt

CURL_LOG=/tmp/verifier-curl.log
CARGO_LOG=/tmp/verifier-cargo.log
: > "$CURL_LOG"
: > "$CARGO_LOG"

CURL_REAL="$(readlink -f "$(command -v curl)")"
CARGO_REAL="$(readlink -f "$(command -v cargo)")"
CURL_BACKUP="${CURL_REAL}.verifier-real.$$"
CARGO_BACKUP="${CARGO_REAL}.verifier-real.$$"

restore_tools() {
    if [ -f "$CURL_BACKUP" ]; then
        rm -f "$CURL_REAL"
        mv "$CURL_BACKUP" "$CURL_REAL"
    fi
    if [ -f "$CARGO_BACKUP" ]; then
        rm -f "$CARGO_REAL"
        mv "$CARGO_BACKUP" "$CARGO_REAL"
    fi
}
trap restore_tools EXIT

mv "$CURL_REAL" "$CURL_BACKUP" || exit 0
cat > "$CURL_REAL" <<EOF
#!/bin/bash
printf 'CALL %s ' "\$\$" >> '$CURL_LOG'
printf '%q ' "\$@" >> '$CURL_LOG'
printf '\n' >> '$CURL_LOG'
'$CURL_BACKUP' "\$@"
rc=\$?
printf 'RC %s %s\n' "\$\$" "\$rc" >> '$CURL_LOG'
exit \$rc
EOF
chmod 755 "$CURL_REAL"

mv "$CARGO_REAL" "$CARGO_BACKUP" || exit 0
cat > "$CARGO_REAL" <<EOF
#!/bin/bash
printf 'CALL %s ' "\$\$" >> '$CARGO_LOG'
printf '%q ' "\$@" >> '$CARGO_LOG'
printf '\n' >> '$CARGO_LOG'
'$CARGO_BACKUP' "\$@"
rc=\$?
printf 'RC %s %s\n' "\$\$" "\$rc" >> '$CARGO_LOG'
exit \$rc
EOF
chmod 755 "$CARGO_REAL"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import itertools
import json
import math
import os
import random
import socket
import subprocess
import time
import urllib.error
import urllib.request
from fractions import Fraction
from pathlib import Path

import pytest

SCRIPT = Path('/home/user/run_e2e.sh')
RESULTS = Path('/home/user/e2e_results.json')
PROJECT = Path('/home/user/math_api')
CURL_LOG = Path('/tmp/verifier-curl.log')
CARGO_LOG = Path('/tmp/verifier-cargo.log')


def port_is_open():
    with socket.socket() as sock:
        sock.settimeout(0.2)
        return sock.connect_ex(('127.0.0.1', 8123)) == 0


def successful_calls(path):
    calls = {}
    successful = set()
    for line in path.read_text(errors='replace').splitlines():
        if line.startswith('CALL '):
            parts = line.split(' ', 2)
            if len(parts) == 3:
                calls[parts[1]] = parts[2]
        elif line.startswith('RC '):
            parts = line.split()
            if len(parts) == 3 and parts[2] == '0':
                successful.add(parts[1])
    return [args for pid, args in calls.items() if pid in successful]


def request_json(url, body=None):
    headers = {}
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        headers['Content-Type'] = 'application/json'
    req = urllib.request.Request(url, data=data, headers=headers)
    with urllib.request.urlopen(req, timeout=3) as response:
        assert 200 <= response.status < 300
        return json.loads(response.read().decode())


def collatz_length(n):
    start = n
    length = 0
    while n != 1:
        n = n // 2 if n % 2 == 0 else 3 * n + 1
        length += 1
        assert length < 100000, f'Unexpectedly long Collatz sequence for {start}'
    return length


def exact_determinant(matrix):
    n = len(matrix)
    total = Fraction(0)
    for perm in itertools.permutations(range(n)):
        inversions = sum(perm[i] > perm[j] for i in range(n) for j in range(i + 1, n))
        term = Fraction(-1 if inversions % 2 else 1)
        for row, col in enumerate(perm):
            term *= Fraction(matrix[row][col])
        total += term
    return float(total)


def test_run_e2e_script_and_results():
    if RESULTS.exists():
        RESULTS.unlink()
    if (PROJECT / 'target').exists():
        subprocess.run(['rm', '-rf', str(PROJECT / 'target')], check=True)

    assert SCRIPT.exists(), f'The script {SCRIPT} does not exist.'
    assert os.access(SCRIPT, os.X_OK), f'The script {SCRIPT} does not have executable permissions.'
    assert not port_is_open(), 'Port 8123 was already occupied before the E2E script ran.'

    result = subprocess.run([str(SCRIPT)], capture_output=True, text=True, timeout=300)
    assert result.returncode == 0, (
        f'The script {SCRIPT} failed with return code {result.returncode}.\n'
        f'STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}'
    )

    assert RESULTS.exists(), f'The results file {RESULTS} was not created by the script.'
    try:
        data = json.loads(RESULTS.read_text())
    except json.JSONDecodeError as exc:
        pytest.fail(f'Failed to parse JSON from {RESULTS}: {exc}')

    assert 'collatz_27' in data, "The key 'collatz_27' is missing from the JSON results."
    assert isinstance(data['collatz_27'], int), "The value for 'collatz_27' must be an integer."
    assert data['collatz_27'] == 111, f"Expected 'collatz_27' to be 111, but got {data['collatz_27']}."

    assert 'determinant' in data, "The key 'determinant' is missing from the JSON results."
    assert isinstance(data['determinant'], (int, float)), "The value for 'determinant' must be a number."
    assert math.isclose(data['determinant'], 4.0, rel_tol=1e-5), (
        f"Expected 'determinant' to be approximately 4.0, but got {data['determinant']}."
    )

    cargo_calls = successful_calls(CARGO_LOG)
    assert any(
        ('build' in call or 'run' in call)
        and ('--release' in call or '-r' in call or '--profile release' in call)
        for call in cargo_calls
    ), 'The E2E script did not successfully invoke Cargo to compile/run in release mode.'

    curl_calls = successful_calls(CURL_LOG)
    assert any('/collatz/27' in call and '8123' in call for call in curl_calls), (
        'The E2E script did not successfully invoke curl for /collatz/27 on port 8123.'
    )
    assert any('/determinant' in call and '8123' in call for call in curl_calls), (
        'The E2E script did not successfully invoke curl for /determinant on port 8123.'
    )

    time.sleep(0.3)
    assert not port_is_open(), 'The E2E script left its API server running on port 8123.'


def test_release_rust_api_on_runtime_generated_inputs():
    assert (PROJECT / 'Cargo.toml').is_file(), 'The Rust project is missing Cargo.toml.'

    build = subprocess.run(
        ['cargo', 'build', '--release'], cwd=PROJECT,
        capture_output=True, text=True, timeout=300
    )
    assert build.returncode == 0, f'Release build failed.\n{build.stdout}\n{build.stderr}'

    metadata_result = subprocess.run(
        ['cargo', 'metadata', '--no-deps', '--format-version', '1'],
        cwd=PROJECT, capture_output=True, text=True, timeout=60
    )
    assert metadata_result.returncode == 0, metadata_result.stderr
    metadata = json.loads(metadata_result.stdout)
    project_manifest = str((PROJECT / 'Cargo.toml').resolve())
    packages = [p for p in metadata['packages'] if str(Path(p['manifest_path']).resolve()) == project_manifest]
    assert packages, 'Cargo metadata contains no package for /home/user/math_api.'

    package = packages[0]
    binary_targets = [t for t in package['targets'] if 'bin' in t.get('kind', [])]
    assert binary_targets, 'The Rust package has no binary server target.'
    default_run = package.get('default_run')
    if default_run:
        binary_targets.sort(key=lambda target: target['name'] != default_run)

    target_dir = Path(metadata['target_directory']) / 'release'
    server = None
    output_file = None
    for target in binary_targets:
        executable = target_dir / target['name']
        assert executable.is_file(), f'Release executable {executable} was not produced.'
        assert os.access(executable, os.X_OK), f'{executable} is not executable.'
        assert executable.read_bytes()[:4] == b'\x7fELF', f'{executable} is not a native release executable.'

        output_file = open('/tmp/math_api_server.log', 'w+')
        candidate = subprocess.Popen(
            [str(executable)], cwd=PROJECT,
            stdout=output_file, stderr=subprocess.STDOUT, start_new_session=True
        )
        deadline = time.time() + 10
        while time.time() < deadline and candidate.poll() is None:
            try:
                probe = request_json('http://127.0.0.1:8123/collatz/1')
                if probe.get('n') == 1 and probe.get('length') == 0:
                    server = candidate
                    break
            except Exception:
                time.sleep(0.05)
        if server is not None:
            break
        candidate.terminate()
        try:
            candidate.wait(timeout=3)
        except subprocess.TimeoutExpired:
            candidate.kill()
            candidate.wait(timeout=3)
        output_file.close()
        output_file = None

    assert server is not None, 'No compiled Rust binary started the required API on 127.0.0.1:8123.'

    try:
        rng = random.Random(int.from_bytes(os.urandom(16), 'big'))
        values = {1, 2, rng.randint(3, 50000), rng.randint(50001, 500000), rng.randint(500001, 1000000)}
        for n in values:
            response = request_json(f'http://127.0.0.1:8123/collatz/{n}')
            assert response.get('n') == n
            assert response.get('length') == collatz_length(n)

        matrices = [[[rng.randint(-9, 9)]]]
        for size in (2, 3, 4):
            matrices.append([[rng.randint(-6, 6) for _ in range(size)] for _ in range(size)])

        for matrix in matrices:
            expected = exact_determinant(matrix)
            response = request_json(
                'http://127.0.0.1:8123/determinant',
                {'matrix': [[float(value) for value in row] for row in matrix]}
            )
            actual = response.get('determinant')
            assert isinstance(actual, (int, float)) and not isinstance(actual, bool)
            assert math.isclose(float(actual), expected, rel_tol=1e-7, abs_tol=1e-7), (
                f'Wrong determinant for runtime-generated matrix {matrix}: expected {expected}, got {actual}'
            )
    finally:
        server.terminate()
        try:
            server.wait(timeout=5)
        except subprocess.TimeoutExpired:
            server.kill()
            server.wait(timeout=3)
        if output_file is not None:
            output_file.close()
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    printf '1\n' > /logs/verifier/reward.txt
else
    printf '0\n' > /logs/verifier/reward.txt
fi
exit 0
