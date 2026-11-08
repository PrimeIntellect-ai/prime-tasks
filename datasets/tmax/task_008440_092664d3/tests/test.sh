#!/bin/bash
set +e
mkdir -p /logs/verifier
ok=1

# Replace the inputs and remove stale outputs so organize.py must be executed
# against fresh, nested, non-lexicographically-numbered fragments.
python3 - <<'PY' || ok=0
import os
import shutil
from pathlib import Path

root = Path('/home/user/project_data')
for base, dirs, files in os.walk(root, followlinks=False):
    for name in files:
        if name.startswith('part_') and name.endswith('.bin'):
            os.unlink(os.path.join(base, name))

for path in Path('/home/user').glob('split_*.bin'):
    path.unlink()
for path in ['/home/user/merged.bin', '/home/user/result.txt']:
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass

locations = [
    ('fragments/a', 1),
    ('fragments/deep/b', 2),
    ('fragments', 3),
    ('fragments/deep/c', 10),
    ('fragments/z', 11),
]
parts = []
for directory, number in locations:
    target_dir = root / directory
    target_dir.mkdir(parents=True, exist_ok=True)
    data = os.urandom(524288)
    target = target_dir / f'part_{number}.bin'
    target.write_bytes(data)
    parts.append((number, data))

with open(root / 'reference.bin', 'wb') as ref:
    for _, data in sorted(parts):
        ref.write(data)
PY

cat <<'PY' > /tmp/instrument_runner.py
import builtins
import fcntl
import io
import json
import mmap
import os
import runpy
import traceback

MERGED = os.path.realpath('/home/user/merged.bin')
REFERENCE = os.path.realpath('/home/user/project_data/reference.bin')
FRAGMENTS = {}
for base, dirs, files in os.walk('/home/user/project_data', followlinks=False):
    for name in files:
        if name.startswith('part_') and name.endswith('.bin'):
            path = os.path.realpath(os.path.join(base, name))
            FRAGMENTS[path] = os.path.getsize(path)
EXPECTED_SIZE = os.path.getsize(REFERENCE)

events = {
    'fragment_bytes': {path: 0 for path in FRAGMENTS},
    'reference_reads': [],
    'merged_writes': 0,
    'merged_write_without_lock': False,
    'reference_read_before_merge': False,
    'locks': 0,
    'unlocks': 0,
    'mmaps': [],
}
locked_fds = set()
orig_open = builtins.open
orig_io_open = io.open
orig_flock = fcntl.flock
orig_mmap = mmap.mmap

def fd_path(fd):
    try:
        return os.path.realpath(os.readlink(f'/proc/self/fd/{int(fd)}'))
    except Exception:
        return None

def note_read(path, requested, returned):
    if path in FRAGMENTS:
        events['fragment_bytes'][path] += returned
    if path == REFERENCE and returned:
        events['reference_reads'].append({'requested': requested, 'returned': returned})
        if events['merged_writes'] < EXPECTED_SIZE:
            events['reference_read_before_merge'] = True

def note_write(path, fd, amount):
    if path == MERGED and amount:
        if fd not in locked_fds:
            events['merged_write_without_lock'] = True
        events['merged_writes'] += amount

class TrackedFile:
    def __init__(self, wrapped, path):
        self._wrapped = wrapped
        self._path = path

    def fileno(self):
        return self._wrapped.fileno()

    def read(self, size=-1):
        data = self._wrapped.read(size)
        note_read(self._path, size, len(data) if data is not None else 0)
        return data

    def read1(self, size=-1):
        data = self._wrapped.read1(size)
        note_read(self._path, size, len(data) if data is not None else 0)
        return data

    def readinto(self, buffer):
        result = self._wrapped.readinto(buffer)
        note_read(self._path, len(buffer), result or 0)
        return result

    def readline(self, size=-1):
        data = self._wrapped.readline(size)
        note_read(self._path, size, len(data) if data is not None else 0)
        return data

    def write(self, data):
        note_write(self._path, self.fileno(), len(data))
        return self._wrapped.write(data)

    def writelines(self, lines):
        materialized = list(lines)
        note_write(self._path, self.fileno(), sum(len(x) for x in materialized))
        return self._wrapped.writelines(materialized)

    def close(self):
        try:
            fd = self.fileno()
        except Exception:
            fd = None
        if fd in locked_fds:
            locked_fds.discard(fd)
            events['unlocks'] += 1
        return self._wrapped.close()

    @property
    def closed(self):
        return self._wrapped.closed

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        self.close()
        return False

    def __iter__(self):
        return self

    def __next__(self):
        data = next(self._wrapped)
        note_read(self._path, -1, len(data))
        return data

    def __getattr__(self, name):
        return getattr(self._wrapped, name)

def tracked_open(file, *args, **kwargs):
    wrapped = orig_open(file, *args, **kwargs)
    try:
        path = os.path.realpath(os.fspath(file))
    except TypeError:
        path = fd_path(wrapped.fileno())
    if path in FRAGMENTS or path in (REFERENCE, MERGED):
        return TrackedFile(wrapped, path)
    return wrapped

def tracked_io_open(file, *args, **kwargs):
    wrapped = orig_io_open(file, *args, **kwargs)
    try:
        path = os.path.realpath(os.fspath(file))
    except TypeError:
        path = fd_path(wrapped.fileno())
    if path in FRAGMENTS or path in (REFERENCE, MERGED):
        return TrackedFile(wrapped, path)
    return wrapped

