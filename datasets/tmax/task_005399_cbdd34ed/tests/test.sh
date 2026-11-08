#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import shutil
import stat
import subprocess
import tarfile
import io
import pytest

HOME = "/home/user"
INCOMING = HOME + "/docs_incoming"
QUARANTINE = HOME + "/quarantine"
EXTRACTED = HOME + "/extracted_docs"
SUMMARY = HOME + "/processing_summary.json"
SOURCE = HOME + "/process_docs.c"
PROGRAM = HOME + "/process_docs"
RECOMPILED = "/tmp/process_docs_recompiled"

FINAL_EXPECTED = {}


def reset_pipeline():
    for path in (INCOMING, QUARANTINE, EXTRACTED):
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)
        os.makedirs(path, mode=0o777)
    if os.path.lexists(SUMMARY):
        os.unlink(SUMMARY)


def make_safe_archive(filename, chapter, content):
    archive = os.path.join(INCOMING, filename)
    toc = f"file,status\n{chapter},DRAFT\n".encode()
    with tarfile.open(archive, "w") as tar:
        for name, payload in (("toc.csv", toc), (chapter, content)):
            info = tarfile.TarInfo(name=name)
            info.size = len(payload)
            info.mode = 0o644
            tar.addfile(info, io.BytesIO(payload))
    return archive, toc


def make_malicious_archive(filename, member, payload):
    archive = os.path.join(INCOMING, filename)
    with tarfile.open(archive, "w") as tar:
        info = tarfile.TarInfo(name=member)
        info.size = len(payload)
        info.mode = 0o644
        tar.addfile(info, io.BytesIO(payload))
    with open(archive, "rb") as f:
        archive_bytes = f.read()
    return archive_bytes


def read_summary():
    with open(SUMMARY, "r") as f:
        return json.load(f)


def validate_run(safe, malicious):
    expected_processed = sorted(safe)
    expected_quarantined = sorted(malicious)

    data = read_summary()
    assert set(data) == {"processed", "quarantined"}
    assert data["processed"] == expected_processed
    assert data["quarantined"] == expected_quarantined

    for filename, spec in safe.items():
        stem = filename[:-4]
        output_dir = os.path.join(EXTRACTED, stem)
        assert os.path.isdir(output_dir)
        assert sorted(os.listdir(output_dir)) == sorted(["toc.csv", spec["chapter"]])
        with open(os.path.join(output_dir, "toc.csv"), "rb") as f:
            assert f.read() == spec["toc"]
        with open(os.path.join(output_dir, spec["chapter"]), "rb") as f:
            actual = f.read()
        assert actual == spec["content"].replace(b"DRAFT", b"FINAL")

    for filename, original_bytes in malicious.items():
        assert not os.path.exists(os.path.join(INCOMING, filename))
        quarantined = os.path.join(QUARANTINE, filename)
        assert os.path.isfile(quarantined)
        with open(quarantined, "rb") as f:
            assert f.read() == original_bytes


def run_program(path):
    result = subprocess.run([path], cwd=HOME, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=20)
    assert result.returncode == 0, (
        f"{path} exited with {result.returncode}\n"
        f"stdout: {result.stdout.decode(errors='replace')}\n"
        f"stderr: {result.stderr.decode(errors='replace')}"
    )


