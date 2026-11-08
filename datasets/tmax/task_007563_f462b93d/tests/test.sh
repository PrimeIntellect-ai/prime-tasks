#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import fcntl
import io
import os
import secrets
import subprocess
import tarfile
import time
import zipfile

import pytest

GO_FILE = "/home/user/organize.go"
TAR_PATH = "/home/user/legacy_archive.tar"
PROCESSED = "/home/user/processed"
ZIP_PATH = "/home/user/final_docs.zip"

TOKEN = secrets.token_hex(6)
FILES = {
    "folder1/doc 1.txt": b"Caf\xe9 and R\xe9sum\xe9\n",
    "folder2/sub/doc 2.txt": b"Jalape\xf1o peppers\n",
    f"deep/{TOKEN}/nested report {TOKEN}.txt": f"V\xe9rification {TOKEN} and pi\xf1ata\n".encode("latin-1"),
    f"other/more notes {TOKEN}.txt": f"Cr\xe8me br\xfbl\xe9e {TOKEN}\n".encode("latin-1"),
}
EXPECTED = {
    os.path.basename(path).replace(" ", "_"): data.decode("latin-1")
    for path, data in FILES.items()
}
IGNORED_NAME = f"ignore {TOKEN}.md"


def create_dynamic_archive():
    with tarfile.open(TAR_PATH, "w") as tf:
        for path, data in FILES.items():
            info = tarfile.TarInfo("./" + path)
            info.size = len(data)
            info.mode = 0o644
            tf.addfile(info, io.BytesIO(data))
        ignored = b"This is not a text input.\n"
        info = tarfile.TarInfo("./misc/" + IGNORED_NAME)
        info.size = len(ignored)
        info.mode = 0o644
        tf.addfile(info, io.BytesIO(ignored))


def blocked_flock_exists(inode):
    try:
        with open("/proc/locks", "r", encoding="ascii") as f:
            for line in f:
                if "->" not in line or "FLOCK" not in line:
                    continue
                if any(field.endswith(":" + str(inode)) for field in line.split()):
                    return True
    except OSError:
        return False
    return False


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert os.path.exists(GO_FILE), f"{GO_FILE} does not exist."
    create_dynamic_archive()

    subprocess.run(["rm", "-rf", "/home/user/extracted", PROCESSED, ZIP_PATH], check=True)
    os.makedirs(PROCESSED, exist_ok=True)
    manifest_path = os.path.join(PROCESSED, "manifest.log")

    build = subprocess.run(
        ["go", "build", "-o", "/tmp/organize_submission", GO_FILE],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=60,
    )
    assert build.returncode == 0, "organize.go did not compile:\n" + build.stdout

    # Hold the exact manifest inode locked while starting the submitted program.
    # A real blocking syscall.Flock attempt appears as a waiting FLOCK in
    # /proc/locks. This proves the lock is executed, rather than merely named in
    # a comment or unused function.
    with open(manifest_path, "a+b", buffering=0) as held_manifest:
        fcntl.flock(held_manifest.fileno(), fcntl.LOCK_EX)
        inode = os.fstat(held_manifest.fileno()).st_ino
        proc = subprocess.Popen(
            ["/tmp/organize_submission"],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        waiting = False
        deadline = time.time() + 10
        while time.time() < deadline:
            if proc.poll() is not None:
                break
            if blocked_flock_exists(inode):
                waiting = True
                break
            time.sleep(0.05)

        assert open(manifest_path, "rb").read() == b"", \
            "manifest.log was written while another process held its exclusive lock"
        fcntl.flock(held_manifest.fileno(), fcntl.LOCK_UN)

    if not waiting:
        if proc.poll() is None:
            proc.kill()
        output = proc.communicate()[0]
        pytest.fail("program did not actually wait on an exclusive FLOCK for manifest.log\n" + output)

    try:
        output = proc.communicate(timeout=20)[0]
    except subprocess.TimeoutExpired:
        proc.kill()
        output = proc.communicate()[0]
        pytest.fail("organize program did not finish after the manifest lock was released\n" + output)
    assert proc.returncode == 0, "organize program failed:\n" + output


def test_organize_go_exists_and_uses_flock():
    assert os.path.exists(GO_FILE), f"{GO_FILE} does not exist."
    with open(GO_FILE, "r", encoding="utf-8") as f:
        content = f.read()
    assert "Flock" in content, f"{GO_FILE} does not contain 'Flock' for file locking."


def test_final_docs_zip_exists_and_valid():
    assert os.path.exists(ZIP_PATH), f"{ZIP_PATH} does not exist."
    assert zipfile.is_zipfile(ZIP_PATH), f"{ZIP_PATH} is not a valid zip file."


def test_processed_directory_and_manifest():
    manifest_path = os.path.join(PROCESSED, "manifest.log")
    assert os.path.isfile(manifest_path), "processed/manifest.log is missing"

    for name, expected_text in EXPECTED.items():
        path = os.path.join(PROCESSED, name)
        assert os.path.isfile(path), f"{name} was not flattened into processed/"
        with open(path, "rb") as f:
            raw = f.read()
        assert raw.decode("utf-8") == expected_text, f"{name} was not converted correctly"

    assert not os.path.exists(os.path.join(PROCESSED, IGNORED_NAME.replace(" ", "_")))
    with open(manifest_path, "r", encoding="utf-8") as f:
        lines = [line.rstrip("\n") for line in f]
    expected_lines = [name + " - UTF8 Converted" for name in EXPECTED]
    assert collections.Counter(lines) == collections.Counter(expected_lines)


def test_zip_contents():
    assert zipfile.is_zipfile(ZIP_PATH)
    with zipfile.ZipFile(ZIP_PATH, "r") as zf:
        namelist = zf.namelist()
        file_names = [name for name in namelist if not name.endswith("/")]
        basenames = [os.path.basename(name) for name in file_names]

        # Preserve the original fixture assertions.
        assert "doc_1.txt" in basenames, "doc_1.txt missing from zip archive."
        assert "doc_2.txt" in basenames, "doc_2.txt missing from zip archive."
        assert "manifest.log" in basenames, "manifest.log missing from zip archive."

        def get_zip_path(basename):
            matches = [name for name in file_names if os.path.basename(name) == basename]
            assert len(matches) == 1, f"expected exactly one archived {basename}"
            return matches[0]

        doc1_content = zf.read(get_zip_path("doc_1.txt")).decode("utf-8")
        assert "Café and Résumé" in doc1_content, "doc_1.txt content invalid or not converted to UTF-8 properly."
        doc2_content = zf.read(get_zip_path("doc_2.txt")).decode("utf-8")
        assert "Jalapeño peppers" in doc2_content, "doc_2.txt content invalid or not converted to UTF-8 properly."

        manifest_content = zf.read(get_zip_path("manifest.log")).decode("utf-8")
        assert "doc_1.txt - UTF8 Converted" in manifest_content, "manifest.log missing doc_1 entry."
        assert "doc_2.txt - UTF8 Converted" in manifest_content, "manifest.log missing doc_2 entry."

        for name, expected_text in EXPECTED.items():
            assert zf.read(get_zip_path(name)).decode("utf-8") == expected_text
        assert IGNORED_NAME.replace(" ", "_") not in basenames

        archived_lines = [line for line in manifest_content.splitlines()]
        expected_lines = [name + " - UTF8 Converted" for name in EXPECTED]
        assert collections.Counter(archived_lines) == collections.Counter(expected_lines)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
