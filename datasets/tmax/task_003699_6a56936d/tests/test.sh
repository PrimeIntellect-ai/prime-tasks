#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import stat
import subprocess
import time
from pathlib import Path

SRC = Path('/home/user/docs/src')
PUBLISHED = Path('/home/user/docs/published')
BACKUPS = Path('/home/user/docs/backups')
LIVE = Path('/home/user/docs/live')
SCRIPT = Path('/home/user/doc_daemon.py')


def test_symlink_live_exists():
    link_path = "/home/user/docs/live"
    target_path = "/home/user/docs/published"
    assert os.path.islink(link_path), f"Expected {link_path} to be a symbolic link."
    assert os.readlink(link_path) == target_path, f"Expected {link_path} to point to {target_path}."


def test_hardlinks_exist_and_match():
    src_ch1 = "/home/user/docs/src/ch1.md"
    pub_ch1 = "/home/user/docs/published/ch1.md"

    assert os.path.isfile(src_ch1), f"Expected {src_ch1} to exist."
    assert os.path.isfile(pub_ch1), f"Expected {pub_ch1} to exist."
    assert os.stat(src_ch1).st_ino == os.stat(pub_ch1).st_ino, f"{pub_ch1} is not a hardlink to {src_ch1}."

    src_logo = "/home/user/docs/src/assets/logo.png"
    pub_logo = "/home/user/docs/published/assets/logo.png"

    assert os.path.isfile(src_logo), f"Expected {src_logo} to exist."
    assert os.path.isfile(pub_logo), f"Expected {pub_logo} to exist."
    assert os.stat(src_logo).st_ino == os.stat(pub_logo).st_ino, f"{pub_logo} is not a hardlink to {src_logo}."


def test_draft_deleted_in_published():
    pub_draft = "/home/user/docs/published/draft.md"
    assert not os.path.exists(pub_draft), f"Expected {pub_draft} to be deleted."


def test_daemon_log_exists_and_format():
    log_path = "/home/user/docs/daemon.log"
    assert os.path.isfile(log_path), f"Expected {log_path} to exist."

    with open(log_path, "r") as f:
        lines = f.readlines()

    assert len(lines) > 0, "Expected daemon.log to have content."

    pattern = re.compile(r"^EVENT:\s+\w+\s+\|\s+PATH:\s+/.+")
    valid_lines = [line for line in lines if pattern.match(line.strip())]

    assert len(valid_lines) > 0, "Expected at least one line matching the EVENT format in daemon.log."


def test_incremental_backups_exist():
    snar_path = "/home/user/docs/backups/snapshot.snar"
    assert os.path.isfile(snar_path), f"Expected {snar_path} to exist."

    backup_0 = "/home/user/docs/backups/backup_0.tar"
    backup_1 = "/home/user/docs/backups/backup_1.tar"

    assert os.path.isfile(backup_0), f"Expected {backup_0} to exist."
    assert os.path.isfile(backup_1), f"Expected {backup_1} to exist."


def _clear_directory(path):
    path.mkdir(parents=True, exist_ok=True)
    for child in list(path.iterdir()):
        if child.is_symlink() or child.is_file():
            child.unlink()
        else:
            import shutil
            shutil.rmtree(child)


def _assert_perfect_hardlink_mirror():
    src_dirs = {p.relative_to(SRC) for p in SRC.rglob('*') if p.is_dir()}
    pub_dirs = {p.relative_to(PUBLISHED) for p in PUBLISHED.rglob('*') if p.is_dir()}
    src_files = {p.relative_to(SRC) for p in SRC.rglob('*') if p.is_file()}
    pub_files = {p.relative_to(PUBLISHED) for p in PUBLISHED.rglob('*') if p.is_file()}

    assert pub_dirs == src_dirs, f'Published directory tree differs: {pub_dirs} != {src_dirs}'
    assert pub_files == src_files, f'Published files differ: {pub_files} != {src_files}'
    for rel in src_files:
        src_stat = os.stat(SRC / rel)
        pub_stat = os.stat(PUBLISHED / rel)
        assert (src_stat.st_dev, src_stat.st_ino) == (pub_stat.st_dev, pub_stat.st_ino), \
            f'{PUBLISHED / rel} is not a hard link to {SRC / rel}'


