#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import re
import shlex
import socket
import subprocess
import tarfile
import time
import uuid
from pathlib import Path

HOME = Path('/home/user')
CONFIG = HOME / 'migration.conf'
LOG = HOME / 'migration.log'
SOURCE = HOME / 'migrator.c'
EXECUTABLE = HOME / 'migrator'
SUCCESS = b'{"status": "success", "phase": "staged"}\n'
FAILED = '{"status": "failed", "reason": "connectivity"}'


def test_original_assertions_and_executed_behavior():
    # Preserve the original verifier's assertions.
    assert SOURCE.is_file(), f'Source file missing: {SOURCE}'
    assert EXECUTABLE.is_file(), f'Executable missing: {EXECUTABLE}'
    assert os.access(EXECUTABLE, os.X_OK), f'File is not executable: {EXECUTABLE}'

    archive = HOME / 'backup_dir/archive.tar.gz'
    assert archive.is_file(), f'Backup archive missing: {archive}'
    assert archive.stat().st_size > 0, f'Backup archive is empty: {archive}'
    with tarfile.open(archive, 'r:gz') as tf:
        assert tf.getmembers(), 'Initial backup is not a nonempty gzipped tar archive'

    for name, expected in [('file1.txt', 'file1_content'), ('file2.txt', 'file2_content')]:
        staged = HOME / 'staging_dir' / name
        assert staged.is_file(), f'Staged file missing: {staged}'
        assert staged.read_text().strip() == expected, f'Incorrect content in {staged}'

    assert LOG.is_file(), f'Log file missing: {LOG}'
    assert '{"status": "success", "phase": "staged"}' in LOG.read_text()

    # The submitted executable must actually be a compiled binary.
    assert EXECUTABLE.read_bytes()[:4] == b'\x7fELF', 'migrator is not an ELF executable'

    rebuilt = Path('/tmp/migrator_rebuilt')
    build = subprocess.run(
        ['gcc', '-Wall', '-Wextra', str(SOURCE), '-o', str(rebuilt)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert build.returncode == 0, f'migrator.c does not compile:\n{build.stderr}'

    # Interpose system() so successful runs prove that the C utility invokes it.
    wrapper_c = Path('/tmp/system_trace.c')
    wrapper_so = Path('/tmp/system_trace.so')
    wrapper_c.write_text(r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
int system(const char *command) {
    static int (*real_system)(const char *) = NULL;
    if (!real_system) real_system = dlsym(RTLD_NEXT, "system");
    const char *trace = getenv("SYSTEM_TRACE");
    if (trace && command) {
        FILE *f = fopen(trace, "a");
        if (f) { fprintf(f, "%s\n", command); fclose(f); }
    }
    return real_system(command);
}
''')
    wrap_build = subprocess.run(
        ['gcc', '-shared', '-fPIC', str(wrapper_c), '-o', str(wrapper_so), '-ldl'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert wrap_build.returncode == 0, wrap_build.stderr

    original_config = CONFIG.read_bytes()
    original_log = LOG.read_bytes() if LOG.exists() else None
    account = pwd.getpwnam('user')

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    def run_as_user(program, trace, timeout=15):
        env = os.environ.copy()
        env['LD_PRELOAD'] = str(wrapper_so)
        env['SYSTEM_TRACE'] = str(trace)
        return subprocess.run(
            [str(program)], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=timeout, env=env, preexec_fn=demote
        )

    def make_tree():
        root = HOME / ('verifier_' + uuid.uuid4().hex)
        source = root / 'source'
        backup = root / 'backup'
        stage = root / 'stage'
        nested = source / 'nested'
        nested.mkdir(parents=True)
        backup.mkdir()
        stage.mkdir()
        expected = {
            'alpha.txt': 'alpha-' + uuid.uuid4().hex,
            'nested/beta.bin': 'beta-' + uuid.uuid4().hex,
        }
        (source / 'alpha.txt').write_text(expected['alpha.txt'])
        (nested / 'beta.bin').write_text(expected['nested/beta.bin'])
        for path in [root, source, backup, stage, nested]:
            os.chmod(path, 0o777)
        for path in source.rglob('*'):
            if path.is_file():
                os.chmod(path, 0o666)
        return root, source, backup, stage, expected

    def write_config(source, backup, stage, port):
        CONFIG.write_text(
            f'SOURCE_DIR={source}\nBACKUP_DIR={backup}\n'
            f'STAGE_DIR={stage}\nCHECK_PORT={port}\n'
        )

    def option_letters(command):
        try:
            tokens = shlex.split(command)
        except ValueError:
            tokens = command.split()
        letters = ''
        for i, token in enumerate(tokens):
            if os.path.basename(token) == 'tar':
                for option in tokens[i + 1:]:
                    if option.startswith('-'):
                        letters += option.lstrip('-')
                    elif re.fullmatch(r'[A-Za-z]+', option):
                        letters += option
                    else:
                        break
        return letters

    def exercise(program):
        # A bound but non-listening socket guarantees connectivity failure.
        root, source, backup, stage, _ = make_tree()
        blocker = socket.socket()
        blocker.bind(('127.0.0.1', 0))
        closed_port = blocker.getsockname()[1]
        trace = root / 'failure-system.trace'
        write_config(source, backup, stage, closed_port)
        if LOG.exists():
            LOG.unlink()
        failed = run_as_user(program, trace)
        blocker.close()
        assert failed.returncode == 1, (
            f'connectivity failure returned {failed.returncode}; stderr={failed.stderr!r}'
        )
        assert LOG.is_file(), 'Failure run did not create migration.log'
        assert LOG.read_text().strip() == FAILED, 'Incorrect connectivity-failure log entry'
        assert not trace.exists() or not trace.read_text().strip(), (
            'Backup/deployment system() commands ran after connectivity failure'
        )

        # Use new paths, unpredictable contents, and a temporary Python HTTP server.
        root, source, backup, stage, expected = make_tree()
        probe = socket.socket()
        probe.bind(('127.0.0.1', 0))
        port = probe.getsockname()[1]
        probe.close()
        server = subprocess.Popen(
            ['python3', '-m', 'http.server', str(port), '--bind', '127.0.0.1',
             '--directory', str(source)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        try:
            for _ in range(50):
                try:
                    with socket.create_connection(('127.0.0.1', port), timeout=.1):
                        break
                except OSError:
                    time.sleep(.05)
            else:
                raise AssertionError('Temporary HTTP server did not start')

            trace = root / 'success-system.trace'
            write_config(source, backup, stage, port)
            if LOG.exists():
                LOG.unlink()
            result = run_as_user(program, trace)
            assert result.returncode == 0, (
                f'Success run returned {result.returncode}; stderr={result.stderr!r}'
            )
        finally:
            server.terminate()
            try:
                server.wait(timeout=3)
            except subprocess.TimeoutExpired:
                server.kill()

        produced = backup / 'archive.tar.gz'
        assert produced.is_file() and produced.stat().st_size > 0
        with tarfile.open(produced, 'r:gz') as tf:
            files = {}
            for member in tf.getmembers():
                if not member.isfile():
                    continue
                name = member.name
                while name.startswith('./'):
                    name = name[2:]
                extracted = tf.extractfile(member)
                files[name] = extracted.read().decode() if extracted else None
        assert files == expected, f'Archive contents differ from configured source: {files}'

        staged = {}
        for path in stage.rglob('*'):
            if path.is_file():
                staged[str(path.relative_to(stage))] = path.read_text()
        assert staged == expected, f'Staged contents differ from configured source: {staged}'
        assert LOG.read_bytes().endswith(SUCCESS), 'Exact success entry with newline was not appended'

        assert trace.is_file(), 'No calls to system() were observed'
        commands = [line for line in trace.read_text().splitlines() if 'tar' in line]
        assert len(commands) >= 2, f'Expected tar backup and restore through system(): {commands}'
        assert all('archive.tar.gz' in command for command in commands[:2])
        letters = [option_letters(command) for command in commands]
        assert any('c' in value for value in letters), f'No tar create command observed: {commands}'
        assert any('x' in value for value in letters), f'No tar extract command observed: {commands}'

    try:
        exercise(EXECUTABLE)
        exercise(rebuilt)
    finally:
        CONFIG.write_bytes(original_config)
        if original_log is None:
            if LOG.exists():
                LOG.unlink()
        else:
            LOG.write_bytes(original_log)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
