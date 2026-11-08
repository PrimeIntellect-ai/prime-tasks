#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import tarfile
import re

def test_clean_docs_archive_exists():
    path = '/home/user/clean_docs.tar.gz'
    assert os.path.exists(path), f"File {path} does not exist."
    assert os.path.isfile(path), f"Path {path} is not a file."
    assert tarfile.is_tarfile(path), f"File {path} is not a valid tar archive."

def test_clean_docs_contents():
    path = '/home/user/clean_docs.tar.gz'
    expected_files = {'intro.txt', 'notes_win.txt', 'nested_doc.txt', 'data.md'}

    with tarfile.open(path, 'r:gz') as tar:
        members = tar.getmembers()
        filenames = set()
        for m in members:
            assert m.isfile(), f"Archive contains non-file member: {m.name}"
            assert '/' not in m.name and '\\' not in m.name, f"Archive member is not in a flat structure: {m.name}"
            filenames.add(m.name)

        assert filenames == expected_files, f"Archive contains incorrect files. Expected {expected_files}, got {filenames}."

def test_file_encodings_and_contents():
    path = '/home/user/clean_docs.tar.gz'

    with tarfile.open(path, 'r:gz') as tar:
        f = tar.extractfile('intro.txt')
        content = f.read()
        try:
            text = content.decode('utf-8')
        except UnicodeDecodeError:
            assert False, "intro.txt is not valid UTF-8."
        assert "This is the introduction." in text, "intro.txt content is incorrect."

        f = tar.extractfile('notes_win.txt')
        content = f.read()
        try:
            text = content.decode('utf-8')
        except UnicodeDecodeError:
            assert False, "notes_win.txt is not valid UTF-8."
        assert "Café and résumé." in text, "notes_win.txt content is incorrect or not properly converted."

        f = tar.extractfile('nested_doc.txt')
        content = f.read()
        try:
            text = content.decode('utf-8')
        except UnicodeDecodeError:
            assert False, "nested_doc.txt is not valid UTF-8."
        assert "Nested secret document." in text, "nested_doc.txt content is incorrect or not properly converted."

def test_markdown_table_format():
    path = '/home/user/clean_docs.tar.gz'
    with tarfile.open(path, 'r:gz') as tar:
        f = tar.extractfile('data.md')
        content = f.read()
        try:
            text = content.decode('utf-8')
        except UnicodeDecodeError:
            assert False, "data.md is not valid UTF-8."

        lines = [line.strip() for line in text.splitlines() if line.strip()]
        assert len(lines) >= 3, "data.md does not have enough lines for a markdown table."
        assert "Item" in lines[0] and "Cost" in lines[0], "data.md table header is incorrect."
        assert lines[0].startswith('|') and lines[0].endswith('|'), "data.md table header is not properly formatted with pipes."
        assert re.search(r'\|[-:]+\|\s*\|?[-:]+\|', lines[1].replace(' ', '')), "data.md table separator is incorrect."
        assert "Apple" in lines[2] and "1.00" in lines[2], "data.md table row 1 is incorrect."
        assert "Über" in lines[3] and "2.50" in lines[3], "data.md table row 2 is incorrect or not properly converted to UTF-8."

def test_processing_log():
    path = '/home/user/processing.log'
    assert os.path.exists(path), f"File {path} does not exist."

    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()

    assert "CORRUPT_ARCHIVES:" in content, "Log file missing CORRUPT_ARCHIVES line."
    assert "PROCESSED_FILES:" in content, "Log file missing PROCESSED_FILES line."

    lines = content.splitlines()
    corrupt_line = next((line for line in lines if line.startswith("CORRUPT_ARCHIVES:")), "")
    processed_line = next((line for line in lines if line.startswith("PROCESSED_FILES:")), "")

    assert "corrupt_nested.zip" in corrupt_line, "Log file does not correctly list corrupt_nested.zip as a corrupt archive."

    expected_processed = ["data.md", "intro.txt", "nested_doc.txt", "notes_win.txt"]
    for file in expected_processed:
        assert file in processed_line, f"Log file PROCESSED_FILES missing {file}."

    processed_files_str = processed_line.split(":", 1)[1].strip()
    processed_files_list = [x.strip() for x in processed_files_str.split(",")]
    assert processed_files_list == sorted(processed_files_list), "PROCESSED_FILES list is not sorted alphabetically."
    assert processed_files_list == expected_processed, f"PROCESSED_FILES list does not match expected exactly. Expected {expected_processed}, got {processed_files_list}."
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_dynamic_workflow.py
import os
import re
import secrets
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from pathlib import Path

