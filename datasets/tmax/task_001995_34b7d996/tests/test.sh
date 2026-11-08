#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import re
import stat
import subprocess
import uuid

import pytest

BWRAP = '/usr/bin/bwrap'
REAL_BWRAP = '/usr/bin/bwrap.verifier-real'
BWRAP_LOG = '/tmp/bwrap-verifier.log'


@pytest.fixture(scope='session', autouse=True)
def instrument_bwrap():
    """Record actual bwrap invocations while preserving its real behavior."""
    assert os.path.isfile(BWRAP), f'{BWRAP} is unavailable'
    assert not os.path.exists(REAL_BWRAP), f'Stale verifier file exists: {REAL_BWRAP}'

    os.rename(BWRAP, REAL_BWRAP)
    try:
        with open(BWRAP, 'w') as f:
            f.write(f'''#!/bin/sh
{{
    printf '\\036'
    for arg in "$@"; do
        printf '%s\\000' "$arg"
    done
}} >> {BWRAP_LOG}
exec {REAL_BWRAP} "$@"
''')
        os.chmod(BWRAP, 0o755)
        open(BWRAP_LOG, 'wb').close()
        yield
    finally:
        try:
            if os.path.lexists(BWRAP):
                os.unlink(BWRAP)
        finally:
            if os.path.exists(REAL_BWRAP):
                os.rename(REAL_BWRAP, BWRAP)


def clear_bwrap_log():
    open(BWRAP_LOG, 'wb').close()


def bwrap_calls():
    with open(BWRAP_LOG, 'rb') as f:
        data = f.read()
    calls = []
    for record in data.split(b'\x1e'):
        if record:
            calls.append([x.decode(errors='replace') for x in record.split(b'\0') if x])
    return calls


def assert_required_bwrap_flags(calls):
    assert calls, 'secure_run.sh did not invoke the installed bwrap executable'
    assert any('--unshare-net' in call for call in calls), \
        'bwrap was not invoked with --unshare-net'

    bind_options = {'--bind', '--bind-try', '--dev-bind', '--dev-bind-try'}
    shared_root = False
    for call in calls:
        for i, arg in enumerate(call[:-2]):
            if arg in bind_options and call[i + 1:i + 3] == ['/', '/']:
                shared_root = True
    assert shared_root, 'bwrap was not given a read/write bind of / onto /'


def node_listening_ports():
    result = subprocess.run(['ss', '-ltnp'], capture_output=True, text=True, check=True)
    ports = set()
    for line in result.stdout.splitlines():
        if re.search(r'\(\("node"(?:,|\))', line):
            match = re.search(r'\s(?:\[[^]]+\]|[^ ]+):(\d+)\s', line)
            if match:
                ports.add(int(match.group(1)))
    return ports


def test_running_node_service_and_log_correlation():
    """The advertised Node service must actually run, and the report must match its traffic."""
    ports = node_listening_ports()
    assert len(ports) == 1, f'Expected one listening Node service port, found {sorted(ports)}'
    node_port = next(iter(ports))

    counts = collections.Counter()
    pattern = re.compile(
        r'^\[[^]]+\]\s+(\d+\.\d+\.\d+\.\d+):\d+\s+->\s+'
        r'127\.0\.0\.1:(\d+)\s+' 
    )
    with open('/home/user/traffic.log') as f:
        for line in f:
            match = pattern.match(line)
            if match and int(match.group(2)) == node_port:
                counts[match.group(1)] += 1

    assert counts, f'No traffic entries found for the Node service on port {node_port}'
    highest = max(counts.values())
    expected = [ip for ip, count in counts.items() if count == highest]
    assert len(expected) == 1, f'Traffic log has no unique highest-volume source: {expected}'

    with open('/home/user/rogue_ip.txt') as f:
        content = f.read().strip()
    assert content == expected[0], f'Expected correlated IP {expected[0]}, got {content!r}'


def test_rogue_ip_file():
    """Keep the original fixed-answer assertion."""
    file_path = '/home/user/rogue_ip.txt'
    assert os.path.isfile(file_path), f'File {file_path} does not exist.'
    with open(file_path, 'r') as f:
        content = f.read().strip()
    assert content == '203.0.113.42', \
        f"Expected IP '203.0.113.42', but got '{content}' in {file_path}."


def test_secure_run_sh_exists_and_executable():
    script_path = '/home/user/secure_run.sh'
    assert os.path.isfile(script_path), f'Script {script_path} does not exist.'
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f'Script {script_path} is not executable.'


def test_secure_run_sh_runs_arbitrary_command_in_bwrap():
    """Exercise a derived command, filesystem sharing, and the actual network namespace."""
    script_path = '/home/user/secure_run.sh'
    nonce = uuid.uuid4().hex
    input_path = f'/home/user/.sandbox_input_{nonce}'
    output_path = f'/home/user/.sandbox_output_{nonce}'
    input_value = uuid.uuid4().hex
    with open(input_path, 'w') as f:
        f.write(input_value)

    code = (
        "import os,sys; "
        "value=open(sys.argv[2]).read(); "
        "assert value==sys.argv[1]; "
        "open(sys.argv[3],'w').write(value); "
        "print(sys.argv[1]); "
        "print(os.readlink('/proc/self/ns/net'))"
    )
    clear_bwrap_log()
    try:
        result = subprocess.run(
            [script_path, 'python3', '-c', code, input_value, input_path, output_path],
            capture_output=True, text=True, timeout=10
        )
        assert result.returncode == 0, \
            f'secure_run.sh failed with {result.returncode}: {result.stderr}'
        lines = result.stdout.strip().splitlines()
        assert input_value in lines, 'The supplied arbitrary command did not produce its derived output'
        assert os.path.isfile(output_path), 'The sandbox could not write through the shared host filesystem'
        with open(output_path) as f:
            assert f.read() == input_value

        namespace_lines = [line for line in lines if line.startswith('net:[')]
        assert namespace_lines, 'The command did not report its network namespace'
        assert namespace_lines[-1] != os.readlink('/proc/self/ns/net'), \
            'The command remained in the verifier host network namespace'

        calls = bwrap_calls()
        assert_required_bwrap_flags(calls)
        assert any('python3' in call and '-c' in call and code in call for call in calls), \
            'The arbitrary command was not passed to bwrap'
    finally:
        for path in (input_path, output_path):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass


def test_secure_run_sh_execution():
    """Keep the original ip-link behavior checks and prove ip was passed to bwrap."""
    script_path = '/home/user/secure_run.sh'
    assert os.path.isfile(script_path), f'Script {script_path} does not exist.'
    clear_bwrap_log()
    try:
        result = subprocess.run(
            [script_path, 'ip', 'link'],
            capture_output=True,
            text=True,
            timeout=5
        )
    except subprocess.TimeoutExpired:
        pytest.fail('Execution of secure_run.sh timed out.')
    except Exception as e:
        pytest.fail(f'Execution of secure_run.sh failed: {e}')

    assert result.returncode == 0, \
        f'secure_run.sh failed with return code {result.returncode}. Stderr: {result.stderr}'
    output = result.stdout.lower()
    assert 'lo:' in output or 'loopback' in output, \
        'Loopback interface (lo) not found in the output. The command might not have executed properly.'
    assert 'eth0:' not in output, \
        "Network is not isolated: 'eth0' was found in the output of 'ip link' inside the sandbox."

    calls = bwrap_calls()
    assert_required_bwrap_flags(calls)
    assert any(any(call[i:i + 2] == ['ip', 'link'] for i in range(len(call) - 1)) for call in calls), \
        "The requested 'ip link' command was not passed to bwrap"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
