#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import re
import stat
import subprocess
import tarfile
import tempfile
from pathlib import Path

DOC_INDEX_PATH = '/home/user/doc_index.txt'
FIRMWARE_PATH = '/home/user/artifacts/firmware.elf'
GCODE_PATH = '/home/user/artifacts/jig_path.gcode'
ARCHIVE_PATH = '/home/user/artifacts/build_logs.tar.gz'
LOCK_LOG = '/tmp/verifier_flock.log'
PRELOAD = '/tmp/verifier_flock.so'


def get_elf_entry_point(filepath):
    try:
        output = subprocess.check_output(['readelf', '-h', filepath], universal_newlines=True)
        for line in output.splitlines():
            if 'Entry point address' in line:
                match = re.search(r'0x[0-9a-fA-F]+', line)
                if match:
                    return match.group(0)
    except Exception:
        pass
    return None


def test_doc_index_exists():
    assert os.path.isfile(DOC_INDEX_PATH), f"{DOC_INDEX_PATH} does not exist."


def test_doc_index_content():
    with open(DOC_INDEX_PATH, 'r') as f:
        content = f.read()

    # Keep the original fixed-fixture assertions.
    assert re.search(r'^MAX_Z:\s*24\.5$', content, re.MULTILINE), "MAX_Z value is incorrect or missing. Expected 24.5."

    expected_entry = get_elf_entry_point(FIRMWARE_PATH)
    assert expected_entry is not None, "Could not determine expected ELF entry point from firmware.elf."

    elf_match = re.search(r'^ELF_ENTRY:\s*(0x[0-9a-fA-F]+)$', content, re.MULTILINE)
    assert elf_match is not None, "ELF_ENTRY line is missing or incorrectly formatted."
    actual_entry = elf_match.group(1)
    assert int(actual_entry, 16) == int(expected_entry, 16), f"ELF_ENTRY value is incorrect. Expected {expected_entry}, got {actual_entry}."

    expected_error_no_spaces = "Memory layout corrupted.Address bus assertion failed.Aborting build."
    expected_error_spaces = "Memory layout corrupted. Address bus assertion failed. Aborting build."
    fatal_error_match = re.search(r'^FATAL_ERROR:\s*(.*)$', content, re.MULTILINE)
    assert fatal_error_match is not None, "FATAL_ERROR line is missing or incorrectly formatted."
    actual_error = fatal_error_match.group(1).strip()
    assert actual_error in (expected_error_no_spaces, expected_error_spaces), f"FATAL_ERROR value is incorrect. Got: {actual_error}"


def readable_script_files():
    files = []
    roots = ['/home/user', '/usr/local/bin']
    excluded = {
        DOC_INDEX_PATH, FIRMWARE_PATH, GCODE_PATH, ARCHIVE_PATH,
        '/home/user/.bashrc', '/home/user/.profile', '/home/user/.bash_logout'
    }
    for root in roots:
        if not os.path.isdir(root):
            continue
        for base, dirs, names in os.walk(root):
            if base.startswith('/home/user/artifacts'):
                dirs[:] = []
                continue
            for name in names:
                path = os.path.join(base, name)
                if path in excluded:
                    continue
                try:
                    if os.path.getsize(path) > 1024 * 1024:
                        continue
                    data = Path(path).read_bytes()
                    text = data.decode('utf-8')
                except (OSError, UnicodeError):
                    continue
                first = text.splitlines()[0] if text.splitlines() else ''
                script_like = (
                    first.startswith('#!') or
                    path.endswith(('.sh', '.bash', '.py', '.awk', '.pl'))
                )
                if script_like:
                    files.append((path, text))
    return files


def strip_comment_lines(text):
    return '\n'.join(line for line in text.splitlines()
                     if not re.match(r'^\s*#', line))


def find_submission():
    files = readable_script_files()
    assert files, "No script was created under /home/user or /usr/local/bin."

    candidates = []
    for path, text in files:
        score = 0
        score += 8 if 'doc_index.txt' in text else 0
        score += 3 if 'firmware.elf' in text else 0
        score += 3 if 'jig_path.gcode' in text else 0
        score += 3 if 'build_logs.tar.gz' in text else 0
        if score >= 8:
            candidates.append((score, path, text))
    assert candidates, "No created script writes /home/user/doc_index.txt."
    candidates.sort(reverse=True)
    return candidates[0][1], files


def command_for(path):
    mode = os.stat(path).st_mode
    if mode & stat.S_IXUSR:
        return [path]
    if path.endswith('.py'):
        return ['python3', path]
    if path.endswith('.awk'):
        return ['awk', '-f', path]
    return ['bash', path]


def build_lock_monitor():
    source = r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <sys/file.h>
#include <sys/syscall.h>
#include <unistd.h>

