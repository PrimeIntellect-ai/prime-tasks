#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_curator_behavior.py
import json
import os
import signal
import subprocess
import tarfile
import time
import uuid
import zipfile
from pathlib import Path

SCRIPT = Path('/home/user/curator.py')
INCOMING = Path('/home/user/incoming')
CURATED = Path('/home/user/curated')
LOGDIR = Path('/home/user/logs')
LOGFILE = LOGDIR / 'curator.log'
AUDIT_DIR = Path('/tmp/curator_audit_hook')
AUDIT_LOG = Path('/tmp/curator_rename_events.jsonl')


def curator_pids():
    found = []
    for entry in Path('/proc').iterdir():
        if not entry.name.isdigit() or int(entry.name) == os.getpid():
            continue
        try:
            args = (entry / 'cmdline').read_bytes().split(b'\0')
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if b'/home/user/curator.py' in args:
            found.append(int(entry.name))
    return found


def stop_existing_curators():
    INCOMING.mkdir(parents=True, exist_ok=True)
    (INCOMING / 'SHUTDOWN').touch()
    deadline = time.time() + 8
    while time.time() < deadline and curator_pids():
        time.sleep(0.1)
    for pid in curator_pids():
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and curator_pids():
        time.sleep(0.1)
    for pid in curator_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def clear_directory(path):
    path.mkdir(parents=True, exist_ok=True)
    for child in path.iterdir():
        if child.is_dir() and not child.is_symlink():
            import shutil
            shutil.rmtree(child)
        else:
            child.unlink()


def make_zip(path, members):
    with zipfile.ZipFile(path, 'w') as archive:
        for name, content in members:
            archive.writestr(name, content)


def wait_processed(zip_path, tar_path, proc, timeout=20):
    deadline = time.time() + timeout
    while time.time() < deadline:
        assert proc.poll() is None, 'curator exited before receiving SHUTDOWN'
        if tar_path.is_file() and not zip_path.exists():
            return
        time.sleep(0.05)
    raise AssertionError(f'curator did not process {zip_path.name} in time')


def inspect_archive(path, expected_files):
    assert path.is_file(), f'{path} is missing'
    with tarfile.open(path, 'r:gz') as archive:
        members = archive.getmembers()
        names = [member.name for member in members]
        for name in names:
            assert '..' not in name, f'malicious traversal member {name!r} was archived'
            assert not name.startswith('/'), f'absolute member {name!r} was archived'

        regular = {member.name: member for member in members if member.isfile()}
        assert set(regular) == set(expected_files), (
            f'{path.name} contains the wrong regular files: {set(regular)!r}'
        )
        for name, expected in expected_files.items():
            extracted = archive.extractfile(regular[name])
            assert extracted is not None
            assert extracted.read() == expected, f'content mismatch for {name!r}'


