#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import base64
import shutil
import subprocess
import threading
import time
import shlex
import pytest

SCRIPT_PATH = "/home/user/build_archive.sh"
ARCHIVE_PATH = "/home/user/master_archive.b64"
RAW_DOCS_DIR = "/home/user/raw_docs"


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_script_contains_required_commands():
    with open(SCRIPT_PATH, 'r') as f:
        content = f.read()

    assert "flock" in content, "Script must use 'flock' for file locking."
    assert "&" in content, "Script must use '&' to run processes in the background."
    assert "wait" in content, "Script must use 'wait' to wait for background jobs."


def test_archive_exists():
    assert os.path.isfile(ARCHIVE_PATH), f"Archive {ARCHIVE_PATH} does not exist."


def test_archive_contents():
    with open(ARCHIVE_PATH, 'r') as f:
        archive_content = f.read()

    txt_files = [f for f in os.listdir(RAW_DOCS_DIR) if f.endswith('.txt')]
    assert len(txt_files) > 0, "No .txt files found in raw_docs."

    for filename in txt_files:
        filepath = os.path.join(RAW_DOCS_DIR, filename)
        with open(filepath, 'r') as f:
            lines = f.readlines()

        processed_lines = []
        for line in lines:
            line = line.strip('\n')
            if not line:
                continue
            line = re.sub(r'[aeiouAEIOU]', '', line)
            processed_lines.append(line)

        processed_text = '\n'.join(processed_lines) + '\n'
        encoded_bytes = base64.b64encode(processed_text.encode('utf-8'))
        encoded_str = encoded_bytes.decode('utf-8')

        pattern = rf"---\[{re.escape(filename)}\]---\n(.*?)\n---\[EOF\]---"
        match = re.search(pattern, archive_content, re.DOTALL)

        assert match is not None, f"Archive is missing the correct format or entry for {filename}."
        actual_b64 = match.group(1).replace('\n', '')
        assert actual_b64 == encoded_str, f"Base64 content for {filename} does not match expected."


def _descendants(root_pid):
    ppid = {}
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        try:
            with open(f'/proc/{entry}/status', 'r') as f:
                status = f.read()
            match = re.search(r'^PPid:\s+(\d+)$', status, re.MULTILINE)
            if match:
                ppid[int(entry)] = int(match.group(1))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass

    found = set()
    frontier = {root_pid}
    while frontier:
        children = {pid for pid, parent in ppid.items() if parent in frontier and pid not in found}
        found.update(children)
        frontier = children
    return found


def _expected_payload(data):
    text = data.decode('utf-8')
    lines = []
    for line in text.splitlines():
        if line == '':
            continue
        lines.append(re.sub(r'[aeiouAEIOU]', '', line))
    return base64.b64encode(('\n'.join(lines) + '\n').encode('utf-8'))


