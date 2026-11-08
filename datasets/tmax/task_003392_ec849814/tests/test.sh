#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import glob
import tempfile
import tarfile
import shutil
import subprocess
import secrets
import pytest


def test_rust_program_exists():
    assert os.path.isfile("/home/user/backup_tool.rs"), "Rust source file /home/user/backup_tool.rs is missing."


def test_extracted_legacy_docs():
    legacy_dir = "/home/user/extracted_legacy/legacy_docs"
    assert os.path.isdir(legacy_dir), f"Directory {legacy_dir} does not exist."

    expected_files = ["draft_api.md", "draft_intro.md", "draft_setup.md"]
    for f in expected_files:
        assert os.path.isfile(os.path.join(legacy_dir, f)), f"Expected legacy file {f} is missing in {legacy_dir}."


def test_diff_docs_directory():
    diff_docs_dir = "/home/user/diff_docs"
    assert os.path.isdir(diff_docs_dir), f"Directory {diff_docs_dir} does not exist."

    assert os.path.isfile(os.path.join(diff_docs_dir, "prod_intro.md")), "prod_intro.md is missing in diff_docs."
    assert os.path.isfile(os.path.join(diff_docs_dir, "prod_faq.md")), "prod_faq.md is missing in diff_docs."

    assert not os.path.exists(os.path.join(diff_docs_dir, "prod_api.md")), "prod_api.md should not be in diff_docs (it was unchanged)."
    assert not os.path.exists(os.path.join(diff_docs_dir, "prod_setup.md")), "prod_setup.md should not be in diff_docs (it was deleted)."


def test_final_archive_and_chunks():
    final_archive_dir = "/home/user/final_archive"
    chunks = sorted(glob.glob(os.path.join(final_archive_dir, "diff.tar.gz.chunk_*")))

    assert len(chunks) > 0, "No chunks found in /home/user/final_archive with prefix diff.tar.gz.chunk_"

    for chunk in chunks[:-1]:
        size = os.path.getsize(chunk)
        assert size == 100, f"Chunk {chunk} has size {size}, expected 100 bytes."

    with tempfile.TemporaryDirectory() as tmpdir:
        reassembled_tar = os.path.join(tmpdir, "diff.tar.gz")
        with open(reassembled_tar, "wb") as outfile:
            for chunk in chunks:
                with open(chunk, "rb") as infile:
                    outfile.write(infile.read())

        assert tarfile.is_tarfile(reassembled_tar), "Reassembled file is not a valid tar archive."

        with tarfile.open(reassembled_tar, "r:gz") as tar:
            tar.extractall(path=tmpdir)

        extracted_diff_docs = os.path.join(tmpdir, "diff_docs")
        assert os.path.isdir(extracted_diff_docs), "Archive did not extract to a 'diff_docs' directory."

        prod_intro = os.path.join(extracted_diff_docs, "prod_intro.md")
        prod_faq = os.path.join(extracted_diff_docs, "prod_faq.md")

        assert os.path.isfile(prod_intro), "prod_intro.md missing in reassembled archive."
        assert os.path.isfile(prod_faq), "prod_faq.md missing in reassembled archive."

        assert not os.path.exists(os.path.join(extracted_diff_docs, "prod_api.md")), "prod_api.md should not be in the archive."
        assert not os.path.exists(os.path.join(extracted_diff_docs, "prod_setup.md")), "prod_setup.md should not be in the archive."

        with open(prod_intro, "r") as f:
            content = f.read()
            assert "Updated for v2.0." in content, "prod_intro.md does not contain the updated text."

        with open(prod_faq, "r") as f:
            content = f.read()
            assert "Q: How do I start?" in content, "prod_faq.md does not contain the expected FAQ text."

        current_dir = "/home/user/current_docs"
        legacy_dir = "/home/user/extracted_legacy/legacy_docs"
        expected = {}
        for name in os.listdir(current_dir):
            current_path = os.path.join(current_dir, name)
            if not os.path.isfile(current_path):
                continue
            with open(current_path, "rb") as f:
                current_content = f.read()
            legacy_path = os.path.join(legacy_dir, name)
            legacy_content = None
            if os.path.isfile(legacy_path):
                with open(legacy_path, "rb") as f:
                    legacy_content = f.read()
            if legacy_content != current_content:
                output_name = "prod_" + name[len("draft_"):] if name.startswith("draft_") else name
                expected[output_name] = current_content

        actual_files = {
            name for name in os.listdir(extracted_diff_docs)
            if os.path.isfile(os.path.join(extracted_diff_docs, name))
        }
        assert actual_files == set(expected), f"Archive file set does not match the computed documentation diff: {actual_files} != {set(expected)}"
        for name, expected_content in expected.items():
            with open(os.path.join(extracted_diff_docs, name), "rb") as f:
                assert f.read() == expected_content, f"Archived content for {name} does not match current_docs."


