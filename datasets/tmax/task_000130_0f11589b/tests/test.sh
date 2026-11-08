#!/bin/bash
set +e
mkdir -p /logs/verifier
STATUS=0

# Stop stale services and remove any pre-existing results so only this run counts.
redis-cli -p 6379 shutdown nosave >/dev/null 2>&1 || true
pkill -f 'uvicorn.*uploader' >/dev/null 2>&1 || true
pkill -x processor >/dev/null 2>&1 || true
sleep 1
rm -rf /home/user/pipeline/incoming/* /home/user/pipeline/extracted/* /home/user/pipeline/manifests/*
rm -f /tmp/pipeline_absolute_escape /tmp/pipeline_traversal_escape /tmp/pipeline_symlink_escape
mkdir -p /app/corpus/evil /app/corpus/clean
rm -f /app/corpus/evil/*.tar /app/corpus/clean/*.tar

# Build a private behavioral corpus with independently known contents.
python3 - <<'PY'
import io
import os
import tarfile

clean = '/app/corpus/clean'
evil = '/app/corpus/evil'

def make_tar(path, entries):
    with tarfile.open(path, 'w') as tf:
        for name, data in entries:
            info = tarfile.TarInfo(name)
            info.mode = 0o644
            info.size = len(data)
            tf.addfile(info, io.BytesIO(data))

shared = b'shared-content-for-hardlink-test\x00\x01\n'
make_tar(os.path.join(clean, 'audit_clean_alpha.tar'), [
    ('shared.bin', shared),
    ('alpha.txt', b'alpha-only\n'),
    ('nested/value.dat', b'nested-alpha-value\n'),
])
make_tar(os.path.join(clean, 'audit_clean_beta.tar'), [
    ('shared-copy.bin', shared),
    ('beta.txt', b'beta-only\n'),
])

make_tar(os.path.join(evil, 'audit_evil_traversal.tar'), [
    ('../../../../tmp/pipeline_traversal_escape', b'escaped'),
    ('apparently-safe.txt', b'archive must be rejected as a whole'),
])
make_tar(os.path.join(evil, 'audit_evil_absolute.tar'), [
    ('/tmp/pipeline_absolute_escape', b'escaped'),
])
with tarfile.open(os.path.join(evil, 'audit_evil_symlink.tar'), 'w') as tf:
    link = tarfile.TarInfo('escape_link')
    link.type = tarfile.SYMTYPE
    link.linkname = '../../../../tmp'
    link.mode = 0o777
    tf.addfile(link)
    payload = b'escaped through symlink'
    child = tarfile.TarInfo('escape_link/pipeline_symlink_escape')
    child.size = len(payload)
    child.mode = 0o644
    tf.addfile(child, io.BytesIO(payload))
PY
if [ $? -ne 0 ]; then STATUS=1; fi

if [ ! -f /home/user/pipeline/start_all.sh ]; then
    STATUS=1
else
    chmod +x /home/user/pipeline/start_all.sh
    (cd /home/user/pipeline && bash ./start_all.sh) >/tmp/pipeline_start.log 2>&1 &
    START_PID=$!

    READY=0
    for _ in $(seq 1 90); do
        if redis-cli -p 6379 ping 2>/dev/null | grep -q '^PONG$' && curl -fsS http://127.0.0.1:8000/openapi.json >/dev/null 2>&1; then
            READY=1
            break
        fi
        sleep 1
    done
    if [ "$READY" -ne 1 ]; then STATUS=1; fi
fi

# Exercise the required HTTP upload path rather than placing work directly on Redis.
if [ "$STATUS" -eq 0 ]; then
    for archive in /app/corpus/clean/*.tar /app/corpus/evil/*.tar; do
        curl -fsS -X POST -F "file=@${archive}" http://127.0.0.1:8000/upload >/dev/null
        if [ $? -ne 0 ]; then STATUS=1; fi
    done
fi

# Give the blocking daemon time to consume all six queue entries.
for _ in $(seq 1 60); do
    if [ -f /home/user/pipeline/manifests/audit_clean_alpha.manifest ] && \
       [ -f /home/user/pipeline/manifests/audit_clean_beta.manifest ]; then
        break
    fi
    sleep 1
done

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import hashlib
import os
import re
from collections import defaultdict


def get_files_in_dir(directory):
    return [f for f in os.listdir(directory) if os.path.isfile(os.path.join(directory, f))]


def test_evil_corpus_rejected():
    evil_corpus_dir = "/app/corpus/evil"
    if not os.path.exists(evil_corpus_dir):
        return

    evil_tars = glob.glob(os.path.join(evil_corpus_dir, "*.tar"))
    bypassed = []

    for tar_path in evil_tars:
        dataset_name = os.path.basename(tar_path)[:-4]
        manifest_path = f"/home/user/pipeline/manifests/{dataset_name}.manifest"
        extracted_dir = f"/home/user/pipeline/extracted/{dataset_name}"

        if os.path.exists(manifest_path) or os.path.exists(extracted_dir):
            bypassed.append(dataset_name)

    assert not bypassed, f"{len(bypassed)} of {len(evil_tars)} evil bypassed: {bypassed}"


def test_clean_corpus_accepted():
    clean_corpus_dir = "/app/corpus/clean"
    if not os.path.exists(clean_corpus_dir):
        return

    clean_tars = glob.glob(os.path.join(clean_corpus_dir, "*.tar"))
    failed = []

    for tar_path in clean_tars:
        dataset_name = os.path.basename(tar_path)[:-4]
        manifest_path = f"/home/user/pipeline/manifests/{dataset_name}.manifest"
        extracted_dir = f"/home/user/pipeline/extracted/{dataset_name}"

        if not os.path.exists(manifest_path) or not os.path.exists(extracted_dir):
            failed.append(dataset_name)

    assert not failed, f"{len(failed)} of {len(clean_tars)} clean modified or rejected: {failed}"


def test_hardlinks_created_for_identical_files():
    extracted_base = "/home/user/pipeline/extracted"
    if not os.path.exists(extracted_base):
        return

    content_map = defaultdict(list)

    for root, _, files in os.walk(extracted_base):
        for file in files:
            file_path = os.path.join(root, file)
            if not os.path.isfile(file_path) or os.path.islink(file_path):
                continue

            hasher = hashlib.sha256()
            with open(file_path, 'rb') as f:
                hasher.update(f.read())
            file_hash = hasher.hexdigest()
            content_map[file_hash].append(file_path)

    for file_hash, paths in content_map.items():
        if len(paths) > 1:
            inodes = {os.stat(p).st_ino for p in paths}
            assert len(inodes) == 1, f"Files with identical content are not hardlinked: {paths}"
            for p in paths:
                assert os.stat(p).st_nlink > 1, f"File {p} does not have link count > 1"


def expected_datasets():
    return {
        'audit_clean_alpha': {
            'shared.bin': b'shared-content-for-hardlink-test\x00\x01\n',
            'alpha.txt': b'alpha-only\n',
            'nested/value.dat': b'nested-alpha-value\n',
        },
        'audit_clean_beta': {
            'shared-copy.bin': b'shared-content-for-hardlink-test\x00\x01\n',
            'beta.txt': b'beta-only\n',
        },
    }


def test_clean_contents_and_manifests_are_exact():
    base = '/home/user/pipeline/extracted'
    manifests = '/home/user/pipeline/manifests'
    for dataset, expected in expected_datasets().items():
        root = os.path.join(base, dataset)
        actual_paths = []
        for walk_root, dirs, files in os.walk(root):
            for name in files:
                path = os.path.join(walk_root, name)
                assert not os.path.islink(path)
                actual_paths.append(os.path.relpath(path, root).replace(os.sep, '/'))
        assert set(actual_paths) == set(expected), (dataset, actual_paths)

        expected_hashes = {}
        for rel, content in expected.items():
            path = os.path.join(root, *rel.split('/'))
            with open(path, 'rb') as f:
                actual = f.read()
            assert actual == content
            expected_hashes[rel] = hashlib.sha256(content).hexdigest()

        manifest_path = os.path.join(manifests, dataset + '.manifest')
        parsed = {}
        with open(manifest_path, 'r', encoding='utf-8') as f:
            for line in f:
                assert re.fullmatch(r'[0-9a-f]{64}  [^\n]+\n', line), repr(line)
                digest, rel = line[:-1].split('  ', 1)
                assert not os.path.isabs(rel) and '..' not in rel.split('/')
                assert rel not in parsed
                parsed[rel] = digest
        assert parsed == expected_hashes


def test_known_cross_dataset_duplicate_is_hardlinked():
    first = '/home/user/pipeline/extracted/audit_clean_alpha/shared.bin'
    second = '/home/user/pipeline/extracted/audit_clean_beta/shared-copy.bin'
    a, b = os.stat(first), os.stat(second)
    assert a.st_dev == b.st_dev and a.st_ino == b.st_ino
    assert a.st_nlink >= 2 and b.st_nlink >= 2
    assert os.path.exists('/home/user/pipeline/hardlink.lock')


def test_malicious_archives_did_not_escape():
    for path in (
        '/tmp/pipeline_absolute_escape',
        '/tmp/pipeline_traversal_escape',
        '/tmp/pipeline_symlink_escape',
    ):
        assert not os.path.lexists(path), f'archive wrote outside extraction root: {path}'


def test_required_rust_and_mmap_implementation_present():
    main_path = '/home/user/pipeline/processor/src/main.rs'
    cargo_path = '/home/user/pipeline/processor/Cargo.toml'
    assert os.path.isfile(main_path) and os.path.isfile(cargo_path)
    source = open(main_path, encoding='utf-8').read()
    cargo = open(cargo_path, encoding='utf-8').read()
    combined = source + '\n' + cargo
    assert 'Hello, world!' not in source
    assert re.search(r'\b(mmap|Mmap|MmapOptions|memmap)\b', combined), 'no memory-mapped I/O implementation found'
    assert os.path.isfile('/home/user/pipeline/start_all.sh')
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
PYTEST_STATUS=$?
if [ "$STATUS" -eq 0 ] && [ "$PYTEST_STATUS" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