HOME = Path('/home/user')
ARCHIVE = HOME / 'clean_docs.tar.gz'
LOG = HOME / 'processing.log'
SOURCE = HOME / 'legacy_docs.zip'
SNAPSHOT = Path(tempfile.mkdtemp(prefix='submitted_code_'))


def fail(message):
    raise AssertionError(message)


def snapshot_code():
    candidates = []
    python_files = []
    for path in HOME.rglob('*'):
        if not path.is_file() or path.is_symlink() or path.suffix.lower() not in {'.py', '.sh'}:
            continue
        rel = path.relative_to(HOME)
        destination = SNAPSHOT / rel
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, destination)
        if path.suffix.lower() == '.py':
            try:
                compile(path.read_bytes(), str(path), 'exec')
            except Exception:
                continue
            python_files.append(rel)
            candidates.append(rel)
        else:
            try:
                shell_text = path.read_text(encoding='utf-8', errors='ignore')
            except OSError:
                continue
            if re.search(r'(^|[^A-Za-z0-9_])(python3?|/[^\s]*python3?)([^A-Za-z0-9_]|$)', shell_text):
                candidates.append(rel)
    if not python_files:
        fail('No valid Python script was found under /home/user.')
    if not candidates:
        fail('No executable Python workflow or shell driver invoking Python was found.')
    return candidates


def reset_home():
    HOME.mkdir(parents=True, exist_ok=True)
    for child in list(HOME.iterdir()):
        if child.is_dir() and not child.is_symlink():
            shutil.rmtree(child)
        else:
            child.unlink(missing_ok=True)
    for source in SNAPSHOT.rglob('*'):
        rel = source.relative_to(SNAPSHOT)
        destination = HOME / rel
        if source.is_dir():
            destination.mkdir(parents=True, exist_ok=True)
        elif source.is_file():
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)


def make_fixture(token):
    intro_name = f'overview_{token}.txt'
    notes_name = f'accents_{token}.txt'
    csv_name = f'inventory_{token}.csv'
    md_name = f'inventory_{token}.md'
    nested_name = f'buried_{token}.txt'
    valid_name = f'valid_{token}.tar.gz'
    corrupt_name = f'broken_{token}.zip'

    intro_text = f'Introduction marker {token}.'
    notes_text = f'Café and résumé marker {token}.'
    nested_text = f'Nested document marker {token}.'
    csv_rows = [
        ['Product', 'Price'],
        [f'Apple-{token}', '7.25'],
        [f'Über-{token}', '9.50'],
    ]

    work = Path(tempfile.mkdtemp(prefix='legacy_fixture_'))
    try:
        (work / intro_name).write_text(intro_text, encoding='utf-8')
        (work / notes_name).write_bytes(notes_text.encode('windows-1252'))
        csv_text = '\n'.join(','.join(row) for row in csv_rows)
        (work / csv_name).write_bytes(csv_text.encode('iso-8859-1'))
        (work / nested_name).write_bytes(nested_text.encode('utf-16'))
        with tarfile.open(work / valid_name, 'w:gz') as nested:
            nested.add(work / nested_name, arcname=nested_name)
        (work / corrupt_name).write_bytes(b'not a zip archive ' + token.encode('ascii'))
        with zipfile.ZipFile(SOURCE, 'w') as outer:
            for name in (intro_name, notes_name, csv_name, valid_name, corrupt_name):
                outer.write(work / name, arcname=name)
    finally:
        shutil.rmtree(work)

    return {
        'intro_name': intro_name,
        'notes_name': notes_name,
        'md_name': md_name,
        'nested_name': nested_name,
        'corrupt_name': corrupt_name,
        'intro_text': intro_text,
        'notes_text': notes_text,
        'nested_text': nested_text,
        'csv_rows': csv_rows,
    }


def table_cells(line):
    line = line.strip()
    if not (line.startswith('|') and line.endswith('|')):
        fail(f'Markdown row is not pipe-delimited: {line!r}')
    return [cell.strip() for cell in line[1:-1].split('|')]


