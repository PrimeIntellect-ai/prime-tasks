#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_backup.py
import gzip
import os
import pwd
import secrets
import stat
import subprocess
import tarfile
import time

HOME = "/home/user"
BASE = "/home/user/db_backups"
SOURCE = "/home/user/backup.go"
BINARY = "/tmp/backup_submission"
ARCHIVE = "/home/user/archive.tar.gz"
LOOP_LOG = "/home/user/loop_log.txt"


def assert_go_program():
    st = os.lstat(SOURCE)
    assert stat.S_ISREG(st.st_mode), f"{SOURCE} must be a regular Go source file"
    assert st.st_size > 0, f"{SOURCE} is empty"
    result = subprocess.run(
        ["go", "build", "-o", BINARY, SOURCE],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"backup.go did not compile:\n{result.stdout}"


def remove_outputs():
    for path in (ARCHIVE, LOOP_LOG):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass


def run_submission(timeout=30):
    user = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    proc = subprocess.Popen(
        [BINARY],
        cwd=HOME,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        preexec_fn=demote,
    )
    deadline = time.monotonic() + timeout
    peak_kib = 0
    while proc.poll() is None:
        try:
            with open(f"/proc/{proc.pid}/status", "r") as status:
                for line in status:
                    if line.startswith(("VmRSS:", "VmHWM:")):
                        peak_kib = max(peak_kib, int(line.split()[1]))
        except FileNotFoundError:
            pass
        if time.monotonic() >= deadline:
            proc.kill()
            proc.wait()
            raise AssertionError("backup program did not terminate; possible symlink loop")
        time.sleep(0.01)
    assert proc.returncode == 0, f"backup program exited with status {proc.returncode}"
    return peak_kib


def read_log():
    assert os.path.exists(LOOP_LOG), f"File {LOOP_LOG} does not exist."
    with open(LOOP_LOG, "r") as f:
        return [line.strip() for line in f if line.strip()]


def assert_archive(expected_files):
    assert os.path.exists(ARCHIVE), f"Archive {ARCHIVE} does not exist."
    assert tarfile.is_tarfile(ARCHIVE), f"File {ARCHIVE} is not a valid tar archive."
    try:
        with tarfile.open(ARCHIVE, "r:gz"):
            pass
    except tarfile.ReadError as exc:
        raise AssertionError(f"Archive {ARCHIVE} is not gzip-compressed.") from exc

    with tarfile.open(ARCHIVE, "r:gz") as tar:
        members = tar.getmembers()
        file_members = [m for m in members if m.isfile()]
        archived_paths = set(m.name for m in file_members)
        assert archived_paths == set(expected_files), (
            f"Archive contains incorrect files. Expected {set(expected_files)}, "
            f"found {archived_paths}."
        )
        assert len(file_members) == len(expected_files), "Archive contains duplicate file entries."
        for member in file_members:
            extracted = tar.extractfile(member)
            assert extracted is not None, f"Could not extract file {member.name} from archive."
            content = extracted.read()
            assert content == expected_files[member.name], (
                f"Content of {member.name} in archive does not match original."
            )


def verify_original_fixture():
    remove_outputs()
    run_submission()

    lines = read_log()
    expected_line = "/home/user/db_backups/cluster2/data/link_back"
    assert len(lines) == 1, f"Expected exactly 1 line in {LOOP_LOG}, found {len(lines)}."
    assert lines[0] == expected_line, f"Expected line to be '{expected_line}', found '{lines[0]}'."

    expected_files = {
        "cluster1/node_a/wal_001.log": b"WAL\x01\x00\x11\x22",
        "cluster2/data/wal_003.log": b"WAL\x01\x99\x88\x77",
        "external/wal_004.log": b"WAL\x01\xAA\xBB\xCC",
    }
    assert_archive(expected_files)


def verify_dynamic_fixture():
    token = secrets.token_hex(8)
    dynamic_name = f"verify_{token}"
    dynamic_root = os.path.join(BASE, dynamic_name)
    deep = os.path.join(dynamic_root, "one", "two")
    os.makedirs(deep)

    local_rel = f"{dynamic_name}/one/two/wal_{token}.log"
    local_content = b"WAL\x01" + secrets.token_bytes(37)
    with open(os.path.join(deep, f"wal_{token}.log"), "wb") as f:
        f.write(local_content)

    with open(os.path.join(deep, f"corrupt_{token}.log"), "wb") as f:
        f.write(b"WAL\x02" + secrets.token_bytes(19))
    with open(os.path.join(deep, f"short_{token}.log"), "wb") as f:
        f.write(b"WAL")

    # A large sparse invalid file checks that the program does not load a whole
    # file merely to inspect its four-byte header.
    huge_path = os.path.join(dynamic_root, f"huge_invalid_{token}.log")
    with open(huge_path, "wb") as f:
        f.write(b"BAD!")
        f.seek(256 * 1024 * 1024 - 1)
        f.write(b"\x00")

    loop_path = os.path.join(deep, f"loop_{token}")
    os.symlink(dynamic_root, loop_path)

    external_dir = os.path.join(HOME, f"external_verify_{token}")
    os.makedirs(external_dir)
    external_content = b"WAL\x01" + secrets.token_bytes(29)
    external_file = f"external_wal_{token}.log"
    with open(os.path.join(external_dir, external_file), "wb") as f:
        f.write(external_content)
    with open(os.path.join(external_dir, f"external_bad_{token}.log"), "wb") as f:
        f.write(b"NOPE" + secrets.token_bytes(11))

    external_link_name = f"external_{token}"
    os.symlink(external_dir, os.path.join(BASE, external_link_name))

    remove_outputs()
    peak_kib = run_submission()
    assert peak_kib < 192 * 1024, (
        f"backup program used {peak_kib} KiB while checking a sparse invalid file; "
        "read only the header needed for validation"
    )

    expected_loops = {
        "/home/user/db_backups/cluster2/data/link_back",
        os.path.abspath(loop_path),
    }
    lines = read_log()
    assert len(lines) == len(expected_loops), (
        f"Expected exactly {len(expected_loops)} loop entries, found {len(lines)}: {lines}"
    )
    assert set(lines) == expected_loops, f"Incorrect loop log entries: {lines}"

    expected_files = {
        "cluster1/node_a/wal_001.log": b"WAL\x01\x00\x11\x22",
        "cluster2/data/wal_003.log": b"WAL\x01\x99\x88\x77",
        "external/wal_004.log": b"WAL\x01\xAA\xBB\xCC",
        local_rel: local_content,
        f"{external_link_name}/{external_file}": external_content,
    }
    assert_archive(expected_files)


assert_go_program()
verify_original_fixture()
verify_dynamic_fixture()
PY_EOF

python3 /tmp/verify_backup.py
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
