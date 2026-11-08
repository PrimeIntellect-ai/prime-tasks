#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tarfile
import tempfile
import uuid


def test_c_program_exists():
    """Verify that the C source code file was created."""
    c_file = "/home/user/process_data.c"
    assert os.path.isfile(c_file), f"C source file missing at {c_file}"


def test_executable_exists():
    """Verify that the compiled executable exists and is executable."""
    exe_file = "/home/user/process_data"
    assert os.path.isfile(exe_file), f"Executable missing at {exe_file}"
    assert os.access(exe_file, os.X_OK), f"File {exe_file} is not executable"


def test_filtered_dataset_csv():
    """Verify the contents of the filtered dataset CSV."""
    csv_file = "/home/user/filtered_dataset.csv"
    assert os.path.isfile(csv_file), f"Filtered dataset missing at {csv_file}"

    with open(csv_file, "r", encoding="utf-8") as f:
        content = f.read().strip().splitlines()

    expected_content = [
        "ID,Timestamp,Sensor,Value,Notes",
        "2,2023-01-01T10:05,TEMP_01,26.1,High",
        "5,2023-01-01T10:20,TEMP_01,28.4,Critical",
        "7,2023-01-01T10:30,TEMP_01,25.5,High"
    ]

    assert content == expected_content, "The filtered dataset does not contain the expected rows or header."


def test_summary_txt():
    """Verify the contents of the summary text file."""
    summary_file = "/home/user/summary.txt"
    assert os.path.isfile(summary_file), f"Summary file missing at {summary_file}"

    with open(summary_file, "r", encoding="utf-8") as f:
        content = f.read().strip()

    assert content == "Filtered rows: 3", f"Summary file content is incorrect: {content}"


def test_processed_dataset_tar_gz():
    """Verify the processed dataset tarball exists and contains the correct files at the root."""
    archive_path = "/home/user/processed_dataset.tar.gz"
    assert os.path.isfile(archive_path), f"Processed dataset archive missing at {archive_path}"
    assert tarfile.is_tarfile(archive_path), f"The file {archive_path} is not a valid tar archive."

    with tarfile.open(archive_path, "r:gz") as tar:
        names = tar.getnames()
        assert "filtered_dataset.csv" in names, "filtered_dataset.csv is missing from the root of the archive."
        assert "summary.txt" in names, "summary.txt is missing from the root of the archive."

        assert "/home/user/filtered_dataset.csv" not in names, "Archive should not contain absolute paths or parent directories."
        assert "home/user/filtered_dataset.csv" not in names, "Archive should not contain the home/user directory structure."

        csv_member = tar.extractfile("filtered_dataset.csv")
        assert csv_member is not None, "Could not extract filtered_dataset.csv from archive."
        csv_content = csv_member.read().decode("utf-8").strip().splitlines()
        expected_csv = [
            "ID,Timestamp,Sensor,Value,Notes",
            "2,2023-01-01T10:05,TEMP_01,26.1,High",
            "5,2023-01-01T10:20,TEMP_01,28.4,Critical",
            "7,2023-01-01T10:30,TEMP_01,25.5,High"
        ]
        assert csv_content == expected_csv, "The filtered_dataset.csv inside the archive does not match expected contents."

        txt_member = tar.extractfile("summary.txt")
        assert txt_member is not None, "Could not extract summary.txt from archive."
        txt_content = txt_member.read().decode("utf-8").strip()
        assert txt_content == "Filtered rows: 3", "The summary.txt inside the archive does not match expected contents."