def test_script_really_runs_jobs_concurrently_and_invokes_flock():
    backup_docs = RAW_DOCS_DIR + '.verifier-backup'
    archive_existed = os.path.exists(ARCHIVE_PATH)
    archive_backup = None
    if archive_existed:
        with open(ARCHIVE_PATH, 'rb') as f:
            archive_backup = f.read()

    flock_path = os.path.realpath(shutil.which('flock'))
    flock_backup = flock_path + '.verifier-real'
    flock_log = '/tmp/verifier-flock-live.log'
    proc = None
    release = threading.Event()
    opened = set()
    opened_lock = threading.Lock()
    threads = []

    names = [f'concurrent_{i}.txt' for i in range(4)]
    payloads = {
        name: ((f'Document {i} has vowels AEIOU and concurrent locking data {i}.\n' * 12000).encode('utf-8'))
        for i, name in enumerate(names)
    }

    def fifo_writer(path, name, data):
        try:
            fd = os.open(path, os.O_WRONLY)
            with opened_lock:
                opened.add(name)
            release.wait(15)
            view = memoryview(data)
            while view:
                written = os.write(fd, view)
                view = view[written:]
            os.close(fd)
        except OSError:
            pass

    try:
        assert not os.path.exists(backup_docs), f"Unexpected verifier backup path: {backup_docs}"
        os.rename(RAW_DOCS_DIR, backup_docs)
        os.mkdir(RAW_DOCS_DIR)
        os.chmod(RAW_DOCS_DIR, 0o777)

        for name in names:
            path = os.path.join(RAW_DOCS_DIR, name)
            os.mkfifo(path, 0o666)
            thread = threading.Thread(target=fifo_writer, args=(path, name, payloads[name]), daemon=True)
            thread.start()
            threads.append(thread)

        if os.path.exists(ARCHIVE_PATH):
            os.unlink(ARCHIVE_PATH)
        if os.path.exists(flock_log):
            os.unlink(flock_log)

        assert not os.path.exists(flock_backup), f"Unexpected flock backup path: {flock_backup}"
        os.rename(flock_path, flock_backup)
        wrapper = (
            '#!/bin/sh\n'
            f"printf '%s\\n' \"$$\" >> {shlex.quote(flock_log)}\n"
            f"exec {shlex.quote(flock_backup)} \"$@\"\n"
        )
        with open(flock_path, 'w') as f:
            f.write(wrapper)
        os.chmod(flock_path, 0o755)

        proc = subprocess.Popen(
            [SCRIPT_PATH],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        deadline = time.time() + 6
        while time.time() < deadline:
            with opened_lock:
                if len(opened) == len(names):
                    break
            if proc.poll() is not None:
                break
            time.sleep(0.02)

        with opened_lock:
            opened_count = len(opened)
        assert opened_count == len(names), (
            f"Only {opened_count}/{len(names)} inputs were opened before any could complete; "
            "the files are not being processed concurrently."
        )

        descendants = _descendants(proc.pid)
        assert len(descendants) >= 2, "No multiple concurrent background worker processes were observed."

        release.set()
        stdout, stderr = proc.communicate(timeout=30)
        assert proc.returncode == 0, f"Script failed when executed:\nstdout={stdout}\nstderr={stderr}"

        assert os.path.isfile(flock_log) and os.path.getsize(flock_log) > 0, (
            "The script completed without executing the flock command."
        )
        assert os.path.isfile(ARCHIVE_PATH), "Executing the script did not create the archive."

        with open(ARCHIVE_PATH, 'r') as f:
            archive = f.read()

        record_re = re.compile(r"---\[([^\]\n]+)\]---\n(.*?)---\[EOF\]---\n?", re.DOTALL)
        matches = list(record_re.finditer(archive))
        assert len(matches) == len(names), "Archive records are missing, duplicated, or interlaced."
        assert ''.join(m.group(0) for m in matches) == archive, "Archive contains malformed or interlaced data."
        assert {m.group(1) for m in matches} == set(names), "Archive contains incorrect filenames."

        for match in matches:
            name = match.group(1)
            actual = ''.join(match.group(2).split()).encode('ascii')
            assert actual == _expected_payload(payloads[name]), f"Incorrect or interlaced content for {name}."
    finally:
        release.set()
        if proc is not None and proc.poll() is None:
            proc.kill()
            proc.wait()

        if os.path.exists(flock_backup):
            try:
                if os.path.exists(flock_path):
                    os.unlink(flock_path)
                os.rename(flock_backup, flock_path)
            except OSError:
                pass

        if os.path.isdir(RAW_DOCS_DIR):
            shutil.rmtree(RAW_DOCS_DIR)
        if os.path.exists(backup_docs):
            os.rename(backup_docs, RAW_DOCS_DIR)

        if archive_existed:
            with open(ARCHIVE_PATH, 'wb') as f:
                f.write(archive_backup)
        elif os.path.exists(ARCHIVE_PATH):
            os.unlink(ARCHIVE_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
