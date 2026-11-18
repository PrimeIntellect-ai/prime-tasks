#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import os
import posixpath
import shutil
import struct
import subprocess
import tarfile
import tempfile

RAW_ARCHIVE = "/home/user/raw_artifacts.tar.gz"
CURATED_ARCHIVE = "/home/user/curated_artifacts.tar.gz"
WORKSPACE = "/home/user/workspace"


def canonical_name(name):
    assert not name.startswith("/"), f"Archive contains an absolute path: {name}"
    normalized = posixpath.normpath(name)
    assert normalized != ".." and not normalized.startswith("../"), f"Archive path escapes its root: {name}"
    return "" if normalized == "." else normalized


def archive_members(tf):
    result = {}
    for member in tf.getmembers():
        name = canonical_name(member.name)
        if not name:
            continue
        assert name not in result, f"Archive contains duplicate member: {name}"
        assert member.isfile() or member.isdir(), f"Archive contains a link or special member: {name}"
        result[name] = member
    return result


def read_member(tf, member):
    stream = tf.extractfile(member)
    assert stream is not None, f"Could not read archive member: {member.name}"
    return stream.read()


def derive_expected():
    assert os.path.isfile(RAW_ARCHIVE), f"Raw archive not found: {RAW_ARCHIVE}"
    assert tarfile.is_tarfile(RAW_ARCHIVE), f"Raw input is not a tar archive: {RAW_ARCHIVE}"

    with tarfile.open(RAW_ARCHIVE, "r:gz") as tf:
        members = archive_members(tf)
        assert "artifact_registry.log" in members and members["artifact_registry.log"].isfile()
        raw_log = read_member(tf, members["artifact_registry.log"]).decode("utf-8")
        lines = raw_log.splitlines()
        assert len(lines) % 5 == 0, "Raw registry is malformed"

        expected_records = []
        expected_files = {}
        for offset in range(0, len(lines), 5):
            record = lines[offset:offset + 5]
            assert record[0] == "[Record Start]"
            assert record[1].startswith("Artifact ID: ")
            assert record[2].startswith("File: ")
            assert record[3].startswith("Expected Magic: ")
            assert record[4] == "Status: UNVERIFIED"

            relpath = record[2].split("File: ", 1)[1].strip()
            assert canonical_name(relpath) == relpath and relpath.startswith("bin/")
            expected_magic = int(record[3].split("Expected Magic: ", 1)[1].strip(), 16)
            member = members.get(relpath)
            if member is None or not member.isfile():
                continue
            data = read_member(tf, member)
            if len(data) < 4 or struct.unpack(">I", data[:4])[0] != expected_magic:
                continue

            expected_records.append(record[:4] + ["Status: VERIFIED"])
            expected_files[relpath] = data

    # Preserve the original deterministic-count assertion as well as deriving truth from the input.
    assert len(expected_records) == 47, f"Expected 47 valid records, derived {len(expected_records)}"
    expected_log = "\n".join(line for record in expected_records for line in record) + "\n"
    return expected_records, expected_log.encode("utf-8"), expected_files


