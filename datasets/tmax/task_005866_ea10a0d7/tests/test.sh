#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import subprocess
import tarfile
import uuid
import zipfile

HOME = "/home/user"
ARCHIVE = f"{HOME}/docs_archive.zip"


def test_integrity_txt():
    """Verify the saved output and independently test the archive's integrity."""
    path = f"{HOME}/integrity.txt"
    assert os.path.exists(path), f"{path} does not exist."
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        content = f.read()
    lowered = content.lower()
    assert "no errors" in lowered or "ok" in lowered, \
        "integrity.txt does not seem to contain successful zip test output."

    commands = [
        ["unzip", "-t", ARCHIVE],
        ["unzip", "-t", "docs_archive.zip"],
        ["zip", "-T", ARCHIVE],
        ["zip", "-T", "docs_archive.zip"],
    ]
    successful_outputs = []
    for command in commands:
        result = subprocess.run(
            command, cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=30
        )
        if result.returncode == 0:
            successful_outputs.append(result.stdout.strip())

    assert successful_outputs, "Standard zip utilities report that docs_archive.zip is invalid."
    assert content.strip() in successful_outputs, \
        "integrity.txt is not the standard output of a successful zip integrity test."


def test_raw_docs_extracted():
    """Verify that the archive was fully and accurately extracted."""
    path = f"{HOME}/raw_docs/system.log"
    assert os.path.exists(path), f"{path} does not exist. Archive might not be extracted correctly."

    with zipfile.ZipFile(ARCHIVE, "r") as archive:
        for info in archive.infolist():
            if info.is_dir():
                continue
            relative = info.filename.rstrip("/")
            extracted = os.path.join(HOME, "raw_docs", relative)
            assert os.path.isfile(extracted), f"Extracted archive member is missing: {extracted}"
            with open(extracted, "rb") as f:
                actual = f.read()
            assert actual == archive.read(info), f"Extracted file differs from the archive: {extracted}"


def test_errors_csv():
    """Verify the contents of errors.csv."""
    path = f"{HOME}/errors.csv"
    assert os.path.exists(path), f"{path} does not exist."

    expected_rows = [
        ["Timestamp", "Message"],
        ["2023-10-01 10:05:23", "Failed to connect to database. Connection timeout on port 5432. Retrying in 5 seconds..."],
        ["2023-10-01 10:12:45", "NullPointerException caught in MainModule. Stack trace:   at MainModule.run(MainModule.java:45)   at Application.main(Application.java:20)"]
    ]

    with open(path, "r", newline="") as f:
        rows = list(csv.reader(f))

    assert len(rows) == len(expected_rows), \
        f"Expected {len(expected_rows)} rows in errors.csv, found {len(rows)}."
    for i, (actual, expected) in enumerate(zip(rows, expected_rows)):
        assert actual == expected, \
            f"Row {i+1} mismatch. Expected: {expected}, Actual: {actual}"


def test_cpp_parser_on_fresh_input():
    """Compile the submitted C++ source and exercise it on verifier-generated log data."""
    source = f"{HOME}/parse_logs.cpp"
    assert os.path.isfile(source) and not os.path.islink(source), \
        f"{source} must be a regular C++ source file."

    executable = "/tmp/verify_parse_logs"
    compile_result = subprocess.run(
        ["g++", "-std=c++17", "-O2", source, "-o", executable],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
    )
    assert compile_result.returncode == 0, \
        f"parse_logs.cpp failed to compile:\n{compile_result.stderr}"

    token = uuid.uuid4().hex
    generated_log = (
        "[2025-02-03 08:00:00] INFO\n"
        f"startup {token}\n"
        "[2025-02-03 08:01:02] ERROR\n"
        f"failure {token}, subsystem alpha\n"
        f"details say \"retry {token}\"\n"
        "[2025-02-03 08:02:03] WARNING\n"
        f"warning {token}\n"
        "[2025-02-03 08:03:04] ERROR\n"
        f"final failure {token}\n"
        f"second line {token}\n"
    )
    expected = [
        ["Timestamp", "Message"],
        ["2025-02-03 08:01:02", f"failure {token}, subsystem alpha details say \"retry {token}\""],
        ["2025-02-03 08:03:04", f"final failure {token} second line {token}"],
    ]

    log_path = f"{HOME}/raw_docs/system.log"
    output_path = f"{HOME}/errors.csv"
    with open(log_path, "rb") as f:
        saved_log = f.read()
    with open(output_path, "rb") as f:
        saved_csv = f.read()

    invocations = [
        [executable],
        [executable, log_path, output_path],
        [executable, log_path],
    ]
    matched = False
    diagnostics = []
    try:
        for command in invocations:
            with open(log_path, "w", encoding="utf-8", newline="") as f:
                f.write(generated_log)
            if os.path.exists(output_path):
                os.unlink(output_path)

            try:
                result = subprocess.run(
                    command, cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    text=True, timeout=20
                )
            except subprocess.TimeoutExpired:
                diagnostics.append(f"{' '.join(command)} timed out")
                continue

            if result.returncode != 0:
                diagnostics.append(f"{' '.join(command)} exited {result.returncode}: {result.stderr}")
                continue
            if not os.path.isfile(output_path):
                diagnostics.append(f"{' '.join(command)} did not create errors.csv")
                continue

            try:
                with open(output_path, "r", newline="", encoding="utf-8") as f:
                    actual = list(csv.reader(f))
            except Exception as exc:
                diagnostics.append(f"{' '.join(command)} produced unreadable CSV: {exc}")
                continue

            if actual == expected:
                matched = True
                break
            diagnostics.append(f"{' '.join(command)} produced {actual!r}")
    finally:
        with open(log_path, "wb") as f:
            f.write(saved_log)
        with open(output_path, "wb") as f:
            f.write(saved_csv)

    assert matched, "Compiled parser failed verifier-generated input. " + " | ".join(diagnostics)


def test_final_docs_tar_gz():
    """Verify the tarball's members and their contents."""
    path = f"{HOME}/final_docs.tar.gz"
    assert os.path.exists(path), f"{path} does not exist."
    assert tarfile.is_tarfile(path), f"{path} is not a valid tar archive."

    expected_files = {
        "errors.csv",
        "raw_docs/notes/2023/meeting_notes.md",
        "raw_docs/drafts/api_v2.md"
    }
    for root, _, files in os.walk(f"{HOME}/raw_docs"):
        for name in files:
            if name.endswith(".md"):
                expected_files.add(os.path.relpath(os.path.join(root, name), HOME))

    with tarfile.open(path, "r:gz") as tar:
        members = tar.getmembers()
        names = [m.name for m in members]

        for member in members:
            assert not member.name.startswith("/"), \
                f"Absolute path found in tarball: {member.name}"

        for expected in expected_files:
            matches = [m for m in members if m.name == expected or m.name == f"./{expected}"]
            assert matches, f"Expected file {expected} not found in {path}."
            assert len(matches) == 1, f"Duplicate tar member for {expected}."
            member = matches[0]
            assert member.isfile(), f"Tar member {expected} is not a regular file."
            archived = tar.extractfile(member).read()
            with open(os.path.join(HOME, expected), "rb") as f:
                current = f.read()
            assert archived == current, f"Tar member {expected} does not match the requested file."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
