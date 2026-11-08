#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import os
import secrets
import shutil
import struct
import subprocess
import tempfile
import time
from pathlib import Path

import pytest


def get_elf64_entry_point(filepath):
    """Extracts the entry point from a 64-bit ELF file using standard library."""
    with open(filepath, 'rb') as f:
        magic = f.read(4)
        if magic != b'\x7fELF':
            return None
        # Check if 64-bit
        ei_class = f.read(1)
        if ei_class != b'\x02':
            return None
        # 64-bit entry point is at offset 0x18
        f.seek(0x18)
        entry_bytes = f.read(8)
        entry_point = struct.unpack('<Q', entry_bytes)[0]
        return hex(entry_point)


def run_parser(parser, path, timeout=5):
    result = subprocess.run(
        [parser, path], text=True, capture_output=True, timeout=timeout
    )
    assert result.returncode == 0, result.stderr
    return result.stdout.strip()


def make_elf(path, entry):
    shutil.copyfile('/bin/true', path)
    with open(path, 'r+b') as f:
        assert f.read(5) == b'\x7fELF\x02'
        f.seek(0x18)
        f.write(struct.pack('<Q', entry))


def exercise_parser(parser, workdir):
    entry = secrets.randbits(52) | 0x1000
    elf_path = os.path.join(workdir, 'sample_' + secrets.token_hex(6))
    make_elf(elf_path, entry)
    assert run_parser(parser, elf_path) == hex(entry)

    text_path = os.path.join(workdir, 'text_' + secrets.token_hex(6))
    Path(text_path).write_bytes(b'not an ELF file\n' + os.urandom(31))
    assert run_parser(parser, text_path) == 'NOT_ELF'

    short_path = os.path.join(workdir, 'short_' + secrets.token_hex(6))
    Path(short_path).write_bytes(b'\x7fELF\x02')
    assert run_parser(parser, short_path) == 'NOT_ELF'


