#!/bin/bash
set -e
mkdir -p /logs/verifier

# Stop any watcher left running by the workflow so the verification tests can
# exercise organize.sh in isolation.
python3 - <<'PY'
import os, signal, time
me = os.getpid()
for entry in os.listdir('/proc'):
    if not entry.isdigit() or int(entry) == me:
        continue
    try:
        cmdline = open(f'/proc/{entry}/cmdline', 'rb').read().replace(b'\0', b' ')
        if b'organize.sh' in cmdline:
            os.kill(int(entry), signal.SIGTERM)
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        pass
time.sleep(0.3)
PY

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import signal
import struct
import subprocess
import time
from pathlib import Path

PARSER_C = Path('/home/user/parser.c')
PARSER = Path('/home/user/parser')
ORGANIZER = Path('/home/user/organize.sh')
LOG = Path('/home/user/project_log.txt')


def test_parser_c_exists():
    assert os.path.isfile('/home/user/parser.c'), '/home/user/parser.c is missing'


def test_parser_executable_exists():
    assert os.path.isfile('/home/user/parser'), '/home/user/parser executable is missing'
    assert os.access('/home/user/parser', os.X_OK), '/home/user/parser is not executable'
    assert PARSER.read_bytes()[:4] == b'\x7fELF', '/home/user/parser is not a compiled ELF executable'


def test_organize_sh_exists():
    assert os.path.isfile('/home/user/organize.sh'), '/home/user/organize.sh is missing'


def test_project_log_contents():
    log_path = '/home/user/project_log.txt'
    assert os.path.isfile(log_path), f'{log_path} is missing'

    expected_lines = {
        '[1630000000] System initialized.',
        '[1630000005] Module A loaded.',
        '[1630000010] Warning: low memory.',
        '[1630000020] User logged in.',
        '[1630000025] Data sync complete.'
    }

    with open(log_path, 'r') as f:
        actual_lines = {line.strip() for line in f if line.strip()}

    missing = expected_lines - actual_lines
    extra = actual_lines - expected_lines

    assert not missing, f'Missing expected lines in project_log.txt: {missing}'
    assert not extra, f'Unexpected extra lines in project_log.txt: {extra}'


def test_staging_directory_empty():
    staging_dir = '/home/user/staging'
    if os.path.isdir(staging_dir):
        files = os.listdir(staging_dir)
        assert len(files) == 0, f'Files were not moved out of staging directory: {files}'


def test_incoming_directory_empty():
    incoming_dir = '/home/user/incoming'
    if os.path.isdir(incoming_dir):
        files = [f for f in os.listdir(incoming_dir) if f.endswith('.bin')]
        assert len(files) == 0, f'Binary files were not deleted from incoming directory after processing: {files}'


def encode_records(records):
    data = bytearray()
    expected = bytearray()
    for timestamp, payload in records:
        payload_bytes = payload.encode('ascii')
        data += b'DATA' + struct.pack('<I', timestamp)
        data += struct.pack('<H', len(payload_bytes)) + payload_bytes
        expected += f'[{timestamp}] {payload}\n'.encode('ascii')
    return bytes(data), bytes(expected)


def run_parser(executable, path, expected):
    result = subprocess.run(
        [str(executable), str(path)], stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=5
    )
    assert result.returncode == 0, f'parser failed for {path}: {result.stderr!r}'
    assert result.stdout == expected, (
        f'wrong parser output for {path}: expected {expected!r}, got {result.stdout!r}'
    )


