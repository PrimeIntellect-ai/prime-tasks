#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_task.py
import os
import secrets
import shutil
import stat
import subprocess
from pathlib import Path

HOME = Path('/home/user')
PROJECT = HOME / 'project_root'
ORGANIZED = HOME / 'organized'
REPORT = HOME / 'report.log'
SOURCE = HOME / 'sorter.cpp'
SORTER = HOME / 'sorter'


def regular_file(path):
    path = Path(path)
    assert path.exists(), f'The file {path} does not exist.'
    assert stat.S_ISREG(path.lstat().st_mode), f'The path {path} is not a regular file.'


def check_original_final_state():
    expected_lines = [
        '[ELF] /home/user/project_root/assets/binary.txt',
        '[PNG] /home/user/project_root/assets/image.dat',
        '[ZIP] /home/user/project_root/docs/archive.bak',
    ]

    regular_file(REPORT)
    with REPORT.open('r') as f:
        lines = [line.strip() for line in f if line.strip()]
    assert lines == expected_lines, f'The contents of {REPORT} do not match the expected output. Got: {lines}'

    expected_originals = {
        PROJECT / 'assets/image.dat': bytes.fromhex('89504e470d0a1a0a0000000d49484452'),
        PROJECT / 'assets/binary.txt': bytes.fromhex('7f454c46020101' + '00' * 9),
        PROJECT / 'docs/archive.bak': bytes.fromhex('504b0304140000000800'),
        PROJECT / 'docs/readme.md': b'Hello World' + bytes([10]),
        PROJECT / 'short.bin': b'OK',
    }
    for path, expected in expected_originals.items():
        regular_file(path)
        actual = path.read_bytes()
        assert actual == expected, f'The original file {path} was not extracted intact.'

    expected_copies = {
        ORGANIZED / 'png/image.dat': expected_originals[PROJECT / 'assets/image.dat'],
        ORGANIZED / 'elf/binary.txt': expected_originals[PROJECT / 'assets/binary.txt'],
        ORGANIZED / 'zip/archive.bak': expected_originals[PROJECT / 'docs/archive.bak'],
    }
    for path, expected in expected_copies.items():
        regular_file(path)
        actual = path.read_bytes()
        assert actual[:4] == expected[:4], f'The file {path} does not have the correct magic bytes.'
        assert actual == expected, f'The file {path} is not a complete copy of its source.'

    regular_file(SOURCE)
    regular_file(SORTER)
    assert os.access(SORTER, os.X_OK), f'The file {SORTER} is not executable.'
    assert SORTER.read_bytes()[:4] == bytes.fromhex('7f454c46'), f'The file {SORTER} is not a compiled ELF executable.'


def compile_source():
    output = Path('/tmp/sorter_compiled_by_verifier')
    if output.exists():
        output.unlink()
    result = subprocess.run(
        ['g++', '-std=c++17', '-o', str(output), str(SOURCE)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, 'sorter.cpp did not compile with the required command:\n' + result.stderr.decode(errors='replace')
    regular_file(output)
    assert os.access(output, os.X_OK), 'The verifier-compiled sorter is not executable.'
    return output


def prepare_dynamic_tree():
    if PROJECT.exists() or PROJECT.is_symlink():
        if PROJECT.is_symlink() or PROJECT.is_file():
            PROJECT.unlink()
        else:
            shutil.rmtree(PROJECT)
    if ORGANIZED.exists() or ORGANIZED.is_symlink():
        if ORGANIZED.is_symlink() or ORGANIZED.is_file():
            ORGANIZED.unlink()
        else:
            shutil.rmtree(ORGANIZED)
    if REPORT.exists() or REPORT.is_symlink():
        REPORT.unlink()

    token = secrets.token_hex(8)
    files = {
        f'level_{token}/deeper/picture_{token}.odd': bytes.fromhex('89504e47') + os.urandom(67),
        f'program_{token}.data': bytes.fromhex('7f454c46') + os.urandom(91),
        f'level_{token}/bundle_{token}.hidden': bytes.fromhex('504b0304') + os.urandom(53),
        f'level_{token}/ordinary_{token}.png': b'NOTP' + os.urandom(35),
        f'level_{token}/deeper/tiny_{token}.bin': os.urandom(3),
        f'empty_{token}.zip': b'',
    }
    for relative, content in files.items():
        path = PROJECT / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
    return files


def exercise(executable):
    files = prepare_dynamic_tree()
    before = {relative: (PROJECT / relative).read_bytes() for relative in files}

    result = subprocess.run(
        [str(executable)],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, f'{executable} exited with status {result.returncode}: ' + result.stderr.decode(errors='replace')

    expected_outputs = {}
    expected_report = []
    types = {
        bytes.fromhex('89504e47'): ('png', 'PNG'),
        bytes.fromhex('7f454c46'): ('elf', 'ELF'),
        bytes.fromhex('504b0304'): ('zip', 'ZIP'),
    }
    for relative, content in files.items():
        if len(content) >= 4 and content[:4] in types:
            directory, label = types[content[:4]]
            expected_outputs[f'{directory}/{Path(relative).name}'] = content
            expected_report.append(f'[{label}] /home/user/project_root/{relative}')
    expected_report.sort(key=lambda line: line.split('] ', 1)[1])

    regular_file(REPORT)
    actual_report = REPORT.read_text().splitlines()
    assert actual_report == expected_report, f'{executable} produced an incorrect dynamically-derived report. Got: {actual_report}'

    assert ORGANIZED.is_dir() and not ORGANIZED.is_symlink(), 'The organized output directory was not created correctly.'
    actual_output_paths = {}
    for path in ORGANIZED.rglob('*'):
        if path.is_symlink():
            raise AssertionError(f'Output {path} is a symbolic link rather than a copied regular file.')
        if path.is_file():
            relative = path.relative_to(ORGANIZED).as_posix()
            actual_output_paths[relative] = path
    assert set(actual_output_paths) == set(expected_outputs), f'{executable} created the wrong organized files. Got: {sorted(actual_output_paths)}'
    for relative, expected_content in expected_outputs.items():
        path = actual_output_paths[relative]
        assert stat.S_ISREG(path.lstat().st_mode), f'Output {path} is not a regular file.'
        assert path.read_bytes() == expected_content, f'Output {path} is not a complete copy of its source.'

    for relative, expected_content in before.items():
        path = PROJECT / relative
        regular_file(path)
        assert path.read_bytes() == expected_content, f'The original file {path} was modified or replaced.'


def main():
    check_original_final_state()
    compiled = compile_source()
    exercise(SORTER)
    exercise(compiled)


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
