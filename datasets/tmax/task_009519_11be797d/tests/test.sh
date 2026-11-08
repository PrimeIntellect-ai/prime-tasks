#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import shutil
import stat
import subprocess
import tarfile
import time
import uuid


def get_sha256(filepath):
    h = hashlib.sha256()
    with open(filepath, 'rb') as f:
        for chunk in iter(lambda: f.read(4096), b""):
            h.update(chunk)
    return h.hexdigest()


def parse_manifest(path):
    with open(path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    records = {}
    raw_records = {}
    for line in lines:
        parts = line.split('|')
        assert len(parts) == 3, f"Manifest line '{line}' does not match format original_filename|mtime|sha256sum."
        name, mtime, checksum = parts
        assert name not in records, f"Duplicate manifest entry for {name}."
        try:
            numeric_mtime = float(mtime)
        except ValueError:
            raise AssertionError(f"mtime '{mtime}' is not a valid number.")
        records[name] = (numeric_mtime, checksum)
        raw_records[name] = line
    return records, raw_records


def run_tool():
    result = subprocess.run(
        ['/home/user/backup_tool'],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"backup_tool exited with {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_backup_tool_exists_and_executable():
    assert os.path.isfile('/home/user/backup_tool.c'), "Source file /home/user/backup_tool.c does not exist."
    assert os.path.isfile('/home/user/backup_tool'), "Compiled binary /home/user/backup_tool does not exist."
    st = os.stat('/home/user/backup_tool')
    assert bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)), "Compiled binary /home/user/backup_tool is not executable."
    with open('/home/user/backup_tool', 'rb') as f:
        assert f.read(4) == b'\x7fELF', "Compiled binary is not an ELF executable."


def test_backup_directory_contains_renamed_files():
    backup_dir = '/home/user/backup'
    assert os.path.isdir(backup_dir), f"Directory {backup_dir} does not exist."

    expected_files = [
        'img_test.png',
        'doc_info.txt',
        'src_app.c',
        'file.bin'
    ]

    source_names = ['test.png', 'info.txt', 'app.c', 'file.bin']
    for backup_name, source_name in zip(expected_files, source_names):
        filepath = os.path.join(backup_dir, backup_name)
        source_path = os.path.join('/home/user/raw_data', source_name)
        assert os.path.isfile(filepath), f"Expected backup file {filepath} does not exist."
        with open(filepath, 'rb') as backed_up, open(source_path, 'rb') as source:
            assert backed_up.read() == source.read(), f"Backup file {filepath} does not match its source."


