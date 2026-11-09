#!/bin/bash
mkdir -p /logs/verifier

run_checks() {
cat << 'TEST_EOF' > /tmp/test_final_state.py
import os


def test_gcode_files_processed():
    original_gcode = '/home/user/backup_source/machine_1/part.gcode'
    assert not os.path.exists(original_gcode), f"Original GCode file {original_gcode} should have been deleted."

    part1 = f"{original_gcode}.part001"
    part2 = f"{original_gcode}.part002"
    part3 = f"{original_gcode}.part003"

    assert os.path.isfile(part1), f"Chunk file {part1} is missing."
    assert os.path.isfile(part2), f"Chunk file {part2} is missing."
    assert os.path.isfile(part3), f"Chunk file {part3} is missing."

    assert os.path.getsize(part1) == 100, f"{part1} should be exactly 100 bytes."
    assert os.path.getsize(part2) == 100, f"{part2} should be exactly 100 bytes."
    assert os.path.getsize(part3) == 45, f"{part3} should be exactly 45 bytes."

    with open(part1, 'rb') as f1, open(part2, 'rb') as f2, open(part3, 'rb') as f3:
        content = f1.read() + f2.read() + f3.read()

    expected_block = "M104 S200 \xb0C \nG28 \nG1 X10 Y10\nM109 S200 \nG1 Z0.2\n".encode('utf-8')
    expected_content = expected_block * 5
    assert content == expected_content, "The reassembled GCode content does not match the expected UTF-8 cleaned output."


def test_elf_files_renamed():
    old_service_orig = '/home/user/backup_source/system/bin/old_service'
    controller_orig = '/home/user/backup_source/machine_1/controller'

    assert not os.path.exists(old_service_orig), f"Original ELF file {old_service_orig} should have been renamed."
    assert not os.path.exists(controller_orig), f"Original ELF file {controller_orig} should have been renamed."

    old_service_bak = f"{old_service_orig}.elf.bak"
    controller_bak = f"{controller_orig}.elf.bak"

    assert os.path.isfile(old_service_bak), f"Renamed ELF file {old_service_bak} is missing."
    assert os.path.isfile(controller_bak), f"Renamed ELF file {controller_bak} is missing."

    expected_old = b'\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00'
    expected_controller = b'\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00'
    with open(old_service_bak, 'rb') as f:
        assert f.read() == expected_old, "Renaming old_service must preserve its ELF contents."
    with open(controller_bak, 'rb') as f:
        assert f.read() == expected_controller, "Renaming controller must preserve its ELF contents."


def test_manifest_log():
    manifest_path = '/home/user/manifest.log'
    assert os.path.isfile(manifest_path), f"Manifest file {manifest_path} is missing."

    expected_lines = [
        "CHUNKED GCODE: machine_1/part.gcode.part001",
        "CHUNKED GCODE: machine_1/part.gcode.part002",
        "CHUNKED GCODE: machine_1/part.gcode.part003",
        "RENAMED ELF: machine_1/controller.elf.bak",
        "RENAMED ELF: system/bin/old_service.elf.bak"
    ]

    with open(manifest_path, 'r', encoding='utf-8') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines == expected_lines, "Manifest log contents do not match the expected sorted output."
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || return 1

    test -f /home/user/archiver.cpp || return 1
    test -f /home/user/archiver || return 1
    test -x /home/user/archiver || return 1
    python3 - <<'PY' || return 1
with open('/home/user/archiver', 'rb') as f:
    assert f.read(4) == b'\x7fELF', '/home/user/archiver is not a compiled ELF executable'
PY

    verifier_binary="/tmp/verifier_archiver_$$"
    g++ -std=c++17 -O2 /home/user/archiver.cpp -o "$verifier_binary" || return 1

    python3 - "$verifier_binary" <<'PY' || return 1
import glob
import os
import secrets
import subprocess
import sys

binary = sys.argv[1]
root = '/home/user/backup_source'
probe_dir = os.path.join(root, 'verifier_probe')
os.makedirs(probe_dir, exist_ok=True)
nonce = secrets.token_hex(12)

gcode_name = f'job_{nonce}.gcode'
gcode_path = os.path.join(probe_dir, gcode_name)
raw_block = (
    b'M117 JOB-' + nonce.encode('ascii') + b' \xb0C ; operator note\n'
    b'G1 X12.5 Y7.25 ; positioning\n'
    b'; full-line comment\n'
    b'\n'
    b'M109 S215 \xb0C ; wait\n'
    b'G1 Z0.35\n'
)
raw = raw_block * 7
with open(gcode_path, 'wb') as f:
    f.write(raw)

elf_name = f'tool_{nonce}'
elf_path = os.path.join(probe_dir, elf_name)
elf_contents = b'\x7fELF' + secrets.token_bytes(73)
with open(elf_path, 'wb') as f:
    f.write(elf_contents)

subprocess.run([binary], cwd='/home/user', check=True, timeout=30)

assert not os.path.exists(gcode_path), 'The compiled program did not delete the probe GCode file'
assert not os.path.exists(elf_path), 'The compiled program did not rename the probe ELF file'
elf_bak = elf_path + '.elf.bak'
assert os.path.isfile(elf_bak), 'The compiled program did not create the probe ELF backup name'
with open(elf_bak, 'rb') as f:
    assert f.read() == elf_contents, 'The compiled program did not preserve the probe ELF contents'

cleaned_lines = []
for line in raw.decode('iso-8859-1').splitlines():
    line = line.split(';', 1)[0]
    if line.strip():
        cleaned_lines.append(line + '\n')
expected = ''.join(cleaned_lines).encode('utf-8')
expected_chunks = [expected[i:i + 100] for i in range(0, len(expected), 100)]

actual_paths = sorted(glob.glob(gcode_path + '.part*'))
expected_paths = [gcode_path + f'.part{i:03d}' for i in range(1, len(expected_chunks) + 1)]
assert actual_paths == expected_paths, 'The compiled program created an incorrect set of probe chunks'
for path, expected_chunk in zip(expected_paths, expected_chunks):
    with open(path, 'rb') as f:
        assert f.read() == expected_chunk, f'Incorrect generated content in {path}'

manifest_path = '/home/user/manifest.log'
assert os.path.isfile(manifest_path), 'The compiled program did not produce a manifest'
with open(manifest_path, 'r', encoding='utf-8') as f:
    lines = [line.strip() for line in f if line.strip()]
assert lines == sorted(lines), 'Manifest lines are not alphabetically sorted'

relative_gcode = os.path.relpath(gcode_path, root)
for i in range(1, len(expected_chunks) + 1):
    event = f'CHUNKED GCODE: {relative_gcode}.part{i:03d}'
    assert lines.count(event) == 1, f'Missing or duplicate manifest event: {event}'
relative_elf = os.path.relpath(elf_bak, root)
elf_event = f'RENAMED ELF: {relative_elf}'
assert lines.count(elf_event) == 1, f'Missing or duplicate manifest event: {elf_event}'
PY

    rm -f "$verifier_binary"
    return 0
}

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
