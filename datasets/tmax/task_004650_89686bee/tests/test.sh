#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import random
import secrets
import shutil
import subprocess
import tarfile
import tempfile

MERGER_SOURCE = '/home/user/merger.c'
ARCHIVE_PATH = '/home/user/staging/assembled.tar.gz'
RELEASE_DIR = '/home/user/release'


def test_merger_c_exists():
    assert os.path.isfile(MERGER_SOURCE), "The C program /home/user/merger.c was not found."


def test_assembled_archive_exists_and_valid():
    assert os.path.isfile(ARCHIVE_PATH), f"The assembled archive {ARCHIVE_PATH} was not found."

    try:
        assert tarfile.is_tarfile(ARCHIVE_PATH), f"{ARCHIVE_PATH} is not a valid tar archive."
        with tarfile.open(ARCHIVE_PATH, 'r:gz') as tar:
            members = tar.getmembers()
            names = [member.name for member in members]
            assert names == ['secret_key.txt', 'dummy_data.bin'], \
                f"Archive contents were incorrect: {names}"
            assert all(member.isfile() for member in members), \
                "The archive must contain exactly two regular files."
            secret = tar.extractfile('secret_key.txt').read()
            assert secret == b'ARTIFACT_VERIFIED_77392\n', \
                "secret_key.txt has incorrect archive content."
            dummy = tar.extractfile('dummy_data.bin').read()
            assert len(dummy) == 100 * 1024, \
                "dummy_data.bin has an incorrect size in the archive."
    except Exception as e:
        assert False, f"Failed to open or validate {ARCHIVE_PATH}: {e}"


def test_extracted_secret_key():
    secret_path = os.path.join(RELEASE_DIR, 'secret_key.txt')
    assert os.path.isfile(secret_path), f"The extracted file {secret_path} was not found."

    with open(secret_path, 'r') as f:
        content = f.read().strip()

    assert content == "ARTIFACT_VERIFIED_77392", \
        f"Incorrect content in {secret_path}. Expected 'ARTIFACT_VERIFIED_77392', got '{content}'."


def test_extracted_dummy_data_matches_archive():
    dummy_path = os.path.join(RELEASE_DIR, 'dummy_data.bin')
    assert os.path.isfile(dummy_path), f"The extracted file {dummy_path} was not found."
    with tarfile.open(ARCHIVE_PATH, 'r:gz') as tar:
        expected = tar.extractfile('dummy_data.bin').read()
    with open(dummy_path, 'rb') as f:
        actual = f.read()
    assert actual == expected, "The extracted dummy_data.bin does not match the archive."


def test_c_program_parses_manifest_and_merges_fresh_chunks():
    executable = os.path.join(tempfile.mkdtemp(prefix='merger-bin-'), 'merger')
    compile_result = subprocess.run(
        ['gcc', '-std=c11', '-O2', MERGER_SOURCE, '-o', executable],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, \
        f"merger.c did not compile successfully:\n{compile_result.stderr}"

    staging = '/home/user/staging'
    work = tempfile.mkdtemp(prefix='merger-verifier-')
    backup = os.path.join(work, 'staging-backup')
    shutil.copytree(staging, backup)

    try:
        shutil.rmtree(staging)
        os.makedirs(staging)

        first_data = secrets.token_bytes(8193)
        second_data = secrets.token_bytes(12289)
        archive_buffer = io.BytesIO()
        with tarfile.open(fileobj=archive_buffer, mode='w:gz') as tar:
            for name, data in [('fresh_alpha.bin', first_data), ('fresh_beta.bin', second_data)]:
                info = tarfile.TarInfo(name)
                info.size = len(data)
                info.mode = 0o600
                tar.addfile(info, io.BytesIO(data))
        expected_archive = archive_buffer.getvalue()

        cut_points = sorted(random.sample(range(1, len(expected_archive)), 4))
        pieces = []
        start = 0
        for end in cut_points + [len(expected_archive)]:
            pieces.append(expected_archive[start:end])
            start = end

        filenames = [f"piece_{secrets.token_hex(5)}.bin" for _ in pieces]
        for filename, piece in zip(filenames, pieces):
            with open(os.path.join(staging, filename), 'wb') as f:
                f.write(piece)

        decoy_name = f"decoy_{secrets.token_hex(5)}.bin"
        with open(os.path.join(staging, decoy_name), 'wb') as f:
            f.write(secrets.token_bytes(777))

        with open(os.path.join(staging, 'manifest.txt'), 'w') as f:
            f.write('# Dynamically generated verifier manifest\n')
            f.write(f'IGNORE_THIS: {decoy_name}\n')
            for index, filename in enumerate(filenames):
                f.write(f'CHUNK: {filename}\n')
                if index == 1:
                    f.write('# comment between chunks\n')
            f.write('NOT_A_CHUNK: missing.bin\n')

        assert not os.path.exists(ARCHIVE_PATH), \
            "The dynamic output path was not clean before running the program."
        run_result = subprocess.run(
            [executable],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert run_result.returncode == 0, \
            f"The compiled merger program failed:\n{run_result.stderr}"
        assert os.path.isfile(ARCHIVE_PATH), \
            "The compiled merger program did not create assembled.tar.gz."
        with open(ARCHIVE_PATH, 'rb') as f:
            actual_archive = f.read()
        assert actual_archive == expected_archive, \
            "The compiled C program did not merge fresh chunks in manifest order."
        assert tarfile.is_tarfile(ARCHIVE_PATH), \
            "The archive produced by the compiled C program is invalid."
    finally:
        if os.path.exists(staging):
            shutil.rmtree(staging)
        shutil.move(backup, staging)
        shutil.rmtree(work, ignore_errors=True)
        shutil.rmtree(os.path.dirname(executable), ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
