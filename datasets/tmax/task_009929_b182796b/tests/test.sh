#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import tempfile
import uuid
from pathlib import Path

HOME = Path('/home/user')
MODULES = HOME / 'organized/modules'
DOCS = HOME / 'organized/docs'
RAW = HOME / 'raw_files'

EXPECTED_MODULES = {
    'core.dat': b'\xDE\xCA\xFB\xADsome_core_data',
    'lib.dat': b'\xDE\xCA\xFB\xADsome_lib_data',
    'deep.dat': b'\xDE\xCA\xFB\xADsome_deep_data',
}
EXPECTED_DOCS = {
    'readme.txt': b'Hello World\n',
    'notes.md': b'Notes here\n',
}
EXPECTED_LOG_LINES = {
    '[SUCCESS] Moved core.dat to /home/user/organized/modules',
    '[SUCCESS] Moved lib.dat to /home/user/organized/modules',
    '[SUCCESS] Moved deep.dat to /home/user/organized/modules',
    '[SUCCESS] Moved readme.txt to /home/user/organized/docs',
    '[SUCCESS] Moved notes.md to /home/user/organized/docs',
}


def test_organized_directories_exist():
    assert MODULES.is_dir(), f'Directory missing: {MODULES}'
    assert DOCS.is_dir(), f'Directory missing: {DOCS}'


def test_organized_modules_contents():
    assert MODULES.is_dir(), f'Directory missing: {MODULES}'
    files = set(os.listdir(MODULES))
    expected = set(EXPECTED_MODULES)
    assert files == expected, f'Expected {expected} in {MODULES}, but found {files}'
    for name, expected_data in EXPECTED_MODULES.items():
        path = MODULES / name
        assert path.is_file(), f'Not a regular file: {path}'
        assert path.read_bytes() == expected_data, f'Incorrect contents in {path}'


def test_organized_docs_contents():
    assert DOCS.is_dir(), f'Directory missing: {DOCS}'
    files = set(os.listdir(DOCS))
    expected = set(EXPECTED_DOCS)
    assert files == expected, f'Expected {expected} in {DOCS}, but found {files}'
    for name, expected_data in EXPECTED_DOCS.items():
        path = DOCS / name
        assert path.is_file(), f'Not a regular file: {path}'
        assert path.read_bytes() == expected_data, f'Incorrect contents in {path}'


def test_raw_files_extraction_state():
    assert RAW.is_dir(), f'Directory missing: {RAW}'
    regular_files = [p for p in RAW.rglob('*') if p.is_file()]
    relative = {str(p.relative_to(RAW)) for p in regular_files}
    assert len(regular_files) == 1, f'Unexpected files remain in raw_files: {relative}'
    remaining = regular_files[0]
    assert remaining.name == 'ignore_me.bin', f'Expected only ignore_me.bin, found {relative}'
    assert remaining.read_bytes() == b'\x00\x01\x02\x03ignore_this'
    assert not any(p.suffix.lower() in {'.zip', '.tar', '.gz'} for p in regular_files), \
        f'Nested archive files were left behind: {relative}'


def test_sort_log_contents():
    log_file = HOME / 'sort.log'
    assert log_file.is_file(), f'Log file missing: {log_file}'
    with log_file.open('r') as f:
        log_lines = {line.strip() for line in f if line.strip()}
    assert log_lines == EXPECTED_LOG_LINES, \
        f'Log file contents do not match expected output. Found: {log_lines}'


def test_cpp_files_exist():
    cpp_file = HOME / 'sorter.cpp'
    executable = HOME / 'sorter'
    assert cpp_file.is_file(), f'C++ source file missing: {cpp_file}'
    assert executable.is_file(), f'Executable missing: {executable}'
    assert os.access(executable, os.X_OK), f'File is not executable: {executable}'


def test_sorter_source_and_executable_behavior():
    cpp_file = HOME / 'sorter.cpp'
    executable = HOME / 'sorter'
    token = uuid.uuid4().hex
    work = Path(tempfile.mkdtemp(prefix='sorter_verify_'))
    saved_raw = work / 'saved_raw'
    saved_organized = work / 'saved_organized'
    saved_rules = (HOME / 'rules.ini').read_bytes()
    had_raw = RAW.exists()
    had_organized = (HOME / 'organized').exists()

    if had_raw:
        shutil.copytree(RAW, saved_raw)
    if had_organized:
        shutil.copytree(HOME / 'organized', saved_organized)

    compiled = work / 'compiled_sorter'
    compile_result = subprocess.run(
        ['g++', '-std=c++17', '-O2', str(cpp_file), '-o', str(compiled)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert compile_result.returncode == 0, \
        f'sorter.cpp does not compile as C++17:\n{compile_result.stderr}'

    module_name = f'module_{token}.bin'
    text_name = f'text_{token}.txt'
    ignored_name = f'ignored_{token}.dat'
    module_data = b'\xDE\xCA\xFB\xAD' + os.urandom(23)
    text_data = b'Printable\nX' + b'\x00after-the-first-ten'
    ignored_data = b'ABC\x00EFGHIJ' + os.urandom(13)

    def exercise(program, label):
        case_root = HOME / f'.sorter_verifier_{token}_{label}'
        module_dest = case_root / 'modules'
        text_dest = case_root / 'docs'

        if RAW.exists():
            shutil.rmtree(RAW)
        (RAW / 'one/two').mkdir(parents=True)
        (RAW / 'other').mkdir(parents=True)
        (RAW / 'one/two' / module_name).write_bytes(module_data)
        (RAW / 'other' / text_name).write_bytes(text_data)
        (RAW / ignored_name).write_bytes(ignored_data)
        (HOME / 'rules.ini').write_text(
            f'MODULE_DIR={module_dest}\nTEXT_DIR={text_dest}\n'
        )

        result = subprocess.run(
            [str(program)], cwd=str(HOME), stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, timeout=15
        )
        assert result.returncode == 0, \
            f'{program} failed with stderr:\n{result.stderr}'

        assert module_dest.is_dir(), 'MODULE_DIR destination was not created'
        assert text_dest.is_dir(), 'TEXT_DIR destination was not created'
        assert set(os.listdir(module_dest)) == {module_name}
        assert set(os.listdir(text_dest)) == {text_name}
        assert (module_dest / module_name).read_bytes() == module_data
        assert (text_dest / text_name).read_bytes() == text_data
        assert not (RAW / 'one/two' / module_name).exists()
        assert not (RAW / 'other' / text_name).exists()
        assert (RAW / ignored_name).read_bytes() == ignored_data

        lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
        expected = {
            f'[SUCCESS] Moved {module_name} to {module_dest}',
            f'[SUCCESS] Moved {text_name} to {text_dest}',
        }
        assert len(lines) == 2 and set(lines) == expected, \
            f'Unexpected sorter output: {lines}'
        shutil.rmtree(case_root)

    try:
        exercise(executable, 'installed')
        exercise(compiled, 'compiled')
    finally:
        if RAW.exists():
            shutil.rmtree(RAW)
        if had_raw:
            shutil.copytree(saved_raw, RAW)
        organized = HOME / 'organized'
        if organized.exists():
            shutil.rmtree(organized)
        if had_organized:
            shutil.copytree(saved_organized, organized)
        (HOME / 'rules.ini').write_bytes(saved_rules)
        for path in HOME.glob(f'.sorter_verifier_{token}_*'):
            if path.is_dir():
                shutil.rmtree(path)
        shutil.rmtree(work, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
