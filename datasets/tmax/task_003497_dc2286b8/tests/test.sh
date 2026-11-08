#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import hashlib
import csv
import pytest
import shutil
import secrets


def get_elf_info(filepath):
    try:
        output = subprocess.check_output(['readelf', '-h', filepath], stderr=subprocess.DEVNULL).decode('utf-8')
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None

    machine = None
    type_str = None
    for line in output.splitlines():
        if "Machine:" in line:
            machine = line.split("Machine:")[1].strip()
        elif "Type:" in line:
            type_raw = line.split("Type:")[1].strip()
            if "EXEC" in type_raw:
                type_str = "EXEC"
            elif "DYN" in type_raw:
                type_str = "DYN"
            else:
                type_str = "UNKNOWN"

    if machine and type_str:
        return machine.replace(" ", "_"), type_str
    return None


def get_sha256(filepath):
    sha256 = hashlib.sha256()
    with open(filepath, 'rb') as f:
        for chunk in iter(lambda: f.read(4096), b""):
            sha256.update(chunk)
    return sha256.hexdigest()


@pytest.fixture(scope="module")
def expected_data():
    incoming_dir = "/home/user/incoming"
    expected = {}
    if not os.path.exists(incoming_dir):
        return expected

    for filename in os.listdir(incoming_dir):
        filepath = os.path.join(incoming_dir, filename)
        if not os.path.isfile(filepath):
            continue

        elf_info = get_elf_info(filepath)
        if elf_info:
            arch, type_str = elf_info
            sha256 = get_sha256(filepath)
            expected[filename] = {
                'sha256': sha256,
                'arch': arch,
                'type': type_str,
                'original_filepath': filepath
            }
    return expected


def test_script_exists():
    script_path = "/home/user/curate.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."


def test_manifest_exists_and_correct(expected_data):
    manifest_path = "/home/user/repo/manifest.csv"
    assert os.path.isfile(manifest_path), f"Manifest file {manifest_path} does not exist."

    actual_manifest = []
    with open(manifest_path, 'r', newline='') as f:
        reader = csv.reader(f)
        for row in reader:
            if row:
                actual_manifest.append(row)

    expected_rows = []
    for filename, data in expected_data.items():
        expected_rows.append([data['sha256'], data['arch'], data['type'], filename])

    assert len(actual_manifest) == len(expected_rows), "Manifest does not contain the correct number of entries."

    actual_sorted = sorted(actual_manifest, key=lambda x: x[3] if len(x) > 3 else "")
    expected_sorted = sorted(expected_rows, key=lambda x: x[3])

    for actual_row, expected_row in zip(actual_sorted, expected_sorted):
        assert actual_row == expected_row, f"Manifest row mismatch. Expected: {expected_row}, Got: {actual_row}"


def test_organized_files(expected_data):
    repo_dir = "/home/user/repo"
    assert os.path.isdir(repo_dir), f"Repo directory {repo_dir} does not exist."

    for filename, data in expected_data.items():
        expected_path = os.path.join(repo_dir, data['arch'], data['type'], filename)
        assert os.path.isfile(expected_path), f"Expected organized file is missing: {expected_path}"

        # Verify it's exactly the same file contents
        copied_sha256 = get_sha256(expected_path)
        assert copied_sha256 == data['sha256'], f"File contents mismatch for {expected_path}"


def remove_path(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


def test_script_processes_fresh_inputs():
    script_path = "/home/user/curate.sh"
    incoming_dir = "/home/user/incoming"
    repo_dir = "/home/user/repo"
    token = secrets.token_hex(8)
    incoming_backup = f"/home/user/.incoming_verifier_backup_{token}"
    repo_backup = f"/home/user/.repo_verifier_backup_{token}"

    os.rename(incoming_dir, incoming_backup)
    os.rename(repo_dir, repo_backup)

    try:
        os.mkdir(incoming_dir)
        os.mkdir(repo_dir)

        dyn_source = None
        for candidate in ['/bin/ls', '/bin/cp', '/lib/x86_64-linux-gnu/libc.so.6', '/lib/x86_64-linux-gnu/libm.so.6']:
            info = get_elf_info(candidate)
            if info and info[1] == 'DYN':
                dyn_source = candidate
                break
        assert dyn_source is not None, "Verifier could not locate a DYN ELF test source."

        dyn_name = f"fresh_dyn_{token}.bin"
        exec_name = f"fresh_exec_{token}.bin"
        junk_name = f"fresh_junk_{token}.txt"
        dyn_path = os.path.join(incoming_dir, dyn_name)
        exec_path = os.path.join(incoming_dir, exec_name)

        shutil.copyfile(dyn_source, dyn_path)
        shutil.copyfile(dyn_source, exec_path)

        # Change only the ELF e_type field from ET_DYN to ET_EXEC so both
        # required classifications are exercised without relying on a compiler.
        with open(exec_path, 'r+b') as f:
            ident = f.read(18)
            assert ident[:4] == b'\x7fELF'
            byteorder = 'little' if ident[5] == 1 else 'big'
            f.seek(16)
            f.write((2).to_bytes(2, byteorder=byteorder))

        with open(os.path.join(incoming_dir, junk_name), 'w') as f:
            f.write("not an ELF file\n")

        expected = {}
        for filename in (dyn_name, exec_name):
            path = os.path.join(incoming_dir, filename)
            info = get_elf_info(path)
            assert info is not None
            arch, type_str = info
            expected[filename] = [get_sha256(path), arch, type_str, filename]

        assert expected[dyn_name][2] == 'DYN'
        assert expected[exec_name][2] == 'EXEC'

        result = subprocess.run(
            ['bash', script_path],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"curate.sh failed on fresh inputs with exit code {result.returncode}. "
            f"stdout: {result.stdout} stderr: {result.stderr}"
        )

        manifest_path = os.path.join(repo_dir, 'manifest.csv')
        assert os.path.isfile(manifest_path), "curate.sh did not create a manifest for fresh inputs."
        with open(manifest_path, 'r', newline='') as f:
            actual_rows = [row for row in csv.reader(f) if row]

        assert sorted(actual_rows) == sorted(expected.values()), (
            f"Fresh-input manifest mismatch. Expected {sorted(expected.values())}, got {sorted(actual_rows)}"
        )

        for filename, row in expected.items():
            sha256, arch, type_str, _ = row
            copied_path = os.path.join(repo_dir, arch, type_str, filename)
            assert os.path.isfile(copied_path), f"Fresh ELF was not organized at {copied_path}"
            assert get_sha256(copied_path) == sha256, f"Fresh organized file differs from {filename}"
    finally:
        remove_path(incoming_dir)
        remove_path(repo_dir)
        os.rename(incoming_backup, incoming_dir)
        os.rename(repo_backup, repo_dir)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