typedef int (*flock_fn)(int, int);
int flock(int fd, int operation) {
    static flock_fn real_flock = 0;
    if (!real_flock) real_flock = (flock_fn)dlsym(RTLD_NEXT, "flock");
    int logfd = syscall(SYS_openat, AT_FDCWD, "/tmp/verifier_flock.log",
                        O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (logfd >= 0) {
        const char msg[] = "flock\n";
        syscall(SYS_write, logfd, msg, sizeof(msg) - 1);
        syscall(SYS_close, logfd);
    }
    return real_flock(fd, operation);
}
'''
    Path('/tmp/verifier_flock.c').write_text(source)
    subprocess.check_call(['gcc', '-shared', '-fPIC', '-o', PRELOAD,
                           '/tmp/verifier_flock.c', '-ldl'])


def run_as_user(cmd):
    env = os.environ.copy()
    env['LD_PRELOAD'] = PRELOAD
    return subprocess.Popen(
        cmd, cwd='/home/user', env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        preexec_fn=lambda: (os.setgid(1000), os.setuid(1000)))


def parse_exact_blocks(content, expected_entry, count):
    lines = content.splitlines()
    assert len(lines) == count * 3, f"Expected {count * 3} output lines, got {len(lines)}: {lines!r}"
    expected_fatal = {
        'Controller omega failed.Sensor 17 unavailable.Recovery stopped.',
        'Controller omega failed. Sensor 17 unavailable. Recovery stopped.'
    }
    for offset in range(0, len(lines), 3):
        m = re.fullmatch(r'ELF_ENTRY:\s*(0x[0-9a-fA-F]+)', lines[offset])
        assert m and int(m.group(1), 16) == int(expected_entry, 16), \
            f"Incorrect dynamic ELF entry line: {lines[offset]!r}"
        assert re.fullmatch(r'MAX_Z:\s*37\.75', lines[offset + 1]), \
            f"Incorrect dynamic MAX_Z line: {lines[offset + 1]!r}"
        m = re.fullmatch(r'FATAL_ERROR:\s*(.*)', lines[offset + 2])
        assert m and m.group(1).strip() in expected_fatal, \
            f"Incorrect dynamic fatal block: {lines[offset + 2]!r}"


def test_created_script_streams_dynamic_inputs_and_locks():
    script, all_scripts = find_submission()
    uncommented = '\n'.join(strip_comment_lines(text) for _, text in all_scripts)

    assert re.search(r'\bflock\b|fcntl\s*\.\s*flock\s*\(', uncommented), \
        "The created scripts do not contain an actual file-locking operation."

    stream_patterns = [
        r'\btar\b[^\n]*(?:--to-stdout|-[A-Za-z]*O[A-Za-z]*)',
        r'\b(?:zcat|gzcat)\b',
        r'\bgzip\b[^\n]*-[A-Za-z]*[cd][A-Za-z]*',
        r'\.extractfile\s*\('
    ]
    assert any(re.search(p, uncommented) for p in stream_patterns), \
        "The archive is not processed through a streaming operation."
    assert not re.search(r'\.extractall\s*\(|\.extract\s*\(', uncommented), \
        "The script uses a tar extraction API instead of streaming."
    for line in uncommented.splitlines():
        if re.search(r'\btar\b', line) and re.search(r'\s-[A-Za-z]*x', line):
            assert re.search(r'--to-stdout|-[A-Za-z]*O[A-Za-z]*', line), \
                f"Tar extraction without stdout streaming was found: {line!r}"

    originals = {p: Path(p).read_bytes() for p in (FIRMWARE_PATH, GCODE_PATH, ARCHIVE_PATH)}
    try:
        with tempfile.TemporaryDirectory() as td:
            c_path = os.path.join(td, 'dynamic.c')
            Path(c_path).write_text('int dynamic_entry(void) { return 7; }\n')
            subprocess.check_call([
                'gcc', '-nostdlib', '-Wl,-e,dynamic_entry', c_path, '-o', FIRMWARE_PATH
            ])

        Path(GCODE_PATH).write_text(
            'G28\nG1 X0 Z-8.5\nG1 X1 Z3\nG1 X2 Y4 Z37.75\nG1 Z19.125\n')

        member_name = 'verification_stream_only_9137.log'
        log_data = (
            'unrelated start\n'
            '--- BEGIN FATAL ---\n'
            'Controller omega failed.\n'
            'Sensor 17 unavailable.\n'
            'Recovery stopped.\n'
            '--- END FATAL ---\n'
            'unrelated end\n'
        ).encode()
        with tarfile.open(ARCHIVE_PATH, 'w:gz') as tf:
            info = tarfile.TarInfo(member_name)
            info.size = len(log_data)
            tf.addfile(info, io.BytesIO(log_data))

        expected_entry = get_elf_entry_point(FIRMWARE_PATH)
        assert expected_entry is not None
        build_lock_monitor()
        Path(LOCK_LOG).write_text('')
        os.chmod(LOCK_LOG, 0o666)

        if os.path.exists(DOC_INDEX_PATH):
            os.unlink(DOC_INDEX_PATH)
        proc = run_as_user(command_for(script))
        out, err = proc.communicate(timeout=30)
        assert proc.returncode == 0, f"Created script failed on dynamic inputs: {out}\n{err}"
        parse_exact_blocks(Path(DOC_INDEX_PATH).read_text(), expected_entry, 1)
        assert Path(LOCK_LOG).read_text().strip(), "No file-locking call occurred while writing doc_index.txt."

        assert not any(Path('/home/user').rglob(member_name)), \
            "The archive member was extracted under /home/user instead of streamed."
        assert not os.path.exists('/tmp/' + member_name), \
            "The archive member was extracted to /tmp instead of streamed."

        os.unlink(DOC_INDEX_PATH)
        Path(LOCK_LOG).write_text('')
        os.chmod(LOCK_LOG, 0o666)
        processes = [run_as_user(command_for(script)) for _ in range(6)]
        failures = []
        for proc in processes:
            out, err = proc.communicate(timeout=30)
            if proc.returncode != 0:
                failures.append((proc.returncode, out, err))
        assert not failures, f"Concurrent script executions failed: {failures!r}"
        parse_exact_blocks(Path(DOC_INDEX_PATH).read_text(), expected_entry, 6)
        assert len(Path(LOCK_LOG).read_text().splitlines()) >= 6, \
            "Concurrent executions did not each perform file locking."
    finally:
        for path, data in originals.items():
            Path(path).write_bytes(data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
