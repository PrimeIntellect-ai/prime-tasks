#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import io
import json
import os
import random
import secrets
import subprocess
import tarfile
import zipfile

import pytest

SCRIPT_PATH = "/home/user/filter_docs.sh"


def run_filter(path):
    try:
        return subprocess.run(
            [SCRIPT_PATH, str(path)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=5,
        ).returncode
    except subprocess.TimeoutExpired:
        return 124


def test_filter_docs_script_exists_and_executable():
    script_path = "/home/user/filter_docs.sh"
    assert os.path.exists(script_path), f"The script {script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a file."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."


def test_clean_corpus_accepted():
    script_path = "/home/user/filter_docs.sh"
    clean_dir = "/home/user/test_data/clean"
    clean_files = glob.glob(os.path.join(clean_dir, "*.docbundle"))

    assert len(clean_files) > 0, "No clean files found."

    failed_files = []
    for filepath in clean_files:
        result = subprocess.run([script_path, filepath], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if result.returncode != 0:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified/rejected. Offending files: {', '.join(failed_files)}")


def test_evil_corpus_rejected():
    script_path = "/home/user/filter_docs.sh"
    evil_dir = "/home/user/test_data/evil"
    evil_files = glob.glob(os.path.join(evil_dir, "*.docbundle"))

    assert len(evil_files) > 0, "No evil files found."

    bypassed_files = []
    for filepath in evil_files:
        result = subprocess.run([script_path, filepath], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if result.returncode == 0:
            bypassed_files.append(os.path.basename(filepath))

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil bypassed. Offending files: {', '.join(bypassed_files)}")


def zip_bytes(entries):
    out = io.BytesIO()
    with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in entries.items():
            archive.writestr(name, data)
    return out.getvalue()


def targz_bytes(entries):
    out = io.BytesIO()
    with tarfile.open(fileobj=out, mode="w:gz") as archive:
        for name, data in entries.items():
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = 0o644
            archive.addfile(info, io.BytesIO(data))
    return out.getvalue()


def write_bundle(path, entries):
    with tarfile.open(path, "w") as archive:
        for kind, name, data in entries:
            info = tarfile.TarInfo(name)
            info.mode = 0o755 if kind == "dir" else 0o644
            if kind == "dir":
                info.type = tarfile.DIRTYPE
                info.size = 0
                archive.addfile(info)
            else:
                info.size = len(data)
                archive.addfile(info, io.BytesIO(data))


def standard_entries(metadata=None):
    if metadata is None:
        metadata = json.dumps({"doc_id": "doc-" + secrets.token_hex(12)}).encode()
    return [
        ("file", "metadata.json", metadata),
        ("dir", "assets", b""),
    ]


def test_generated_bundles_exercise_validation_rules(tmp_path):
    png = b"\x89PNG\r\n\x1a\n" + secrets.token_bytes(24)
    jpg = b"\xff\xd8\xff\xe0" + secrets.token_bytes(24)
    nested_zip = zip_bytes({"deeper.zip": zip_bytes({"note.txt": b"nested"})})
    nested_targz = targz_bytes({"deeper.tar.gz": targz_bytes({"note.txt": b"nested"})})

    cases = []

    def add_case(should_accept, entries=None, raw=None):
        path = tmp_path / (secrets.token_hex(16) + ".docbundle")
        if raw is not None:
            path.write_bytes(raw)
        else:
            write_bundle(path, entries)
        cases.append((path, should_accept))

    # Independently generated valid bundles.
    add_case(True, standard_entries())
    add_case(True, standard_entries() + [
        ("file", "assets/pictures/a.png", png),
        ("file", "assets/pictures/b.jpg", jpg),
        ("file", "assets/readme.txt", secrets.token_bytes(13)),
    ])
    add_case(True, standard_entries(json.dumps({"doc_id": "", "extra": [1, 2, 3]}).encode()) + [
        ("file", "assets/content.zip", zip_bytes({"folder/image.png": png, "note.txt": b"ok"})),
        ("file", "assets/more.tar.gz", targz_bytes({"folder/image.jpg": jpg})),
    ])

    # Missing, duplicated, malformed, or incorrectly typed required data.
    add_case(False, [("dir", "assets", b"")])
    add_case(False, standard_entries() + [("file", "metadata.json", json.dumps({"doc_id": "duplicate"}).encode())])
    add_case(False, [("file", "metadata.json", json.dumps({"doc_id": "x"}).encode())])
    add_case(False, [("file", "metadata.json", json.dumps({"doc_id": "x"}).encode()), ("file", "assets", b"not a directory")])
    add_case(False, standard_entries(b"{not valid json"))
    add_case(False, standard_entries(json.dumps({"title": "missing id"}).encode()))
    add_case(False, standard_entries(json.dumps({"doc_id": 12345}).encode()))

    # Image magic must agree with the extension, including within allowed archives.
    add_case(False, standard_entries() + [("file", "assets/bad.png", b"GIF89a" + secrets.token_bytes(20))])
    add_case(False, standard_entries() + [("file", "assets/bad.jpg", b"\x89PNG\r\n\x1a\n" + secrets.token_bytes(20))])
    add_case(False, standard_entries() + [("file", "assets/images.zip", zip_bytes({"bad.png": b"GIF89a"}))])
    add_case(False, standard_entries() + [("file", "assets/images.tar.gz", targz_bytes({"bad.jpg": b"GIF89a"}))])

    # Archives may only be zip/tar.gz and may not contain another archive.
    add_case(False, standard_entries() + [("file", "assets/outer.zip", nested_zip)])
    add_case(False, standard_entries() + [("file", "assets/outer.tar.gz", nested_targz)])
    add_case(False, standard_entries() + [("file", "assets/broken.zip", b"not a zip archive")])
    add_case(False, standard_entries() + [("file", "assets/broken.tar.gz", b"not a gzip archive")])
    add_case(False, standard_entries() + [("file", "assets/disallowed.tar", targz_bytes({"note.txt": b"x"}))])

    # The top-level input itself must be a tar bundle.
    add_case(False, raw=secrets.token_bytes(97))

    random.SystemRandom().shuffle(cases)
    failures = []
    for path, should_accept in cases:
        rc = run_filter(path)
        accepted = rc == 0
        if accepted != should_accept:
            failures.append(f"{path.name}: expected {'accept' if should_accept else 'reject'}, exit={rc}")

    assert not failures, "Generated bundle checks failed:\n" + "\n".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