def tracked_flock(file, operation):
    fd = file if isinstance(file, int) else file.fileno()
    path = fd_path(fd)
    result = orig_flock(file, operation)
    if path == MERGED:
        if operation & fcntl.LOCK_UN:
            if fd in locked_fds:
                locked_fds.discard(fd)
                events['unlocks'] += 1
        elif operation & fcntl.LOCK_EX:
            locked_fds.add(fd)
            events['locks'] += 1
    return result

def tracked_mmap(fileno, length, *args, **kwargs):
    path = fd_path(fileno)
    if path:
        events['mmaps'].append(path)
    return orig_mmap(fileno, length, *args, **kwargs)

builtins.open = tracked_open
io.open = tracked_io_open
fcntl.flock = tracked_flock
mmap.mmap = tracked_mmap

status = 0
try:
    os.chdir('/home/user')
    runpy.run_path('/home/user/organize.py', run_name='__main__')
except BaseException:
    status = 1
    traceback.print_exc()
finally:
    with orig_open('/tmp/organize_events.json', 'w') as output:
        json.dump(events, output)
raise SystemExit(status)
PY

if [ "$ok" -eq 1 ]; then
    timeout 20s python3 /tmp/instrument_runner.py
    [ $? -eq 0 ] || ok=0
fi

cat <<'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os


def get_file_hash(filepath):
    hasher = hashlib.md5()
    with open(filepath, 'rb') as f:
        for chunk in iter(lambda: f.read(4096), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def test_result_txt_content():
    result_file = "/home/user/result.txt"
    assert os.path.isfile(result_file), f"{result_file} does not exist."
    with open(result_file, 'r') as f:
        content = f.read().strip()
    assert content == "MATCH", f"{result_file} contains '{content}', expected 'MATCH'."


def test_merged_bin_matches_reference():
    merged_file = "/home/user/merged.bin"
    ref_file = "/home/user/project_data/reference.bin"
    assert os.path.isfile(merged_file), f"{merged_file} does not exist."
    assert os.path.isfile(ref_file), f"{ref_file} does not exist."
    assert get_file_hash(merged_file) == get_file_hash(ref_file), \
        "The merged.bin file does not match the reference.bin file."


def test_split_files():
    ref_file = "/home/user/project_data/reference.bin"
    assert os.path.isfile(ref_file), f"{ref_file} does not exist."
    split_0 = "/home/user/split_0.bin"
    split_1 = "/home/user/split_1.bin"
    split_2 = "/home/user/split_2.bin"
    assert os.path.isfile(split_0), f"{split_0} does not exist."
    assert os.path.isfile(split_1), f"{split_1} does not exist."
    assert os.path.isfile(split_2), f"{split_2} does not exist."
    assert os.path.getsize(split_0) == 1048576, f"{split_0} size is incorrect."
    assert os.path.getsize(split_1) == 1048576, f"{split_1} size is incorrect."
    assert os.path.getsize(split_2) == 524288, f"{split_2} size is incorrect."
    assert not os.path.exists('/home/user/split_3.bin'), "An unexpected split_3.bin was created."
    hasher = hashlib.md5()
    for split_file in [split_0, split_1, split_2]:
        with open(split_file, 'rb') as f:
            for chunk in iter(lambda: f.read(4096), b""):
                hasher.update(chunk)
    assert hasher.hexdigest() == get_file_hash(ref_file), \
        "The concatenated split files do not match the reference.bin file."


def test_script_contains_required_modules():
    script_file = "/home/user/organize.py"
    assert os.path.isfile(script_file), f"Script {script_file} does not exist."
    with open(script_file, 'r') as f:
        content = f.read()
    assert "fcntl" in content, "The script does not seem to use the 'fcntl' module."
    assert "mmap" in content, "The script does not seem to use the 'mmap' module."


def test_required_operations_were_exercised():
    with open('/tmp/organize_events.json') as f:
        events = json.load(f)

    assert events['fragment_bytes'], "No fragment files were discovered."
    for path, byte_count in events['fragment_bytes'].items():
        assert byte_count >= os.path.getsize(path), f"Fragment was not fully read: {path}"

    expected_size = os.path.getsize('/home/user/project_data/reference.bin')
    assert events['merged_writes'] >= expected_size, "merged.bin was not produced by writing merged data."
    assert events['locks'] >= 1, "No exclusive flock was acquired on merged.bin."
    assert events['unlocks'] >= 1, "The merged.bin lock was not released."
    assert not events['merged_write_without_lock'], "merged.bin was written while not exclusively locked."
    assert not events['reference_read_before_merge'], "reference.bin was read to produce merged.bin."

    mmaps = set(events['mmaps'])
    assert os.path.realpath('/home/user/merged.bin') in mmaps, "merged.bin was not memory-mapped."
    assert os.path.realpath('/home/user/project_data/reference.bin') in mmaps, \
        "reference.bin was not memory-mapped."

    reads = events['reference_reads']
    assert sum(item['returned'] for item in reads) >= expected_size, \
        "reference.bin was not streamed while creating the split files."
    assert all(0 <= item['requested'] <= 262144 for item in reads), \
        "reference.bin was read in an unbounded or excessively large block instead of streaming."
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
[ $? -eq 0 ] || ok=0

if [ "$ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
