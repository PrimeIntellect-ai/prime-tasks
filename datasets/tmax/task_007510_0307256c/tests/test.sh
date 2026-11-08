#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import fcntl
import os
import secrets
import shutil
import stat
import subprocess
import sys
import tempfile
import time

import pytest

BASE_DIR = '/home/user/project_dump'
REPORT_FILE = '/home/user/report.txt'
SCRIPT_FILE = '/home/user/organizer.py'


def test_organizer_script_exists_and_uses_flock():
    assert os.path.exists(SCRIPT_FILE), f"Organizer script {SCRIPT_FILE} is missing."
    assert not os.path.islink(SCRIPT_FILE), f"Organizer script {SCRIPT_FILE} must be a regular file, not a symlink."
    assert stat.S_ISREG(os.stat(SCRIPT_FILE).st_mode), f"Organizer script {SCRIPT_FILE} is not a regular file."

    with open(SCRIPT_FILE, 'r', encoding='utf-8') as f:
        source = f.read()

    try:
        tree = ast.parse(source, filename=SCRIPT_FILE)
    except SyntaxError as exc:
        pytest.fail(f"Organizer script is not valid Python: {exc}")

    fcntl_aliases = {'fcntl'}
    flock_aliases = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for item in node.names:
                if item.name == 'fcntl':
                    fcntl_aliases.add(item.asname or item.name)
        elif isinstance(node, ast.ImportFrom) and node.module == 'fcntl':
            for item in node.names:
                if item.name == 'flock':
                    flock_aliases.add(item.asname or item.name)

    uses_flock = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if isinstance(func, ast.Attribute) and func.attr == 'flock':
            if isinstance(func.value, ast.Name) and func.value.id in fcntl_aliases:
                uses_flock = True
        elif isinstance(func, ast.Name) and func.id in flock_aliases:
            uses_flock = True

    assert uses_flock, "Organizer script must call fcntl.flock."


def test_report_file():
    assert os.path.exists(REPORT_FILE), f"Report file {REPORT_FILE} is missing."
    with open(REPORT_FILE, 'r', encoding='utf-8') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 2, "Report file must contain at least two lines."
    assert lines[0] == '5', f"Expected 5 total .txt files processed, got {lines[0]}"
    assert lines[1] == '2', f"Expected 2 hard links created, got {lines[1]}"


def test_files_are_utf8():
    expected_contents = {
        "module_a/desc.txt": "Résumé of the café project.",
        "module_b/notes.txt": "こんにちは世界",
        "module_b/desc_backup.txt": "Résumé of the café project.",
        "docs/ReadMe.txt": "How to use this system.",
        "docs/intro.txt": "Résumé of the café project.",
    }

    for rel_path, expected_text in expected_contents.items():
        full_path = os.path.join(BASE_DIR, rel_path)
        assert os.path.exists(full_path), f"File {full_path} is missing."
        try:
            with open(full_path, 'r', encoding='utf-8') as f:
                content = f.read()
            assert content == expected_text, f"Content mismatch in {full_path}. Expected '{expected_text}', got '{content}'"
        except UnicodeDecodeError:
            pytest.fail(f"File {full_path} is not valid UTF-8.")


def test_hard_link_deduplication():
    file1 = os.path.join(BASE_DIR, "module_a/desc.txt")
    file2 = os.path.join(BASE_DIR, "module_b/desc_backup.txt")
    file3 = os.path.join(BASE_DIR, "docs/intro.txt")

    assert os.path.exists(file1), f"Missing {file1}"
    assert os.path.exists(file2), f"Missing {file2}"
    assert os.path.exists(file3), f"Missing {file3}"

    stat1 = os.stat(file1)
    stat2 = os.stat(file2)
    stat3 = os.stat(file3)

    assert stat1.st_ino == stat2.st_ino == stat3.st_ino, "Files with identical content were not hard-linked to the same inode."


def test_symlink_created():
    symlink_path = os.path.join(BASE_DIR, "docs/README.md")
    target_path = os.path.join(BASE_DIR, "docs/ReadMe.txt")

    assert os.path.exists(symlink_path), f"Symlink {symlink_path} is missing."
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symbolic link."

    target = os.readlink(symlink_path)
    abs_target = os.path.abspath(os.path.join(os.path.dirname(symlink_path), target))
    assert abs_target == os.path.abspath(target_path), f"Symlink {symlink_path} points to {target}, expected {target_path}"


