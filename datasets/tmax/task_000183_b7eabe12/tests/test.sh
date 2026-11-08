#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
from pathlib import Path

import pytest

SCRIPT_PATH = "/home/user/process_configs.sh"
CLEAN_CORPUS = "/app/corpus/clean"
EVIL_CORPUS = "/app/corpus/evil"


def get_device_type(filepath):
    with open(filepath, 'rb') as f:
        content = f.read()

    # Skip 16 byte header
    text_content = content[16:].decode('utf-8', errors='ignore')
    for line in text_content.splitlines():
        if line.startswith("DeviceType: "):
            return line.split("DeviceType: ")[1].strip()
    return None


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"
    result = subprocess.run(["bash", "-n", SCRIPT_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"Script has invalid Bash syntax: {result.stderr}"


def test_clean_corpus_processed_correctly():
    with tempfile.TemporaryDirectory() as out_dir:
        result = subprocess.run(["bash", SCRIPT_PATH, CLEAN_CORPUS, out_dir], capture_output=True, text=True)
        assert result.returncode == 0, f"Script failed on clean corpus. stderr: {result.stderr}"

        clean_files = os.listdir(CLEAN_CORPUS)
        missing = []
        wrong_group = []

        for fname in clean_files:
            src_path = os.path.join(CLEAN_CORPUS, fname)
            device_type = get_device_type(src_path)
            if not device_type:
                continue

            expected_out_path = os.path.join(out_dir, device_type, fname)
            if not os.path.exists(expected_out_path):
                found = False
                for root, dirs, files in os.walk(out_dir):
                    if fname in files:
                        wrong_group.append(fname)
                        found = True
                        break
                if not found:
                    missing.append(fname)

        assert not missing, f"{len(missing)} of {len(clean_files)} clean files missing from output. Offending files: {missing[:5]}"
        assert not wrong_group, f"{len(wrong_group)} of {len(clean_files)} clean files placed in wrong subdirectory. Offending files: {wrong_group[:5]}"


def test_evil_corpus_rejected():
    with tempfile.TemporaryDirectory() as out_dir:
        subprocess.run(["bash", SCRIPT_PATH, EVIL_CORPUS, out_dir], capture_output=True, text=True)

        evil_files = os.listdir(EVIL_CORPUS)
        bypassed = []

        for root, dirs, files in os.walk(out_dir):
            for fname in files:
                bypassed.append(fname)

        assert not bypassed, f"{len(bypassed)} of {len(evil_files)} evil configurations bypassed validation. Offending files: {bypassed[:5]}"


def unquoted_shell_text(source):
    """Remove quoted text and shell comments before checking control operators."""
    result = []
    quote = None
    escaped = False
    line_start = True
    previous_space = True

    for ch in source:
        if ch == '\n':
            result.append(ch)
            quote = None if quote is None else quote
            escaped = False
            line_start = True
            previous_space = True
            continue

        if quote is not None:
            if quote == '"' and escaped:
                escaped = False
            elif quote == '"' and ch == '\\':
                escaped = True
            elif ch == quote:
                quote = None
            result.append(' ')
            continue

        if ch in ("'", '"'):
            quote = ch
            result.append(' ')
            line_start = False
            previous_space = False
            continue

        if ch == '#' and (line_start or previous_space):
            result.append(' ')
            # Consume the rest of this source line as spaces.
            continue

        # If already inside an unquoted comment, detect it from the current line.
        current_line = ''.join(result).rsplit('\n', 1)[-1]
        if current_line.rstrip().endswith('#'):
            result.append(' ')
            continue

        result.append(ch)
        line_start = False
        previous_space = ch.isspace()

    return ''.join(result).replace('\\\n', ' ')


def test_script_contains_parallel_processing():
    source = Path(SCRIPT_PATH).read_text(errors='replace')
    code = unquoted_shell_text(source)

    uses_xargs_parallel = bool(re.search(r'\bxargs\b[^\n]*\s-P(?:\s|[0-9])', code))
    uses_parallel_command = bool(re.search(r'(^|[;|&()\s])parallel(?:\s|$)', code, re.MULTILINE))
    uses_background_jobs = bool(re.search(r'(?<!&)&(?!&)', code) and re.search(r'(^|[;\s])wait(?:\s|$)', code, re.MULTILINE))
    uses_coproc = bool(re.search(r'(^|[;\s])coproc(?:\s|$)', code, re.MULTILINE))

    assert uses_xargs_parallel or uses_parallel_command or uses_background_jobs or uses_coproc, (
        "The script does not implement the required parallel processing with xargs -P, "
        "parallel, Bash background jobs plus wait, or coproc"
    )


def oracle_result(data):
    if len(data) < 16 or data[:6] != b"CFG!\x02\x00":
        return None
    try:
        lines = data[16:].decode('utf-8').splitlines()
    except UnicodeDecodeError:
        return None

    hostnames = [line for line in lines if re.fullmatch(r'hostname [A-Za-z0-9-]+', line)]
    if len(hostnames) != 1:
        return None
    if any('password 7 ' in line for line in lines):
        return None

    device_types = []
    for line in lines:
        match = re.fullmatch(r'DeviceType: (.+)', line)
        if match:
            device_types.append(match.group(1).strip())
    if not device_types or not device_types[0]:
        return None
    return device_types[0]


def make_config(lines, valid_signature=True):
    header = bytearray(b"CFG!\x02\x00" + secrets.token_bytes(10))
    if not valid_signature:
        header[secrets.randbelow(6)] ^= 0x55
    return bytes(header) + ('\n'.join(lines) + '\n').encode()


def test_randomized_mixed_corpus_exact_outputs_and_safe_filenames():
    token = secrets.token_hex(8)
    with tempfile.TemporaryDirectory() as input_dir, tempfile.TemporaryDirectory() as out_dir:
        input_path = Path(input_dir)
        source_bytes = {}

        unusual_names = [
            f"space name {token}.conf",
            f"--leading-dash-{token}.conf",
            f"semi;colon-{token}.conf",
            f"glob*[x]-{token}.conf",
            f"quote'and\"-{token}.conf",
            f"dollar$-{token}.conf",
        ]
        types = [f"core-{token}", f"edge-{token}", f"switch-{token}", f"access-{token}"]

        for index in range(72):
            name = unusual_names[index] if index < len(unusual_names) else f"random-{token}-{index}-{secrets.token_hex(3)}.conf"
            hostname = f"node-{index}-{secrets.token_hex(3)}"
            data = make_config([
                f"hostname {hostname}",
                f"interface description random-{secrets.token_hex(4)}",
                f"DeviceType: {types[index % len(types)]}",
            ])
            (input_path / name).write_bytes(data)
            source_bytes[name] = data

        invalid_cases = [
            make_config([f"hostname badsig-{token}", f"DeviceType: {types[0]}"], valid_signature=False),
            make_config([f"DeviceType: {types[0]}"]),
            make_config([f"hostname first-{token}", f"hostname second-{token}", f"DeviceType: {types[0]}"]),
            make_config([f"hostname bad_name_{token}", f"DeviceType: {types[0]}"]),
            make_config([f"hostname extra-{token} trailing", f"DeviceType: {types[0]}"]),
            make_config([f"hostname weak-{token}", "password 7 secret", f"DeviceType: {types[0]}"]),
            make_config([f"hostname no-device-{token}"]),
            make_config([f" hostname indented-{token}", f"DeviceType: {types[0]}"]),
        ]
        for index, data in enumerate(invalid_cases):
            name = f"invalid-{token}-{index}-{secrets.token_hex(3)}.conf"
            (input_path / name).write_bytes(data)
            source_bytes[name] = data

        expected = {}
        for name, data in source_bytes.items():
            device_type = oracle_result(data)
            if device_type is not None:
                expected[os.path.join(device_type, name)] = data

        result = subprocess.run(
            ["bash", SCRIPT_PATH, input_dir, out_dir],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"Script failed on randomized corpus. stderr: {result.stderr}"

        actual = {}
        actual_dirs = set()
        for root, dirs, files in os.walk(out_dir):
            rel_root = os.path.relpath(root, out_dir)
            for dirname in dirs:
                rel_dir = dirname if rel_root == '.' else os.path.join(rel_root, dirname)
                actual_dirs.add(rel_dir)
            for filename in files:
                full_path = os.path.join(root, filename)
                rel_path = filename if rel_root == '.' else os.path.join(rel_root, filename)
                assert os.path.isfile(full_path) and not os.path.islink(full_path), f"Output is not a regular copied file: {rel_path!r}"
                actual[rel_path] = Path(full_path).read_bytes()

        assert set(actual) == set(expected), (
            f"Output set mismatch. Missing: {sorted(set(expected) - set(actual))[:8]!r}; "
            f"unexpected: {sorted(set(actual) - set(expected))[:8]!r}"
        )
        assert actual == expected, "One or more copied configurations differ from their input bytes"

        expected_dirs = {os.path.dirname(path) for path in expected}
        assert actual_dirs == expected_dirs, f"Unexpected or missing output directories: {actual_dirs ^ expected_dirs!r}"

        for name, original in source_bytes.items():
            assert (input_path / name).read_bytes() == original, f"Input file was modified: {name!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
