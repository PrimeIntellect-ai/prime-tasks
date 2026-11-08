#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import hashlib
import subprocess
import tempfile
import tarfile

RESTORE_DIR = '/home/user/restore'
FINAL_HASHES_FILE = '/home/user/final_hashes.txt'
MERGED_TAR = '/home/user/merged.tar.gz'
EXTRACTOR_SRC = '/home/user/extractor.c'
PATCHER_SRC = '/home/user/patcher.c'


def compile_c(source, output):
    assert os.path.isfile(source), f"{source} was not created."
    assert os.path.getsize(source) > 0, f"{source} is empty."
    result = subprocess.run(
        ['gcc', '-std=c11', '-D_POSIX_C_SOURCE=200809L', '-Wall', '-Wextra', '-Werror', source, '-o', output],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert result.returncode == 0, f"Failed to compile {source}:\n{result.stdout}{result.stderr}"


def test_c_programs_parse_fresh_inputs():
    # Compile and execute the submitted programs against fresh, derived test data.
    # Run in a copied filesystem tree because the required programs use fixed paths.
    with tempfile.TemporaryDirectory() as td:
        root = os.path.join(td, 'root')
        os.makedirs(os.path.join(root, 'home', 'user', 'backups', 'increments'))
        os.makedirs(os.path.join(root, 'home', 'user', 'restore'))

        extractor_bin = os.path.join(root, 'extractor')
        patcher_bin = os.path.join(root, 'patcher')
        compile_c(EXTRACTOR_SRC, extractor_bin)
        compile_c(PATCHER_SRC, patcher_bin)

        # Build a new tar.gz whose bytes and chunk boundaries are not the setup fixture.
        base_dir = os.path.join(td, 'base')
        os.makedirs(os.path.join(base_dir, 'nested'))
        base_a = b'fresh base text\nwith another line\n'
        base_b = bytes(range(256)) + b'\x00marker-like:[CHUNK_END]\n'
        doomed = b'remove this fresh file'
        open(os.path.join(base_dir, 'alpha.txt'), 'wb').write(base_a)
        open(os.path.join(base_dir, 'nested', 'data.bin'), 'wb').write(base_b)
        open(os.path.join(base_dir, 'doomed.txt'), 'wb').write(doomed)
        fresh_tar = os.path.join(td, 'fresh.tar.gz')
        with tarfile.open(fresh_tar, 'w:gz') as tf:
            tf.add(os.path.join(base_dir, 'alpha.txt'), arcname='alpha.txt')
            tf.add(os.path.join(base_dir, 'nested'), arcname='nested')
        tar_bytes = open(fresh_tar, 'rb').read()

        cuts = [1, max(2, len(tar_bytes)//5), max(3, len(tar_bytes)//2), len(tar_bytes)-1]
        cuts = sorted(set(c for c in cuts if 0 < c < len(tar_bytes)))
        chunks = []
        start = 0
        for end in cuts + [len(tar_bytes)]:
            chunks.append(tar_bytes[start:end])
            start = end

        raw_path = os.path.join(root, 'home', 'user', 'backups', 'raw_dump.dat')
        with open(raw_path, 'wb') as out:
            out.write(b'unrelated logs\n[CHUNK_START:not-a-size]\nmore text\n')
            for i, chunk in enumerate(chunks):
                out.write(f'[CHUNK_START:{len(chunk)}]\n'.encode())
                out.write(chunk)
                out.write(b'\n[CHUNK_END]\n')
                out.write(f'log after chunk {i}\n'.encode())

        # chroot makes the absolute paths required by the task refer to this fresh tree.
        for binary in (extractor_bin, patcher_bin):
            # Dynamically linked binaries need their loader and libc in the chroot.
            ldd = subprocess.check_output(['ldd', binary], text=True)
            libs = []
            for line in ldd.splitlines():
                for token in line.replace('=>', ' ').split():
                    if token.startswith('/') and os.path.isfile(token):
                        libs.append(token)
            for lib in libs:
                dest = root + lib
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                if not os.path.exists(dest):
                    import shutil
                    shutil.copy2(lib, dest)

        r = subprocess.run(['chroot', root, '/extractor'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert r.returncode == 0, f'extractor failed on fresh input: {r.stderr.decode(errors="replace")}'
        merged = os.path.join(root, 'home', 'user', 'merged.tar.gz')
        assert os.path.isfile(merged), 'extractor did not create merged.tar.gz on fresh input'
        assert open(merged, 'rb').read() == tar_bytes, 'extractor did not reconstruct fresh chunks exactly'

        fresh_restore = os.path.join(root, 'home', 'user', 'restore')
        with tarfile.open(merged, 'r:gz') as tf:
            tf.extractall(fresh_restore)
        # doomed.txt was deliberately not archived above; create it to exercise DELETE.
        open(os.path.join(fresh_restore, 'doomed.txt'), 'wb').write(doomed)

        add_a = b'fresh append\x00text\n'
        add_b = bytes(reversed(range(64)))
        inc_dir = os.path.join(root, 'home', 'user', 'backups', 'increments')
        open(os.path.join(inc_dir, 'a.inc'), 'wb').write(add_a)
        open(os.path.join(inc_dir, 'b.inc'), 'wb').write(add_b)
        diff = os.path.join(root, 'home', 'user', 'backups', 'differential.log')
        with open(diff, 'w', newline='\n') as f:
            f.write('OPERATION: APPEND\nTARGET: nested/data.bin\nSOURCE: /home/user/backups/increments/b.inc\n---\n')
            f.write('OPERATION: DELETE\nTARGET: doomed.txt\n---\n')
            f.write('OPERATION: APPEND\nTARGET: alpha.txt\nSOURCE: /home/user/backups/increments/a.inc\n---\n')

        r = subprocess.run(['chroot', root, '/patcher'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert r.returncode == 0, f'patcher failed on fresh input: {r.stderr.decode(errors="replace")}'
        assert open(os.path.join(fresh_restore, 'alpha.txt'), 'rb').read() == base_a + add_a
        assert open(os.path.join(fresh_restore, 'nested', 'data.bin'), 'rb').read() == base_b + add_b
        assert not os.path.exists(os.path.join(fresh_restore, 'doomed.txt'))


def test_merged_tarball_exists():
    assert os.path.isfile(MERGED_TAR), f"{MERGED_TAR} was not created."
    assert os.path.getsize(MERGED_TAR) > 0, f"{MERGED_TAR} is empty."


def test_file3_deleted():
    file3_path = os.path.join(RESTORE_DIR, 'file3.txt')
    assert not os.path.exists(file3_path), f"file3.txt should have been deleted from {RESTORE_DIR}."


def test_file1_content():
    file1_path = os.path.join(RESTORE_DIR, 'file1.txt')
    assert os.path.isfile(file1_path), f"{file1_path} is missing."
    expected_content = b"Base data AAppended data A"
    with open(file1_path, 'rb') as f:
        actual_content = f.read()
    assert actual_content == expected_content, f"Content of {file1_path} is incorrect. Expected {expected_content}, got {actual_content}."


def test_file2_content():
    file2_path = os.path.join(RESTORE_DIR, 'file2.bin')
    assert os.path.isfile(file2_path), f"{file2_path} is missing."
    expected_content = (b'\x01' * 100) + (b'\x02' * 50)
    with open(file2_path, 'rb') as f:
        actual_content = f.read()
    assert actual_content == expected_content, f"Content of {file2_path} is incorrect."


def test_final_hashes_file():
    assert os.path.isfile(FINAL_HASHES_FILE), f"{FINAL_HASHES_FILE} was not created."
    f1_hash = hashlib.sha256(b"Base data AAppended data A").hexdigest()
    f2_hash = hashlib.sha256((b'\x01' * 100) + (b'\x02' * 50)).hexdigest()
    with open(FINAL_HASHES_FILE, 'r') as f:
        lines = f.read().strip().split('\n')
    actual_hashes = {}
    for line in lines:
        if not line.strip():
            continue
        parts = line.split()
        if len(parts) >= 2:
            actual_hashes[parts[1]] = parts[0]
    assert './file1.txt' in actual_hashes, './file1.txt missing from final_hashes.txt'
    assert actual_hashes['./file1.txt'] == f1_hash, f"Hash for ./file1.txt is incorrect in {FINAL_HASHES_FILE}"
    assert './file2.bin' in actual_hashes, './file2.bin missing from final_hashes.txt'
    assert actual_hashes['./file2.bin'] == f2_hash, f"Hash for ./file2.bin is incorrect in {FINAL_HASHES_FILE}"
    assert './file3.txt' not in actual_hashes, './file3.txt should not be present in final_hashes.txt'


def test_no_extra_files_in_restore():
    expected_files = {'file1.txt', 'file2.bin'}
    actual_files = set(os.listdir(RESTORE_DIR))
    assert actual_files == expected_files, f"Unexpected files in {RESTORE_DIR}: {actual_files - expected_files}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