def test_source_compiles_and_processes_unseen_manifest():
    """Compile the submitted source and exercise it on unseen mixed-encoding chunks."""
    source = "/home/user/process_data.c"
    home = "/home/user"
    output = os.path.join(home, "filtered_dataset.csv")

    with open(source, "r", encoding="utf-8", errors="replace") as f:
        source_text = f.read()
    assert re.search(r"#\s*include\s*[<\"]iconv\.h[>\"]", source_text), "Source must include iconv.h."
    for function in ("iconv_open", "iconv", "iconv_close"):
        assert re.search(r"\b" + function + r"\s*\(", source_text), f"Source does not call {function}."

    token = uuid.uuid4().hex
    chunk_specs = [
        (f"first_{token}.csv", "UTF-16LE", [
            ["ID", "Timestamp", "Sensor", "Value", "Notes"],
            ["41", "2040-02-01T01:00", "TEMP_01", "30.25", "Über"],
            ["42", "2040-02-01T01:05", "TEMP_01", "25.0", "Boundary"],
        ]),
        (f"second_{token}.csv", "ISO-8859-1", [
            ["43", "2040-02-01T01:10", "TEMP_010", "99", "Wrong sensor"],
            ["44", "2040-02-01T01:15", "TEMP_01", "-2", "Low"],
            ["45", "2040-02-01T01:20", "TEMP_01", "26", "Café"],
        ]),
        (f"third_{token}.csv", "UTF-8", [
            ["46", "2040-02-01T01:25", "HUM_01", "80", "Other"],
            ["47", "2040-02-01T01:30", "TEMP_01", "25.0001", "Niño"],
        ]),
    ]

    all_data_rows = []
    for _, _, rows in chunk_specs:
        for row in rows:
            if row[0] != "ID":
                all_data_rows.append(row)
    expected_rows = [
        row for row in all_data_rows
        if row[2] == "TEMP_01" and float(row[3]) > 25.0
    ]
    expected = ["ID,Timestamp,Sensor,Value,Notes"] + [",".join(row) for row in expected_rows]

    protected = [
        os.path.join(home, "manifest.csv"),
        os.path.join(home, "raw_dataset.tar.gz"),
        output,
        os.path.join(home, "summary.txt"),
        os.path.join(home, "processed_dataset.tar.gz"),
    ]

    with tempfile.TemporaryDirectory() as tempdir:
        backups = {}
        for path in protected:
            if os.path.exists(path):
                backup = os.path.join(tempdir, "backup_" + str(len(backups)))
                shutil.copy2(path, backup)
                backups[path] = backup

        test_exe = os.path.join(tempdir, "process_data_from_source")
        created_chunks = []
        try:
            compile_result = subprocess.run(
                ["gcc", source, "-o", test_exe, "-lm"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=30,
            )
            assert compile_result.returncode == 0, f"Submitted C source does not compile:\n{compile_result.stderr}"

            symbols = subprocess.run(
                ["nm", "-D", test_exe],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
            assert symbols.returncode == 0, f"Could not inspect compiled executable: {symbols.stderr}"
            for function in ("iconv_open", "iconv", "iconv_close"):
                assert function in symbols.stdout, f"Compiled program does not use the POSIX {function} API."

            manifest_lines = []
            for filename, encoding, rows in chunk_specs:
                path = os.path.join(home, filename)
                created_chunks.append(path)
                text = "\n".join(",".join(row) for row in rows) + "\n"
                codec = {"UTF-16LE": "utf-16le", "ISO-8859-1": "iso-8859-1", "UTF-8": "utf-8"}[encoding]
                with open(path, "wb") as f:
                    f.write(text.encode(codec))
                manifest_lines.append(f"{filename},{encoding}")

            manifest_path = os.path.join(home, "manifest.csv")
            with open(manifest_path, "w", encoding="utf-8", newline="") as f:
                f.write("\n".join(manifest_lines) + "\n")

            with tarfile.open(os.path.join(home, "raw_dataset.tar.gz"), "w:gz") as tar:
                tar.add(manifest_path, arcname="manifest.csv")
                for path in created_chunks:
                    tar.add(path, arcname=os.path.basename(path))

            if os.path.exists(output):
                os.remove(output)

            run_result = subprocess.run(
                [test_exe],
                cwd=home,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=30,
            )
            assert run_result.returncode == 0, (
                f"Compiled program failed on the test manifest (exit {run_result.returncode}):\n"
                f"stdout: {run_result.stdout}\nstderr: {run_result.stderr}"
            )
            assert os.path.isfile(output), "Running the compiled source did not create filtered_dataset.csv."
            with open(output, "r", encoding="utf-8") as f:
                actual = f.read().strip().splitlines()
            assert actual == expected, f"Program produced incorrect output for unseen mixed-encoding data: {actual!r}"
        finally:
            for path in created_chunks:
                if os.path.exists(path):
                    os.remove(path)
            for path in protected:
                if path in backups:
                    shutil.copy2(backups[path], path)
                elif os.path.exists(path):
                    os.remove(path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
