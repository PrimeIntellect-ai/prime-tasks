#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import struct
import subprocess
from pathlib import Path

PROJECT = Path('/home/user/artifact_manager')
BUNDLE = Path('/home/user/artifacts/bundle.bin')
EXTRACTED = Path('/home/user/extracted')
REPORT = Path('/home/user/report.json')
LOG = Path('/home/user/extraction.log')


def make_elf(entry):
    header = bytearray(b'\x7fELF\x02\x01\x01\x00' + b'\x00' * 8)
    header += struct.pack(
        '<HHIQQQIHHHHHH',
        2, 62, 1, entry, 0x40, 0, 0, 64, 56, 1, 64, 0, 0
    )
    return bytes(header) + b'\x00' * 100


def write_archive(entries):
    BUNDLE.parent.mkdir(parents=True, exist_ok=True)
    with BUNDLE.open('wb') as f:
        f.write(b'ARTF')
        f.write(struct.pack('<I', len(entries)))
        for path, data in entries:
            encoded_path = path.encode('utf-8')
            f.write(struct.pack('<H', len(encoded_path)))
            f.write(encoded_path)
            f.write(struct.pack('<I', len(data)))
            f.write(data)


def remove_path(path):
    path = Path(path)
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path)


def reset_outputs(escape_paths):
    if EXTRACTED.is_symlink() or EXTRACTED.is_file():
        EXTRACTED.unlink()
    elif EXTRACTED.is_dir():
        shutil.rmtree(EXTRACTED)
    EXTRACTED.mkdir(parents=True)

    for path in (REPORT, LOG):
        if path.is_symlink() or path.exists():
            remove_path(path)
    for path in escape_paths:
        if os.path.lexists(path):
            remove_path(path)


