#!/bin/bash
mkdir -p /logs/verifier

run_verification() {
cat <<'C_EOF' > /tmp/trace_rename.c
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/syscall.h>
#include <unistd.h>

static void record_rename(const char *oldpath, const char *newpath, int result) {
    if (result != 0 || oldpath == NULL || newpath == NULL) return;
    int saved = errno;
    int fd = (int)syscall(SYS_openat, AT_FDCWD, "/tmp/organizer_rename_trace", O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd >= 0) {
        dprintf(fd, "%s\t%s\n", oldpath, newpath);
        close(fd);
    }
    errno = saved;
}

int rename(const char *oldpath, const char *newpath) {
    static int (*real_rename)(const char *, const char *) = NULL;
    if (!real_rename) real_rename = dlsym(RTLD_NEXT, "rename");
    int result = real_rename(oldpath, newpath);
    record_rename(oldpath, newpath, result);
    return result;
}

int renameat(int olddirfd, const char *oldpath, int newdirfd, const char *newpath) {
    static int (*real_renameat)(int, const char *, int, const char *) = NULL;
    if (!real_renameat) real_renameat = dlsym(RTLD_NEXT, "renameat");
    int result = real_renameat(olddirfd, oldpath, newdirfd, newpath);
    record_rename(oldpath, newpath, result);
    return result;
}

int renameat2(int olddirfd, const char *oldpath, int newdirfd, const char *newpath, unsigned int flags) {
    static int (*real_renameat2)(int, const char *, int, const char *, unsigned int) = NULL;
    if (!real_renameat2) real_renameat2 = dlsym(RTLD_NEXT, "renameat2");
    if (!real_renameat2) {
        errno = ENOSYS;
        return -1;
    }
    int result = real_renameat2(olddirfd, oldpath, newdirfd, newpath, flags);
    record_rename(oldpath, newpath, result);
    return result;
}
C_EOF

cc -shared -fPIC -O2 -o /tmp/trace_rename.so /tmp/trace_rename.c -ldl || return 1

cat <<'PY_EOF' > /tmp/test_organizer.py
import os
import secrets
import shutil
import subprocess
from pathlib import Path

HOME = Path('/home/user')
LOGS = HOME / 'project_logs'
ARTIFACTS = HOME / 'artifacts'
QUARANTINE = HOME / 'quarantine'
REPORT = HOME / 'quarantine_report.txt'
TMP_REPORT = HOME / 'quarantine_report.txt.tmp'
PROJECT = HOME / 'organizer'
TRACE = Path('/tmp/organizer_rename_trace')


def test_original_final_state():
    for name in ['bin-00002.dat', 'bin-00004.dat']:
        assert (QUARANTINE / name).is_file(), f'Expected quarantined file {name} is missing'
        assert not (ARTIFACTS / name).exists(), f'{name} was not removed from artifacts'

    for name in ['bin-00001.dat', 'bin-00003.dat', 'bin-00005.dat']:
        assert (ARTIFACTS / name).is_file(), f'Artifact {name} should not have been moved'

    assert REPORT.is_file(), 'Report file is missing'
    assert REPORT.read_text().strip() == 'bin-00002\nbin-00004', 'Initial report content is incorrect'
    assert not TMP_REPORT.exists(), 'Temporary report file was left behind'


def test_rust_program_on_fresh_unpredictable_input():
    assert PROJECT.is_dir(), 'Rust project /home/user/organizer is missing'
    assert (PROJECT / 'Cargo.toml').is_file(), 'Cargo.toml is missing'
    assert (PROJECT / 'src' / 'main.rs').is_file(), 'Rust src/main.rs is missing'

    for directory in (LOGS, ARTIFACTS, QUARANTINE):
        shutil.rmtree(directory, ignore_errors=True)
        directory.mkdir(parents=True)
    REPORT.unlink(missing_ok=True)
    TMP_REPORT.unlink(missing_ok=True)
    TRACE.unlink(missing_ok=True)

    ids = [f'bin-{secrets.randbelow(90000) + 10000}' for _ in range(7)]
    while len(set(ids)) != len(ids):
        ids = [f'bin-{secrets.randbelow(90000) + 10000}' for _ in range(7)]

    payloads = {}
    for artifact_id in ids:
        payload = secrets.token_bytes(193 + secrets.randbelow(257))
        payloads[artifact_id] = payload
        (ARTIFACTS / f'{artifact_id}.dat').write_bytes(payload)

    # Two valid records, plus records that must not match because the required
    # fields are absent, in different blocks, or have a different value.
    (LOGS / 'first.log').write_text(f'''[random]\nReason: Checksum mismatch\nArtifactID: {ids[0]}\nLevel: ERROR\n---\nLevel: INFO\nArtifactID: {ids[1]}\nReason: Checksum mismatch\n---\nLevel: ERROR\nArtifactID: {ids[2]}\nReason: Format invalid\n---\nLevel: ERROR\nArtifactID: {ids[3]}\n---\nArtifactID: {ids[4]}\nReason: Checksum mismatch\n''')
    (LOGS / 'second.log').write_text(f'''ArtifactID: {ids[5]}\nLevel: ERROR\nReason: Checksum mismatch\n''')
    # A matching-looking record in a non-.log file must be ignored.
    (LOGS / 'ignored.txt').write_text(f'''Level: ERROR\nArtifactID: {ids[6]}\nReason: Checksum mismatch\n''')

    expected = sorted([ids[0], ids[5]])
    env = os.environ.copy()
    env['LD_PRELOAD'] = '/tmp/trace_rename.so'
    result = subprocess.run(
        ['cargo', 'run', '--quiet', '--manifest-path', str(PROJECT / 'Cargo.toml')],
        cwd=str(PROJECT), env=env, text=True, capture_output=True, timeout=120
    )
    assert result.returncode == 0, f'cargo run failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}'

    for artifact_id in ids:
        source = ARTIFACTS / f'{artifact_id}.dat'
        destination = QUARANTINE / f'{artifact_id}.dat'
        if artifact_id in expected:
            assert not source.exists(), f'{artifact_id} was not removed from artifacts'
            assert destination.is_file(), f'{artifact_id} was not quarantined'
            assert destination.read_bytes() == payloads[artifact_id], f'{artifact_id} contents changed while moving'
        else:
            assert source.is_file(), f'Non-corrupt artifact {artifact_id} was moved'
            assert source.read_bytes() == payloads[artifact_id], f'Artifact {artifact_id} contents changed'
            assert not destination.exists(), f'Non-corrupt artifact {artifact_id} appeared in quarantine'

    assert sorted(p.name for p in QUARANTINE.iterdir()) == sorted(f'{x}.dat' for x in expected)
    assert REPORT.is_file(), 'Fresh report was not generated'
    assert REPORT.read_text().strip() == '\n'.join(expected), 'Fresh report is not sorted or has incorrect IDs'
    assert not TMP_REPORT.exists(), 'Temporary report file was left behind'

    assert TRACE.is_file(), 'No filesystem rename operation was observed'
    operations = []
    for line in TRACE.read_text(errors='replace').splitlines():
        if '\t' in line:
            operations.append(tuple(line.split('\t', 1)))
    valid_old = {str(TMP_REPORT), TMP_REPORT.name}
    valid_new = {str(REPORT), REPORT.name}
    assert any(old in valid_old and new in valid_new for old, new in operations), \
        'Report was not atomically renamed from quarantine_report.txt.tmp to quarantine_report.txt'
PY_EOF

python3 -m pytest /tmp/test_organizer.py -x --tb=short
}

if run_verification 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
