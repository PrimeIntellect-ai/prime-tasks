#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import io
import os
import re
import secrets
import struct
import subprocess
import tarfile
import time

import pytest
from elftools.elf.elffile import ELFFile

SPOOL = "/home/user/spool"
ARCHIVE = "/home/user/archive"
WAL = "/home/user/config_wal.log"
CASES = {}


def write_complete(path, data):
    mode = "wb" if isinstance(data, bytes) else "w"
    kwargs = {} if isinstance(data, bytes) else {"encoding": "utf-8"}
    with open(path, mode, **kwargs) as f:
        f.write(data)
        f.flush()
        os.fsync(f.fileno())


def patch_machine(data, machine):
    result = bytearray(data)
    assert result[:4] == b"\x7fELF"
    endian = "<" if result[5] == 1 else ">"
    struct.pack_into(endian + "H", result, 18, machine)
    return bytes(result)


def elf_machine(data):
    return ELFFile(io.BytesIO(data))["e_machine"]


def expected_wal_line(filename, file_type, metadata):
    pattern = re.compile(
        r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] \| "
        + re.escape(filename)
        + r" \| "
        + re.escape(file_type)
        + r" \| "
        + re.escape(metadata)
        + r"$",
        re.MULTILINE,
    )
    return pattern


def watcher_process_running():
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\x00", b" ").decode("utf-8", "ignore")
            if "/home/user/fleet_watcher.py" in cmdline:
                return True
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return False


@pytest.fixture(scope="session", autouse=True)
def inject_files_and_wait():
    assert os.path.isfile("/home/user/fleet_watcher.py"), "fleet_watcher.py is missing."
    assert os.path.isfile("/home/user/ready.flag"), "ready.flag is missing."
    assert watcher_process_running(), "fleet_watcher.py is not running."
    os.makedirs(SPOOL, exist_ok=True)
    os.makedirs(ARCHIVE, exist_ok=True)

    token = secrets.token_hex(8)
    random_machine = "Fleet_" + secrets.token_hex(10)
    random_job = f"job_{token}.gcode"
    random_firmware = f"firmware_{token}.elf"

    fixed_gcode = (
        "; BEGIN CONFIG\n"
        "; MATERIAL: PLA\n"
        "; MACHINE_TYPE: Ender_3_Pro\n"
        "; END CONFIG\n"
        "G28\n"
        f"; payload {secrets.token_hex(24)}\n"
    ).encode()
    random_gcode = (
        "; BEGIN CONFIG\n"
        "; PROFILE: verification\n"
        f"; MACHINE_TYPE: {random_machine}\n"
        "; NOZZLE: 0.4\n"
        "; END CONFIG\n"
        "; MACHINE_TYPE: Wrong_Outside_Block\n"
        f"G1 X{secrets.randbelow(200)} Y{secrets.randbelow(200)}\n"
        f"; unique {secrets.token_hex(32)}\n"
    ).encode()

    source = f"/tmp/verifier_fw_{token}.c"
    binary = f"/tmp/verifier_fw_{token}.elf"
    with open(source, "w", encoding="utf-8") as f:
        f.write("int main(void) { return 0; }\n")
    subprocess.run(["gcc", source, "-o", binary], check=True)
    with open(binary, "rb") as f:
        base_elf = f.read()

    fixed_elf = patch_machine(base_elf, 62)
    random_arch_number = secrets.choice([3, 40, 83, 183])
    random_elf = patch_machine(base_elf, random_arch_number)
    random_arch = elf_machine(random_elf)
    assert elf_machine(fixed_elf) == "EM_X86_64"
    assert isinstance(random_arch, str) and random_arch.startswith("EM_")

    CASES.update({
        "print_job.gcode": (fixed_gcode, "GCODE", "Ender_3_Pro"),
        "firmware_update.elf": (fixed_elf, "ELF", "EM_X86_64"),
        random_job: (random_gcode, "GCODE", random_machine),
        random_firmware: (random_elf, "ELF", random_arch),
    })

    # Remove any pre-fabricated results for these names and start a clean WAL window.
    for filename in CASES:
        for path in (os.path.join(SPOOL, filename), os.path.join(ARCHIVE, filename + ".tar.gz")):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
    if os.path.exists(WAL):
        os.truncate(WAL, 0)

    for filename, (data, _, _) in CASES.items():
        write_complete(os.path.join(SPOOL, filename), data)

    deadline = time.time() + 30
    while time.time() < deadline:
        archives_ready = all(
            os.path.isfile(os.path.join(ARCHIVE, filename + ".tar.gz"))
            for filename in CASES
        )
        sources_removed = all(not os.path.exists(os.path.join(SPOOL, filename)) for filename in CASES)
        try:
            with open(WAL, "r", encoding="utf-8") as f:
                wal = f.read()
        except FileNotFoundError:
            wal = ""
        entries_ready = all(
            expected_wal_line(filename, file_type, metadata).search(wal)
            for filename, (_, file_type, metadata) in CASES.items()
        )
        if archives_ready and sources_removed and entries_ready:
            return
        time.sleep(0.2)

    pytest.fail("Watcher did not process all injected files within 30 seconds.")


