#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import hashlib
import os
import re
import shutil
import struct
import subprocess

FINAL_DOC_PATH = '/home/user/final_doc.md'
DRAFT_PATH = '/home/user/draft.md'
SOURCE_PATH = '/home/user/doc_builder.cpp'
BUILDER_PATH = '/home/user/doc_builder'
ASSETS_DIR = '/home/user/assets'
ELF_PATH = '/home/user/assets/firmware.elf'


def get_elf_entry_point(filepath):
    with open(filepath, 'rb') as f:
        e_ident = f.read(16)
        if e_ident[:4] != b'\x7fELF':
            raise ValueError('Not an ELF file')
        is_64_bit = e_ident[4] == 2
        endianness = '<' if e_ident[5] == 1 else '>'
        f.seek(24)
        if is_64_bit:
            return hex(struct.unpack(endianness + 'Q', f.read(8))[0])
        return hex(struct.unpack(endianness + 'I', f.read(4))[0])


def get_sha256sums():
    sums = []
    for filepath in sorted(glob.glob(os.path.join(ASSETS_DIR, '*'))):
        if os.path.isfile(filepath):
            with open(filepath, 'rb') as f:
                digest = hashlib.sha256(f.read()).hexdigest()
            sums.append(f'{digest}  {filepath}')
    return sums


def gcode_stats(filepath):
    maxima = {'X': float('-inf'), 'Y': float('-inf'), 'Z': float('-inf')}
    number = r'[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?'
    with open(filepath, 'r') as f:
        for line in f:
            if not (line.startswith('G0') or line.startswith('G1')):
                continue
            for axis, value in re.findall(r'([XYZ])(' + number + r')', line):
                maxima[axis] = max(maxima[axis], float(value))
    return f"Max X: {maxima['X']:.1f}, Max Y: {maxima['Y']:.1f}, Max Z: {maxima['Z']:.1f}"


def reference_transform(text):
    def replace_gcode(match):
        return gcode_stats(os.path.join('/home/user', match.group(1)))

    def replace_elf(match):
        path = os.path.join('/home/user', match.group(1))
        return f'Entry Point: {get_elf_entry_point(path)}'

    text = re.sub(r'\{\{GCODE_STATS:([^}]+)\}\}', replace_gcode, text)
    return re.sub(r'\{\{ELF_ENTRY:([^}]+)\}\}', replace_elf, text)


def test_final_doc_exists():
    assert os.path.isfile(FINAL_DOC_PATH), f'The file {FINAL_DOC_PATH} does not exist.'


def test_required_program_artifacts_exist():
    assert os.path.isfile(SOURCE_PATH), f'The source file {SOURCE_PATH} does not exist.'
    assert os.path.getsize(SOURCE_PATH) > 0, 'doc_builder.cpp is empty.'
    assert os.path.isfile(BUILDER_PATH), f'The compiled executable {BUILDER_PATH} does not exist.'
    assert os.access(BUILDER_PATH, os.X_OK), 'doc_builder is not executable.'
    with open(BUILDER_PATH, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'doc_builder is not a compiled ELF executable.'


def test_gcode_stats_replaced():
    with open(FINAL_DOC_PATH, 'r') as f:
        content = f.read()
    expected_str = 'Max X: 120.5, Max Y: 110.0, Max Z: 15.0'
    assert expected_str in content, f"Expected GCode stats '{expected_str}' not found in final_doc.md."
    assert '{{GCODE_STATS' not in content, 'GCODE_STATS placeholder was not removed.'


def test_elf_entry_replaced():
    expected_str = f'Entry Point: {get_elf_entry_point(ELF_PATH)}'
    with open(FINAL_DOC_PATH, 'r') as f:
        content = f.read()
    assert expected_str in content, f"Expected ELF entry point '{expected_str}' not found in final_doc.md."
    assert '{{ELF_ENTRY' not in content, 'ELF_ENTRY placeholder was not removed.'


def test_manifest_appended():
    with open(FINAL_DOC_PATH, 'r') as f:
        content = f.read()
    assert '## Manifest' in content, "Manifest header '## Manifest' not found in final_doc.md."
    expected_sums = get_sha256sums()
    for checksum in expected_sums:
        assert checksum in content, f"Expected checksum line '{checksum}' not found in the manifest section of final_doc.md."

    with open(DRAFT_PATH, 'r') as f:
        expected_body = reference_transform(f.read())
    expected_manifest = '\n'.join(expected_sums) + ('\n' if expected_sums else '')
    expected_document = expected_body + '\n## Manifest\n' + expected_manifest
    assert content == expected_document, 'final_doc.md does not exactly preserve and transform the draft followed by the required manifest.'


def test_builder_executes_and_handles_derived_inputs():
    test_gcode = '/home/user/verifier_dynamic.gcode'
    test_elf = '/home/user/verifier_dynamic.elf'
    original_draft = open(DRAFT_PATH, 'rb').read()
    original_final = open(FINAL_DOC_PATH, 'rb').read()

    try:
        with open(test_gcode, 'w') as f:
            f.write('G21 ; ignored\n')
            f.write('G1 X1.0 Y101.0 Z2.0\n')
            f.write('G0 X42.5 Y-3.0 Z7.5\n')
            f.write('G1 X8.0 Y9.0 Z4.0\n')

        shutil.copyfile(ELF_PATH, test_elf)
        with open(test_elf, 'r+b') as f:
            ident = f.read(16)
            assert ident[:4] == b'\x7fELF' and ident[4] == 2
            endian = '<' if ident[5] == 1 else '>'
            f.seek(24)
            f.write(struct.pack(endian + 'Q', 0x1234ABCDE))

        dynamic_draft = (
            '# Dynamic verification\n\n'
            'Keep this prose unchanged.\n'
            'Stats A: {{GCODE_STATS:verifier_dynamic.gcode}}\n'
            'Firmware: {{ELF_ENTRY:verifier_dynamic.elf}}\n'
            'Stats B: {{GCODE_STATS:verifier_dynamic.gcode}}\n'
            'Tail text.\n'
        )
        with open(DRAFT_PATH, 'w') as f:
            f.write(dynamic_draft)
        if os.path.exists(FINAL_DOC_PATH):
            os.remove(FINAL_DOC_PATH)

        result = subprocess.run(
            [BUILDER_PATH], cwd='/home/user', stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=15
        )
        assert result.returncode == 0, f'doc_builder failed when executed: {result.stderr.decode(errors="replace")}'
        assert os.path.isfile(FINAL_DOC_PATH), 'Executing doc_builder did not create final_doc.md.'

        with open(FINAL_DOC_PATH, 'r') as f:
            actual = f.read()
        expected = reference_transform(dynamic_draft)
        assert actual == expected, 'Executing doc_builder did not correctly transform independently generated placeholders while preserving the draft.'
        assert '{{GCODE_STATS' not in actual and '{{ELF_ENTRY' not in actual
    finally:
        with open(DRAFT_PATH, 'wb') as f:
            f.write(original_draft)
        with open(FINAL_DOC_PATH, 'wb') as f:
            f.write(original_final)
        for path in (test_gcode, test_elf):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
