#!/bin/bash
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import base64
import os
import random
import shutil
import stat
import string
import subprocess
import tempfile
import time
from pathlib import Path

HOME = Path('/home/user')
LEGACY = HOME / 'legacy_data'
ORGANIZED = HOME / 'organized_data'
LOG = HOME / 'processed.log'
LIBRARY = HOME / 'libchecker.so'


def check_original_assertions():
    assert ORGANIZED.is_dir(), f'Directory {ORGANIZED} is missing.'
    expected_files = {
        'file1.txt': 'hello',
        'file2.txt': 'café',
        'file4.txt': 'jalapeño',
    }
    for filename, expected_content in expected_files.items():
        filepath = ORGANIZED / filename
        assert filepath.is_file(), f'Expected processed file {filepath} is missing.'
        content = filepath.read_bytes()
        try:
            text_content = content.decode('utf-8').strip()
        except UnicodeDecodeError as exc:
            raise AssertionError(f'File {filepath} is not valid UTF-8.') from exc
        assert text_content == expected_content, (
            f'Content of {filepath} is incorrect. Expected {expected_content!r}, '
            f'got {text_content!r}.'
        )

    ignored = ORGANIZED / 'file3.txt'
    assert not ignored.exists(), f'File {ignored} should not exist because it fails the magic check.'

    assert LOG.is_file(), f'Log file {LOG} is missing.'
    with LOG.open('r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    expected_lines = ['file1.txt', 'file2.txt', 'file4.txt']
    assert lines == expected_lines, (
        f'Contents of {LOG} are incorrect or not sorted. '
        f'Expected {expected_lines}, got {lines}.'
    )


def artifact_candidates():
    excluded_roots = {LEGACY.resolve(), ORGANIZED.resolve()}
    excluded_files = {LIBRARY.resolve(), LOG.resolve()}
    recognized = {'.py', '.sh', '.go', '.js', '.rb', '.pl'}
    found = []

    for root, dirs, files in os.walk(HOME):
        root_path = Path(root)
        dirs[:] = [
            d for d in dirs
            if not d.startswith('.')
            and d not in {'legacy_data', 'organized_data', 'node_modules', '__pycache__'}
        ]
        try:
            if root_path.resolve() in excluded_roots:
                dirs[:] = []
                continue
        except OSError:
            continue

        for name in files:
            path = root_path / name
            try:
                resolved = path.resolve()
                if resolved in excluded_files or not path.is_file() or path.is_symlink():
                    continue
                suffix = path.suffix.lower()
                executable = os.access(path, os.X_OK)
                if suffix not in recognized and not executable:
                    continue
                with path.open('rb') as f:
                    data = f.read(16 * 1024 * 1024)
                lower = data.lower()
                score = 0
                for marker, value in [
                    (b'check_magic', 8),
                    (b'libchecker', 8),
                    (b'legacy_data', 4),
                    (b'organized_data', 4),
                    (b'processed.log', 3),
                ]:
                    if marker in lower:
                        score += value
                if suffix in recognized:
                    score += 1
                if data.startswith(b'\x7fELF'):
                    score += 1
                if score >= 5:
                    found.append((score, path))
            except (OSError, ValueError):
                continue

    found.sort(key=lambda item: (-item[0], len(str(item[1])), str(item[1])))
    return [path for _, path in found[:25]]


def command_for(path, index):
    suffix = path.suffix.lower()
    if suffix == '.py':
        return ['python3', str(path)]
    if suffix == '.sh':
        return ['bash', str(path)]
    if suffix == '.go':
        go = shutil.which('go')
        return [go, 'run', str(path)] if go else None
    if suffix == '.js':
        node = shutil.which('node')
        return [node, str(path)] if node else None
    if suffix == '.rb':
        ruby = shutil.which('ruby')
        return [ruby, str(path)] if ruby else None
    if suffix == '.pl':
        perl = shutil.which('perl')
        return [perl, str(path)] if perl else None
    if os.access(path, os.X_OK):
        return [str(path)]
    return None


def build_spy_library(destination):
    source = Path('/tmp/checker_spy.c')
    source.write_text(r'''
#include <sys/file.h>
#include <sys/types.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>

static void update_state(int delta, const char *filepath) {
    int fd = open("/tmp/checker_state", O_RDWR | O_CREAT, 0666);
    if (fd < 0) return;
    flock(fd, LOCK_EX);
    char buf[128] = {0};
    int active = 0, maximum = 0, calls = 0;
    lseek(fd, 0, SEEK_SET);
    read(fd, buf, sizeof(buf) - 1);
    sscanf(buf, "%d %d %d", &active, &maximum, &calls);
    active += delta;
    if (delta > 0) {
        calls++;
        if (active > maximum) maximum = active;
        int logfd = open("/tmp/checker_calls.log", O_WRONLY | O_CREAT | O_APPEND, 0666);
        if (logfd >= 0) {
            write(logfd, filepath, strlen(filepath));
            write(logfd, "\n", 1);
            close(logfd);
        }
    }
    int len = snprintf(buf, sizeof(buf), "%d %d %d\n", active, maximum, calls);
    ftruncate(fd, 0);
    lseek(fd, 0, SEEK_SET);
    write(fd, buf, len);
    fsync(fd);
    flock(fd, LOCK_UN);
    close(fd);
}

int check_magic(const char *filepath) {
    update_state(1, filepath);
    usleep(300000);
    FILE *f = fopen(filepath, "rb");
    char header[4] = {0};
    int valid = 0;
    if (f) {
        valid = fread(header, 1, 4, f) == 4 && memcmp(header, "WXYZ", 4) == 0;
        fclose(f);
    }
    update_state(-1, filepath);
    return valid ? 1 : 0;
}
''')
    subprocess.run(
        ['gcc', '-shared', '-fPIC', '-O2', '-o', str(destination), str(source)],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )


def make_corpus():
    token = ''.join(random.SystemRandom().choice(string.ascii_lowercase) for _ in range(12))
    valid = {}
    invalid = []
    raw_values = [
        b'caf\xe9-' + token.encode(),
        b'jalape\xf1o-' + token.encode(),
        b'cr\xe8me-' + token.encode(),
        b'pi\xf1ata-' + token.encode(),
        b'\xc0-la-carte-' + token.encode(),
        b'gar\xe7on-' + token.encode(),
    ]
    for i, raw in enumerate(raw_values):
        name = f'{token}_{i}_{random.randrange(100000, 999999)}.dat'
        valid[name] = raw.decode('iso-8859-1').encode('utf-8')
        (LEGACY / name).write_bytes(b'WXYZ' + base64.b64encode(raw))
    for i in range(3):
        name = f'{token}_bad_{i}_{random.randrange(100000, 999999)}.dat'
        invalid.append(name)
        raw = b'ignored-' + token.encode()
        (LEGACY / name).write_bytes(b'ABCD' + base64.b64encode(raw))
    return valid, invalid


def reset_attempt():
    if LEGACY.exists():
        shutil.rmtree(LEGACY)
    LEGACY.mkdir(parents=True)
    if ORGANIZED.exists():
        shutil.rmtree(ORGANIZED)
    ORGANIZED.mkdir(parents=True)
    if LOG.exists():
        LOG.unlink()
    Path('/tmp/checker_state').write_text('0 0 0\n')
    Path('/tmp/checker_calls.log').write_text('')
    return make_corpus()


def validate_attempt(valid, invalid):
    expected_names = sorted(valid)
    actual_names = sorted(p.name for p in ORGANIZED.iterdir() if p.is_file())
    assert actual_names == expected_names, f'Unexpected organized files: {actual_names}'
    for name, expected_bytes in valid.items():
        assert (ORGANIZED / name).read_bytes() == expected_bytes, f'Incorrect conversion for {name}'
    for name in invalid:
        assert not (ORGANIZED / name).exists(), f'Invalid-magic file {name} was not ignored'

    assert LOG.is_file(), 'processed.log was not created by the submitted artifact'
    with LOG.open('r', encoding='utf-8') as f:
        logged = [line.strip() for line in f if line.strip()]
    assert logged == expected_names, f'processed.log is incorrect or unsorted: {logged}'

    state = Path('/tmp/checker_state').read_text().split()
    assert len(state) >= 3, 'FFI instrumentation state is missing'
    active, maximum, calls = map(int, state[:3])
    all_names = sorted(expected_names + invalid)
    called_paths = [line for line in Path('/tmp/checker_calls.log').read_text().splitlines() if line]
    called_names = sorted(os.path.basename(path) for path in called_paths)
    assert active == 0, 'check_magic calls were still active when the script exited'
    assert maximum == 2, f'Expected exactly 2 concurrent check_magic calls, observed {maximum}'
    assert calls == len(all_names), f'check_magic must be called once for every input; observed {calls} calls'
    assert called_names == all_names, f'check_magic was not invoked exactly once for every input: {called_names}'


def check_dynamic_execution():
    candidates = artifact_candidates()
    assert candidates, 'No submitted processing script or executable artifact was found.'

    spy = Path('/tmp/libchecker_spy.so')
    build_spy_library(spy)
    backup = Path(tempfile.mkstemp(prefix='libchecker-backup-', suffix='.so')[1])
    shutil.copy2(LIBRARY, backup)
    failures = []
    try:
        shutil.copy2(spy, LIBRARY)
        os.chmod(LIBRARY, 0o755)
        for index, candidate in enumerate(candidates):
            command = command_for(candidate, index)
            if not command:
                continue
            valid, invalid = reset_attempt()
            try:
                result = subprocess.run(
                    command,
                    cwd=str(HOME),
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=45,
                    env=os.environ.copy(),
                )
                time.sleep(0.5)
                assert result.returncode == 0, (
                    f'exited with {result.returncode}: '
                    f'{result.stderr.decode("utf-8", "replace")[-1000:]}'
                )
                validate_attempt(valid, invalid)
                return
            except Exception as exc:
                failures.append(f'{candidate}: {exc}')
        raise AssertionError('No submitted artifact passed execution checks. ' + ' | '.join(failures[-5:]))
    finally:
        shutil.copy2(backup, LIBRARY)
        backup.unlink(missing_ok=True)


def main():
    check_original_assertions()
    check_dynamic_execution()


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
