#!/bin/bash
mkdir -p /logs/verifier
status=0

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os

def test_zip_slip_log():
    log_path = '/home/user/zip_slip.log'
    assert os.path.exists(log_path), f"{log_path} does not exist. Zip Slip mitigation log is missing."
    with open(log_path, 'r') as f:
        content = f.read().strip()
    assert content == '../../../home/user/malicious.sh', f"Expected log to contain skipped malicious path, got: {content}"

def test_restored_wal_file():
    wal_path = '/home/user/restored/valid_log.wal'
    assert os.path.exists(wal_path), f"{wal_path} does not exist. WAL file was not extracted."
    with open(wal_path, 'rb') as f:
        content = f.read()
    expected = b'WAL\x00 + some random WAL data for testing'
    assert content == expected, f"Content of {wal_path} is incorrect."

def test_restored_elf_file():
    elf_path = '/home/user/restored/bin/system_tool'
    assert os.path.exists(elf_path), f"{elf_path} does not exist. ELF file was not extracted."
    with open(elf_path, 'rb') as f:
        content = f.read()
    expected = b'\x7fELF + valid binary data here'
    assert content == expected, f"Content of {elf_path} is incorrect."

def test_ignored_files():
    notes_path = '/home/user/restored/random_notes.txt'
    assert not os.path.exists(notes_path), f"{notes_path} should not have been extracted because of invalid magic bytes."

def test_malicious_file_not_extracted():
    malicious_path = '/home/user/malicious.sh'
    assert not os.path.exists(malicious_path), f"{malicious_path} exists! Path traversal vulnerability was not prevented."
TEST_EOF

if ! python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    status=1
fi

cat << 'TEST_EOF' > /tmp/test_tool_behavior.py
import os
import stat
import struct
import subprocess
import tempfile
import zlib

SCRIPT = '/home/user/extract_backup.py'
LOG = '/home/user/zip_slip.log'

assert os.path.exists(SCRIPT), f'{SCRIPT} does not exist'
assert not os.path.islink(SCRIPT), f'{SCRIPT} must be a regular Python source file, not a symlink'
assert stat.S_ISREG(os.stat(SCRIPT).st_mode), f'{SCRIPT} is not a regular file'
with open(SCRIPT, 'rb') as f:
    source = f.read()
compile(source, SCRIPT, 'exec')

def make_cba(path, entries):
    with open(path, 'wb') as f:
        f.write(b'CB')
        f.write(struct.pack('<I', len(entries)))
        for name, data in entries:
            encoded = name.encode('utf-8')
            packed = zlib.compress(data)
            f.write(struct.pack('<H', len(encoded)))
            f.write(encoded)
            f.write(struct.pack('<I', len(packed)))
            f.write(packed)

def run_tool(archive, output, env=None):
    return subprocess.run(
        ['python3', SCRIPT, archive, output],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
        env=env,
    )

root = tempfile.mkdtemp(prefix='cba-verifier-')
out = os.path.join(root, 'out')
outside = os.path.join(root, 'outside')
os.makedirs(out)
os.makedirs(outside)
os.symlink(outside, os.path.join(out, 'link'))
archive = os.path.join(root, 'generated.cba')
absolute_escape = os.path.join(root, 'absolute-pwn')
malicious_names = [
    '../outside/sibling-pwn',
    absolute_escape,
    'link/symlink-pwn',
]
entries = [
    ('nested/db.wal', b'WAL\x00generated WAL payload'),
    ('tools/generated-app', b'\x7fELFgenerated executable payload'),
    ('sub/../inside.wal', b'WAL\x00normalized safe payload'),
    ('ignored.wal', b'NOTWthis must be ignored'),
    (malicious_names[0], b'WAL\x00sibling escape'),
    (malicious_names[1], b'\x7fELFabsolute escape'),
    (malicious_names[2], b'WAL\x00symlink escape'),
]
make_cba(archive, entries)
with open(LOG, 'w', encoding='utf-8'):
    pass
result = run_tool(archive, out)
assert result.returncode == 0, result.stderr.decode('utf-8', errors='replace')

expected = {
    'nested/db.wal': b'WAL\x00generated WAL payload',
    'tools/generated-app': b'\x7fELFgenerated executable payload',
    'inside.wal': b'WAL\x00normalized safe payload',
}
for relative, data in expected.items():
    path = os.path.join(out, relative)
    assert os.path.isfile(path), f'missing dynamically generated output {relative}'
    with open(path, 'rb') as f:
        assert f.read() == data, f'incorrect data in dynamically generated output {relative}'
