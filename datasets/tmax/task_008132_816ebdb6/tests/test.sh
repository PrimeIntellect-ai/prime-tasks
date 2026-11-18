#!/bin/bash
set -e
mkdir -p /logs/verifier

cat > /tmp/test_curator.py <<'PY'
import io
import os
import pathlib
import secrets
import signal
import subprocess
import tarfile
import time

HOME = pathlib.Path('/home/user')
INCOMING = HOME / 'incoming'
CURATED = HOME / 'curated'
SOURCE = HOME / 'curator.c'
EXECUTABLE = HOME / 'curator'
ARCHIVE = CURATED / 'artifact_curated.tar.gz'
SUMMARY = CURATED / 'summary.txt'


def check(condition, message):
    if not condition:
        raise AssertionError(message)


def add_bytes(tar, name, data):
    info = tarfile.TarInfo(name)
    info.size = len(data)
    info.mode = 0o644
    info.mtime = int(time.time())
    tar.addfile(info, io.BytesIO(data))


def stop_old_curators():
    subprocess.run(['pkill', '-x', 'curator'], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.2)


def clean_directory(path):
    path.mkdir(parents=True, exist_ok=True)
    for child in path.iterdir():
        if child.is_dir() and not child.is_symlink():
            import shutil
            shutil.rmtree(child)
        else:
            child.unlink()


