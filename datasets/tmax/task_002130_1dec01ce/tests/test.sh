#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import stat
import struct
import subprocess
import tarfile
import tempfile
import uuid


def test_process_log():
    log_path = '/home/user/process.log'
    assert os.path.isfile(log_path), f"{log_path} is missing."

    with open(log_path, 'r') as f:
        content = f.read().strip()

    expected_line = "CORRUPT: broken_release.tar.gz"
    assert expected_line in content, f"Expected '{expected_line}' to be in {log_path}, but found: {content}"


def test_archive_backup_contents():
    backup_dir = '/home/user/archive_backup/'
    assert os.path.isdir(backup_dir), f"{backup_dir} is missing."

    files = set(os.listdir(backup_dir))
    expected_files = {'release_v1.tar.gz', 'release_v2.tar.gz'}

    assert files == expected_files, f"Expected {backup_dir} to contain exactly {expected_files}, but found {files}"


def test_doc_db_wal():
    wal_path = '/home/user/doc_db.wal'
    assert os.path.isfile(wal_path), f"{wal_path} is missing."

    with open(wal_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {wal_path}, found {len(lines)}"

    parsed_records = {}
    for line in lines:
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            assert False, f"Failed to parse JSON from line: {line}"

        release_name = record.get("release")
        parsed_records[release_name] = record

    assert "release_v1.tar.gz" in parsed_records, "Missing record for release_v1.tar.gz"
    assert "release_v2.tar.gz" in parsed_records, "Missing record for release_v2.tar.gz"

    # Check v1
    v1 = parsed_records["release_v1.tar.gz"]
    assert "binaries" in v1 and len(v1["binaries"]) == 1, "Invalid binaries list for v1"
    assert v1["binaries"][0]["name"] == "firmware.elf", "Expected firmware.elf in v1 binaries"
    assert isinstance(v1["binaries"][0].get("arch"), str) and len(v1["binaries"][0]["arch"]) > 0, "Missing or invalid architecture for firmware.elf"

    assert "gcode_times" in v1 and len(v1["gcode_times"]) == 1, "Invalid gcode_times list for v1"
    assert v1["gcode_times"][0] == {"name": "test.gcode", "time": "4500s"}, f"Unexpected gcode_times for v1: {v1['gcode_times']}"

    # Check v2
    v2 = parsed_records["release_v2.tar.gz"]
    assert "binaries" in v2 and len(v2["binaries"]) == 1, "Invalid binaries list for v2"
    assert v2["binaries"][0]["name"] == "util.bin", "Expected util.bin in v2 binaries"
    assert isinstance(v2["binaries"][0].get("arch"), str) and len(v2["binaries"][0]["arch"]) > 0, "Missing or invalid architecture for util.bin"

    assert "gcode_times" in v2 and len(v2["gcode_times"]) == 1, "Invalid gcode_times list for v2"
    assert v2["gcode_times"][0] == {"name": "calib.gcode", "time": "120s"}, f"Unexpected gcode_times for v2: {v2['gcode_times']}"


def _arch_matches(value, machine):
    assert isinstance(value, str) and value.strip(), "Architecture must be a nonempty string"
    normalized = value.strip().lower()
    if machine == 62:
        return any(token in normalized for token in ('x86-64', 'x86_64', 'amd64'))
    if machine == 183:
        return normalized == 'arm' or any(token in normalized for token in ('aarch64', 'arm64'))
    return False


def test_script_executes_and_processes_generated_archives():
    script = '/home/user/process_releases.py'
    assert os.path.exists(script), f"{script} is missing"
    assert stat.S_ISREG(os.stat(script).st_mode), f"{script} is not a regular file"
    compile_result = subprocess.run(
        ['python3', '-m', 'py_compile', script], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert compile_result.returncode == 0, compile_result.stderr

    token = uuid.uuid4().hex[:12]
    state_dir = tempfile.mkdtemp(prefix='release-verifier-state-')
    build_dir = tempfile.mkdtemp(prefix='release-verifier-build-')
    managed = [
        '/home/user/dropzone',
        '/home/user/archive_backup',
        '/home/user/process.log',
        '/home/user/doc_db.wal',
    ]
    saved = {}

    try:
        for path in managed:
            if os.path.lexists(path):
                destination = os.path.join(state_dir, os.path.basename(path))
                shutil.move(path, destination)
                saved[path] = destination

        dropzone = '/home/user/dropzone'
        backup = '/home/user/archive_backup'
        os.makedirs(dropzone)
        os.makedirs(backup)

        x86_name = f'zeta_{token}.payload'
        arm_name = f'alpha_{token}.txt'
        gcode_z = f'zeta_{token}.gcode'
        gcode_a = f'alpha_{token}.gcode'
        second_gcode = f'only_{token}.gcode'
        time_a = f'{int(token[:4], 16)}s'
        time_z = f'{int(token[4:8], 16)}m'
        time_second = f'{int(token[8:12], 16)}h'

        x86_path = os.path.join(build_dir, x86_name)
        arm_path = os.path.join(build_dir, arm_name)
        shutil.copyfile('/bin/true', x86_path)
        shutil.copyfile('/bin/true', arm_path)

        # e_machine is at byte offset 18 in a little-endian ELF header.
        with open(x86_path, 'r+b') as f:
            f.seek(18)
            f.write(struct.pack('<H', 62))
        with open(arm_path, 'r+b') as f:
            f.seek(18)
            f.write(struct.pack('<H', 183))

        with open(os.path.join(build_dir, gcode_z), 'w') as f:
            f.write(f"G28\n ; TIME: ignored-{token}\n; TIME: {time_z}\n")
        with open(os.path.join(build_dir, gcode_a), 'w') as f:
            f.write(f";TIME: ignored-{token}\n; TIME: {time_a}\nG1 X1\n")
        with open(os.path.join(build_dir, second_gcode), 'w') as f:
            f.write(f"G28\n; TIME: {time_second}\n")

        release_one = f'dynamic_{token}_one.tar.gz'
        release_two = f'dynamic_{token}_two.tar.gz'
        corrupt_name = f'dynamic_{token}_broken.tar.gz'

        release_one_path = os.path.join(dropzone, release_one)
        release_two_path = os.path.join(dropzone, release_two)
        with tarfile.open(release_one_path, 'w:gz') as archive:
            for name in (x86_name, arm_name, gcode_z, gcode_a):
                archive.add(os.path.join(build_dir, name), arcname=name)
        with tarfile.open(release_two_path, 'w:gz') as archive:
            archive.add(os.path.join(build_dir, second_gcode), arcname=second_gcode)
        with open(os.path.join(dropzone, corrupt_name), 'wb') as f:
            f.write(os.urandom(173))

        expected_archive_bytes = {}
        for name in (release_one, release_two):
            with open(os.path.join(dropzone, name), 'rb') as f:
                expected_archive_bytes[name] = f.read()

        result = subprocess.run(
            ['python3', script], text=True, timeout=30,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        assert result.returncode == 0, (
            f"Script exited with {result.returncode}. stdout={result.stdout!r} "
            f"stderr={result.stderr!r}"
        )

        with open('/home/user/process.log', 'r') as f:
            log_lines = [line.rstrip('\n') for line in f if line.rstrip('\n')]
        assert log_lines == [f'CORRUPT: {corrupt_name}'], f"Unexpected process.log: {log_lines}"

        backup_files = set(os.listdir(backup))
        assert backup_files == {release_one, release_two}, f"Unexpected backup files: {backup_files}"
        for name, expected_bytes in expected_archive_bytes.items():
            with open(os.path.join(backup, name), 'rb') as f:
                assert f.read() == expected_bytes, f"Backup of {name} differs from the valid archive"

        with open('/home/user/doc_db.wal', 'r') as f:
            wal_lines = [line.strip() for line in f if line.strip()]
        assert len(wal_lines) == 2, f"Expected two generated WAL records, got {len(wal_lines)}"
        records = [json.loads(line) for line in wal_lines]
        assert all(isinstance(record, dict) for record in records)
        by_release = {record.get('release'): record for record in records}
        assert set(by_release) == {release_one, release_two}, f"Unexpected releases: {set(by_release)}"

        first = by_release[release_one]
        binaries = first.get('binaries')
        assert isinstance(binaries, list)
        assert [entry.get('name') for entry in binaries] == sorted([arm_name, x86_name])
        binary_by_name = {entry.get('name'): entry for entry in binaries}
        assert _arch_matches(binary_by_name[x86_name].get('arch'), 62), binary_by_name[x86_name]
        assert _arch_matches(binary_by_name[arm_name].get('arch'), 183), binary_by_name[arm_name]
        assert first.get('gcode_times') == [
            {'name': gcode_a, 'time': time_a},
            {'name': gcode_z, 'time': time_z},
        ], first.get('gcode_times')

        second = by_release[release_two]
        assert second.get('binaries') == [], second.get('binaries')
        assert second.get('gcode_times') == [
            {'name': second_gcode, 'time': time_second}
        ], second.get('gcode_times')
    finally:
        for path in managed:
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            elif os.path.lexists(path):
                os.unlink(path)
        for original, stored in saved.items():
            shutil.move(stored, original)
        shutil.rmtree(state_dir, ignore_errors=True)
        shutil.rmtree(build_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