def test_rust_program_compiles_and_computes_unseen_diff():
    source = "/home/user/backup_tool.rs"
    current_dir = "/home/user/current_docs"
    extracted_dir = "/home/user/extracted_legacy"
    legacy_dir = os.path.join(extracted_dir, "legacy_docs")
    diff_dir = "/home/user/diff_docs"

    with tempfile.TemporaryDirectory() as tmpdir:
        binary = os.path.join(tmpdir, "backup_tool")
        compiled = subprocess.run(
            ["rustc", source, "-o", binary],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        assert compiled.returncode == 0, f"backup_tool.rs did not compile:\n{compiled.stderr}"

        backups = {}
        for label, path in (("current", current_dir), ("extracted", extracted_dir), ("diff", diff_dir)):
            backup = os.path.join(tmpdir, label)
            if os.path.exists(path):
                shutil.copytree(path, backup)
                backups[path] = backup
            else:
                backups[path] = None

        try:
            for path in (current_dir, extracted_dir, diff_dir):
                if os.path.isdir(path):
                    shutil.rmtree(path)
                elif os.path.exists(path):
                    os.remove(path)

            os.makedirs(current_dir)
            os.makedirs(legacy_dir)

            token = secrets.token_hex(12)
            same_name = f"draft_same_{token}.md"
            changed_name = f"draft_changed_{token}.md"
            new_name = f"draft_new_{token}.md"
            removed_name = f"draft_removed_{token}.md"

            same_content = secrets.token_bytes(41)
            old_content = secrets.token_bytes(43)
            changed_content = secrets.token_bytes(47)
            new_content = secrets.token_bytes(53)

            fixtures = {
                os.path.join(legacy_dir, same_name): same_content,
                os.path.join(current_dir, same_name): same_content,
                os.path.join(legacy_dir, changed_name): old_content,
                os.path.join(current_dir, changed_name): changed_content,
                os.path.join(current_dir, new_name): new_content,
                os.path.join(legacy_dir, removed_name): secrets.token_bytes(37),
            }
            for path, content in fixtures.items():
                with open(path, "wb") as f:
                    f.write(content)

            executed = subprocess.run(
                [binary],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=30,
            )
            assert executed.returncode == 0, f"Compiled Rust program failed:\n{executed.stderr}"
            assert os.path.isdir(diff_dir), "Compiled Rust program did not create /home/user/diff_docs/."

            expected = {
                f"prod_changed_{token}.md": changed_content,
                f"prod_new_{token}.md": new_content,
            }
            actual = {
                name for name in os.listdir(diff_dir)
                if os.path.isfile(os.path.join(diff_dir, name))
            }
            assert actual == set(expected), f"Rust program produced the wrong files for an unseen diff: {actual} != {set(expected)}"
            for name, content in expected.items():
                with open(os.path.join(diff_dir, name), "rb") as f:
                    assert f.read() == content, f"Rust program copied incorrect content for {name}."
        finally:
            for path in (current_dir, extracted_dir, diff_dir):
                if os.path.isdir(path):
                    shutil.rmtree(path)
                elif os.path.exists(path):
                    os.remove(path)
                backup = backups[path]
                if backup is not None:
                    shutil.copytree(backup, path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
