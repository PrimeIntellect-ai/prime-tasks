#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import builtins
import json
import os
import runpy
import shutil
import struct
import tarfile
import zipfile

import pytest

ARCHIVE = '/home/user/artifacts.tar.gz'
EXTRACTED = '/home/user/extracted'
REGISTRY = '/home/user/registry.json'
CURATED = '/home/user/curated.zip'


def archive_expectations():
    valid = {}
    registry = {}
    invalid_originals = set()

    with tarfile.open(ARCHIVE, 'r:gz') as tf:
        for member in tf.getmembers():
            if not member.isfile():
                continue
            original = os.path.basename(member.name)
            stream = tf.extractfile(member)
            assert stream is not None
            data = stream.read()

            if len(data) < 24 or data[:4] != b'ARTF':
                invalid_originals.add(original)
                continue

            name_bytes = data[4:20].rstrip(b'\x00')
            true_name = name_bytes.decode('ascii')
            version = struct.unpack('<I', data[20:24])[0]
            new_name = f'{true_name}_v{version}.bin'
            valid[new_name] = data
            registry[new_name] = original

    return valid, registry, invalid_originals


def test_extracted_directory_exists():
    assert os.path.isdir('/home/user/extracted'), "/home/user/extracted directory does not exist."


def test_corrupt_file_deleted():
    assert not os.path.exists('/home/user/extracted/fileC.bin'), "Corrupt file fileC.bin was not deleted."


def test_valid_files_renamed():
    expected_files = {
        'libnetwork_v2.bin',
        'core_engine_v15.bin'
    }
    extracted_files = set(os.listdir('/home/user/extracted'))

    for f in expected_files:
        assert f in extracted_files, f"Expected file {f} is missing from /home/user/extracted."

    assert 'fileA.bin' not in extracted_files, "Original fileA.bin was not renamed."
    assert 'fileB.bin' not in extracted_files, "Original fileB.bin was not renamed."


def test_registry_json_contents():
    registry_path = '/home/user/registry.json'
    assert os.path.isfile(registry_path), f"{registry_path} does not exist."

    with open(registry_path, 'r') as f:
        try:
            registry = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("registry.json is not valid JSON.")

    expected_registry = {
        "libnetwork_v2.bin": "fileA.bin",
        "core_engine_v15.bin": "fileB.bin"
    }

    assert registry == expected_registry, f"registry.json contents do not match expected mapping. Got: {registry}"


def test_curated_zip_contents():
    zip_path = '/home/user/curated.zip'
    assert os.path.isfile(zip_path), f"{zip_path} does not exist."
    assert zipfile.is_zipfile(zip_path), f"{zip_path} is not a valid zip archive."

    with zipfile.ZipFile(zip_path, 'r') as z:
        names = z.namelist()

    expected_names = {'libnetwork_v2.bin', 'core_engine_v15.bin'}
    assert set(names) == expected_names, f"Zip contents do not match exactly. Expected {expected_names}, got {set(names)}."

    for name in names:
        assert '/' not in name and '\\' not in name, f"File {name} in zip archive contains directory paths."


def find_python_scripts():
    scripts = []
    extracted_prefix = os.path.realpath(EXTRACTED) + os.sep
    for root, dirs, files in os.walk('/home/user'):
        real_root = os.path.realpath(root)
        if real_root == os.path.realpath(EXTRACTED) or real_root.startswith(extracted_prefix):
            dirs[:] = []
            continue
        for filename in files:
            if filename.endswith('.py'):
                scripts.append(os.path.join(root, filename))
    return sorted(scripts)


def clear_outputs():
    if os.path.lexists(EXTRACTED):
        if os.path.isdir(EXTRACTED) and not os.path.islink(EXTRACTED):
            shutil.rmtree(EXTRACTED)
        else:
            os.unlink(EXTRACTED)
    for path in (REGISTRY, CURATED):
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)


def validate_full_outputs(expected_data, expected_registry, invalid_originals):
    assert os.path.isdir(EXTRACTED)
    entries = set(os.listdir(EXTRACTED))
    assert entries == set(expected_data), f'Unexpected extracted directory contents: {entries}'

    for original in invalid_originals:
        assert not os.path.exists(os.path.join(EXTRACTED, original))

    for filename, expected_bytes in expected_data.items():
        path = os.path.join(EXTRACTED, filename)
        assert os.path.isfile(path), f'{path} is not a regular file'
        with open(path, 'rb') as f:
            assert f.read() == expected_bytes, f'Binary contents of {filename} differ from the source artifact'

    assert os.path.isfile(REGISTRY)
    with open(REGISTRY, 'r', encoding='utf-8') as f:
        assert json.load(f) == expected_registry

    assert os.path.isfile(CURATED)
    assert zipfile.is_zipfile(CURATED)
    with zipfile.ZipFile(CURATED, 'r') as z:
        names = z.namelist()
        assert len(names) == len(expected_data), 'ZIP contains duplicate or extra entries'
        assert set(names) == set(expected_data)
        for name in names:
            assert '/' not in name and '\\' not in name
            assert not z.getinfo(name).is_dir()
            assert z.read(name) == expected_data[name], f'ZIP entry {name} does not contain the original artifact data'


def test_script_reexecutes_and_preserves_binary_data_atomically():
    expected_data, expected_registry, invalid_originals = archive_expectations()
    scripts = find_python_scripts()
    assert scripts, 'No Python curation script was left in /home/user'

    with open(ARCHIVE, 'rb') as f:
        archive_bytes = f.read()

    failures = []
    for script in scripts:
        real_replace = os.replace
        replace_events = []
        try:
            clear_outputs()
            with open(ARCHIVE, 'wb') as f:
                f.write(archive_bytes)

            def monitored_replace(src, dst, *args, **kwargs):
                src_text = os.fsdecode(os.fspath(src))
                dst_text = os.fsdecode(os.fspath(dst))
                src_abs = os.path.abspath(src_text)
                dst_abs = os.path.abspath(dst_text)
                if dst_abs == REGISTRY:
                    assert src_abs != REGISTRY, 'os.replace must use a distinct temporary file'
                    assert os.path.isfile(src_abs), 'Registry temporary file did not exist before os.replace'
                    with open(src_abs, 'rb') as temp_file:
                        temp_data = temp_file.read()
                    source_inode = os.stat(src_abs).st_ino
                    result = real_replace(src, dst, *args, **kwargs)
                    assert os.path.isfile(REGISTRY)
                    assert os.stat(REGISTRY).st_ino == source_inode
                    replace_events.append((src_abs, temp_data))
                    return result
                return real_replace(src, dst, *args, **kwargs)

            os.replace = monitored_replace
            os.chdir('/home/user')
            try:
                runpy.run_path(script, run_name='__main__')
            except SystemExit as exc:
                if exc.code not in (None, 0):
                    raise
            finally:
                os.replace = real_replace

            assert replace_events, 'The script did not atomically install registry.json using Python os.replace'
            temp_path, replaced_data = replace_events[-1]
            assert temp_path != REGISTRY
            with open(REGISTRY, 'rb') as f:
                assert f.read() == replaced_data, 'Final registry is not the data installed from the temporary file'

            validate_full_outputs(expected_data, expected_registry, invalid_originals)
            return
        except BaseException as exc:
            os.replace = real_replace
            failures.append(f'{script}: {type(exc).__name__}: {exc}')

    pytest.fail('No submitted Python script correctly reproduced the outputs and atomic workflow:\n' + '\n'.join(failures))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