def run_tool():
    env = os.environ.copy()
    env['HOME'] = '/home/user'
    cargo_home = Path('/home/user/.cargo')
    if cargo_home.exists():
        env['CARGO_HOME'] = str(cargo_home)
    result = subprocess.run(
        ['cargo', 'run', '--quiet', '--manifest-path', str(PROJECT / 'Cargo.toml')],
        cwd=str(PROJECT), env=env, text=True, capture_output=True, timeout=180
    )
    assert result.returncode == 0, (
        f'Rust tool failed with exit code {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def read_report():
    assert REPORT.is_file(), f'Report file {REPORT} does not exist.'
    try:
        with REPORT.open('r', encoding='utf-8') as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        raise AssertionError(f'Failed to parse {REPORT} as JSON: {e}')


def read_log_lines():
    assert LOG.is_file(), f'Log file {LOG} does not exist.'
    with LOG.open('r', encoding='utf-8') as f:
        content = f.read().strip()
    return content, [line for line in content.split('\n') if line.strip()]


def test_project_and_archive_ingestion_behavior():
    # The requested artifact must be a Rust binary project and must actually run.
    assert PROJECT.is_dir(), f'Rust project {PROJECT} does not exist.'
    assert (PROJECT / 'Cargo.toml').is_file(), 'Cargo.toml does not exist.'
    assert (PROJECT / 'src' / 'main.rs').is_file(), 'src/main.rs does not exist.'

    # Recreate and process the task's original archive rather than trusting stale outputs.
    original_elf = make_elf(0x401000)
    original_metadata_text = 'Version: 1.2.4\nAuthor: SecOps'
    original_metadata_utf16 = original_metadata_text.encode('utf-16le')
    write_archive([
        ('bin/app.elf', original_elf),
        ('../../../escape.sh', b"echo 'You have been hacked'"),
        ('metadata.txt', original_metadata_utf16),
    ])
    reset_outputs(['/home/user/escape.sh', '/escape.sh'])
    run_tool()

    content, lines = read_log_lines()
    expected_line = 'MALICIOUS: ../../../escape.sh'
    assert expected_line in content, f"Expected '{expected_line}' in {LOG}, but got: {content}"
    assert len(lines) == 1, f'Expected exactly 1 malicious file logged, but found {len(lines)}.'

    report = read_report()
    assert 'extracted_files' in report, "Missing 'extracted_files' in report.json"
    extracted_files = set(report['extracted_files'])
    assert 'bin/app.elf' in extracted_files, 'bin/app.elf missing from extracted_files'
    assert 'metadata.txt' in extracted_files, 'metadata.txt missing from extracted_files'
    assert len(extracted_files) == 2, f'Expected 2 extracted files in report, got {len(extracted_files)}'
    assert report.get('malicious_files_prevented') == 1, 'Expected malicious_files_prevented to be 1'
    assert 'elf_entry_points' in report, "Missing 'elf_entry_points' in report.json"
    assert report['elf_entry_points'].get('bin/app.elf') == '0x401000', 'Incorrect or missing ELF entry point for bin/app.elf'
    assert report.get('metadata_text') == original_metadata_text, 'Incorrect metadata_text in report.json'

    app_path = EXTRACTED / 'bin/app.elf'
    metadata_path = EXTRACTED / 'metadata.txt'
    assert app_path.is_file(), f'Extracted file {app_path} does not exist.'
    assert metadata_path.is_file(), f'Extracted file {metadata_path} does not exist.'
    assert app_path.read_bytes() == original_elf, 'Extracted ELF contents differ from the archive.'
    assert metadata_path.read_bytes() == original_metadata_text.encode('utf-8'), 'metadata.txt was not converted to UTF-8.'
    assert not os.path.exists('/home/user/escape.sh'), 'Malicious file was extracted to /home/user/escape.sh'
    assert not os.path.exists('/escape.sh'), 'Malicious file was extracted to /escape.sh'

    # Exercise the implementation on unpredictable names, data, entry point, and two
    # traversal forms so a fixed report/output cannot pass.
    token = secrets.token_hex(8)
    entry_point = 0x400000 + secrets.randbelow(0x0fffff)
    elf_rel = f'bin/{token}.elf'
    data_rel = f'docs/{token}.dat'
    data_bytes = secrets.token_bytes(73)
    metadata_text = f'Build: {token}\nOwner: Repository Team'
    traversal_path = f'../../../tmp/traversal-{token}.sh'
    absolute_path = f'/tmp/absolute-{token}.sh'
    traversal_target = f'/tmp/traversal-{token}.sh'
    absolute_target = absolute_path
    dynamic_elf = make_elf(entry_point)

    write_archive([
        (elf_rel, dynamic_elf),
        (data_rel, data_bytes),
        ('metadata.txt', metadata_text.encode('utf-16le')),
        (traversal_path, b'traversal payload'),
        (absolute_path, b'absolute payload'),
    ])
    reset_outputs([traversal_target, absolute_target])
    run_tool()

    dynamic_report = read_report()
    assert set(dynamic_report.get('extracted_files', [])) == {elf_rel, data_rel, 'metadata.txt'}
    assert len(dynamic_report.get('extracted_files', [])) == 3
    assert dynamic_report.get('malicious_files_prevented') == 2
    assert dynamic_report.get('elf_entry_points', {}).get(elf_rel) == hex(entry_point)
    assert dynamic_report.get('metadata_text') == metadata_text

    assert (EXTRACTED / elf_rel).read_bytes() == dynamic_elf
    assert (EXTRACTED / data_rel).read_bytes() == data_bytes
    assert (EXTRACTED / 'metadata.txt').read_bytes() == metadata_text.encode('utf-8')

    _, dynamic_lines = read_log_lines()
    assert dynamic_lines == [
        f'MALICIOUS: {traversal_path}',
        f'MALICIOUS: {absolute_path}',
    ]
    assert not os.path.exists(traversal_target), f'Malicious file was extracted to {traversal_target}'
    assert not os.path.exists(absolute_target), f'Malicious file was extracted to {absolute_target}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
