#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import shutil
import string
import struct
import subprocess
import tempfile


def generate_random_string(length):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))


def create_fuzz_directory(base_dir):
    num_files = random.randint(5, 50)
    num_dirs = random.randint(1, 5)
    num_symlinks = random.randint(1, 3)

    dirs = [base_dir]
    for _ in range(num_dirs):
        directory = os.path.join(random.choice(dirs), generate_random_string(8))
        os.makedirs(directory, exist_ok=True)
        dirs.append(directory)

    extensions = ['.tmp', '.log', '.txt', '.bin', '.dat']
    for _ in range(num_files):
        directory = random.choice(dirs)
        extension = random.choice(extensions)
        path = os.path.join(directory, generate_random_string(8) + extension)
        with open(path, 'wb') as handle:
            handle.write(os.urandom(random.randint(0, 10240)))
        mtime = random.randint(1000000000, 2000000000)
        os.utime(path, (mtime, mtime))

    # Always include a real circular directory symlink.
    os.symlink(base_dir, os.path.join(base_dir, 'self_loop'))
    for _ in range(num_symlinks):
        directory = random.choice(dirs)
        link_name = os.path.join(directory, generate_random_string(8))
        if not os.path.lexists(link_name):
            os.symlink(random.choice(dirs), link_name)

    exclude_extensions = random.sample(extensions, k=random.randint(1, 3))
    min_mtime = random.randint(1000000000, 2000000000)
    config = {
        'exclude_extensions': exclude_extensions,
        'min_mtime': min_mtime,
    }

    # Requirement 2 names this exact configuration path.
    with open('/home/user/backup_config.json', 'w') as handle:
        json.dump(config, handle)

    # A contradictory file in the target catches implementations which silently
    # prefer <target>/backup_config.json. Under the required configuration this
    # is just another eligible input file.
    local_config = os.path.join(base_dir, 'backup_config.json')
    with open(local_config, 'w') as handle:
        json.dump({'exclude_extensions': extensions, 'min_mtime': 3000000000}, handle)
    os.utime(local_config, (2100000000, 2100000000))

    return config


def expected_archive(target_dir, config):
    exclude_extensions = config['exclude_extensions']
    min_mtime = config['min_mtime']
    visited = set()
    selected = []

    def traverse(directory):
        try:
            stat_result = os.stat(directory)
            inode = (stat_result.st_dev, stat_result.st_ino)
            if inode in visited:
                return
            visited.add(inode)
        except OSError:
            return

        try:
            entries = sorted(os.listdir(directory))
        except OSError:
            return

        for entry in entries:
            full_path = os.path.join(directory, entry)
            if os.path.isdir(full_path):
                traverse(full_path)
                continue

            if os.path.splitext(entry)[1] in exclude_extensions:
                continue
            try:
                mtime = int(os.path.getmtime(full_path))
                if os.path.getmtime(full_path) <= min_mtime:
                    continue
                with open(full_path, 'rb') as handle:
                    contents = handle.read()
            except OSError:
                continue
            selected.append((os.path.relpath(full_path, target_dir), mtime, contents))

    traverse(target_dir)
    selected.sort(key=lambda item: item[0])

    result = bytearray()
    for relative_path, mtime, contents in selected:
        encoded_path = relative_path.encode('utf-8')
        result.extend(struct.pack('>H', len(encoded_path)))
        result.extend(encoded_path)
        result.extend(struct.pack('>Q', mtime))
        result.extend(struct.pack('>I', len(contents)))
        result.extend(contents)
    return bytes(result)


def test_fuzz_equivalence():
    random.seed(42)
    agent_script = '/home/user/archiver.py'
    assert os.path.isfile(agent_script), f'Agent script {agent_script} not found.'

    for iteration in range(50):
        with tempfile.TemporaryDirectory() as fuzz_dir, tempfile.TemporaryDirectory() as output_dir:
            config = create_fuzz_directory(fuzz_dir)
            expected = expected_archive(fuzz_dir, config)
            agent_output = os.path.join(output_dir, 'agent_output.bin')

            try:
                process = subprocess.run(
                    ['python3', agent_script, fuzz_dir, agent_output],
                    capture_output=True,
                    timeout=10,
                )
            except subprocess.TimeoutExpired:
                assert False, f'Agent hung on iteration {iteration}, likely on a symlink loop.'

            assert process.returncode == 0, (
                f'Agent failed on iteration {iteration}:\n{process.stderr.decode(errors="replace")}'
            )
            assert os.path.isfile(agent_output), 'Agent output not generated.'
            with open(agent_output, 'rb') as handle:
                actual = handle.read()
            assert actual == expected, (
                f'Output mismatch on iteration {iteration}. '
                f'Expected size: {len(expected)}, agent size: {len(actual)}'
            )


def test_dirsync_patched():
    import sys
    sys.path.insert(0, '/app/dirsync-2.2.5')
    try:
        import dirsync
    except ImportError:
        assert False, 'Could not import dirsync from /app/dirsync-2.2.5'

    with tempfile.TemporaryDirectory() as src, tempfile.TemporaryDirectory() as dst:
        os.symlink(src, os.path.join(src, 'loop'))
        with open(os.path.join(src, 'test.txt'), 'w') as handle:
            handle.write('test')

        try:
            dirsync.sync(src, dst, action='update', create=True)
        except RecursionError:
            assert False, 'dirsync raised RecursionError; symlink loop detection is not patched.'
        except Exception as error:
            assert False, f'dirsync raised unexpected exception: {error}'

        assert os.path.exists(os.path.join(dst, 'test.txt')), 'dirsync failed to copy files.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
