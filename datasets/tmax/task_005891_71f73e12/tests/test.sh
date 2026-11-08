#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import subprocess
import tarfile
import tempfile
import uuid

import pytest

HOME = "/home/user"
CSV_PATH = os.path.join(HOME, "curated_artifacts.csv")
BACKUP_PATH = os.path.join(HOME, "backups", "csv_backup.tar.gz")


def read_csv_lines(path=CSV_PATH):
    with open(path, "rb") as f:
        data = f.read()
    assert b"\r" not in data, "CSV contains non-UNIX line endings"
    text = data.decode("utf-8")
    assert not text or text.endswith("\n"), "CSV does not end with a UNIX newline"
    return [line for line in text.splitlines() if line]


def write_utf16_log(path, records, trailing_comma=True):
    lines = []
    for index, record in enumerate(records):
        line = json.dumps(record, ensure_ascii=False, separators=(",", ":"))
        if trailing_comma and index % 2 == 0:
            line += ","
        lines.append(line)
    with open(path, "wb") as f:
        f.write(("\n".join(lines) + "\n").encode("utf-16le"))


def make_fixture(directory, token):
    records = [
        {"id": "DYN-A-" + token, "note": "Résumé dynamique " + token},
        {"id": "DYN-B-" + token, "note": "Secürity Δ " + token},
        {"id": "DYN-C-" + token, "note": "Plain note " + token},
    ]
    write_utf16_log(os.path.join(directory, "artifacts.log"), records[:2])
    write_utf16_log(os.path.join(directory, "artifacts.log.7"), records[2:])
    write_utf16_log(
        os.path.join(directory, "unrelated.log"),
        [{"id": "MUST-NOT-APPEAR-" + token, "note": "ignored"}],
    )
    return [record["id"] + "," + record["note"] for record in records]


def run_curator(executable, input_directory, expected):
    if os.path.exists(CSV_PATH):
        os.unlink(CSV_PATH)
    result = subprocess.run(
        [executable, input_directory],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
        check=False,
    )
    assert result.returncode == 0, (
        f"{executable} failed with exit code {result.returncode}: "
        + result.stderr.decode("utf-8", "replace")
    )
    assert os.path.isfile(CSV_PATH), "Curator did not create curated_artifacts.csv"
    assert sorted(read_csv_lines()) == sorted(expected)


def archive_contains_exact_csv(expected_bytes):
    assert os.path.isfile(BACKUP_PATH), "The backup file is missing"
    try:
        with tarfile.open(BACKUP_PATH, "r:gz") as archive:
            matching = []
            for member in archive.getmembers():
                if member.isfile() and member.name.endswith("curated_artifacts.csv"):
                    extracted = archive.extractfile(member)
                    if extracted is not None:
                        matching.append(extracted.read())
            assert matching, "The backup archive does not contain curated_artifacts.csv"
            assert expected_bytes in matching, "The backup does not contain the current CSV contents"
    except tarfile.TarError as exc:
        pytest.fail(f"The backup is not a valid tar.gz archive: {exc}")


