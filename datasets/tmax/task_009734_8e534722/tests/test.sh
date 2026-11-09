#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_archiver.py
import os
import re
import shutil
import subprocess
import tempfile
import uuid
from pathlib import Path

ACTIVE = Path('/home/user/active_logs')
ARCHIVED = Path('/home/user/archived_logs')
SOURCE = Path('/home/user/archiver.go')
SUMMARY = Path('/home/user/redaction_summary.txt')

BASELINE = {
    'app1/server.log': (
        'INFO Starting server\n'
        'DEBUG User login IP: 192.168.1.50 success\n'
        'ERROR Failed transaction SSN: 123-45-6789\n'
        'INFO User logout\n'
    ),
    'app1/subs/db.log': (
        'WARN Connection timeout IP: 10.0.0.1\n'
        'INFO Reconnected\n'
        'ERROR Duplicate entry SSN: 987-65-4321, IP: 172.16.254.1\n'
    ),
    'app2/api.log': (
        'INFO Request received\n'
        'INFO Processing SSN: 111-22-3333 for user\n'
        'INFO Done\n'
    ),
}

IP_RE = re.compile(rb'IP: [0-9]{1,3}(?:\.[0-9]{1,3}){3}')
SSN_RE = re.compile(rb'SSN: [0-9]{3}-[0-9]{2}-[0-9]{4}')

def transform(data):
    return SSN_RE.sub(b'SSN: ***-**-****', IP_RE.sub(b'IP: REDACTED', data))

def redacted_line_count(data):
    return sum(1 for line in data.splitlines(keepends=True) if transform(line) != line)

def check_initial_sources():
    assert ACTIVE.is_dir(), 'active_logs directory is missing'
    for rel, expected in BASELINE.items():
        path = ACTIVE / rel
        assert path.is_file(), f'Original file {path} is missing'
        actual = path.read_text()
        assert actual == expected, f'Original file {path} was modified'
    server = (ACTIVE / 'app1/server.log').read_text()
    assert 'IP: 192.168.1.50' in server, 'Original server log is missing its IP'
    assert 'SSN: 123-45-6789' in server, 'Original server log is missing its SSN'

def add_unpredictable_logs():
    tag = uuid.uuid4().hex
    first = ACTIVE / ('runtime_' + tag) / 'nested' / 'extra.log'
    second = ACTIVE / ('runtime_' + tag) / 'other.log'
    first.parent.mkdir(parents=True)
    second.parent.mkdir(parents=True)
    a = int.from_bytes(os.urandom(2), 'big') % 200 + 1
    b = int.from_bytes(os.urandom(2), 'big') % 200 + 1
    ssn1 = f'{a:03d}-{b % 100:02d}-{(a * 37 + b) % 10000:04d}'
    ssn2 = f'{b:03d}-{a % 100:02d}-{(b * 41 + a) % 10000:04d}'
    first.write_text(
        'INFO dynamically added log\n'
        f'WARN client IP: 203.0.{a % 255}.{b % 255} and SSN: {ssn1}\n'
        'INFO text that must remain byte-for-byte unchanged\n'
        f'WARN retry IP: 10.{b % 255}.{a % 255}.7\n'
    )
    second.write_text(
        'START ordinary content\n'
        f'USER SSN: {ssn2}\n'
        f'PAIR IP: 172.20.{a % 255}.{b % 255}, IP: 192.168.{b % 255}.{a % 255}\n'
        'END ordinary content\n'
    )

def inspect_go_source():
    assert SOURCE.is_file(), '/home/user/archiver.go is missing'
    source = SOURCE.read_text(errors='replace')
    assert '"os/exec"' in source, 'archiver.go does not import os/exec'
    assert re.search(r'\bCommand(?:Context)?\s*\(', source), 'archiver.go does not create an external command'
    assert re.search(r'\b(?:sed|awk|gawk|tr)\b', source), 'archiver.go does not invoke sed, awk, or tr'
    assert ('|' in source or 'StdoutPipe' in source or 'StdinPipe' in source or 'io.Pipe' in source), \
        'archiver.go does not implement a stream pipeline'

