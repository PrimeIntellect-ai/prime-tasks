#!/bin/bash
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import shutil
import subprocess
import tarfile
import tempfile

HOME = "/home/user"
SOURCE = os.path.join(HOME, "curator.c")
BINARY = os.path.join(HOME, "curator")
ARTIFACTS = os.path.join(HOME, "artifacts")
LOG = os.path.join(HOME, "repo.log")
CSV = os.path.join(HOME, "valid_artifacts.csv")
ARCHIVE = os.path.join(HOME, "curated.tar.gz")
COMPILED_SOURCE = "/tmp/curator_from_source"


def remove_outputs():
    for path in (CSV, ARCHIVE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def run_program(path):
    result = subprocess.run(
        [path], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=15, check=False
    )
    assert result.returncode == 0, (
        f"{path} exited with status {result.returncode}.\n"
        f"stdout: {result.stdout.decode(errors='replace')}\n"
        f"stderr: {result.stderr.decode(errors='replace')}"
    )


def install_fixture():
    shutil.rmtree(ARTIFACTS)
    os.makedirs(ARTIFACTS)

    token = secrets.token_hex(6)
    names = [f"valid_{token}.bin", f"bad_{token}.bin",
             f"missing_{token}.bin", f"also_valid_{token}.bin"]
    magics = [secrets.token_bytes(4) for _ in names]
    descriptions = [
        f"Random valid {token}",
        f"Damaged upload {token}",
        f"Absent upload {token}",
        f"Crème numéro {random.randint(1000, 9999)} {token}",
    ]

    valid_data_1 = magics[0] + secrets.token_bytes(19)
    valid_data_2 = magics[3] + secrets.token_bytes(23)
    with open(os.path.join(ARTIFACTS, names[0]), "wb") as f:
        f.write(valid_data_1)
    wrong_prefix = bytes([magics[1][0] ^ 0xFF]) + magics[1][1:]
    with open(os.path.join(ARTIFACTS, names[1]), "wb") as f:
        f.write(wrong_prefix + secrets.token_bytes(11))
    with open(os.path.join(ARTIFACTS, names[3]), "wb") as f:
        f.write(valid_data_2)

    with open(LOG, "wb") as f:
        for name, magic, description in zip(names, magics, descriptions):
            f.write(b"BEGIN ARTIFACT\n")
            f.write(f"File: {name}\n".encode("ascii"))
            f.write(f"Magic: {magic.hex().upper()}\n".encode("ascii"))
            f.write(b"Desc: " + description.encode("iso-8859-1") + b"\n")
            f.write(b"END ARTIFACT\n")

    expected_lines = [
        "Filename,Magic,Description",
        f"{names[0]},{magics[0].hex().upper()},{descriptions[0]}",
        f"{names[3]},{magics[3].hex().upper()},{descriptions[3]}",
    ]
    expected_files = {
        names[0]: valid_data_1,
        names[3]: valid_data_2,
    }
    return expected_lines, expected_files


def validate_generated_outputs(expected_lines, expected_files):
    assert os.path.isfile(CSV), f"{CSV} does not exist after running the program."
    with open(CSV, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    assert lines == expected_lines, f"Generated CSV is incorrect: {lines!r}"

    assert os.path.isfile(ARCHIVE), f"{ARCHIVE} does not exist after running the program."
    assert tarfile.is_tarfile(ARCHIVE), f"{ARCHIVE} is not a valid tar archive."
    with tarfile.open(ARCHIVE, "r:gz") as tar:
        members = tar.getmembers()
        assert [m.name for m in members] == list(expected_files), (
            f"Archive members are incorrect: {[m.name for m in members]!r}"
        )
        assert all(m.isfile() and "/" not in m.name for m in members), (
            "Archive must contain only regular files at its root."
        )
        for member in members:
            extracted = tar.extractfile(member)
            assert extracted is not None
            assert extracted.read() == expected_files[member.name], (
                f"Archived bytes for {member.name} do not match the repository file."
            )


def test_csv_exists_and_content():
    csv_path = "/home/user/valid_artifacts.csv"
    assert os.path.isfile(csv_path), f"{csv_path} does not exist."

    with open(csv_path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 3, f"Expected 3 lines in CSV (header + 2 valid artifacts), found {len(lines)}."

    assert lines[0] == "Filename,Magic,Description", "CSV header is incorrect."
    assert lines[1] == "file1.bin,CAFEBABE,First valid file", "First valid artifact entry is incorrect."
    assert lines[2] == "file3.bin,12345678,Third valid file with special char: É", "Second valid artifact entry is incorrect or not properly UTF-8 encoded."


def test_tar_gz_exists_and_content():
    tar_path = "/home/user/curated.tar.gz"
    assert os.path.isfile(tar_path), f"{tar_path} does not exist."

    assert tarfile.is_tarfile(tar_path), f"{tar_path} is not a valid tar archive."

    with tarfile.open(tar_path, "r:gz") as tar:
        members = tar.getnames()

    expected_members = {"file1.bin", "file3.bin"}
    actual_members = set(members)

    assert actual_members == expected_members, f"Archive contents mismatch. Expected {expected_members}, found {actual_members}. Make sure there are no directory paths."

    with tarfile.open(tar_path, "r:gz") as tar:
        detailed_members = tar.getmembers()
        assert all(m.isfile() and "/" not in m.name for m in detailed_members), (
            "Archive must contain only regular files at its root."
        )
        for member in detailed_members:
            archived = tar.extractfile(member)
            assert archived is not None
            with open(os.path.join(ARTIFACTS, member.name), "rb") as original:
                assert archived.read() == original.read(), (
                    f"Archived bytes for {member.name} do not match the artifact."
                )


def main():
    assert os.path.isfile(SOURCE), f"{SOURCE} does not exist."
    assert os.path.isfile(BINARY), f"{BINARY} does not exist."
    assert os.access(BINARY, os.X_OK), f"{BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not a compiled executable."

    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE, "-o", COMPILED_SOURCE],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20, check=False
    )
    assert compile_result.returncode == 0, (
        "curator.c does not compile successfully:\n" +
        compile_result.stderr.decode(errors="replace")
    )

    backup_root = tempfile.mkdtemp(prefix="curator-verifier-")
    backup_artifacts = os.path.join(backup_root, "artifacts")
    backup_log = os.path.join(backup_root, "repo.log")
    shutil.copytree(ARTIFACTS, backup_artifacts)
    shutil.copy2(LOG, backup_log)

    try:
        for executable in (BINARY, COMPILED_SOURCE):
            expected_lines, expected_files = install_fixture()
            remove_outputs()
            run_program(executable)
            validate_generated_outputs(expected_lines, expected_files)
    finally:
        shutil.rmtree(ARTIFACTS, ignore_errors=True)
        shutil.copytree(backup_artifacts, ARTIFACTS)
        shutil.copy2(backup_log, LOG)
        shutil.rmtree(backup_root, ignore_errors=True)

    remove_outputs()
    run_program(BINARY)
    test_csv_exists_and_content()
    test_tar_gz_exists_and_content()


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