def test_execute_organizer_on_derived_inputs_with_exclusive_locks():
    token = secrets.token_hex(6)
    backup_root = tempfile.mkdtemp(prefix='organizer-verifier-', dir='/home/user')
    backup_project = os.path.join(backup_root, 'project_dump')
    backup_report = os.path.join(backup_root, 'report.txt')
    had_report = os.path.lexists(REPORT_FILE)
    process = None
    locked_files = []

    os.rename(BASE_DIR, backup_project)
    if had_report:
        os.rename(REPORT_FILE, backup_report)

    try:
        left_dir = os.path.join(BASE_DIR, 'left_' + token)
        right_dir = os.path.join(BASE_DIR, 'nested_' + token, 'right')
        docs_dir = os.path.join(BASE_DIR, 'manual_' + token)
        os.makedirs(left_dir)
        os.makedirs(right_dir)
        os.makedirs(docs_dir)

        duplicate_text = f"Résumé for dynamic café {token}."
        unique_text = f"こんにちは動的世界-{token}"
        readme_text = f"Dynamic instructions {token}."

        first = os.path.join(left_dir, 'primary_' + token + '.txt')
        second = os.path.join(right_dir, 'copy_' + token + '.TXT')
        unique = os.path.join(right_dir, 'unique_' + token + '.txt')
        readme = os.path.join(docs_dir, 'rEaDmE.TxT')
        nontext = os.path.join(BASE_DIR, 'keep_' + token + '.bin')

        with open(first, 'wb') as f:
            f.write(duplicate_text.encode('windows-1252'))
        with open(second, 'wb') as f:
            f.write(duplicate_text.encode('utf-8'))
        with open(unique, 'wb') as f:
            f.write(unique_text.encode('utf-8'))
        with open(readme, 'wb') as f:
            f.write(readme_text.encode('utf-8'))
        with open(nontext, 'wb') as f:
            f.write(b'unchanged-non-text-' + token.encode('ascii'))

        original_bytes = {path: open(path, 'rb').read() for path in (first, second, unique, readme)}

        # Shared locks allow other shared locks but block the exclusive lock required
        # by the task. Lock every input so traversal order cannot avoid this check.
        for path in (first, second, unique, readme):
            handle = open(path, 'rb')
            fcntl.flock(handle.fileno(), fcntl.LOCK_SH)
            locked_files.append(handle)

        process = subprocess.Popen(
            [sys.executable, SCRIPT_FILE],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        time.sleep(0.75)
        assert process.poll() is None, "Organizer did not wait for exclusive access to the locked .txt files."
        assert not os.path.exists(REPORT_FILE), "Organizer produced its report before acquiring the required exclusive file locks."
        for path, expected in original_bytes.items():
            with open(path, 'rb') as f:
                assert f.read() == expected, f"Organizer modified {path} without first obtaining an exclusive lock."

        for handle in locked_files:
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
            handle.close()
        locked_files.clear()

        stdout, stderr = process.communicate(timeout=20)
        assert process.returncode == 0, f"Organizer execution failed with code {process.returncode}. stdout={stdout!r}, stderr={stderr!r}"

        expected = {
            first: duplicate_text,
            second: duplicate_text,
            unique: unique_text,
            readme: readme_text,
        }
        for path, text in expected.items():
            assert os.path.isfile(path), f"Organizer removed expected text file {path}."
            try:
                with open(path, 'r', encoding='utf-8') as f:
                    actual = f.read()
            except UnicodeDecodeError:
                pytest.fail(f"Dynamically generated file {path} was not converted to UTF-8.")
            assert actual == text, f"Unexpected converted content in {path}: {actual!r}"

        assert os.stat(first).st_ino == os.stat(second).st_ino, "Dynamic duplicate files were not hard-linked."
        assert os.stat(first).st_dev == os.stat(second).st_dev, "Dynamic duplicate files are not the same hard link."
        assert os.stat(unique).st_ino != os.stat(first).st_ino, "Different dynamic content was incorrectly deduplicated."

        readme_link = os.path.join(docs_dir, 'README.md')
        assert os.path.islink(readme_link), "README.md symlink was not created for a case-insensitive readme.txt name."
        target = os.readlink(readme_link)
        resolved = os.path.abspath(os.path.join(docs_dir, target))
        assert resolved == os.path.abspath(readme), f"Dynamic README.md points to {target!r}, not {readme!r}."

        with open(nontext, 'rb') as f:
            assert f.read() == b'unchanged-non-text-' + token.encode('ascii'), "Non-text file was modified."

        assert os.path.isfile(REPORT_FILE), "Organizer did not create report.txt when executed."
        with open(REPORT_FILE, 'r', encoding='utf-8') as f:
            lines = [line.strip() for line in f if line.strip()]
        assert len(lines) >= 2, "Dynamic report must contain at least two lines."
        assert lines[0] == '4', f"Dynamic report expected 4 processed files, got {lines[0]!r}."
        assert lines[1] == '1', f"Dynamic report expected 1 deduplication hard link, got {lines[1]!r}."
    finally:
        if process is not None and process.poll() is None:
            process.kill()
            process.communicate()
        for handle in locked_files:
            try:
                fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
                handle.close()
            except Exception:
                pass
        if os.path.lexists(BASE_DIR):
            shutil.rmtree(BASE_DIR)
        if os.path.lexists(REPORT_FILE):
            os.unlink(REPORT_FILE)
        if os.path.exists(backup_project):
            os.rename(backup_project, BASE_DIR)
        if had_report and os.path.exists(backup_report):
            os.rename(backup_report, REPORT_FILE)
        shutil.rmtree(backup_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
