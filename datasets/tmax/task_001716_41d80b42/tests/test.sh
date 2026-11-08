#!/bin/bash
set +e
mkdir -p /logs/verifier
reward=0

python3 - <<'FIXTURE_EOF'
import io
import os
import secrets
import struct
import tarfile
import zipfile

root = '/home/user/datasets'
os.makedirs(root, exist_ok=True)
token = secrets.token_hex(8)

zip_name = f'verifier_safe_{token}.zip'
zip_gcode = f'nested_{token}/model.gcode'
zip_elf = f'nested_{token}/program.bin'
elf = bytearray(64)
elf[:4] = b'\x7fELF'
elf[0x12:0x14] = struct.pack('<H', 183)
with zipfile.ZipFile(os.path.join(root, zip_name), 'w') as z:
    z.writestr(zip_gcode, 'G1 X1 E12.3\nG0 X2\nG1 Y4 E7.8\n')
    z.writestr(zip_elf, bytes(elf))

bad_zip_name = f'verifier_bad_{token}.zip'
with zipfile.ZipFile(os.path.join(root, bad_zip_name), 'w') as z:
    z.writestr(f'../escape_{token}.txt', 'do not extract')

tar_name = f'verifier_safe_{token}.tar.gz'
tar_gcode = f'parts_{token}/part.gcode'
tar_elf = f'parts_{token}/binary.dat'
elf2 = bytearray(64)
elf2[:4] = b'\x7fELF'
elf2[0x12:0x14] = struct.pack('<H', 243)
with tarfile.open(os.path.join(root, tar_name), 'w:gz') as t:
    data = b'G1 E31.4\nG1 X8 E2.7\n'
    info = tarfile.TarInfo(tar_gcode)
    info.size = len(data)
    t.addfile(info, io.BytesIO(data))
    info = tarfile.TarInfo(tar_elf)
    info.size = len(elf2)
    t.addfile(info, io.BytesIO(bytes(elf2)))

bad_tar_name = f'verifier_bad_{token}.tar.gz'
with tarfile.open(os.path.join(root, bad_tar_name), 'w:gz') as t:
    data = b'do not extract'
    info = tarfile.TarInfo(f'/absolute_{token}.txt')
    info.size = len(data)
    t.addfile(info, io.BytesIO(data))
FIXTURE_EOF
fixture_status=$?

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import zipfile
import tarfile
import struct
import re
import runpy
import shutil
from unittest import mock
import pytest

DATASETS_DIR = '/home/user/datasets'
SCRIPT_PATH = '/home/user/process_datasets.py'
MALICIOUS_LOG = '/home/user/malicious.log'
REPORT_JSON = '/home/user/report.json'

def is_malicious_path(path):
    # Check for absolute paths or directory traversal
    if path.startswith('/'):
        return True
    parts = path.split('/')
    if '..' in parts:
        return True
    return False

def get_expected_results():
    malicious_files = set()
    report_data = {}

    for filename in os.listdir(DATASETS_DIR):
        filepath = os.path.join(DATASETS_DIR, filename)
        if not (filename.endswith('.zip') or filename.endswith('.tar.gz')):
            continue

        is_malicious = False
        archive_items = []

        if filename.endswith('.zip'):
            try:
                with zipfile.ZipFile(filepath, 'r') as z:
                    for info in z.infolist():
                        if is_malicious_path(info.filename):
                            is_malicious = True
                            break
                        archive_items.append((info.filename, z.read(info.filename)))
            except zipfile.BadZipFile:
                continue
        elif filename.endswith('.tar.gz'):
            try:
                with tarfile.open(filepath, 'r:gz') as t:
                    for info in t.getmembers():
                        if is_malicious_path(info.name):
                            is_malicious = True
                            break
                        f = t.extractfile(info)
                        if f is not None:
                            archive_items.append((info.name, f.read()))
            except tarfile.ReadError:
                continue

        if is_malicious:
            malicious_files.add(filename)
        else:
            report_data[filename] = {
                "gcode_totals": {},
                "elf_architectures": {}
            }
            for name, content in archive_items:
                if name.endswith('.gcode'):
                    total_e = 0.0
                    lines = content.decode('utf-8', errors='ignore').splitlines()
                    for line in lines:
                        if line.startswith('G1 '):
                            match = re.search(r'\bE([0-9.]+)', line)
                            if match:
                                total_e += float(match.group(1))
                    if total_e > 0 or any(line.startswith('G1 ') and 'E' in line for line in lines):
                        report_data[filename]["gcode_totals"][name] = round(total_e, 1)

                if content.startswith(b'\x7fELF'):
                    if len(content) >= 0x14:
                        e_machine = struct.unpack('<H', content[0x12:0x14])[0]
                        report_data[filename]["elf_architectures"][name] = e_machine

    return malicious_files, report_data

@pytest.fixture(scope='session', autouse=True)
def execute_submission():
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} does not exist or is not a regular file."
    assert not os.path.islink(SCRIPT_PATH), f"{SCRIPT_PATH} must be the submitted Python script, not a symlink."

    for output in (MALICIOUS_LOG, REPORT_JSON):
        if os.path.lexists(output):
            assert not os.path.isdir(output), f"{output} is a directory."
            os.unlink(output)

    def extraction_forbidden(*args, **kwargs):
        raise AssertionError('Archive extraction is forbidden; process members from compressed streams.')

    with mock.patch.object(zipfile.ZipFile, 'extract', extraction_forbidden), \
         mock.patch.object(zipfile.ZipFile, 'extractall', extraction_forbidden), \
         mock.patch.object(tarfile.TarFile, 'extract', extraction_forbidden), \
         mock.patch.object(tarfile.TarFile, 'extractall', extraction_forbidden), \
         mock.patch.object(shutil, 'unpack_archive', extraction_forbidden):
        runpy.run_path(SCRIPT_PATH, run_name='__main__')

def test_malicious_log():
    assert os.path.isfile(MALICIOUS_LOG), f"{MALICIOUS_LOG} does not exist."

    expected_malicious, _ = get_expected_results()

    with open(MALICIOUS_LOG, 'r') as f:
        actual_malicious = set(line.strip() for line in f if line.strip())

    assert actual_malicious == expected_malicious, f"Expected malicious files {expected_malicious}, but found {actual_malicious} in {MALICIOUS_LOG}"

def test_report_json():
    assert os.path.isfile(REPORT_JSON), f"{REPORT_JSON} does not exist."

    _, expected_report = get_expected_results()

    with open(REPORT_JSON, 'r') as f:
        try:
            actual_report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{REPORT_JSON} is not a valid JSON file.")

    assert actual_report == expected_report, f"Report JSON content mismatch. Expected: {expected_report}, Actual: {actual_report}"
TEST_EOF
cat_status=$?

if [ "$fixture_status" -eq 0 ] && [ "$cat_status" -eq 0 ] && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    reward=1
fi

echo "$reward" > /logs/verifier/reward.txt
