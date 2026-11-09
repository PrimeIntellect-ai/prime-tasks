#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import hashlib
import os
import stat
import subprocess
import tarfile

RAW_DATA_DIR = "/home/user/raw_data"
MANIFEST_PATH = "/home/user/checksums.sha256"
TARBALL_PATH = "/home/user/secure_backup.tar.gz"
HOME_DIR = "/home/user"

EXPECTED_FILES = {
    "project-alpha.doc": b"project info",
    "financial-report-2023.xls": b"money",
    "image-001.jpg": b"fake image",
    "notes.txt": b"just notes",
}

ORIGINAL_NAMES = {
    "project-alpha.doc": "Project Alpha.doc",
    "financial-report-2023.xls": "FINANCIAL_report_2023.XLS",
    "image-001.jpg": "Image_001.JPG",
    "notes.txt": "notes.txt",
}


def expected_manifest_lines():
    return {
        f"{hashlib.sha256(content).hexdigest()}  {filename}"
        for filename, content in EXPECTED_FILES.items()
    }


def find_rename_script():
    candidates = []
    for root, dirs, files in os.walk(HOME_DIR, followlinks=False):
        if os.path.abspath(root) == RAW_DATA_DIR:
            dirs[:] = []
            continue
        for name in files:
            path = os.path.join(root, name)
            if name.endswith(".py") and os.path.isfile(path) and not os.path.islink(path):
                candidates.append(path)
    assert len(candidates) == 1, (
        "Expected exactly one retained Python renaming script under /home/user; "
        f"found {candidates}"
    )
    return candidates[0]


def test_renamed_files_and_content():
    assert os.path.isdir(RAW_DATA_DIR), f"Directory {RAW_DATA_DIR} does not exist."

    actual_files = set(os.listdir(RAW_DATA_DIR))
    expected_filenames = set(EXPECTED_FILES.keys())

    missing_files = expected_filenames - actual_files
    extra_files = actual_files - expected_filenames

    assert not missing_files, f"Missing renamed files in {RAW_DATA_DIR}: {missing_files}"
    assert not extra_files, f"Unexpected or unrenamed files in {RAW_DATA_DIR}: {extra_files}"

    for filename, expected_content in EXPECTED_FILES.items():
        filepath = os.path.join(RAW_DATA_DIR, filename)
        assert os.path.isfile(filepath) and not os.path.islink(filepath), f"{filename} is not a regular file."
        with open(filepath, "rb") as f:
            content = f.read()
        assert content == expected_content, f"Content of {filename} is incorrect."


def test_checksum_manifest():
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file {MANIFEST_PATH} does not exist."
    assert not os.path.islink(MANIFEST_PATH), "Manifest must be a regular file, not a symlink."

    expected_lines = []
    for filename, content in EXPECTED_FILES.items():
        file_hash = hashlib.sha256(content).hexdigest()
        expected_lines.append(f"{file_hash}  {filename}")

    with open(MANIFEST_PATH, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), "Manifest does not contain the correct number of entries."
    for expected_line in expected_lines:
        assert expected_line in actual_lines, f"Expected entry '{expected_line}' not found in manifest."

    with open(MANIFEST_PATH, "rb") as f:
        manifest_bytes = f.read()
    assert manifest_bytes.endswith(b"\n"), "Manifest must end with a newline like sha256sum output."
    decoded = manifest_bytes.decode("utf-8")
    exact_lines = decoded.splitlines()
    assert len(exact_lines) == len(EXPECTED_FILES), "Manifest contains blank or extra lines."
    assert set(exact_lines) == expected_manifest_lines(), (
        "Manifest must use exact sha256sum formatting with hashes, two spaces, and basenames."
    )