def main():
    # Preserve the original source/executable assertions.
    check(SOURCE.exists(), 'Source file /home/user/curator.c is missing.')
    check(EXECUTABLE.exists(), 'Executable /home/user/curator is missing.')
    check(os.access(EXECUTABLE, os.X_OK), '/home/user/curator is not executable.')

    source_text = SOURCE.read_text(encoding='utf-8', errors='replace')
    check(source_text.strip(), 'curator.c is empty.')

    # Build the submitted source so the behavior being tested cannot come from an
    # unrelated fabricated executable.
    build = subprocess.run(
        ['gcc', '-std=gnu11', '-O2', str(SOURCE), '-o', str(EXECUTABLE)],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    check(build.returncode == 0, 'curator.c did not compile:\n' + build.stdout)
    check(os.access(EXECUTABLE, os.X_OK), 'Compiled curator is not executable.')

    # Verify that the compiled C artifact actually links to the required native APIs.
    symbols_run = subprocess.run(['nm', '-D', str(EXECUTABLE)], text=True,
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    check(symbols_run.returncode == 0, 'Could not inspect compiled curator symbols.')
    symbols = symbols_run.stdout
    check(('inotify_init' in symbols or 'inotify_init1' in symbols) and
          'inotify_add_watch' in symbols,
          'Compiled curator does not use the Linux inotify API.')
    check('iconv_open' in symbols and 'iconv_close' in symbols and ' iconv' in symbols,
          'Compiled curator does not use the iconv API for conversion.')
    traversal_apis = ('opendir', 'readdir', 'scandir', 'nftw', 'ftw', 'fts_open', 'glob')
    check(any(api in symbols for api in traversal_apis),
          'Compiled curator does not use a native C directory traversal API.')

    stop_old_curators()
    clean_directory(INCOMING)
    clean_directory(CURATED)
    ready = HOME / 'ready'
    if ready.exists():
        ready.unlink()

    token = secrets.token_hex(12)
    expected_text = 'System boot sequence initiated.\nError 0x44: Legacy module failed.'
    sys_text = expected_text + '\nverification-token=' + token + '\n'
    nested_name = 'diagnostic_' + token + '.log'
    nested_text = 'Nested legacy log\nvalue=' + secrets.token_hex(18) + '\n'
    expected_by_basename = {
        'sys_report.log': sys_text.encode('utf-8'),
        nested_name: nested_text.encode('utf-8'),
    }

    # Generate a fresh tar archive whose contents and split point are unknown until
    # verification. All log payloads are strictly UTF-16LE.
    tar_buffer = io.BytesIO()
    with tarfile.open(fileobj=tar_buffer, mode='w') as tar:
        add_bytes(tar, 'sys_report.log', sys_text.encode('utf-16le'))
        add_bytes(tar, 'deep/subdirectory/' + nested_name,
                  nested_text.encode('utf-16le'))
        add_bytes(tar, 'binary_data.bin', os.urandom(257))
        add_bytes(tar, 'deep/ignore_' + token + '.txt',
                  'not a log'.encode('utf-16le'))
    archive_bytes = tar_buffer.getvalue()
    split_at = len(archive_bytes) // 2 + secrets.randbelow(101) - 50
    split_at = max(1, min(len(archive_bytes) - 1, split_at))

    out_file = open('/tmp/curator.stdout', 'wb')
    err_file = open('/tmp/curator.stderr', 'wb')
    proc = None
    try:
        proc = subprocess.Popen([str(EXECUTABLE)], cwd=str(HOME),
                                stdout=out_file, stderr=err_file)
        time.sleep(0.7)
        check(proc.poll() is None, 'curator exited before manifest.done was created.')
        ready.touch()

        (INCOMING / 'artifact.tar.001').write_bytes(archive_bytes[:split_at])
        (INCOMING / 'artifact.tar.002').write_bytes(archive_bytes[split_at:])

        # Archive parts alone must not trigger processing.
        time.sleep(0.7)
        check(proc.poll() is None, 'curator exited before the inotify trigger.')
        check(not ARCHIVE.exists() and not SUMMARY.exists(),
              'curator processed the archive before manifest.done was created.')

        (INCOMING / 'manifest.done').touch()
        try:
            return_code = proc.wait(timeout=20)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
            raise AssertionError('curator did not process manifest.done and exit in time.')
        check(return_code == 0, 'curator exited with status %s.' % return_code)
    finally:
        if proc is not None and proc.poll() is None:
            proc.send_signal(signal.SIGTERM)
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
        out_file.close()
        err_file.close()

    # Preserve and strengthen the original curated-archive assertions.
    check(ARCHIVE.exists(), 'Archive /home/user/curated/artifact_curated.tar.gz is missing.')
    check(tarfile.is_tarfile(ARCHIVE), 'Curated output is not a valid tar archive.')
    with tarfile.open(ARCHIVE, 'r:gz') as tar:
        members = tar.getmembers()
        check(all(not pathlib.PurePosixPath(m.name).is_absolute() and
                  '..' not in pathlib.PurePosixPath(m.name).parts
                  for m in members), 'Archive contains an absolute or unsafe path.')
        check(all(m.isfile() or m.isdir() for m in members),
              'Archive contains a link or special file.')
        files = [m for m in members if m.isfile()]
        check(all(m.name.endswith('.log') for m in files),
              'Archive contains a non-.log file.')
        check(not any(m.name.endswith('binary_data.bin') for m in files),
              'Archive should not contain binary_data.bin.')
        check(len(files) == 2, 'Archive must contain exactly the two input log files.')
        check({pathlib.PurePosixPath(m.name).name for m in files} == set(expected_by_basename),
              'Archive has missing, renamed, or unexpected log files.')

        for member in files:
            basename = pathlib.PurePosixPath(member.name).name
            extracted = tar.extractfile(member)
            check(extracted is not None, 'Could not extract ' + member.name)
            content = extracted.read()
            try:
                content.decode('utf-8')
            except UnicodeDecodeError as exc:
                raise AssertionError(member.name + ' is not valid UTF-8.') from exc
            check(content == expected_by_basename[basename],
                  member.name + ' was not correctly converted from UTF-16LE to UTF-8.')

        sys_member = next(m for m in files if m.name.endswith('sys_report.log'))
        sys_content = tar.extractfile(sys_member).read().decode('utf-8')
        check(expected_text in sys_content.replace('\r\n', '\n'),
              'sys_report.log does not contain the original expected text.')

    # Preserve the original summary assertion while requiring a complete, exact list.
    check(SUMMARY.exists(), 'Summary file /home/user/curated/summary.txt is missing.')
    summary_text = SUMMARY.read_text(encoding='utf-8')
    check('sys_report.log' in summary_text,
          'summary.txt does not contain the processed sys_report.log name.')
    lines = [line.strip() for line in summary_text.splitlines() if line.strip()]
    check(len(lines) == 2, 'summary.txt must contain one line for each processed log.')
    summary_basenames = [pathlib.PurePosixPath(line).name for line in lines]
    check(set(summary_basenames) == set(expected_by_basename) and
          len(set(summary_basenames)) == 2,
          'summary.txt has missing, duplicate, or unexpected file names.')


if __name__ == '__main__':
    main()
PY

if python3 /tmp/test_curator.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
