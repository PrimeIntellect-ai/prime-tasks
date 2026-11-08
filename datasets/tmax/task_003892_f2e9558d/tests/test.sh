#!/bin/bash
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import fcntl
import os
import pathlib
import shutil
import subprocess
import time
import uuid

import pytest

OUTPUT = pathlib.Path('/home/user/merged_output.txt')
SOURCE = pathlib.Path('/home/user/merge_dataset.c')
EXECUTABLE = pathlib.Path('/home/user/merge_dataset')
DATASET = pathlib.Path('/home/user/dataset')


def test_merged_output_exists():
    assert os.path.isfile(OUTPUT), 'The output file /home/user/merged_output.txt does not exist.'


def test_merged_output_content():
    expected_content = 'Record 1: Alpha\nRecord 2: Beta\nRecord 3: Gamma\n'
    try:
        with open(OUTPUT, 'r', encoding='utf-8') as f:
            actual_content = f.read()
    except UnicodeDecodeError:
        pytest.fail('The output file /home/user/merged_output.txt is not properly UTF-8 encoded.')
    assert actual_content.strip() == expected_content.strip(), 'The content of /home/user/merged_output.txt does not match the expected output.'


def test_c_source_code_exists_and_uses_flock():
    assert os.path.isfile(SOURCE), f'The C source file {SOURCE} does not exist.'
    with open(SOURCE, 'r', encoding='utf-8', errors='ignore') as f:
        source_code = f.read()
    assert 'flock' in source_code, "The C source code does not use 'flock' as required for concurrency safety."


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f'The executable file {EXECUTABLE} does not exist.'
    assert os.access(EXECUTABLE, os.X_OK), f'The file {EXECUTABLE} is not executable.'
    with open(EXECUTABLE, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'merge_dataset is not a compiled executable.'


TRACER_SOURCE = r'''
#define _GNU_SOURCE
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/ptrace.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/user.h>
#include <sys/wait.h>
#include <unistd.h>

static int same_output_fd(pid_t pid, long fd, const char *output) {
    char linkpath[128];
    struct stat a, b;
    snprintf(linkpath, sizeof(linkpath), "/proc/%ld/fd/%ld", (long)pid, fd);
    if (stat(linkpath, &a) != 0 || stat(output, &b) != 0) return 0;
    return a.st_dev == b.st_dev && a.st_ino == b.st_ino;
}

static long long output_size(const char *output) {
    struct stat st;
    if (stat(output, &st) != 0) return -1;
    return (long long)st.st_size;
}

int main(int argc, char **argv) {
#if !defined(__x86_64__)
    fprintf(stderr, "unsupported verifier architecture\n");
    return 125;
#else
    if (argc != 4) return 125;
    FILE *log = fopen(argv[1], "w");
    if (!log) return 125;
    setvbuf(log, NULL, _IONBF, 0);

    pid_t child = fork();
    if (child < 0) return 125;
    if (child == 0) {
        if (ptrace(PTRACE_TRACEME, 0, 0, 0) != 0) _exit(125);
        raise(SIGSTOP);
        execl(argv[3], argv[3], (char *)NULL);
        _exit(126);
    }

    int status;
    if (waitpid(child, &status, 0) < 0 || !WIFSTOPPED(status)) return 125;
    ptrace(PTRACE_SETOPTIONS, child, 0, PTRACE_O_TRACESYSGOOD | PTRACE_O_EXITKILL);
    ptrace(PTRACE_SYSCALL, child, 0, 0);

    int entering = 1;
    int pending_ex = 0;
    for (;;) {
        if (waitpid(child, &status, 0) < 0) return 125;
        if (WIFEXITED(status)) return WEXITSTATUS(status);
        if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
        if (!WIFSTOPPED(status)) continue;

        int sig = WSTOPSIG(status);
        if (sig == (SIGTRAP | 0x80)) {
            struct user_regs_struct r;
            if (ptrace(PTRACE_GETREGS, child, 0, &r) != 0) return 125;
            if (entering) {
                pending_ex = 0;
                if ((long)r.orig_rax == SYS_flock && same_output_fd(child, (long)r.rdi, argv[2])) {
                    int op = (int)r.rsi;
                    if (op & LOCK_EX) {
                        fprintf(log, "A %lld\n", output_size(argv[2]));
                        pending_ex = 1;
                    } else if (op & LOCK_UN) {
                        fprintf(log, "U %lld\n", output_size(argv[2]));
                    }
                }
            } else if (pending_ex) {
                if ((long)r.rax == 0)
                    fprintf(log, "E %lld\n", output_size(argv[2]));
                else
                    fprintf(log, "X %lld\n", output_size(argv[2]));
                pending_ex = 0;
            }
            entering = !entering;
            ptrace(PTRACE_SYSCALL, child, 0, 0);
        } else {
            int deliver = (sig == SIGSTOP || sig == SIGTRAP) ? 0 : sig;
            ptrace(PTRACE_SYSCALL, child, 0, deliver);
        }
    }
#endif
}
'''


def test_program_behavior_and_lock_boundaries(tmp_path):
    tracer_c = tmp_path / 'trace_flock.c'
    tracer = tmp_path / 'trace_flock'
    trace_log = tmp_path / 'flock.log'
    tracer_c.write_text(TRACER_SOURCE, encoding='utf-8')
    subprocess.run(['gcc', '-O2', '-Wall', '-Wextra', '-o', str(tracer), str(tracer_c)], check=True)

    token = uuid.uuid4().hex
    dataset_backup = pathlib.Path(f'/home/user/dataset.verifier-backup-{token}')
    output_backup = pathlib.Path(f'/home/user/merged_output.verifier-backup-{token}')
    os.rename(DATASET, dataset_backup)
    output_existed = OUTPUT.exists()
    if output_existed:
        os.rename(OUTPUT, output_backup)

    chunks = {
        'chunk_030.dat': f'Third {token}: 漢字\n',
        'chunk_010.dat': f'First {token}: café\n',
        'chunk_020.dat': f'Second {token}: 😀\n',
    }
    sentinel = f'PREFIX-{token}\n'.encode('utf-8')

    try:
        DATASET.mkdir()
        for name, text in chunks.items():
            (DATASET / name).write_bytes(text.encode('utf-16le'))

        (DATASET / 'chunk_000.txt').write_bytes('ignored text\n'.encode('utf-16le'))
        (DATASET / 'symlink_target.bin').write_bytes('SYMLINK MUST BE IGNORED\n'.encode('utf-16le'))
        os.symlink(DATASET / 'symlink_target.bin', DATASET / 'chunk_015.dat')
        os.symlink(DATASET, DATASET / 'loop_link')
        os.symlink(DATASET, DATASET / 'chunk_loop.dat')
        (DATASET / 'nested_directory').mkdir()
        (DATASET / 'nested_directory' / 'chunk_005.dat').write_bytes('NESTED MUST BE IGNORED\n'.encode('utf-16le'))
        OUTPUT.write_bytes(sentinel)

        expected_parts = [chunks[name].encode('utf-8') for name in sorted(chunks)]
        expected = sentinel + b''.join(expected_parts)

        with open(OUTPUT, 'r+b', buffering=0) as held:
            fcntl.flock(held.fileno(), fcntl.LOCK_EX)
            proc = subprocess.Popen([str(tracer), str(trace_log), str(OUTPUT), str(EXECUTABLE)])

            deadline = time.monotonic() + 5
            saw_attempt = False
            while time.monotonic() < deadline:
                if trace_log.exists() and any(line.startswith('A ') for line in trace_log.read_text().splitlines()):
                    saw_attempt = True
                    break
                if proc.poll() is not None:
                    break
                time.sleep(0.02)

            assert saw_attempt, 'The executable did not attempt an exclusive flock on merged_output.txt.'
            assert proc.poll() is None, 'The executable did not block while another process held the output lock.'
            assert OUTPUT.read_bytes() == sentinel, 'The executable modified or truncated the output before acquiring its lock.'
            fcntl.flock(held.fileno(), fcntl.LOCK_UN)

        try:
            rc = proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
            pytest.fail('merge_dataset did not terminate, possibly due to following a symlink loop.')
        assert rc == 0, f'merge_dataset exited with status {rc}.'
        assert OUTPUT.read_bytes() == expected, 'Execution did not correctly sort, convert, append, or ignore symlinks/non-data entries.'

        events = []
        for line in trace_log.read_text().splitlines():
            op, size = line.split()
            events.append((op, int(size)))
        assert events and all(op != 'X' for op, _ in events), 'An exclusive flock call failed.'

        state = 'A'
        start_size = None
        growths = []
        previous_size = len(sentinel)
        for op, size in events:
            if state == 'A':
                assert op == 'A', 'Output locks were not acquired and released in valid pairs.'
                assert size == previous_size, 'Output data was written outside a per-chunk lock.'
                start_size = size
                state = 'E'
            elif state == 'E':
                assert op == 'E' and size == start_size, 'The output changed before exclusive-lock acquisition completed.'
                state = 'U'
            else:
                assert op == 'U' and size >= start_size, 'The exclusive lock was not released after a chunk write.'
                growths.append(size - start_size)
                previous_size = size
                state = 'A'
        assert state == 'A', 'The final exclusive output lock was not released.'
        assert growths == [len(part) for part in expected_parts], 'The program must acquire and release an exclusive flock separately around each sorted chunk write.'
    finally:
        if 'proc' in locals() and proc.poll() is None:
            proc.kill()
            proc.wait()
        if DATASET.exists() or DATASET.is_symlink():
            shutil.rmtree(DATASET)
        os.rename(dataset_backup, DATASET)
        if OUTPUT.exists() or OUTPUT.is_symlink():
            OUTPUT.unlink()
        if output_existed:
            os.rename(output_backup, OUTPUT)
PY_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
