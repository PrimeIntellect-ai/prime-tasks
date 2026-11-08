#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import shutil
import subprocess
import tarfile
import tempfile
import uuid
import zipfile


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def machine_type(path):
    result = subprocess.run(
        ["readelf", "-h", path], text=True, capture_output=True, check=True
    )
    for line in result.stdout.splitlines():
        if "Machine:" in line:
            return line.split("Machine:", 1)[1].strip().replace(" ", "_")
    raise AssertionError(f"No Machine field found for {path}")


def assert_elf_archive(path, archive_kind, expected_machine):
    with tempfile.TemporaryDirectory() as tmp:
        if archive_kind == "tar":
            subprocess.run(["tar", "-tzf", path], check=True, capture_output=True)
            with tarfile.open(path, "r:gz") as archive:
                archive.extractall(tmp)
        else:
            subprocess.run(["unzip", "-t", path], check=True, capture_output=True)
            with zipfile.ZipFile(path) as archive:
                archive.extractall(tmp)

        found = []
        for root, _, files in os.walk(tmp):
            for name in files:
                candidate = os.path.join(root, name)
                result = subprocess.run(
                    ["readelf", "-h", candidate], capture_output=True, text=True
                )
                if result.returncode == 0:
                    found.append(machine_type(candidate))
        assert found == [expected_machine], f"Unexpected ELF contents in {path}: {found}"


def test_quarantine_files():
    quarantine_dir = "/home/user/quarantine"
    assert os.path.isdir(quarantine_dir), "Quarantine directory does not exist."

    expected_files = ["corrupt_data.tar.gz", "bad_archive.zip"]
    for f in expected_files:
        file_path = os.path.join(quarantine_dir, f)
        assert os.path.isfile(file_path), f"Corrupt file {f} is not in quarantine."

    assert subprocess.run(
        ["tar", "-tzf", os.path.join(quarantine_dir, "corrupt_data.tar.gz")],
        capture_output=True,
    ).returncode != 0, "Quarantined corrupt_data.tar.gz is not corrupt."
    assert subprocess.run(
        ["unzip", "-t", os.path.join(quarantine_dir, "bad_archive.zip")],
        capture_output=True,
    ).returncode != 0, "Quarantined bad_archive.zip is not corrupt."


def test_curated_artifacts_elf_x86():
    dir_path = "/home/user/curated_artifacts/ELF/Advanced_Micro_Devices_X86-64"
    assert os.path.isdir(dir_path), f"Directory {dir_path} does not exist."

    file_path = os.path.join(dir_path, "app_x86.tar.gz")
    assert os.path.isfile(file_path), f"File app_x86.tar.gz is not in {dir_path}."
    assert_elf_archive(file_path, "tar", "Advanced_Micro_Devices_X86-64")


def test_curated_artifacts_elf_arm():
    dir_path = "/home/user/curated_artifacts/ELF/ARM"
    assert os.path.isdir(dir_path), f"Directory {dir_path} does not exist."

    file_path = os.path.join(dir_path, "firmware_arm.zip")
    assert os.path.isfile(file_path), f"File firmware_arm.zip is not in {dir_path}."
    assert_elf_archive(file_path, "zip", "ARM")


def test_curated_artifacts_gcode_abs():
    dir_path = "/home/user/curated_artifacts/GCode/ABS"
    assert os.path.isdir(dir_path), f"Directory {dir_path} does not exist."

    file_path = os.path.join(dir_path, "model_abs.tar.gz")
    assert os.path.isfile(file_path), f"File model_abs.tar.gz is not in {dir_path}."
    subprocess.run(["tar", "-tzf", file_path], check=True, capture_output=True)
    with tarfile.open(file_path, "r:gz") as archive:
        members = [m for m in archive.getmembers() if m.isfile()]
        assert len(members) == 1
        contents = archive.extractfile(members[0]).read().decode()
    assert re.search(r"^; filament_type = ABS$", contents, re.MULTILINE)


def test_curation_log():
    log_path = "/home/user/curation.log"
    assert os.path.isfile(log_path), "Curation log file does not exist."

    with open(log_path, "r") as f:
        log_contents = f.read()

    expected_lines = [
        "[VALID] app_x86.tar.gz - ELF - Advanced_Micro_Devices_X86-64",
        "[VALID] firmware_arm.zip - ELF - ARM",
        "[VALID] model_abs.tar.gz - GCode - ABS",
        "[CORRUPT] corrupt_data.tar.gz - UNKNOWN - N/A",
        "[CORRUPT] bad_archive.zip - UNKNOWN - N/A"
    ]

    for line in expected_lines:
        assert line in log_contents, f"Expected log line '{line}' not found in {log_path}."


def test_originals_were_removed_from_incoming_tree():
    original_names = {
        "app_x86.tar.gz", "firmware_arm.zip", "model_abs.tar.gz",
        "corrupt_data.tar.gz", "bad_archive.zip"
    }
    remaining = set()
    for root, _, files in os.walk("/home/user/incoming_artifacts"):
        remaining.update(original_names.intersection(files))
    assert not remaining, f"Original archives were not moved: {sorted(remaining)}"