def test_00_original_final_state_assertions():
    assert os.path.isfile("/home/user/curator.c"), "The C program /home/user/curator.c is missing."

    assert os.path.isfile("/home/user/curator"), "The compiled binary /home/user/curator is missing."
    assert os.access("/home/user/curator", os.X_OK), "The binary /home/user/curator is not executable."
    with open("/home/user/curator", "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/curator is not a compiled ELF binary"

    script_path = "/home/user/process_and_backup.sh"
    assert os.path.isfile(script_path), f"The bash script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"The bash script {script_path} is not executable."

    assert os.path.isfile(CSV_PATH), f"The output file {CSV_PATH} is missing."
    expected_lines = [
        "BIN-001,Initial release résumé",
        "BIN-002,Patch update",
        "BIN-003,Secürity fix",
        "BIN-004,Deprecated",
    ]
    assert sorted(read_csv_lines()) == sorted(expected_lines), (
        f"The contents of {CSV_PATH} do not match the expected output."
    )

    assert os.path.isfile(BACKUP_PATH), f"The backup file {BACKUP_PATH} is missing."
    try:
        with tarfile.open(BACKUP_PATH, "r:gz") as archive:
            assert any(name.endswith("curated_artifacts.csv") for name in archive.getnames()), (
                "The backup archive does not contain curated_artifacts.csv."
            )
    except tarfile.TarError:
        pytest.fail(f"The file {BACKUP_PATH} is not a valid tar.gz archive.")


def test_10_binary_and_c_source_process_runtime_generated_inputs():
    token = uuid.uuid4().hex
    with tempfile.TemporaryDirectory(prefix="curator-input-") as input_directory:
        expected = make_fixture(input_directory, token)
        run_curator("/home/user/curator", input_directory, expected)

        rebuilt = os.path.join(input_directory, "rebuilt-curator")
        compilation = subprocess.run(
            ["gcc", "/home/user/curator.c", "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
            check=False,
        )
        assert compilation.returncode == 0, (
            "curator.c does not compile: " + compilation.stderr.decode("utf-8", "replace")
        )
        run_curator(rebuilt, input_directory, expected)


def test_20_script_runs_curator_and_refreshes_incremental_backup():
    token = uuid.uuid4().hex
    incoming = "/home/user/incoming"
    os.makedirs(incoming, exist_ok=True)
    for name in os.listdir(incoming):
        path = os.path.join(incoming, name)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)

    first_records = [
        {"id": "SCRIPT-A-" + token, "note": "Première entrée " + token},
        {"id": "SCRIPT-B-" + token, "note": "München " + token},
    ]
    write_utf16_log(os.path.join(incoming, "artifacts.log"), first_records)
    first_expected = [record["id"] + "," + record["note"] for record in first_records]

    for path in (CSV_PATH, BACKUP_PATH):
        if os.path.exists(path):
            os.unlink(path)

    real_curator = "/home/user/curator.real-for-verifier"
    marker = "/tmp/curator-invocations-" + token
    os.replace("/home/user/curator", real_curator)
    try:
        with open("/home/user/curator", "w", encoding="utf-8") as wrapper:
            wrapper.write(
                "#!/bin/sh\n"
                f"printf '%s\\n' \"$#\" \"$@\" >> {marker}\n"
                f"exec {real_curator} \"$@\"\n"
            )
        os.chmod("/home/user/curator", 0o755)

        first_run = subprocess.run(
            ["/home/user/process_and_backup.sh"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=25,
            check=False,
        )
        assert first_run.returncode == 0, first_run.stderr.decode("utf-8", "replace")
        assert sorted(read_csv_lines()) == sorted(first_expected)
        with open(CSV_PATH, "rb") as f:
            archive_contains_exact_csv(f.read())

        os.unlink(os.path.join(incoming, "artifacts.log"))
        second_record = {"id": "SCRIPT-C-" + token, "note": "更新 " + token}
        write_utf16_log(os.path.join(incoming, "artifacts.log.2"), [second_record])

        second_run = subprocess.run(
            ["/home/user/process_and_backup.sh"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=25,
            check=False,
        )
        assert second_run.returncode == 0, second_run.stderr.decode("utf-8", "replace")
        final_expected = first_expected + [second_record["id"] + "," + second_record["note"]]
        assert sorted(read_csv_lines()) == sorted(final_expected)
        with open(CSV_PATH, "rb") as f:
            archive_contains_exact_csv(f.read())

        with open(marker, "r", encoding="utf-8") as f:
            invocation_lines = [line.rstrip("\n") for line in f]
        assert invocation_lines.count("1") >= 2
        assert invocation_lines.count("/home/user/incoming") >= 2, (
            "process_and_backup.sh did not invoke curator with /home/user/incoming"
        )
    finally:
        if os.path.exists("/home/user/curator"):
            os.unlink("/home/user/curator")
        if os.path.exists(real_curator):
            os.replace(real_curator, "/home/user/curator")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