def test_new_manifest_format_and_content():
    manifest_path = '/home/user/new_manifest.txt'
    assert os.path.isfile(manifest_path), f"Manifest file {manifest_path} does not exist."

    with open(manifest_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 4, f"Expected 4 lines in manifest, found {len(lines)}."

    raw_data_dir = '/home/user/raw_data'
    expected_entries = {}
    for orig_name in ['test.png', 'info.txt', 'app.c', 'file.bin']:
        raw_path = os.path.join(raw_data_dir, orig_name)
        if os.path.isfile(raw_path):
            expected_entries[orig_name] = get_sha256(raw_path)

    found_files = set()
    for line in lines:
        parts = line.split('|')
        assert len(parts) == 3, f"Manifest line '{line}' does not match format original_filename|mtime|sha256sum."
        orig_name, mtime, sha256sum = parts
        found_files.add(orig_name)

        assert orig_name in expected_entries, f"Unexpected file {orig_name} in manifest."
        assert sha256sum == expected_entries[orig_name], f"Checksum mismatch for {orig_name}."
        assert mtime.isdigit() or (mtime.replace('.','',1).isdigit()), f"mtime '{mtime}' is not a valid number."
        expected_mtime = int(os.stat(os.path.join(raw_data_dir, orig_name)).st_mtime)
        assert int(float(mtime)) == expected_mtime, f"mtime mismatch for {orig_name}."

    assert found_files == set(expected_entries.keys()), "Not all original files were found in the manifest."


def test_backup_archive_exists_and_valid():
    archive_path = '/home/user/backup_archive.tar.gz'
    assert os.path.isfile(archive_path), f"Archive file {archive_path} does not exist."
    assert tarfile.is_tarfile(archive_path), f"{archive_path} is not a valid tar archive."

    expected = {
        'img_test.png': '/home/user/raw_data/test.png',
        'doc_info.txt': '/home/user/raw_data/info.txt',
        'src_app.c': '/home/user/raw_data/app.c',
        'file.bin': '/home/user/raw_data/file.bin',
    }

    with tarfile.open(archive_path, 'r:gz') as tar:
        members = [member for member in tar.getmembers() if member.isfile()]
        basenames = [os.path.basename(member.name) for member in members]

        for name, source_path in expected.items():
            assert name in basenames, f"Expected file {name} not found in the tarball."
            matching = [member for member in members if os.path.basename(member.name) == name]
            assert len(matching) == 1, f"Expected exactly one archived regular file named {name}."
            extracted = tar.extractfile(matching[0])
            assert extracted is not None
            with open(source_path, 'rb') as source:
                assert extracted.read() == source.read(), f"Archived file {name} does not match its source."


def test_tool_execution_configuration_copying_and_incremental_behavior():
    raw_dir = '/home/user/raw_data'
    backup_dir = '/home/user/backup'
    rules_path = '/home/user/rules.cfg'
    manifest_path = '/home/user/manifest.txt'
    new_manifest_path = '/home/user/new_manifest.txt'

    shutil.rmtree(raw_dir, ignore_errors=True)
    shutil.rmtree(backup_dir, ignore_errors=True)
    os.makedirs(raw_dir)
    os.makedirs(backup_dir)
    for path in (manifest_path, new_manifest_path):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    token = uuid.uuid4().hex
    prefix_a = f'cfgA_{token}_'
    prefix_b = f'cfgB_{token}_'
    with open(rules_path, 'w') as f:
        f.write(f'.qdat={prefix_a}\n')
        f.write(f'.qsrc={prefix_b}\n')

    unchanged = f'unchanged_{token}.qdat'
    changed = f'changed_{token}.qsrc'
    no_rule = f'plain_{token}.other'
    initial_contents = {
        unchanged: os.urandom(137),
        changed: os.urandom(211),
        no_rule: os.urandom(89),
    }

    base_mtime = int(time.time()) - 1000
    for index, (name, content) in enumerate(initial_contents.items()):
        path = os.path.join(raw_dir, name)
        with open(path, 'wb') as f:
            f.write(content)
        timestamp = base_mtime + index * 10
        os.utime(path, (timestamp, timestamp))

    run_tool()

    assert os.path.isfile(new_manifest_path), "Tool did not create new_manifest.txt on its first run."
    first_records, first_raw = parse_manifest(new_manifest_path)
    assert set(first_records) == set(initial_contents), "First-run manifest does not describe exactly the source files."

    renamed = {
        unchanged: prefix_a + unchanged,
        changed: prefix_b + changed,
        no_rule: no_rule,
    }
    for source_name, backup_name in renamed.items():
        source_path = os.path.join(raw_dir, source_name)
        backup_path = os.path.join(backup_dir, backup_name)
        assert os.path.isfile(backup_path), f"Tool did not create configured backup name {backup_name}."
        with open(source_path, 'rb') as source, open(backup_path, 'rb') as backup:
            assert backup.read() == source.read(), f"Copied bytes for {source_name} are incorrect."
        recorded_mtime, recorded_hash = first_records[source_name]
        assert int(recorded_mtime) == int(os.stat(source_path).st_mtime), f"First-run mtime is wrong for {source_name}."
        assert recorded_hash == get_sha256(source_path), f"First-run checksum is wrong for {source_name}."

    # Install the generated manifest as the old manifest, but give the unchanged
    # entry a recognizable old checksum. Exact-mtime incremental handling must
    # preserve that old record and must not recopy its destination.
    fake_old_hash = 'a' * 64
    patched_lines = []
    for name in initial_contents:
        if name == unchanged:
            mtime_text = first_raw[name].split('|')[1]
            patched_lines.append(f'{name}|{mtime_text}|{fake_old_hash}')
        else:
            patched_lines.append(first_raw[name])
    with open(manifest_path, 'w') as f:
        f.write('\n'.join(patched_lines) + '\n')
    os.remove(new_manifest_path)

    unchanged_backup = os.path.join(backup_dir, renamed[unchanged])
    marker = b'UNCHANGED_DESTINATION_MUST_NOT_BE_RECOPIED_' + token.encode()
    with open(unchanged_backup, 'wb') as f:
        f.write(marker)

    changed_content = os.urandom(313)
    changed_path = os.path.join(raw_dir, changed)
    with open(changed_path, 'wb') as f:
        f.write(changed_content)
    changed_mtime = base_mtime + 200
    os.utime(changed_path, (changed_mtime, changed_mtime))

    added = f'added_{token}.qdat'
    added_content = os.urandom(173)
    added_path = os.path.join(raw_dir, added)
    with open(added_path, 'wb') as f:
        f.write(added_content)
    added_mtime = base_mtime + 300
    os.utime(added_path, (added_mtime, added_mtime))

    run_tool()

    second_records, second_raw = parse_manifest(new_manifest_path)
    expected_second_names = set(initial_contents) | {added}
    assert set(second_records) == expected_second_names, "Second-run manifest does not describe exactly the current source files."

    expected_old_line = f"{unchanged}|{first_raw[unchanged].split('|')[1]}|{fake_old_hash}"
    assert second_raw[unchanged] == expected_old_line, "Unchanged file's old manifest record was not preserved."
    with open(unchanged_backup, 'rb') as f:
        assert f.read() == marker, "Unchanged file was copied again instead of being skipped."

    assert second_raw[no_rule] == first_raw[no_rule], "Another unchanged file's old record was not preserved."

    changed_record_mtime, changed_record_hash = second_records[changed]
    assert int(changed_record_mtime) == changed_mtime, "Modified file's new mtime was not recorded."
    assert changed_record_hash == hashlib.sha256(changed_content).hexdigest(), "Modified file's checksum was not recalculated."
    with open(os.path.join(backup_dir, renamed[changed]), 'rb') as f:
        assert f.read() == changed_content, "Modified file was not recopied with the configured name."

    added_record_mtime, added_record_hash = second_records[added]
    assert int(added_record_mtime) == added_mtime, "New file's mtime was not recorded."
    assert added_record_hash == hashlib.sha256(added_content).hexdigest(), "New file's checksum is incorrect."
    with open(os.path.join(backup_dir, prefix_a + added), 'rb') as f:
        assert f.read() == added_content, "New file was not copied using the parsed configuration rule."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