def test_runtime_daemon_behavior():
    assert SCRIPT.is_file(), f'Expected {SCRIPT} to exist.'
    assert not SCRIPT.is_symlink(), f'Expected {SCRIPT} to be a regular Python script.'
    assert SCRIPT.stat().st_size > 0, f'Expected {SCRIPT} to be nonempty.'
    subprocess.run(['python3', '-m', 'py_compile', str(SCRIPT)], check=True)

    _clear_directory(SRC)
    _clear_directory(PUBLISHED)
    _clear_directory(BACKUPS)
    if LIVE.is_symlink() or LIVE.is_file():
        LIVE.unlink()
    elif LIVE.exists():
        import shutil
        shutil.rmtree(LIVE)

    # A real full sync must remove entries that do not exist in src.
    (PUBLISHED / 'stale').mkdir()
    (PUBLISHED / 'stale' / 'old.txt').write_text('stale')

    runtime_log = Path('/tmp/doc_daemon_runtime.log')
    runtime_err = Path('/tmp/doc_daemon_runtime.err')
    tar_trace = Path('/tmp/doc_daemon_tar_trace.log')
    for path in (runtime_log, runtime_err, tar_trace):
        if path.exists():
            path.unlink()

    # Interpose GNU tar while retaining its real behavior, so the verifier can
    # prove that each archive was produced by an invocation using --listed-incremental.
    tar_path = Path('/usr/bin/tar')
    real_tar = Path('/usr/bin/tar.verifier-real')
    assert tar_path.exists() and not real_tar.exists()
    os.rename(tar_path, real_tar)
    tar_path.write_text(
        '#!/bin/sh\n'
        'printf "%s\\n" "$*" >> /tmp/doc_daemon_tar_trace.log\n'
        'exec /usr/bin/tar.verifier-real "$@"\n'
    )
    tar_path.chmod(0o755)

    proc = None
    out = runtime_log.open('wb')
    err = runtime_err.open('wb')
    try:
        proc = subprocess.Popen(
            ['python3', str(SCRIPT)],
            cwd='/home/user', stdout=out, stderr=err,
            start_new_session=True,
        )

        deadline = time.time() + 8
        while time.time() < deadline:
            if proc.poll() is not None:
                break
            if LIVE.is_symlink() and os.readlink(LIVE) == str(PUBLISHED):
                break
            time.sleep(0.1)
        assert proc.poll() is None, f'Daemon exited during startup; stderr: {runtime_err.read_text(errors="replace")}'
        assert LIVE.is_symlink() and os.readlink(LIVE) == str(PUBLISHED)
        time.sleep(1)

        nested = SRC / 'probe' / 'item.txt'
        nested.parent.mkdir()
        time.sleep(0.8)
        nested.write_text('version one\n')
        time.sleep(0.8)
        with nested.open('a') as f:
            f.write('version two\n')
        time.sleep(0.8)
        root_file = SRC / 'root.md'
        root_file.write_text('# Runtime probe\n')
        time.sleep(0.8)
        nested.unlink()

        deadline = time.time() + 15
        while time.time() < deadline:
            expected = PUBLISHED / 'root.md'
            deleted = PUBLISHED / 'probe' / 'item.txt'
            if expected.is_file() and not deleted.exists() and not (PUBLISHED / 'stale').exists():
                try:
                    if os.stat(expected).st_ino == os.stat(root_file).st_ino:
                        break
                except FileNotFoundError:
                    pass
            assert proc.poll() is None, f'Daemon exited early; stderr: {runtime_err.read_text(errors="replace")}'
            time.sleep(0.15)
        _assert_perfect_hardlink_mirror()
        time.sleep(3)
    finally:
        if proc is not None and proc.poll() is None:
            os.killpg(proc.pid, signal.SIGINT)
            try:
                proc.wait(timeout=6)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGTERM)
                try:
                    proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(proc.pid, signal.SIGKILL)
                    proc.wait(timeout=3)
        out.close()
        err.close()
        if tar_path.exists():
            tar_path.unlink()
        if real_tar.exists():
            os.rename(real_tar, tar_path)

    assert LIVE.is_symlink() and os.readlink(LIVE) == str(PUBLISHED)
    _assert_perfect_hardlink_mirror()

    lines = runtime_log.read_text(errors='replace').splitlines()
    assert lines, 'The executed daemon produced no event log lines.'
    exact = re.compile(r'^EVENT: ([A-Za-z_]+) \| PATH: (/home/user/docs/src(?:/.*)?)$')
    parsed = []
    for line in lines:
        match = exact.fullmatch(line)
        assert match, f'Unexpected stdout line or incorrect event format: {line!r}'
        parsed.append((match.group(1), match.group(2)))

    nested_path = str(SRC / 'probe' / 'item.txt')
    root_path = str(SRC / 'root.md')
    assert ('created', nested_path) in parsed, 'Missing watchdog creation event for probe file.'
    assert ('modified', nested_path) in parsed, 'Missing watchdog modification event for probe file.'
    assert ('deleted', nested_path) in parsed, 'Missing watchdog deletion event for probe file.'
    assert ('created', root_path) in parsed, 'Missing watchdog creation event for root file.'

    snar = BACKUPS / 'snapshot.snar'
    assert snar.is_file() and snar.stat().st_size > 0, 'GNU incremental snapshot file was not produced.'
    assert snar.read_bytes().startswith(b'GNU tar-'), 'snapshot.snar is not a GNU tar snapshot file.'

    archives = sorted(BACKUPS.glob('backup_*.tar'), key=lambda p: int(re.fullmatch(r'backup_(\d+)\.tar', p.name).group(1)))
    numbers = [int(re.fullmatch(r'backup_(\d+)\.tar', p.name).group(1)) for p in archives]
    assert len(archives) >= 4, 'Expected multiple runtime incremental archives.'
    assert numbers == list(range(len(archives))), f'Backup numbering is not sequential from zero: {numbers}'

    trace_lines = tar_trace.read_text(errors='replace').splitlines() if tar_trace.exists() else []
    assert len(trace_lines) == len(archives), 'Every backup must come from one GNU tar invocation.'
    assert len(lines) == len(archives), 'Every logged watchdog event must trigger exactly one backup.'
    for index, (archive, invocation) in enumerate(zip(archives, trace_lines)):
        assert '--listed-incremental=/home/user/docs/backups/snapshot.snar' in invocation, \
            f'Backup {index} did not use the required GNU incremental option.'
        assert str(archive) in invocation, f'GNU tar invocation did not target {archive}.'
        assert archive.stat().st_size > 0, f'{archive} is empty.'
        result = subprocess.run(['/usr/bin/tar', '-tf', str(archive)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert result.returncode == 0, f'{archive} is not a valid tar archive: {result.stderr.decode(errors="replace")}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
