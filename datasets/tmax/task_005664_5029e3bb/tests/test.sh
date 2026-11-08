#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import gzip
import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile

SCRIPT = '/home/user/process_docs.py'
PROCESSED = '/home/user/processed_docs'
MANIFEST = '/home/user/manifest.jsonl'
CHECKSUM = '/home/user/manifest_checksum.txt'


def test_script_exists_and_contains_requirements():
    """Preserve the original source-presence assertions."""
    assert os.path.exists(SCRIPT), f"Script {SCRIPT} does not exist."
    with open(SCRIPT, 'r') as f:
        content = f.read()
    assert 'multiprocessing' in content, "Script does not use multiprocessing."
    assert 'fcntl' in content and 'flock' in content, "Script does not use fcntl.flock."


def test_processed_docs_files_and_line_counts():
    """Preserve the original output assertions."""
    assert os.path.isdir(PROCESSED), f"Directory {PROCESSED} does not exist."
    expected_files = {
        'intro.md': 30,
        'api_reference.md': 50,
        'advanced_guide_part1.md': 50,
        'advanced_guide_part2.md': 50,
        'advanced_guide_part3.md': 25,
    }
    actual_files = os.listdir(PROCESSED)
    assert set(actual_files) == set(expected_files), f"Files in {PROCESSED} do not match expected files."
    for filename, expected_lines in expected_files.items():
        with open(os.path.join(PROCESSED, filename), 'r') as f:
            lines = f.readlines()
        assert len(lines) == expected_lines, f"File {filename} has {len(lines)} lines, expected {expected_lines}."


def test_initial_processed_contents_match_archive():
    """Ensure the submitted initial outputs contain the archive's actual bytes."""
    expected = {}
    with tarfile.open('/home/user/raw_docs.tar.gz', 'r:gz') as tf:
        for member in tf.getmembers():
            if member.isfile() and member.name.endswith('.md'):
                expected[os.path.basename(member.name)] = tf.extractfile(member).read()

    reconstructed = {
        'intro.md': open(os.path.join(PROCESSED, 'intro.md'), 'rb').read(),
        'api_reference.md': open(os.path.join(PROCESSED, 'api_reference.md'), 'rb').read(),
        'advanced_guide.md': b''.join(
            open(os.path.join(PROCESSED, f'advanced_guide_part{i}.md'), 'rb').read()
            for i in (1, 2, 3)
        ),
    }
    assert reconstructed == expected


def test_manifest_content():
    """Preserve the original manifest assertions."""
    assert os.path.exists(MANIFEST), f"Manifest file {MANIFEST} does not exist."
    expected_records = [
        {"original": "intro.md", "chunks": ["intro.md"]},
        {"original": "api_reference.md", "chunks": ["api_reference.md"]},
        {"original": "advanced_guide.md", "chunks": ["advanced_guide_part1.md", "advanced_guide_part2.md", "advanced_guide_part3.md"]},
    ]
    actual_records = []
    with open(MANIFEST, 'r') as f:
        for line in f:
            line = line.strip()
            if line:
                actual_records.append(json.loads(line))
    assert len(actual_records) == len(expected_records), "Manifest does not contain the expected number of records."
    expected_records.sort(key=lambda x: x['original'])
    actual_records.sort(key=lambda x: x['original'])
    assert actual_records == expected_records, "Manifest JSON records do not match expected records."


def test_manifest_checksum():
    """Preserve the original checksum assertions."""
    assert os.path.exists(MANIFEST), f"Manifest file {MANIFEST} does not exist."
    assert os.path.exists(CHECKSUM), f"Checksum file {CHECKSUM} does not exist."
    sha256 = hashlib.sha256()
    with open(MANIFEST, 'rb') as f:
        for block in iter(lambda: f.read(4096), b''):
            sha256.update(block)
    actual_hash = sha256.hexdigest()
    with open(CHECKSUM, 'r') as f:
        checksum_content = f.read().strip()
    assert checksum_content.startswith(actual_hash), "Checksum in manifest_checksum.txt does not match the actual SHA256 of manifest.jsonl."
    assert 'manifest.jsonl' in checksum_content, "Checksum file does not contain the filename 'manifest.jsonl'."


def test_source_uses_stream_members_pool_and_exclusive_flock():
    """Check executable constructs rather than accepting requirement words in comments."""
    with open(SCRIPT, 'r') as f:
        tree = ast.parse(f.read(), SCRIPT)

    calls = [n for n in ast.walk(tree) if isinstance(n, ast.Call)]
    attrs = [n.func.attr for n in calls if isinstance(n.func, ast.Attribute)]
    names = [n.func.id for n in calls if isinstance(n.func, ast.Name)]

    assert 'extractall' not in attrs and 'extract' not in attrs, \
        "The archive must not be extracted to disk before processing."
    assert 'extractfile' in attrs or 'extractfile' in names, \
        "Markdown members must be read directly from the tar archive."
    assert any(x in attrs + names for x in ('Pool', 'Process')), \
        "No multiprocessing Pool or Process is actually constructed."
    assert 'flock' in attrs + names, "fcntl.flock is not called."

    lock_ex_used = any(
        isinstance(n, ast.Attribute) and n.attr == 'LOCK_EX'
        for n in ast.walk(tree)
    )
    assert lock_ex_used, "flock must be invoked with an exclusive LOCK_EX lock."