def test_script_recursively_processes_unseen_archives_and_preserves_bytes():
    script = "/home/user/curate.sh"
    assert os.path.isfile(script), "curate.sh does not exist."
    assert os.path.getsize(script) > 0, "curate.sh is empty."
    subprocess.run(["bash", "-n", script], check=True, capture_output=True)

    token = uuid.uuid4().hex
    incoming = "/home/user/incoming_artifacts"
    deep_elf = os.path.join(incoming, "verification", token, "elf", "nested")
    deep_other = os.path.join(incoming, "verification", token, "other", "nested")
    os.makedirs(deep_elf, exist_ok=True)
    os.makedirs(deep_other, exist_ok=True)

    elf_name = f"runtime_{token}.tar.gz"
    gcode_name = f"print_{token}.zip"
    bad_tar_name = f"damaged_{token}.tar.gz"
    bad_zip_name = f"broken_{token}.zip"
    filament = f"VERIFY_{token}"

    elf_source = os.path.join(deep_elf, f"binary_{token}")
    shutil.copyfile("/bin/true", elf_source)
    os.chmod(elf_source, 0o755)
    expected_machine = machine_type(elf_source)
    elf_archive = os.path.join(deep_elf, elf_name)
    with tarfile.open(elf_archive, "w:gz") as archive:
        archive.add(elf_source, arcname=os.path.basename(elf_source))
    os.remove(elf_source)

    gcode_source = os.path.join(deep_other, f"part_{token}.gcode")
    with open(gcode_source, "w") as f:
        f.write("; generated verification input\n")
        f.write(f"; filament_type = {filament}\n")
        f.write("G28\n")
    gcode_archive = os.path.join(deep_other, gcode_name)
    with zipfile.ZipFile(gcode_archive, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.write(gcode_source, arcname=os.path.basename(gcode_source))
    os.remove(gcode_source)

    bad_tar = os.path.join(deep_other, bad_tar_name)
    bad_zip = os.path.join(deep_elf, bad_zip_name)
    with open(bad_tar, "wb") as f:
        f.write(b"not a gzip archive\x00" + os.urandom(73))
    with open(bad_zip, "wb") as f:
        f.write(b"not a zip archive\x00" + os.urandom(79))

    source_paths = [elf_archive, gcode_archive, bad_tar, bad_zip]
    expected_hashes = {os.path.basename(p): sha256(p) for p in source_paths}

    old_paths = [
        "/home/user/curated_artifacts/ELF/Advanced_Micro_Devices_X86-64/app_x86.tar.gz",
        "/home/user/curated_artifacts/ELF/ARM/firmware_arm.zip",
        "/home/user/curated_artifacts/GCode/ABS/model_abs.tar.gz",
        "/home/user/quarantine/corrupt_data.tar.gz",
        "/home/user/quarantine/bad_archive.zip",
    ]
    old_hashes = {p: sha256(p) for p in old_paths}
    with open("/home/user/curation.log", "rb") as f:
        old_log = f.read()

    subprocess.run(["bash", script], check=True, timeout=30, capture_output=True, text=True)

    for path in source_paths:
        assert not os.path.exists(path), f"Input archive was not moved: {path}"

    elf_dest = os.path.join(
        "/home/user/curated_artifacts/ELF", expected_machine, elf_name
    )
    gcode_dest = os.path.join(
        "/home/user/curated_artifacts/GCode", filament, gcode_name
    )
    bad_tar_dest = os.path.join("/home/user/quarantine", bad_tar_name)
    bad_zip_dest = os.path.join("/home/user/quarantine", bad_zip_name)
    destinations = [elf_dest, gcode_dest, bad_tar_dest, bad_zip_dest]

    for path in destinations:
        assert os.path.isfile(path), f"Expected moved archive is missing: {path}"
        assert sha256(path) == expected_hashes[os.path.basename(path)], \
            f"Archive bytes changed or were fabricated: {path}"

    assert_elf_archive(elf_dest, "tar", expected_machine)
    subprocess.run(["unzip", "-t", gcode_dest], check=True, capture_output=True)
    with zipfile.ZipFile(gcode_dest) as archive:
        names = [n for n in archive.namelist() if not n.endswith("/")]
        assert len(names) == 1
        gcode_contents = archive.read(names[0]).decode()
    assert re.search(
        rf"^; filament_type = {re.escape(filament)}$", gcode_contents, re.MULTILINE
    )
    assert subprocess.run(["tar", "-tzf", bad_tar_dest], capture_output=True).returncode != 0
    assert subprocess.run(["unzip", "-t", bad_zip_dest], capture_output=True).returncode != 0

    for path, digest in old_hashes.items():
        assert os.path.isfile(path), f"Previously curated artifact disappeared: {path}"
        assert sha256(path) == digest, f"Previously curated artifact changed: {path}"

    with open("/home/user/curation.log", "rb") as f:
        new_log = f.read()
    assert new_log.startswith(old_log), "curate.sh did not append to the existing log."
    appended = new_log[len(old_log):].decode().splitlines()
    expected_lines = {
        f"[VALID] {elf_name} - ELF - {expected_machine}",
        f"[VALID] {gcode_name} - GCode - {filament}",
        f"[CORRUPT] {bad_tar_name} - UNKNOWN - N/A",
        f"[CORRUPT] {bad_zip_name} - UNKNOWN - N/A",
    }
    assert set(appended) == expected_lines and len(appended) == 4, \
        f"Incorrect appended log records: {appended}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
