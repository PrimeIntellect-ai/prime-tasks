#!/bin/bash
set -e
mkdir -p /logs/verifier

SNAPSHOT=$(mktemp -d)
for name in data master_archive.dat backup.stamp compress_append; do
    path="/home/user/$name"
    if [ -e "$path" ]; then
        touch "$SNAPSHOT/$name.exists"
        cp -a "$path" "$SNAPSHOT/$name"
    fi
done

cleanup() {
    rm -rf /home/user/data
    rm -f /home/user/master_archive.dat /home/user/backup.stamp
    rm -f /home/user/compress_append /home/user/compress_append.real-verifier
    for name in data master_archive.dat backup.stamp compress_append; do
        if [ -e "$SNAPSHOT/$name.exists" ]; then
            cp -a "$SNAPSHOT/$name" "/home/user/$name"
        fi
    done
    rm -rf "$SNAPSHOT"
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import struct
import subprocess
import tempfile
import time
import zlib
import pytest


def parse_archive(path):
    records = []
    with open(path, "rb") as f:
        while True:
            len_byte = f.read(1)
            if not len_byte:
                break
            assert len(len_byte) == 1, "Unexpected EOF while reading filename length."
            name_len = struct.unpack("B", len_byte)[0]
            filename = f.read(name_len)
            assert len(filename) == name_len, "Unexpected EOF while reading filename."
            size_bytes = f.read(4)
            assert len(size_bytes) == 4, "Unexpected EOF while reading compressed payload size."
            comp_size = struct.unpack("<I", size_bytes)[0]
            comp_data = f.read(comp_size)
            assert len(comp_data) == comp_size, "Unexpected EOF while reading compressed data."
            try:
                payload = zlib.decompress(comp_data)
            except Exception as e:
                pytest.fail(f"Failed to decompress payload for {filename!r}: {e}")
            records.append((filename, payload))
    return records


def test_executables_and_scripts_exist():
    assert os.path.exists("/home/user/compress_append.c"), "C source file compress_append.c is missing."
    assert os.path.exists("/home/user/compress_append"), "Compiled executable compress_append is missing."
    assert os.access("/home/user/compress_append", os.X_OK), "compress_append is not executable."
    assert os.path.exists("/home/user/backup.sh"), "Bash script backup.sh is missing."
    assert os.path.exists("/home/user/backup.stamp"), "State file backup.stamp is missing."


def test_archive_exists():
    assert os.path.exists("/home/user/master_archive.dat"), "Archive file master_archive.dat is missing."


def test_archive_contents():
    archive_path = "/home/user/master_archive.dat"
    assert os.path.exists(archive_path), "Archive file master_archive.dat is missing."

    records = []
    with open(archive_path, "rb") as f:
        while True:
            len_byte = f.read(1)
            if not len_byte:
                break
            assert len(len_byte) == 1, "Unexpected EOF while reading filename length."
            name_len = struct.unpack("B", len_byte)[0]
            filename_bytes = f.read(name_len)
            assert len(filename_bytes) == name_len, "Unexpected EOF while reading filename."
            filename = filename_bytes.decode("utf-8")
            size_bytes = f.read(4)
            assert len(size_bytes) == 4, "Unexpected EOF while reading compressed payload size."
            comp_size = struct.unpack("<I", size_bytes)[0]
            comp_data = f.read(comp_size)
            assert len(comp_data) == comp_size, "Unexpected EOF while reading compressed data."
            try:
                uncompressed = zlib.decompress(comp_data).decode("utf-8")
            except Exception as e:
                pytest.fail(f"Failed to decompress payload for {filename}: {e}")
            records.append((filename, uncompressed))

    assert len(records) == 4, f"Expected exactly 4 backup records, found {len(records)}."
    first_run = sorted(records[:3], key=lambda x: x[0])
    expected_first_run = [
        ("alpha.txt", "Initial content for alpha file. This needs to be backed up.\n"),
        ("beta.txt", "Beta file is somewhat shorter.\n"),
        ("gamma.txt", "Gamma file is the third file in this directory.\n")
    ]
    for i in range(3):
        assert first_run[i][0] == expected_first_run[i][0], f"Expected {expected_first_run[i][0]} in first run, got {first_run[i][0]}"
        assert first_run[i][1] == expected_first_run[i][1], f"Content mismatch for {first_run[i][0]} in first run."
    assert records[3][0] == "alpha.txt", "The fourth record (incremental backup) should be alpha.txt."
    expected_mod = "Initial content for alpha file. This needs to be backed up.\n[MODIFIED] Additional data appended.\n"
    assert records[3][1] == expected_mod, "Content mismatch for the modified alpha.txt in the incremental backup."


def exercise_archiver(executable):
    with tempfile.TemporaryDirectory() as td:
        token = secrets.token_hex(8)
        first_name = f"first_{token}.txt"
        second_name = f"second_{token}.bin"
        first_path = os.path.join(td, first_name)
        second_path = os.path.join(td, second_name)
        archive = os.path.join(td, "result.dat")
        first_data = b"dynamic text " + secrets.token_bytes(37) + b"\x00tail"
        second_data = secrets.token_bytes(513)
        with open(first_path, "wb") as f:
            f.write(first_data)
        with open(second_path, "wb") as f:
            f.write(second_data)

        subprocess.run([executable, first_path, archive], check=True, timeout=10)
        subprocess.run([executable, second_path, archive], check=True, timeout=10)
        assert parse_archive(archive) == [
            (first_name.encode(), first_data),
            (second_name.encode(), second_data),
        ]
        assert subprocess.run([executable], timeout=10).returncode != 0
        assert subprocess.run([executable, first_path, archive, "extra"], timeout=10).returncode != 0


def test_submitted_executable_behavior():
    exercise_archiver("/home/user/compress_append")


def test_c_source_compiles_and_behaves():
    with tempfile.TemporaryDirectory() as td:
        built = os.path.join(td, "compress_append_from_source")
        subprocess.run(
            ["gcc", "/home/user/compress_append.c", "-o", built, "-lz"],
            check=True,
            timeout=20,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        exercise_archiver(built)


def test_backup_script_behavior_and_archiver_invocation():
    data_dir = "/home/user/data"
    archive = "/home/user/master_archive.dat"
    stamp = "/home/user/backup.stamp"
    executable = "/home/user/compress_append"
    real_executable = "/home/user/compress_append.real-verifier"
    log = os.path.join(tempfile.gettempdir(), "compress_calls_" + secrets.token_hex(8))

    shutil.rmtree(data_dir, ignore_errors=True)
    os.mkdir(data_dir)
    for path in (archive, stamp, log, real_executable):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    token = secrets.token_hex(6)
    names = [f"one_{token}.txt", f"two_{token}.txt"]
    contents = {
        names[0]: ("first dynamic content " + secrets.token_hex(20) + "\n").encode(),
        names[1]: ("second dynamic content " + secrets.token_hex(20) + "\n").encode(),
    }
    for name, content in contents.items():
        with open(os.path.join(data_dir, name), "wb") as f:
            f.write(content)
        os.utime(os.path.join(data_dir, name), (1000000000, 1000000000))
    with open(os.path.join(data_dir, f"ignored_{token}.bin"), "wb") as f:
        f.write(secrets.token_bytes(40))

    os.replace(executable, real_executable)
    try:
        wrapper = f'''#!/bin/bash
printf '%s\\t%s\\n' "$1" "$2" >> {log!r}
exec /home/user/compress_append.real-verifier "$@"
'''
        with open(executable, "w") as f:
            f.write(wrapper)
        os.chmod(executable, 0o755)

        def run_backup():
            result = subprocess.run(
                ["bash", "/home/user/backup.sh"], cwd="/home/user",
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20,
            )
            assert result.returncode == 0, result.stderr.decode(errors="replace")

        run_backup()
        assert os.path.exists(stamp), "backup.sh did not create backup.stamp"
        expected_initial = sorted((n.encode(), contents[n]) for n in names)
        assert sorted(parse_archive(archive)) == expected_initial
        with open(log) as f:
            calls_after_first = [line.rstrip("\n").split("\t") for line in f]
        assert sorted(call[0] for call in calls_after_first) == sorted(os.path.join(data_dir, n) for n in names)
        assert all(call[1] == archive for call in calls_after_first)

        archive_bytes = open(archive, "rb").read()
        run_backup()
        assert open(archive, "rb").read() == archive_bytes, "Unchanged files were backed up again"
        with open(log) as f:
            assert len(f.readlines()) == len(names), "Archiver was invoked for unchanged files"

        changed = names[0]
        changed_content = contents[changed] + b"incremental-" + secrets.token_bytes(24)
        with open(os.path.join(data_dir, changed), "wb") as f:
            f.write(changed_content)
        old_stamp_time = time.time() - 100
        os.utime(stamp, (old_stamp_time, old_stamp_time))
        os.utime(os.path.join(data_dir, changed), None)

        run_backup()
        records = parse_archive(archive)
        assert sorted(records[:2]) == expected_initial
        assert records[2:] == [(changed.encode(), changed_content)], "Incremental run did not append only the modified file"
        with open(log) as f:
            calls = [line.rstrip("\n").split("\t") for line in f]
        assert len(calls) == len(names) + 1
        assert calls[-1] == [os.path.join(data_dir, changed), archive]
        assert os.path.getmtime(stamp) > old_stamp_time, "backup.sh did not update backup.stamp"
    finally:
        try:
            os.remove(executable)
        except FileNotFoundError:
            pass
        if os.path.exists(real_executable):
            os.replace(real_executable, executable)
        try:
            os.remove(log)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