assert not os.path.exists(os.path.join(out, 'ignored.wal')), 'invalid-magic file was extracted'
assert not os.path.exists(os.path.join(outside, 'sibling-pwn')), 'relative traversal escaped the output directory'
assert not os.path.exists(absolute_escape), 'absolute path escaped the output directory'
assert not os.path.exists(os.path.join(outside, 'symlink-pwn')), 'symlink traversal escaped the output directory'
with open(LOG, 'r', encoding='utf-8') as f:
    logged = f.read().splitlines()
assert logged == malicious_names, f'wrong dynamically generated traversal log: {logged!r}'

allowed_regular = {os.path.realpath(os.path.join(out, p)) for p in expected}
for directory, _, files in os.walk(out, followlinks=False):
    for filename in files:
        path = os.path.realpath(os.path.join(directory, filename))
        assert path in allowed_regular, f'unexpected or leftover temporary file: {path}'

# Fault-inject writes to the final target. A direct write fails, while a proper
# temporary-file write followed by rename/replace succeeds. The hook also rejects
# renaming a tracked temporary file before it has been closed.
atomic_out = os.path.join(root, 'atomic-out')
os.makedirs(atomic_out)
atomic_archive = os.path.join(root, 'atomic.cba')
atomic_data = b'WAL\x00atomic replacement payload'
make_cba(atomic_archive, [('atomic.wal', atomic_data)])
atomic_final = os.path.realpath(os.path.join(atomic_out, 'atomic.wal'))
with open(atomic_final, 'wb') as f:
    f.write(b'old complete file')

hooks = os.path.join(root, 'hooks')
os.makedirs(hooks)
sitecustomize = r'''
import builtins
import io
import os

_target = os.path.realpath(os.environ['CBA_ATOMIC_FINAL'])
_real_builtin_open = builtins.open
_real_io_open = io.open
_real_os_open = os.open
_real_replace = os.replace
_real_rename = os.rename
_tracked = {}

class Tracked:
    def __init__(self, wrapped, path):
        self._wrapped = wrapped
        self._path = path
        _tracked[path] = self
    def __getattr__(self, name):
        return getattr(self._wrapped, name)
    def __enter__(self):
        return self
    def __exit__(self, typ, value, tb):
        self.close()
        return False
    def close(self):
        return self._wrapped.close()
    @property
    def closed(self):
        return self._wrapped.closed
    def write(self, data):
        return self._wrapped.write(data)

def _path(value):
    if isinstance(value, int):
        return None
    try:
        return os.path.realpath(os.fspath(value))
    except TypeError:
        return None

def _writing(mode):
    return any(c in str(mode) for c in 'wax+')

def _open(real_open, file, mode='r', *args, **kwargs):
    path = _path(file)
    if path == _target and _writing(mode):
        raise OSError('verification fault: direct final-path write')
    wrapped = real_open(file, mode, *args, **kwargs)
    if path is not None and _writing(mode):
        return Tracked(wrapped, path)
    return wrapped

def builtin_open(file, mode='r', *args, **kwargs):
    return _open(_real_builtin_open, file, mode, *args, **kwargs)

def io_open(file, mode='r', *args, **kwargs):
    return _open(_real_io_open, file, mode, *args, **kwargs)

def os_open(path, flags, *args, **kwargs):
    resolved = _path(path)
    writing = flags & (os.O_WRONLY | os.O_RDWR | os.O_CREAT | os.O_TRUNC | os.O_APPEND)
    if resolved == _target and writing:
        raise OSError('verification fault: direct final-path os.open')
    return _real_os_open(path, flags, *args, **kwargs)

def _check_closed(src):
    path = _path(src)
    tracked = _tracked.get(path)
    if tracked is not None and not tracked.closed:
        raise OSError('verification fault: temporary file renamed before close')

def replace(src, dst, *args, **kwargs):
    _check_closed(src)
    return _real_replace(src, dst, *args, **kwargs)

def rename(src, dst, *args, **kwargs):
    _check_closed(src)
    return _real_rename(src, dst, *args, **kwargs)

builtins.open = builtin_open
io.open = io_open
os.open = os_open
os.replace = replace
os.rename = rename
'''
with open(os.path.join(hooks, 'sitecustomize.py'), 'w', encoding='utf-8') as f:
    f.write(sitecustomize)
env = os.environ.copy()
env['CBA_ATOMIC_FINAL'] = atomic_final
env['PYTHONPATH'] = hooks + (os.pathsep + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
result = run_tool(atomic_archive, atomic_out, env)
assert result.returncode == 0, 'atomic-write test failed: ' + result.stderr.decode('utf-8', errors='replace')
with open(atomic_final, 'rb') as f:
    assert f.read() == atomic_data, 'final file was not atomically replaced with complete data'
for directory, _, files in os.walk(atomic_out):
    for filename in files:
        assert os.path.realpath(os.path.join(directory, filename)) == atomic_final, 'temporary file remained after atomic extraction'
TEST_EOF

if ! python3 /tmp/test_tool_behavior.py 2>&1; then
    status=1
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