def validate_curated(expected_records, expected_log, expected_files):
    assert os.path.exists(CURATED_ARCHIVE), f"Archive not found: {CURATED_ARCHIVE}"
    assert os.path.isfile(CURATED_ARCHIVE), f"Path is not a file: {CURATED_ARCHIVE}"
    assert tarfile.is_tarfile(CURATED_ARCHIVE), f"File is not a valid tar archive: {CURATED_ARCHIVE}"

    with tempfile.TemporaryDirectory() as tmpdir:
        with tarfile.open(CURATED_ARCHIVE, "r:gz") as tf:
            members = archive_members(tf)
            assert "artifact_registry.log" in members and members["artifact_registry.log"].isfile(), \
                "artifact_registry.log is missing from the archive root."

            submitted_log = read_member(tf, members["artifact_registry.log"])
            assert submitted_log == expected_log, "The curated registry does not match the records derived from the raw archive."

            archived_bin_files = {
                name for name, member in members.items()
                if name.startswith("bin/") and member.isfile()
            }
            assert archived_bin_files == set(expected_files), \
                f"Files in bin/ do not match the valid raw artifacts: {archived_bin_files.symmetric_difference(expected_files)}"

            for relpath, expected_data in expected_files.items():
                actual_data = read_member(tf, members[relpath])
                assert actual_data == expected_data, f"Archived file differs from the raw artifact: {relpath}"

            tf.extractall(tmpdir)

        log_path = os.path.join(tmpdir, "artifact_registry.log")
        bin_dir = os.path.join(tmpdir, "bin")
        assert os.path.exists(log_path), "artifact_registry.log is missing from the archive root."
        assert os.path.isdir(bin_dir), "bin/ directory is missing from the archive root."

        with open(log_path, "r", encoding="utf-8") as f:
            lines = f.read().strip().split("\n")
        assert len(lines) % 5 == 0, "Log file does not have a multiple of 5 lines."
        num_records = len(lines) // 5
        assert num_records == 47, f"Expected 47 valid records, found {num_records}."

        log_files = set()
        for i in range(num_records):
            record = lines[i * 5:(i + 1) * 5]
            assert record[0] == "[Record Start]"
            assert record[1].startswith("Artifact ID: ")
            assert record[2].startswith("File: ")
            assert record[3].startswith("Expected Magic: ")
            assert record[4] == "Status: VERIFIED"
            relpath = record[2].split("File: ", 1)[1].strip()
            log_files.add(relpath)
            expected_magic = int(record[3].split("Expected Magic: ", 1)[1].strip(), 16)
            path = os.path.join(tmpdir, relpath)
            assert os.path.exists(path), f"File {relpath} listed in log but missing from archive."
            with open(path, "rb") as f:
                magic = f.read(4)
            assert len(magic) == 4
            assert struct.unpack(">I", magic)[0] == expected_magic

        actual_files = set()
        for root, _, files in os.walk(bin_dir):
            for filename in files:
                actual_files.add(os.path.relpath(os.path.join(root, filename), tmpdir))
        assert actual_files == log_files, f"Files in bin/ do not match log exactly: {actual_files.symmetric_difference(log_files)}"


def find_python_scripts():
    scripts = []
    for root, dirs, files in os.walk("/home/user", followlinks=False):
        dirs[:] = [d for d in dirs if not os.path.islink(os.path.join(root, d))]
        for filename in files:
            if not filename.endswith(".py"):
                continue
            path = os.path.join(root, filename)
            if os.path.isfile(path) and not os.path.islink(path):
                with open(path, "rb") as f:
                    source = f.read()
                compile(source, path, "exec")
                scripts.append((path, source, os.stat(path).st_mode & 0o777))
    assert scripts, "No Python automation script was found under /home/user."
    return scripts


def reset_inputs(raw_bytes, scripts):
    if os.path.isdir(WORKSPACE):
        shutil.rmtree(WORKSPACE)
    elif os.path.lexists(WORKSPACE):
        os.unlink(WORKSPACE)
    if os.path.isdir(CURATED_ARCHIVE):
        shutil.rmtree(CURATED_ARCHIVE)
    elif os.path.lexists(CURATED_ARCHIVE):
        os.unlink(CURATED_ARCHIVE)
    with open(RAW_ARCHIVE, "wb") as f:
        f.write(raw_bytes)

    # Restore scripts outside workspace, including helper modules a main script may import.
    for path, source, mode in scripts:
        if path == WORKSPACE or path.startswith(WORKSPACE + os.sep):
            continue
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(source)
        os.chmod(path, mode)


def verify_automation(scripts, raw_bytes, expected_records, expected_log, expected_files):
    for index, (path, source, mode) in enumerate(scripts):
        inside_workspace = path == WORKSPACE or path.startswith(WORKSPACE + os.sep)
        candidate_path = path
        if inside_workspace:
            candidate_path = f"/tmp/curation_candidate_{index}.py"
            with open(candidate_path, "wb") as f:
                f.write(source)
            os.chmod(candidate_path, mode)

        cwd_options = ["/home/user"]
        if not inside_workspace and os.path.dirname(path) not in cwd_options:
            cwd_options.append(os.path.dirname(path))

        for cwd in cwd_options:
            reset_inputs(raw_bytes, scripts)
            try:
                result = subprocess.run(
                    ["python3", candidate_path], cwd=cwd,
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    timeout=60, check=False
                )
            except (OSError, subprocess.TimeoutExpired):
                continue
            if result.returncode != 0:
                continue
            try:
                validate_curated(expected_records, expected_log, expected_files)
                return
            except AssertionError:
                continue

    raise AssertionError("No submitted Python script successfully regenerated the curated archive from the raw input.")


def main():
    expected_records, expected_log, expected_files = derive_expected()
    validate_curated(expected_records, expected_log, expected_files)
    scripts = find_python_scripts()
    with open(RAW_ARCHIVE, "rb") as f:
        raw_bytes = f.read()
    verify_automation(scripts, raw_bytes, expected_records, expected_log, expected_files)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