def assert_archive_preserves(filename):
    expected = CASES[filename][0]
    archive_path = os.path.join(ARCHIVE, filename + ".tar.gz")
    assert os.path.isfile(archive_path), f"Archive {archive_path} is missing."
    assert tarfile.is_tarfile(archive_path), f"{archive_path} is not a valid tar file."
    with tarfile.open(archive_path, "r:gz") as tar:
        members = tar.getnames()
        assert filename in members, f"{filename} is missing from the tar archive."
        assert os.path.join(SPOOL, filename) not in members, "Archive should not contain absolute paths."
        member = tar.getmember(filename)
        assert member.isfile(), f"{filename} is not a regular archived file."
        extracted = tar.extractfile(member)
        assert extracted is not None
        assert extracted.read() == expected, f"Archive did not preserve the contents of {filename}."


def test_watcher_script_exists():
    assert os.path.isfile("/home/user/fleet_watcher.py"), "fleet_watcher.py is missing."
    assert os.path.isfile("/home/user/ready.flag"), "ready.flag is missing."


def test_watcher_script_is_python_and_running():
    with open("/home/user/fleet_watcher.py", "rb") as f:
        source = f.read()
    compile(source, "/home/user/fleet_watcher.py", "exec")
    assert watcher_process_running(), "fleet_watcher.py stopped running."


def test_spool_directory_empty():
    spool_dir = "/home/user/spool"
    assert os.path.isdir(spool_dir), f"{spool_dir} is missing."
    files_in_spool = os.listdir(spool_dir)
    assert "print_job.gcode" not in files_in_spool, "print_job.gcode was not removed from spool."
    assert "firmware_update.elf" not in files_in_spool, "firmware_update.elf was not removed from spool."
    for filename in CASES:
        assert filename not in files_in_spool, f"{filename} was not removed from spool."


def test_archive_gcode_file():
    archive_path = "/home/user/archive/print_job.gcode.tar.gz"
    assert os.path.isfile(archive_path), f"Archive {archive_path} is missing."

    assert tarfile.is_tarfile(archive_path), f"{archive_path} is not a valid tar file."
    with tarfile.open(archive_path, "r:gz") as tar:
        members = tar.getnames()
        assert "print_job.gcode" in members, "print_job.gcode is missing from the tar archive."
        assert "/home/user/spool/print_job.gcode" not in members, "Archive should not contain absolute paths."
    assert_archive_preserves("print_job.gcode")


def test_archive_elf_file():
    archive_path = "/home/user/archive/firmware_update.elf.tar.gz"
    assert os.path.isfile(archive_path), f"Archive {archive_path} is missing."

    assert tarfile.is_tarfile(archive_path), f"{archive_path} is not a valid tar file."
    with tarfile.open(archive_path, "r:gz") as tar:
        members = tar.getnames()
        assert "firmware_update.elf" in members, "firmware_update.elf is missing from the tar archive."
        assert "/home/user/spool/firmware_update.elf" not in members, "Archive should not contain absolute paths."
    assert_archive_preserves("firmware_update.elf")


def test_randomized_archives_preserve_inputs():
    for filename in CASES:
        assert_archive_preserves(filename)


def test_wal_log_contents():
    log_path = "/home/user/config_wal.log"
    assert os.path.isfile(log_path), f"WAL log {log_path} is missing."

    with open(log_path, "r", encoding="utf-8") as f:
        content = f.read()

    gcode_pattern = re.compile(r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] \| print_job\.gcode \| GCODE \| Ender_3_Pro$", re.MULTILINE)
    elf_pattern = re.compile(r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] \| firmware_update\.elf \| ELF \| EM_X86_64$", re.MULTILINE)

    assert gcode_pattern.search(content), "WAL log is missing the correct entry for print_job.gcode."
    assert elf_pattern.search(content), "WAL log is missing the correct entry for firmware_update.elf."

    strict_pattern = re.compile(
        r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] \| ([^|/]+) \| (GCODE|ELF) \| ([^|\r\n]+)$"
    )
    for line in content.splitlines():
        if not line:
            continue
        match = strict_pattern.fullmatch(line)
        assert match, f"Malformed WAL line: {line!r}"
        datetime.datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S")

    for filename, (_, file_type, metadata) in CASES.items():
        assert expected_wal_line(filename, file_type, metadata).search(content), (
            f"WAL log is missing the derived entry for {filename}."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