@pytest.fixture(scope="session", autouse=True)
def execute_and_verify_artifacts():
    for path in (SOURCE, PROGRAM):
        st = os.lstat(path)
        assert stat.S_ISREG(st.st_mode), f"{path} is not a regular file"
    assert os.access(PROGRAM, os.X_OK), f"{PROGRAM} is not executable"
    with open(PROGRAM, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{PROGRAM} is not a compiled ELF executable"

    compile_result = subprocess.run(
        ["gcc", SOURCE, "-o", RECOMPILED], stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=20
    )
    assert compile_result.returncode == 0, (
        "process_docs.c did not compile:\n" +
        compile_result.stderr.decode(errors="replace")
    )

    # Exercise the submitted C source on archive names and contents generated
    # only after the agent has finished.
    reset_pipeline()
    token = secrets.token_hex(8)
    safe = {}
    for prefix, chapter in (("alpha", "guide.md"), ("zeta", "notes.txt")):
        filename = f"{prefix}_{token}.tar"
        content = f"{token}:{prefix}: DRAFT\nDRAFT/{token}/DRAFT\n".encode()
        _, toc = make_safe_archive(filename, chapter, content)
        safe[filename] = {"chapter": chapter, "content": content, "toc": toc}

    traversal_name = f"bad_traversal_{token}.tar"
    absolute_name = f"bad_absolute_{token}.tar"
    abs_target = f"/tmp/process_docs_escape_{token}"
    if os.path.lexists(abs_target):
        os.unlink(abs_target)
    malicious = {
        traversal_name: make_malicious_archive(
            traversal_name, f"nested/../../escape_{token}.txt", token.encode()),
        absolute_name: make_malicious_archive(
            absolute_name, abs_target, ("absolute-" + token).encode()),
    }
    run_program(RECOMPILED)
    validate_run(safe, malicious)
    assert not os.path.exists(abs_target), "absolute-path tar member was extracted"
    assert not os.path.exists(os.path.join(HOME, f"escape_{token}.txt")), \
        "traversal tar member was extracted"

    # Recreate the named input set and execute the submitted compiled artifact,
    # leaving the required final state for the original assertions below.
    reset_pipeline()
    token = secrets.token_hex(8)
    safe = {}
    original_specs = {
        "docA.tar": ("chapter1.md", f"This is a DRAFT document {token}.\nDo not share this DRAFT.\n".encode()),
        "docC.tar": ("chapter2.md", f"Another DRAFT file {token}.\nDRAFT is here.\n".encode()),
    }
    for filename, (chapter, content) in original_specs.items():
        _, toc = make_safe_archive(filename, chapter, content)
        safe[filename] = {"chapter": chapter, "content": content, "toc": toc}

    malicious = {
        "docB.tar": make_malicious_archive("docB.tar", "../malicious.txt", b"malicious-" + token.encode()),
        "docD.tar": make_malicious_archive("docD.tar", "/tmp/passwd_overwrite", b"malicious2-" + token.encode()),
    }
    for escaped in (os.path.join(HOME, "malicious.txt"), "/tmp/passwd_overwrite"):
        if os.path.lexists(escaped):
            os.unlink(escaped)

    run_program(PROGRAM)
    validate_run(safe, malicious)
    assert not os.path.exists(os.path.join(HOME, "malicious.txt"))
    assert not os.path.exists("/tmp/passwd_overwrite")
    FINAL_EXPECTED.update(safe)


def test_quarantined_files():
    quarantine_dir = "/home/user/quarantine"
    expected_quarantined = ["docB.tar", "docD.tar"]
    for filename in expected_quarantined:
        filepath = os.path.join(quarantine_dir, filename)
        assert os.path.isfile(filepath), f"Malicious archive {filename} was not moved to quarantine at {filepath}."


def test_extracted_docs_docA():
    docA_dir = "/home/user/extracted_docs/docA"
    assert os.path.isdir(docA_dir), f"Directory {docA_dir} does not exist."
    toc_path = os.path.join(docA_dir, "toc.csv")
    assert os.path.isfile(toc_path), f"File {toc_path} does not exist."
    chapter_path = os.path.join(docA_dir, "chapter1.md")
    assert os.path.isfile(chapter_path), f"File {chapter_path} does not exist."
    with open(chapter_path, "r") as f:
        content = f.read()
    assert "DRAFT" not in content, f"Found 'DRAFT' in {chapter_path}, text replacement failed."
    assert "FINAL" in content, f"Expected 'FINAL' in {chapter_path}, but it was not found."


def test_extracted_docs_docC():
    docC_dir = "/home/user/extracted_docs/docC"
    assert os.path.isdir(docC_dir), f"Directory {docC_dir} does not exist."
    toc_path = os.path.join(docC_dir, "toc.csv")
    assert os.path.isfile(toc_path), f"File {toc_path} does not exist."
    chapter_path = os.path.join(docC_dir, "chapter2.md")
    assert os.path.isfile(chapter_path), f"File {chapter_path} does not exist."
    with open(chapter_path, "r") as f:
        content = f.read()
    assert "DRAFT" not in content, f"Found 'DRAFT' in {chapter_path}, text replacement failed."
    assert "FINAL" in content, f"Expected 'FINAL' in {chapter_path}, but it was not found."


def test_exact_transformed_contents():
    for filename, spec in FINAL_EXPECTED.items():
        stem = filename[:-4]
        path = os.path.join(EXTRACTED, stem, spec["chapter"])
        with open(path, "rb") as f:
            assert f.read() == spec["content"].replace(b"DRAFT", b"FINAL")


def test_processing_summary_json():
    summary_path = "/home/user/processing_summary.json"
    assert os.path.isfile(summary_path), f"Summary log {summary_path} does not exist."
    with open(summary_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {summary_path} is not valid JSON.")
    assert "processed" in data, "Key 'processed' missing in JSON summary."
    assert "quarantined" in data, "Key 'quarantined' missing in JSON summary."
    expected_processed = ["docA.tar", "docC.tar"]
    expected_quarantined = ["docB.tar", "docD.tar"]
    assert sorted(data["processed"]) == sorted(expected_processed), \
        f"Processed list in JSON {data['processed']} does not match expected {expected_processed}."
    assert sorted(data["quarantined"]) == sorted(expected_quarantined), \
        f"Quarantined list in JSON {data['quarantined']} does not match expected {expected_quarantined}."
    assert data["processed"] == expected_processed
    assert data["quarantined"] == expected_quarantined
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