def test_tarball_exists_and_contents():
    assert os.path.isfile(TARBALL_PATH), f"Tarball {TARBALL_PATH} does not exist."
    assert not os.path.islink(TARBALL_PATH), "Tarball must be a regular file, not a symlink."
    assert tarfile.is_tarfile(TARBALL_PATH), f"{TARBALL_PATH} is not a valid tar archive."

    with open(TARBALL_PATH, "rb") as f:
        assert f.read(2) == b"\x1f\x8b", "Archive is not gzip-compressed."

    with open(MANIFEST_PATH, "rb") as f:
        expected_manifest = f.read()

    with tarfile.open(TARBALL_PATH, "r:gz") as tar:
        members = tar.getmembers()
        normalized = []
        for member in members:
            name = member.name
            while name.startswith("./"):
                name = name[2:]
            name = name.rstrip("/") if name != "/" else name
            assert name and not name.startswith("/") and ".." not in name.split("/"), (
                f"Unsafe archive member: {member.name}"
            )
            normalized.append(name)

        counts = collections.Counter(normalized)
        required_files = {"checksums.sha256"} | {
            f"raw_data/{filename}" for filename in EXPECTED_FILES
        }
        allowed_members = required_files | {"raw_data"}

        assert set(normalized) <= allowed_members, (
            f"Tarball contains unexpected members: {set(normalized) - allowed_members}"
        )
        for name in required_files:
            assert counts[name] == 1, f"Tarball must contain exactly one {name}"
        assert counts["raw_data"] <= 1, "Tarball contains duplicate raw_data directory entries."

        for member, name in zip(members, normalized):
            if name == "raw_data":
                assert member.isdir(), "raw_data archive member must be a directory."
                continue
            assert member.isfile() and not member.issym() and not member.islnk(), (
                f"Archive member {name} must be a regular file."
            )
            archived = tar.extractfile(member)
            assert archived is not None
            archived_bytes = archived.read()
            if name == "checksums.sha256":
                assert archived_bytes == expected_manifest, "Archived manifest differs from the final manifest."
            else:
                filename = name.split("/", 1)[1]
                assert archived_bytes == EXPECTED_FILES[filename], (
                    f"Archived content of {filename} is incorrect."
                )


def test_python_renaming_script_executes():
    script = find_rename_script()

    # Return the fixture to its original names, then execute the submitted script.
    # This verifies that the required Python artifact actually performs the rename.
    for normalized, original in ORIGINAL_NAMES.items():
        source = os.path.join(RAW_DATA_DIR, normalized)
        destination = os.path.join(RAW_DATA_DIR, original)
        if source != destination:
            os.rename(source, destination)

    result = subprocess.run(
        ["python3", script],
        cwd=HOME_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Python renaming script failed with exit code {result.returncode}: {result.stderr}"
    )

    actual_files = set(os.listdir(RAW_DATA_DIR))
    assert actual_files == set(EXPECTED_FILES), (
        f"Python script did not apply the required filename normalization: {actual_files}"
    )
    for filename, expected_content in EXPECTED_FILES.items():
        with open(os.path.join(RAW_DATA_DIR, filename), "rb") as f:
            assert f.read() == expected_content, f"Script changed the content of {filename}."


def test_no_temporary_files_in_home():
    script = find_rename_script()
    allowed = {
        RAW_DATA_DIR,
        MANIFEST_PATH,
        TARBALL_PATH,
        os.path.join(HOME_DIR, ".bash_logout"),
        os.path.join(HOME_DIR, ".bashrc"),
        os.path.join(HOME_DIR, ".profile"),
        script,
    }

    parent = os.path.dirname(script)
    while parent != HOME_DIR:
        allowed.add(parent)
        parent = os.path.dirname(parent)

    for filename in EXPECTED_FILES:
        allowed.add(os.path.join(RAW_DATA_DIR, filename))

    actual = set()
    for root, dirs, files in os.walk(HOME_DIR, followlinks=False):
        for name in dirs + files:
            actual.add(os.path.join(root, name))

    extras = actual - allowed
    assert not extras, f"Temporary or unexpected files remain in /home/user: {sorted(extras)}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