def test_parser_uses_mmap_and_handles_additional_inputs(tmp_path):
    source = PARSER_C.read_text(errors='replace')
    source_without_comments = re.sub(r'/\*.*?\*/|//[^\n]*', '', source, flags=re.S)
    assert re.search(r'\bmmap\s*\(', source_without_comments), 'parser.c does not call mmap()'

    rebuilt = tmp_path / 'parser-from-source'
    build = subprocess.run(
        ['gcc', str(PARSER_C), '-o', str(rebuilt)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert build.returncode == 0, f'parser.c does not compile: {build.stderr.decode(errors="replace")}'

    symbols = subprocess.run(
        ['nm', '-D', str(rebuilt)], stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=5, text=True
    )
    assert re.search(r'\bmmap(?:64)?(?:@[^ ]*)?$', symbols.stdout, re.M), (
        'the program compiled from parser.c does not reference mmap'
    )

    token = secrets.token_hex(12)
    cases = [
        [(secrets.randbits(32), 'dynamic-' + token)],
        [
            (secrets.randbits(32), ''),
            (secrets.randbits(32), 'first-' + token),
            (secrets.randbits(32), 'X' * 257),
        ],
        [(secrets.randbits(32), 'symbols !@#$%^&*() ' + token)],
    ]

    for index, records in enumerate(cases):
        blob, expected = encode_records(records)
        input_path = tmp_path / f'additional-{index}.bin'
        input_path.write_bytes(blob)
        # Exercise both the submitted executable and a fresh build of parser.c.
        run_parser(PARSER, input_path, expected)
        run_parser(rebuilt, input_path, expected)


def stop_process(proc):
    if proc is not None and proc.poll() is None:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def wait_until(predicate, timeout=6):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(0.1)
    return predicate()


def test_organize_script_runs_parser_and_watches_multiple_arrivals(tmp_path):
    script = ORGANIZER.read_text(errors='replace')
    script_without_comments = re.sub(r'#[^\n]*', '', script)
    assert re.search(r'(^|[;\n]\s*)sleep\s+1(?:\s|;|$)', script_without_comments), (
        'organize.sh does not pause for 1 second in its watcher loop'
    )

    incoming = Path('/home/user/incoming')
    incoming.mkdir(parents=True, exist_ok=True)
    assert not list(incoming.iterdir()), 'incoming must be empty before watcher exercise'

    marker = tmp_path / 'parser-invocations.txt'
    real_parser = Path('/home/user/parser.verifier-real')
    proc = None
    created = []
    baseline_size = LOG.stat().st_size

    os.replace(PARSER, real_parser)
    try:
        PARSER.write_text(
            '#!/bin/bash\n'
            f'printf "%s\\n" "$1" >> {str(marker)!r}\n'
            f'exec {str(real_parser)!r} "$@"\n'
        )
        PARSER.chmod(0o755)

        first_records = [(secrets.randbits(32), 'watch-one-' + secrets.token_hex(8))]
        first_blob, first_expected = encode_records(first_records)
        first = incoming / ('verify-first-' + secrets.token_hex(6) + '.bin')
        first.write_bytes(first_blob)
        created.append(first)

        proc = subprocess.Popen(
            ['/bin/bash', str(ORGANIZER)], cwd='/home/user',
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
            start_new_session=True
        )
        assert wait_until(lambda: not first.exists()), 'organize.sh did not process the first arriving file'
        assert proc.poll() is None, 'organize.sh exited instead of continuing to watch'

        second_records = [
            (secrets.randbits(32), 'watch-two-' + secrets.token_hex(8)),
            (secrets.randbits(32), 'watch-three-' + secrets.token_hex(8)),
        ]
        second_blob, second_expected = encode_records(second_records)
        second = incoming / ('verify-second-' + secrets.token_hex(6) + '.bin')
        second.write_bytes(second_blob)
        created.append(second)

        expected_tail = first_expected + second_expected
        assert wait_until(
            lambda: (not second.exists()) and LOG.stat().st_size >= baseline_size + len(expected_tail)
        ), 'the running watcher did not process a later arrival'

        with LOG.open('rb') as f:
            f.seek(baseline_size)
            actual_tail = f.read()
        assert actual_tail == expected_tail, (
            f'organize.sh appended incorrect output: expected {expected_tail!r}, got {actual_tail!r}'
        )

        invocations = marker.read_text().splitlines() if marker.exists() else []
        assert str(first) in invocations, 'organize.sh did not invoke ./parser for the first file'
        assert str(second) in invocations, 'organize.sh did not invoke ./parser for the later file'
    finally:
        stop_process(proc)
        for path in created:
            try:
                path.unlink()
            except FileNotFoundError:
                pass
        try:
            PARSER.unlink()
        except FileNotFoundError:
            pass
        if real_parser.exists():
            os.replace(real_parser, PARSER)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