def clear_outputs():
    shutil.rmtree(PROCESSED, ignore_errors=True)
    for path in (MANIFEST, CHECKSUM):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def make_archive(path, entries):
    with tarfile.open(path, 'w:gz') as tf:
        for name, data in entries.items():
            info = tarfile.TarInfo(name)
            info.size = len(data)
            tf.addfile(info, io.BytesIO(data))


def run_script(archive, env=None):
    merged = os.environ.copy()
    if env:
        merged.update(env)
    proc = subprocess.Popen(
        [sys.executable, SCRIPT, archive], cwd='/home/user', env=merged,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    out, err = proc.communicate(timeout=30)
    return proc.pid, proc.returncode, out, err


def read_manifest():
    with open(MANIFEST, 'r') as f:
        lines = [line for line in f if line.strip()]
    return [json.loads(line) for line in lines]


def test_script_on_derived_archive_with_real_workers_and_flock():
    """Execute the artifact on fresh data and record real flock calls and process IDs."""
    clear_outputs()
    work = tempfile.mkdtemp(prefix='docs-verifier-')
    try:
        archive = os.path.join(work, 'new_docs.tar.gz')
        seven = b''.join(f'unique alpha {i}\n'.encode() for i in range(1, 8))
        fifty = b''.join(f'exact boundary {i}\n'.encode() for i in range(1, 51))
        fifty_one = b''.join(f'split payload {i}\n'.encode() for i in range(1, 51)) + b'last line without newline'
        entries = {
            'alpha.md': seven,
            'boundary.md': fifty,
            'changing.md': fifty_one,
            'ignored.txt': b'not markdown\n',
        }
        make_archive(archive, entries)

        hookdir = os.path.join(work, 'hook')
        os.mkdir(hookdir)
        locklog = os.path.join(work, 'flock.log')
        hook = """import fcntl, os
_real_flock = fcntl.flock
_log = os.environ.get('VERIFY_FLOCK_LOG')
def _tracked_flock(fd, operation):
    if _log:
        out = os.open(_log, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o666)
        try:
            os.write(out, ('%d %d\\n' % (os.getpid(), operation)).encode())
        finally:
            os.close(out)
    return _real_flock(fd, operation)
fcntl.flock = _tracked_flock
"""
        with open(os.path.join(hookdir, 'sitecustomize.py'), 'w') as f:
            f.write(hook)

        old_pythonpath = os.environ.get('PYTHONPATH', '')
        pythonpath = hookdir + (os.pathsep + old_pythonpath if old_pythonpath else '')
        parent_pid, rc, out, err = run_script(archive, {
            'PYTHONPATH': pythonpath,
            'VERIFY_FLOCK_LOG': locklog,
        })
        assert rc == 0, f"Script failed on valid archive: stdout={out!r}, stderr={err!r}"

        expected_files = {
            'alpha.md': seven,
            'boundary.md': fifty,
            'changing_part1.md': b''.join(f'split payload {i}\n'.encode() for i in range(1, 51)),
            'changing_part2.md': b'last line without newline',
        }
        assert os.path.isdir(PROCESSED)
        assert set(os.listdir(PROCESSED)) == set(expected_files)
        for name, expected_bytes in expected_files.items():
            with open(os.path.join(PROCESSED, name), 'rb') as f:
                assert f.read() == expected_bytes, f"Incorrect content in {name}"

        expected_records = [
            {"original": "alpha.md", "chunks": ["alpha.md"]},
            {"original": "boundary.md", "chunks": ["boundary.md"]},
            {"original": "changing.md", "chunks": ["changing_part1.md", "changing_part2.md"]},
        ]
        actual_records = read_manifest()
        assert sorted(actual_records, key=lambda r: r['original']) == sorted(expected_records, key=lambda r: r['original'])

        assert os.path.exists(locklog), "No actual fcntl.flock call was observed."
        with open(locklog, 'r') as f:
            lock_calls = [tuple(map(int, line.split())) for line in f if line.strip()]
        assert len(lock_calls) >= 3, "Each worker manifest append must be protected by flock."
        assert all(operation & 2 for _, operation in lock_calls), "Observed flock was not exclusive (LOCK_EX)."
        assert any(pid != parent_pid for pid, _ in lock_calls), \
            "Manifest locking did not occur in a multiprocessing worker process."
    finally:
        shutil.rmtree(work, ignore_errors=True)


def test_corrupt_gzip_exits_one_before_producing_outputs():
    """A bad gzip CRC must be detected before markdown processing starts."""
    clear_outputs()
    work = tempfile.mkdtemp(prefix='corrupt-verifier-')
    try:
        raw_tar = io.BytesIO()
        with tarfile.open(fileobj=raw_tar, mode='w') as tf:
            data = b'should never be emitted\n'
            info = tarfile.TarInfo('forbidden.md')
            info.size = len(data)
            tf.addfile(info, io.BytesIO(data))
        damaged = bytearray(gzip.compress(raw_tar.getvalue()))
        damaged[-8] ^= 0x01  # invalidate the gzip CRC while retaining a readable tar payload
        archive = os.path.join(work, 'bad.tar.gz')
        with open(archive, 'wb') as f:
            f.write(damaged)

        _, rc, out, err = run_script(archive)
        assert rc == 1, f"Corrupt gzip must exit with status 1, got {rc}: stdout={out!r}, stderr={err!r}"
        assert not os.path.exists(MANIFEST) or os.path.getsize(MANIFEST) == 0, \
            "The archive was processed before gzip integrity verification completed."
        assert not os.path.isdir(PROCESSED) or os.listdir(PROCESSED) == [], \
            "Files were written from an archive whose gzip integrity was invalid."
    finally:
        shutil.rmtree(work, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
