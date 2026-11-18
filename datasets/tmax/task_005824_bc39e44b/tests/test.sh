#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import hashlib
import secrets
import subprocess
from pathlib import Path
import pytest


def get_expected_json(csv_path: str) -> str:
    """Reads the original UTF-16LE CSV and computes the expected minified JSON string."""
    with open(csv_path, 'rb') as f:
        content = f.read().decode('utf-16le')

    lines = [line.strip() for line in content.splitlines() if line.strip()]
    if not lines:
        return "[]"

    data = []
    for line in lines[1:]:
        parts = line.split(',', 2)
        if len(parts) == 3:
            data.append({
                "t": int(parts[0]),
                "s": parts[1],
                "m": parts[2]
            })

    return json.dumps(data, separators=(',', ':'))


def read_rle(rle_path: str) -> str:
    with open(rle_path, 'rb') as f:
        rle_data = f.read()

    assert len(rle_data) > 0, f"{rle_path} is empty."
    assert len(rle_data) % 2 == 0, f"{rle_path} length is not even; invalid strict RLE format."

    decompressed = bytearray()
    for i in range(0, len(rle_data), 2):
        count = rle_data[i]
        char = rle_data[i + 1]
        assert 1 <= count <= 255, f"Invalid RLE count {count} at byte {i} in {rle_path}."
        decompressed.extend(bytes([char]) * count)

    try:
        return decompressed.decode('utf-8')
    except UnicodeDecodeError:
        pytest.fail(f"Decompressed data from {rle_path} is not valid UTF-8.")


def test_rle_files_exist_and_correct():
    """Test that the RLE compressed files exist, follow strict RLE rules, and decompress to the correct JSON."""
    for log_name in ["log1", "log2"]:
        rle_path = f"/home/user/archive/{log_name}.json.rle"
        assert os.path.isfile(rle_path), f"Expected compressed file {rle_path} is missing."
        decompressed_str = read_rle(rle_path)
        csv_path = f"/home/user/legacy_logs/{log_name}.csv"
        expected_json = get_expected_json(csv_path)
        assert decompressed_str == expected_json, f"Decompressed content of {rle_path} does not match the expected JSON."


def test_checksums_file():
    """Test that checksums.txt exists and contains the correct SHA-256 hashes for the decompressed JSON."""
    checksums_path = "/home/user/checksums.txt"
    assert os.path.isfile(checksums_path), f"{checksums_path} is missing."

    with open(checksums_path, 'r', encoding='utf-8') as f:
        content = f.read()

    for log_name in ["log1", "log2"]:
        csv_path = f"/home/user/legacy_logs/{log_name}.csv"
        expected_json = get_expected_json(csv_path)
        expected_hash = hashlib.sha256(expected_json.encode('utf-8')).hexdigest()
        expected_line = f"{expected_hash}  {log_name}.json"
        assert expected_line in content, f"Expected checksum line '{expected_line}' not found in {checksums_path}."


def compile_cpp_utilities():
    roots = [Path('/home/user'), Path('/root'), Path('/tmp')]
    sources = []
    for root in roots:
        if not root.exists():
            continue
        for pattern in ('*.cpp', '*.cc', '*.cxx'):
            sources.extend(root.rglob(pattern))

    sources = sorted({p.resolve() for p in sources if '/tmp/verifier_cpp_bins/' not in str(p)})
    assert sources, "No C++ source file implementing the requested utility was found."

    build_dir = Path('/tmp/verifier_cpp_bins')
    build_dir.mkdir(parents=True, exist_ok=True)
    binaries = []
    attempts = []

    # Support both single-file programs and programs split into source files in one directory.
    source_groups = [[p] for p in sources]
    by_parent = {}
    for source in sources:
        by_parent.setdefault(source.parent, []).append(source)
    source_groups.extend(group for group in by_parent.values() if len(group) > 1)

    seen_groups = set()
    for index, group in enumerate(source_groups):
        key = tuple(sorted(str(p) for p in group))
        if key in seen_groups:
            continue
        seen_groups.add(key)
        output = build_dir / f'utility_{index}'
        command = ['g++', '-std=c++17', '-O2', *[str(p) for p in group], '-o', str(output), '-lssl', '-lcrypto']
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=90)
        attempts.append(result.stderr)
        if result.returncode == 0 and output.is_file():
            binaries.append((output, group[0].parent))

    assert binaries, "The submitted C++ source could not be compiled.\n" + '\n'.join(attempts[-3:])
    return binaries


def outputs_are_correct(log_names):
    checksums_path = Path('/home/user/checksums.txt')
    if not checksums_path.is_file():
        return False
    try:
        checksum_content = checksums_path.read_text(encoding='utf-8')
        for log_name in log_names:
            csv_path = f"/home/user/legacy_logs/{log_name}.csv"
            expected_json = get_expected_json(csv_path)
            rle_path = f"/home/user/archive/{log_name}.json.rle"
            if not os.path.isfile(rle_path) or read_rle(rle_path) != expected_json:
                return False
            expected_hash = hashlib.sha256(expected_json.encode('utf-8')).hexdigest()
            if f"{expected_hash}  {log_name}.json" not in checksum_content:
                return False
    except (OSError, AssertionError, UnicodeError, ValueError):
        return False
    return True


def test_compiled_cpp_processes_new_csv_files():
    binaries = compile_cpp_utilities()

    challenge_name = 'audit_' + secrets.token_hex(8)
    timestamp = 1700000000 + secrets.randbelow(10000000)
    message = secrets.token_hex(12) + ('A' * 300) + secrets.token_hex(12)
    csv_text = (
        'Timestamp,Severity,Message\n'
        f'{timestamp},INFO,{message}\n'
    )
    challenge_path = Path(f'/home/user/legacy_logs/{challenge_name}.csv')
    challenge_path.write_bytes(csv_text.encode('utf-16le'))

    archive = Path('/home/user/archive')
    archive.mkdir(parents=True, exist_ok=True)
    for old_output in archive.glob('*.json.rle'):
        old_output.unlink()
    checksums = Path('/home/user/checksums.txt')
    if checksums.exists():
        checksums.unlink()

    expected_names = ['log1', 'log2', challenge_name]

    # Run only freshly compiled submissions. Multiple passes permit a legitimate
    # separate compressor and decompressor/checksum program to cooperate.
    for _ in range(2):
        for binary, cwd in binaries:
            try:
                subprocess.run([str(binary)], cwd=str(cwd), stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, timeout=30)
            except (subprocess.TimeoutExpired, OSError):
                continue
            if outputs_are_correct(expected_names):
                return

    assert outputs_are_correct(expected_names), (
        "Freshly compiled C++ source did not process every CSV file, including "
        "a verifier-generated input, into correct RLE and checksum outputs."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