def test_curator_end_to_end():
    assert SCRIPT.is_file(), '/home/user/curator.py is missing or is not a file'

    stop_existing_curators()
    clear_directory(INCOMING)
    clear_directory(CURATED)
    clear_directory(LOGDIR)
    clear_directory(AUDIT_DIR)
    AUDIT_LOG.unlink(missing_ok=True)

    # Runtime instrumentation records actual rename/replace operations without
    # changing the submitted script. Python emits the os.rename audit event for
    # both os.rename and os.replace.
    (AUDIT_DIR / 'sitecustomize.py').write_text(r'''
import json
import os

_log = os.environ.get("CURATOR_RENAME_AUDIT")

def _resolve(path, dir_fd):
    path = os.fsdecode(path)
    if os.path.isabs(path):
        return os.path.normpath(path)
    if dir_fd not in (None, -1):
        try:
            base = os.readlink("/proc/self/fd/%d" % dir_fd)
        except OSError:
            base = os.getcwd()
    else:
        base = os.getcwd()
    return os.path.normpath(os.path.join(base, path))

def _hook(event, args):
    if event != "os.rename" or not _log:
        return
    src_fd = args[2] if len(args) > 2 else -1
    dst_fd = args[3] if len(args) > 3 else -1
    record = [_resolve(args[0], src_fd), _resolve(args[1], dst_fd)]
    with open(_log, "a", encoding="utf-8") as output:
        output.write(json.dumps(record) + "\n")

import sys
sys.addaudithook(_hook)
''', encoding='utf-8')

    env = os.environ.copy()
    old_pythonpath = env.get('PYTHONPATH')
    env['PYTHONPATH'] = str(AUDIT_DIR) + (os.pathsep + old_pythonpath if old_pythonpath else '')
    env['CURATOR_RENAME_AUDIT'] = str(AUDIT_LOG)

    log_handle = open(LOGFILE, 'wb')
    proc = subprocess.Popen(
        ['python3', str(SCRIPT)],
        cwd='/home/user',
        stdout=log_handle,
        stderr=subprocess.STDOUT,
        env=env,
    )

    token = uuid.uuid4().hex
    dynamic_name = f'watch_{token}.zip'
    dynamic_stem = dynamic_name[:-4]
    safe_blob = os.urandom(8192)
    nested_blob = os.urandom(513)
    escape_target = Path('/home/user') / f'{token}_escape.txt'
    absolute_target = Path('/tmp') / f'{token}_absolute.txt'
    escape_target.unlink(missing_ok=True)
    absolute_target.unlink(missing_ok=True)

    archives = [
        (
            'build_v1.zip',
            [
                ('safe1.txt', b'safe data'),
                ('dir/safe2.txt', b'more safe data'),
                ('../escape.txt', b'evil data'),
                ('/absolute.txt', b'evil data 2'),
            ],
            {'safe1.txt': b'safe data', 'dir/safe2.txt': b'more safe data'},
            2,
            2,
        ),
        (
            'build_v2.zip',
            [('config.json', b'{"status": "ok"}')],
            {'config.json': b'{"status": "ok"}'},
            1,
            0,
        ),
        (
            dynamic_name,
            [
                (f'payload_{token}.bin', safe_blob),
                (f'nested/{token}/data.dat', nested_blob),
                (f'../{token}_escape.txt', b'escape'),
                (str(absolute_target), b'absolute'),
                (f'odd..name_{token}.txt', b'double-dot'),
            ],
            {
                f'payload_{token}.bin': safe_blob,
                f'nested/{token}/data.dat': nested_blob,
            },
            2,
            3,
        ),
    ]

    try:
        # Files are introduced only after the submitted daemon is running, and
        # later files arrive after earlier processing has completed.
        time.sleep(0.4)
        assert proc.poll() is None, 'curator did not remain running as a watcher'
        for filename, members, expected, _, _ in archives:
            zip_path = INCOMING / filename
            tar_path = CURATED / (filename[:-4] + '.tar.gz')
            make_zip(zip_path, members)
            wait_processed(zip_path, tar_path, proc)
            inspect_archive(tar_path, expected)

        (INCOMING / 'SHUTDOWN').touch()
        returncode = proc.wait(timeout=10)
        assert returncode == 0, f'curator exited with status {returncode}'
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait(timeout=5)
        log_handle.close()

    # Preserve the original final-state checks explicitly.
    assert (CURATED / 'build_v1.tar.gz').is_file()
    with tarfile.open(CURATED / 'build_v1.tar.gz', 'r:gz') as archive:
        names = archive.getnames()
        assert 'safe1.txt' in names
        assert 'dir/safe2.txt' in names
        assert not any('escape' in name for name in names)
        assert not any('absolute' in name for name in names)
    assert (CURATED / 'build_v2.tar.gz').is_file()
    with tarfile.open(CURATED / 'build_v2.tar.gz', 'r:gz') as archive:
        assert 'config.json' in archive.getnames()

    incoming_names = os.listdir(INCOMING)
    assert 'build_v1.zip' not in incoming_names
    assert 'build_v2.zip' not in incoming_names
    assert dynamic_name not in incoming_names
    assert 'SHUTDOWN' in incoming_names
    assert not escape_target.exists(), 'a traversal member was written outside the workspace'
    assert not absolute_target.exists(), 'an absolute-path member was written to the filesystem'

    assert LOGFILE.is_file()
    lines = LOGFILE.read_text(encoding='utf-8').splitlines()
    expected_lines = [
        'Processed build_v1.zip: 2 safe, 2 malicious',
        'Processed build_v2.zip: 1 safe, 0 malicious',
        f'Processed {dynamic_name}: 2 safe, 3 malicious',
    ]
    assert sorted(lines) == sorted(expected_lines), (
        'stdout must contain exactly one correctly formatted line per processed zip; '
        f'got {lines!r}'
    )

    assert AUDIT_LOG.is_file(), 'no runtime rename/replace operations were observed'
    rename_events = [json.loads(line) for line in AUDIT_LOG.read_text().splitlines() if line]
    curated_real = os.path.realpath(CURATED)
    for filename, _, _, _, _ in archives:
        final_path = os.path.realpath(CURATED / (filename[:-4] + '.tar.gz'))
        matching_sources = [
            src for src, dst in rename_events
            if os.path.realpath(dst) == final_path
            and os.path.realpath(os.path.dirname(src)) == curated_real
            and os.path.basename(src).startswith('.')
            and os.path.realpath(src) != final_path
        ]
        assert matching_sources, (
            f'{filename} was not finalized by renaming a hidden temporary file '
            'from /home/user/curated'
        )

    leftovers = [p.name for p in CURATED.iterdir() if p.name.startswith('.')]
    assert not leftovers, f'temporary curated files were left behind: {leftovers!r}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_curator_behavior.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
