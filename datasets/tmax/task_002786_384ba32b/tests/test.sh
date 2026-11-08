#!/bin/bash
mkdir -p /logs/verifier

cat << 'SECCOMP_EOF' > /tmp/noexec.c
#include <stddef.h>
#include <errno.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <linux/filter.h>
#include <linux/seccomp.h>

int install_noexec(void) {
    struct sock_filter filter[] = {
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, nr)),
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_execve, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | EPERM),
#ifdef __NR_execveat
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_execveat, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | EPERM),
#endif
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
    };
    struct sock_fprog program = {
        .len = (unsigned short)(sizeof(filter) / sizeof(filter[0])),
        .filter = filter,
    };

    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0)
        return -1;
    if (prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &program) != 0)
        return -1;
    return 0;
}
SECCOMP_EOF

cat << 'RUNNER_EOF' > /tmp/run_agent_noexec.py
import ctypes
import os
import runpy
import sys

agent_path = sys.argv[1]
agent_args = sys.argv[2:]

lib = ctypes.CDLL('/tmp/libnoexec.so', use_errno=True)
lib.install_noexec.restype = ctypes.c_int
if lib.install_noexec() != 0:
    error = ctypes.get_errno()
    raise OSError(error, os.strerror(error))

sys.argv = [agent_path] + agent_args
runpy.run_path(agent_path, run_name='__main__')
RUNNER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import json
import os
import random
import string
import subprocess
import tempfile
import pytest


def generate_random_file(path, size):
    with open(path, 'wb') as f:
        f.write(os.urandom(size))


def create_random_directory_structure(base_dir, num_files, max_depth=3):
    extensions = ['.txt', '.log', '.tmp', '.dat', '.bin', '.csv']
    dirs = [base_dir]

    for depth in range(max_depth):
        new_dirs = []
        for d in dirs:
            for _ in range(random.randint(0, 2)):
                sub = os.path.join(d, ''.join(random.choices(string.ascii_letters, k=5)))
                os.makedirs(sub, exist_ok=True)
                new_dirs.append(sub)
        dirs.extend(new_dirs)

    all_files = []
    for _ in range(num_files):
        d = random.choice(dirs)
        ext = random.choice(extensions)
        name = ''.join(random.choices(string.ascii_letters, k=8)) + ext
        filepath = os.path.join(d, name)
        size = random.randint(0, 1024 * 100)
        generate_random_file(filepath, size)
        all_files.append(filepath)

    num_symlinks = random.randint(0, 5)
    for _ in range(num_symlinks):
        if not all_files:
            break
        target = random.choice(all_files)
        d = random.choice(dirs)
        linkname = ''.join(random.choices(string.ascii_letters, k=8)) + '.lnk'
        linkpath = os.path.join(d, linkname)
        if not os.path.exists(linkpath):
            os.symlink(target, linkpath)

    num_hardlinks = random.randint(0, 5)
    for _ in range(num_hardlinks):
        if not all_files:
            break
        target = random.choice(all_files)
        d = random.choice(dirs)
        linkname = ''.join(random.choices(string.ascii_letters, k=8)) + '.hlnk'
        linkpath = os.path.join(d, linkname)
        if not os.path.exists(linkpath):
            os.link(target, linkpath)

    return extensions


def test_fuzz_equivalence():
    oracle_path = '/app/legacy_backup_tool'
    agent_path = '/home/user/new_backup_tool.py'

    assert os.path.exists(oracle_path), f'Oracle not found at {oracle_path}'
    assert os.path.exists(agent_path), f'Agent script not found at {agent_path}'
    assert os.path.isfile(agent_path), f'Agent path is not a regular file: {agent_path}'
    assert not filecmp.cmp(agent_path, oracle_path, shallow=False), 'Agent submission is the legacy binary'

    random.seed(42)
    num_tests = 50

    with tempfile.TemporaryDirectory() as temp_base:
        cases = []

        # Create every case and obtain every oracle result before any agent code
        # runs. Agent execution is subsequently placed under a seccomp filter
        # that denies execve and execveat, so it cannot invoke the legacy tool
        # (or a copied version of it) as a subprocess.
        for i in range(num_tests):
            test_dir = os.path.join(temp_base, f'fuzz_dir_{i}')
            os.makedirs(test_dir)

            num_files = random.randint(5, 25)
            available_exts = create_random_directory_structure(test_dir, num_files)
            config = {
                'ignore_extensions': random.sample(
                    available_exts,
                    random.randint(0, min(3, len(available_exts)))
                ),
                'follow_symlinks': random.choice([True, False]),
                'extract_header_bytes': random.randint(0, 64),
            }

            config_path = os.path.join(temp_base, f'config_{i}.json')
            with open(config_path, 'w') as f:
                json.dump(config, f)

            try:
                oracle_result = subprocess.run(
                    [oracle_path, config_path, test_dir],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=10,
                    check=True,
                )
            except subprocess.CalledProcessError as e:
                pytest.fail(
                    f"Oracle failed on test {i}: "
                    f"{e.stderr.decode('utf-8', errors='ignore')}"
                )

            cases.append((i, test_dir, config_path, config, oracle_result.stdout))

        for i, test_dir, config_path, config, oracle_out in cases:
            try:
                agent_result = subprocess.run(
                    ['python3', '-I', '/tmp/run_agent_noexec.py',
                     agent_path, config_path, test_dir],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=10,
                    check=True,
                )
                agent_out = agent_result.stdout
            except subprocess.CalledProcessError as e:
                pytest.fail(
                    f"Agent failed on test {i}: "
                    f"{e.stderr.decode('utf-8', errors='ignore')}"
                )

            assert oracle_out == agent_out, (
                f'Mismatch on test {i}!\n'
                f'Config: {config}\n'
                f'Directory: {test_dir}\n'
                f'Oracle output length: {len(oracle_out)}, '
                f'Agent output length: {len(agent_out)}\n'
                'Outputs differ bit-for-bit.'
            )
TEST_EOF

if gcc -shared -fPIC -O2 -o /tmp/libnoexec.so /tmp/noexec.c && \
   python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