def validate(expected):
    if not ARCHIVE.is_file() or not tarfile.is_tarfile(ARCHIVE):
        fail('Workflow did not create a valid /home/user/clean_docs.tar.gz.')

    wanted = {
        expected['intro_name'], expected['notes_name'],
        expected['nested_name'], expected['md_name'],
    }
    with tarfile.open(ARCHIVE, 'r:gz') as archive:
        members = archive.getmembers()
        if any(not member.isfile() for member in members):
            fail('Dynamic archive contains a non-file member.')
        names = {member.name for member in members}
        if any('/' in name or '\\' in name for name in names):
            fail('Dynamic archive is not flat.')
        if names != wanted:
            fail(f'Dynamic archive names are wrong: expected {wanted}, got {names}.')

        for name, wanted_text in (
            (expected['intro_name'], expected['intro_text']),
            (expected['notes_name'], expected['notes_text']),
            (expected['nested_name'], expected['nested_text']),
        ):
            data = archive.extractfile(name).read()
            try:
                text = data.decode('utf-8')
            except UnicodeDecodeError as exc:
                fail(f'{name} is not UTF-8: {exc}')
            if text.strip() != wanted_text:
                fail(f'{name} did not preserve the dynamically generated text.')

        md_data = archive.extractfile(expected['md_name']).read()
        try:
            md_text = md_data.decode('utf-8')
        except UnicodeDecodeError as exc:
            fail(f"{expected['md_name']} is not UTF-8: {exc}")
        lines = [line.strip() for line in md_text.splitlines() if line.strip()]
        if len(lines) != 4:
            fail('Dynamic CSV was not converted to the expected four-line Markdown table.')
        if table_cells(lines[0]) != expected['csv_rows'][0]:
            fail('Dynamic Markdown header is wrong.')
        separator = table_cells(lines[1])
        if len(separator) != 2 or any(not re.fullmatch(r':?-{3,}:?', cell) for cell in separator):
            fail('Dynamic Markdown separator is wrong.')
        if table_cells(lines[2]) != expected['csv_rows'][1] or table_cells(lines[3]) != expected['csv_rows'][2]:
            fail('Dynamic Markdown rows are wrong.')

    if not LOG.is_file():
        fail('Workflow did not create processing.log for the dynamic fixture.')
    try:
        lines = LOG.read_text(encoding='utf-8').splitlines()
    except UnicodeDecodeError as exc:
        fail(f'processing.log is not UTF-8: {exc}')
    corrupt = [line for line in lines if line.startswith('CORRUPT_ARCHIVES:')]
    processed = [line for line in lines if line.startswith('PROCESSED_FILES:')]
    if len(corrupt) != 1 or len(processed) != 1:
        fail('Dynamic log does not contain exactly one required line of each type.')
    corrupt_items = [x.strip() for x in corrupt[0].split(':', 1)[1].split(',') if x.strip()]
    processed_items = [x.strip() for x in processed[0].split(':', 1)[1].split(',') if x.strip()]
    if corrupt_items != [expected['corrupt_name']]:
        fail(f'Dynamic corrupt archive list is wrong: {corrupt_items}.')
    if processed_items != sorted(wanted):
        fail(f'Dynamic processed file list is wrong or unsorted: {processed_items}.')


def main():
    candidates = snapshot_code()
    errors = []
    for relative in candidates:
        reset_home()
        token = secrets.token_hex(5)
        expected = make_fixture(token)
        candidate = HOME / relative
        if candidate.suffix.lower() == '.py':
            command = [sys.executable, str(candidate)]
        else:
            command = ['/bin/bash', str(candidate)]
        try:
            result = subprocess.run(
                command, cwd=str(HOME), stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT, timeout=45, text=True,
                errors='replace'
            )
            if result.returncode != 0:
                errors.append(f'{relative}: exited {result.returncode}')
                continue
            validate(expected)
            return
        except Exception as exc:
            errors.append(f'{relative}: {exc}')
    fail('No submitted workflow script processed a randomized archive correctly. ' + '; '.join(errors[-8:]))


if __name__ == '__main__':
    main()
DYNAMIC_EOF

ok=1
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || ok=0
if [ "$ok" -eq 1 ]; then
    python3 /tmp/test_dynamic_workflow.py 2>&1 || ok=0
fi

if [ "$ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