def install_tool_wrappers(log_path):
    wrapped = []
    seen = set()
    for tool in ('/usr/bin/sed', '/usr/bin/awk', '/usr/bin/tr', '/usr/bin/gawk'):
        path = Path(tool)
        if not path.exists() and not path.is_symlink():
            continue
        identity = os.path.realpath(tool)
        key = (tool, identity)
        if key in seen:
            continue
        seen.add(key)
        backup = path.with_name('.verifier-real-' + path.name + '-' + uuid.uuid4().hex)
        os.rename(path, backup)
        wrapper = '#!/bin/sh\nprintf \'%s\\n\' ' + path.name + ' >> ' + str(log_path) + '\nexec ' + str(backup) + ' "$@"\n'
        path.write_text(wrapper)
        path.chmod(0o755)
        wrapped.append((path, backup))
    return wrapped

def restore_tool_wrappers(wrapped):
    for path, backup in reversed(wrapped):
        try:
            if path.exists() or path.is_symlink():
                path.unlink()
            os.rename(backup, path)
        except FileNotFoundError:
            pass

def build_and_run():
    binary = Path(tempfile.gettempdir()) / ('archiver-' + uuid.uuid4().hex)
    subprocess.run(
        ['go', 'build', '-o', str(binary), str(SOURCE)],
        cwd='/home/user', check=True, timeout=60,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )

    if ARCHIVED.exists():
        shutil.rmtree(ARCHIVED)
    if SUMMARY.exists():
        SUMMARY.unlink()

    tool_log = Path('/tmp/archiver-tool-' + uuid.uuid4().hex + '.log')
    tool_log.write_text('')
    tool_log.chmod(0o666)
    wrapped = []
    try:
        wrapped = install_tool_wrappers(tool_log)
        env = os.environ.copy()
        env['PATH'] = '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
        subprocess.run(
            [str(binary)], cwd='/home/user', env=env, check=True, timeout=30,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
    finally:
        restore_tool_wrappers(wrapped)
        try:
            binary.unlink()
        except FileNotFoundError:
            pass

    invoked = set(tool_log.read_text().splitlines())
    assert invoked.intersection({'sed', 'awk', 'gawk', 'tr'}), \
        'The executed Go program did not invoke sed, awk, or tr'

def verify_results(snapshot):
    assert ARCHIVED.is_dir(), 'archived_logs directory is missing after execution'

    actual_files = {
        str(path.relative_to(ARCHIVED))
        for path in ARCHIVED.rglob('*') if path.is_file()
    }
    assert actual_files == set(snapshot), \
        f'Archived file set is incorrect. Expected {sorted(snapshot)}, got {sorted(actual_files)}'

    expected_summary = []
    for rel in sorted(snapshot):
        source_data = snapshot[rel]
        archived_path = ARCHIVED / rel
        assert archived_path.is_file(), f'Archived file {archived_path} is missing'
        actual = archived_path.read_bytes()
        expected = transform(source_data)
        assert actual == expected, \
            f'{archived_path} does not exactly preserve all content except the required redactions'
        expected_summary.append(f'{rel}: {redacted_line_count(source_data)}')

    assert SUMMARY.is_file(), 'redaction_summary.txt is missing'
    lines = [line.strip() for line in SUMMARY.read_text().splitlines() if line.strip()]
    assert lines == expected_summary, \
        f'Summary file contents incorrect. Expected {expected_summary}, got {lines}'

    for rel, original in snapshot.items():
        assert (ACTIVE / rel).read_bytes() == original, f'Original file {ACTIVE / rel} was modified'

check_initial_sources()
add_unpredictable_logs()
snapshot = {
    str(path.relative_to(ACTIVE)): path.read_bytes()
    for path in ACTIVE.rglob('*.log') if path.is_file()
}
inspect_go_source()
build_and_run()
verify_results(snapshot)
PY_EOF

if python3 /tmp/verify_archiver.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