def verify_shared_lock(parser, workdir):
    first = secrets.randbits(52) | 0x1000
    second = secrets.randbits(52) | 0x2000
    while second == first:
        second = secrets.randbits(52) | 0x2000
    path = os.path.join(workdir, 'locked_' + secrets.token_hex(6))
    make_elf(path, first)

    with open(path, 'r+b', buffering=0) as locked:
        fcntl.flock(locked.fileno(), fcntl.LOCK_EX)
        proc = subprocess.Popen(
            [parser, path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        try:
            time.sleep(0.35)
            assert proc.poll() is None, 'parser did not wait for an exclusive file lock'
            locked.seek(0x18)
            locked.write(struct.pack('<Q', second))
            os.fsync(locked.fileno())
            fcntl.flock(locked.fileno(), fcntl.LOCK_UN)
            stdout, stderr = proc.communicate(timeout=5)
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.communicate()
        assert proc.returncode == 0, stderr
        assert stdout.strip() == hex(second)


def test_elf_parser_c_exists_and_contains_flock():
    path = "/home/user/elf_parser.c"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    assert "flock" in content, f"{path} does not seem to use flock as required."
    lowered = content.lower()
    assert 'readelf' not in lowered and 'objdump' not in lowered, \
        'The C parser must parse the ELF header itself.'


def test_elf_parser_executable():
    path = "/home/user/elf_parser"
    assert os.path.isfile(path), f"Compiled executable {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    with open(path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"{path} is not a compiled ELF executable."


def test_curate_sh_executable():
    path = "/home/user/curate.sh"
    assert os.path.isfile(path), f"Script {path} does not exist."
    assert os.access(path, os.X_OK), f"Script {path} is not executable."


def test_curation_report_content():
    report_path = "/home/user/curation_report.txt"
    assert os.path.isfile(report_path), f"Report file {report_path} does not exist."

    with open(report_path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in the report, found {len(lines)}."

    expected_ls_ep = get_elf64_entry_point("/home/user/artifacts/bin_ls")
    expected_cat_ep = get_elf64_entry_point("/home/user/artifacts/bin_cat")

    expected_ls_line = f"/home/user/artifacts/bin_ls : {expected_ls_ep}"
    expected_cat_line = f"/home/user/artifacts/bin_cat : {expected_cat_ep}"

    assert expected_ls_line in lines, f"Missing or incorrect entry for bin_ls. Expected: '{expected_ls_line}'"
    assert expected_cat_line in lines, f"Missing or incorrect entry for bin_cat. Expected: '{expected_cat_line}'"


def test_parser_behavior_and_rebuilt_source():
    with tempfile.TemporaryDirectory() as workdir:
        submitted = '/home/user/elf_parser'
        exercise_parser(submitted, workdir)
        verify_shared_lock(submitted, workdir)

        rebuilt = os.path.join(workdir, 'rebuilt_parser')
        result = subprocess.run(
            ['gcc', '-std=c11', '-O2', '/home/user/elf_parser.c', '-o', rebuilt],
            text=True, capture_output=True, timeout=15
        )
        assert result.returncode == 0, 'elf_parser.c did not compile:\n' + result.stderr
        exercise_parser(rebuilt, workdir)
        verify_shared_lock(rebuilt, workdir)


def test_curate_dynamic_traversal_deduplication_and_parser_invocation():
    artifacts = '/home/user/artifacts'
    report = '/home/user/curation_report.txt'
    parser = '/home/user/elf_parser'
    token = secrets.token_hex(8)
    artifacts_backup = '/tmp/artifacts_backup_' + token
    report_backup = '/tmp/report_backup_' + token
    parser_backup = '/tmp/elf_parser_backup_' + token
    call_log = '/tmp/parser_calls_' + token

    report_had_backup = False
    parser_moved = False
    artifacts_moved = False
    try:
        os.rename(artifacts, artifacts_backup)
        artifacts_moved = True
        if os.path.lexists(report):
            os.rename(report, report_backup)
            report_had_backup = True

        os.mkdir(artifacts)
        nested = os.path.join(artifacts, 'nested_' + secrets.token_hex(4))
        os.mkdir(nested)
        first_path = os.path.join(artifacts, 'elf_' + secrets.token_hex(5))
        second_path = os.path.join(nested, 'elf_' + secrets.token_hex(5))
        text_path = os.path.join(nested, 'note_' + secrets.token_hex(5))
        first_entry = secrets.randbits(52) | 0x1000
        second_entry = secrets.randbits(52) | 0x2000
        make_elf(first_path, first_entry)
        make_elf(second_path, second_entry)
        Path(text_path).write_text('dynamic non-ELF fixture\n', encoding='utf-8')

        os.symlink(os.path.basename(first_path), os.path.join(artifacts, 'alias_first'))
        os.symlink(os.path.basename(first_path), os.path.join(artifacts, 'alias_first_2'))
        os.symlink(os.path.basename(second_path), os.path.join(nested, 'alias_second'))
        os.symlink(os.path.basename(nested), os.path.join(artifacts, 'alias_directory'))
        os.symlink(artifacts, os.path.join(nested, 'back_to_root'))
        os.symlink('loop_b', os.path.join(artifacts, 'loop_a'))
        os.symlink('loop_a', os.path.join(artifacts, 'loop_b'))

        # Wrap the submitted parser so every invocation is recorded, while still
        # delegating parsing to the submitted compiled implementation.
        os.rename(parser, parser_backup)
        parser_moved = True
        wrapper = (
            '#!/bin/bash\n'
            + "printf '%s\\0' \"$1\" >> " + repr(call_log) + '\n'
            + 'exec ' + repr(parser_backup) + ' "$@"\n'
        )
        Path(parser).write_text(wrapper, encoding='utf-8')
        os.chmod(parser, 0o755)

        result = subprocess.run(
            ['/home/user/curate.sh'], text=True, capture_output=True, timeout=10
        )
        assert result.returncode == 0, (
            'curate.sh failed on symlink cycles:\n' + result.stdout + result.stderr
        )
        assert os.path.isfile(report), 'curate.sh did not generate the report'

        with open(report, encoding='utf-8') as f:
            lines = [line.strip() for line in f if line.strip()]
        expected = {
            f"{os.path.realpath(first_path)} : {hex(first_entry)}",
            f"{os.path.realpath(second_path)} : {hex(second_entry)}",
        }
        assert len(lines) == 2, f'Expected exactly two unique ELF entries, got: {lines}'
        assert set(lines) == expected

        raw_calls = Path(call_log).read_bytes().split(b'\0')
        calls = [os.path.realpath(x.decode()) for x in raw_calls if x]
        expected_calls = {
            os.path.realpath(first_path),
            os.path.realpath(second_path),
            os.path.realpath(text_path),
        }
        assert set(calls) == expected_calls, \
            f'curate.sh did not invoke the parser for exactly the regular files: {calls}'
        assert len(calls) == len(expected_calls), \
            f'curate.sh processed one or more target files more than once: {calls}'
    finally:
        if os.path.lexists(parser) and parser_moved:
            os.unlink(parser)
        if parser_moved and os.path.exists(parser_backup):
            os.rename(parser_backup, parser)
        if os.path.lexists(artifacts) and artifacts_moved:
            shutil.rmtree(artifacts)
        if artifacts_moved and os.path.exists(artifacts_backup):
            os.rename(artifacts_backup, artifacts)
        if os.path.lexists(report):
            os.unlink(report)
        if report_had_backup and os.path.exists(report_backup):
            os.rename(report_backup, report)
        if os.path.exists(call_log):
            os.unlink(call_log)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
