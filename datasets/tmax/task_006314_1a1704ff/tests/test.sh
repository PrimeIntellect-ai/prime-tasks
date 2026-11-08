#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import tarfile
import tempfile
import uuid
import zipfile

import pytest


def test_raw_zips_are_extracted_from_tar_and_integrity_is_respected():
    tar_path = "/home/user/research_data.tar"
    raw_dir = "/home/user/raw_zips"
    extracted_dir = "/home/user/extracted_texts"

    assert os.path.isdir(raw_dir), f"Directory {raw_dir} does not exist."

    with tarfile.open(tar_path, "r") as archive:
        members = [m for m in archive.getmembers() if m.isfile()]
        assert members, "The source tar contains no files."
        assert all(m.name.lower().endswith(".zip") for m in members), "The tar contains a non-ZIP file."

        expected_raw_names = sorted(os.path.basename(m.name) for m in members)
        actual_raw_names = sorted(
            name for name in os.listdir(raw_dir)
            if os.path.isfile(os.path.join(raw_dir, name))
        )
        assert actual_raw_names == expected_raw_names, (
            f"raw_zips contents are incorrect. Expected {expected_raw_names}, got {actual_raw_names}."
        )

        for member in members:
            source = archive.extractfile(member)
            assert source is not None
            with source, open(os.path.join(raw_dir, os.path.basename(member.name)), "rb") as actual:
                assert actual.read() == source.read(), f"{member.name} was not correctly extracted from the tar."

    expected_extracted = {}
    valid_zips = []
    invalid_zips = []
    for name in expected_raw_names:
        path = os.path.join(raw_dir, name)
        try:
            with zipfile.ZipFile(path, "r") as zf:
                bad_member = zf.testzip()
                if bad_member is not None:
                    invalid_zips.append(name)
                    continue
                valid_zips.append(name)
                for info in zf.infolist():
                    if info.is_dir():
                        continue
                    output_name = os.path.basename(info.filename)
                    assert output_name, f"Invalid member name in {name}."
                    assert output_name not in expected_extracted, f"Duplicate extracted filename {output_name}."
                    expected_extracted[output_name] = zf.read(info)
        except (zipfile.BadZipFile, EOFError, OSError):
            invalid_zips.append(name)

    assert valid_zips, "No valid ZIP archives were found."
    assert invalid_zips, "No corrupted ZIP archive was identified."
    assert os.path.isdir(extracted_dir), f"Directory {extracted_dir} does not exist."
    actual_extracted = sorted(
        name for name in os.listdir(extracted_dir)
        if os.path.isfile(os.path.join(extracted_dir, name))
    )
    assert actual_extracted == sorted(expected_extracted), (
        f"extracted_texts must contain exactly the files from valid ZIPs; got {actual_extracted}."
    )
    for name, expected_bytes in expected_extracted.items():
        with open(os.path.join(extracted_dir, name), "rb") as f:
            assert f.read() == expected_bytes, f"Extracted contents of {name} do not match its valid ZIP member."


def test_extracted_texts_directory():
    dir_path = "/home/user/extracted_texts"
    assert os.path.isdir(dir_path), f"Directory {dir_path} does not exist."

    expected_files = ["alpha_data.txt", "beta_data.txt", "gamma_data.txt"]
    for f in expected_files:
        file_path = os.path.join(dir_path, f)
        assert os.path.isfile(file_path), f"Expected file {f} is missing in {dir_path}."


def test_cleaned_texts_directory_and_contents():
    dir_path = "/home/user/cleaned_texts"
    assert os.path.isdir(dir_path), f"Directory {dir_path} does not exist."

    expected_contents = {
        "alpha_data.txt": "Experiment 1: [UPDATED_TAG] recorded at dawn.\n",
        "beta_data.txt": "[UPDATED_TAG] is no longer used. [UPDATED_TAG]\n",
        "gamma_data.txt": "Gamma results with [UPDATED_TAG] present.\n"
    }

    for filename, expected_text in expected_contents.items():
        file_path = os.path.join(dir_path, filename)
        assert os.path.isfile(file_path), f"Cleaned file {filename} is missing."

        try:
            with open(file_path, "r", encoding="utf-8") as f:
                content = f.read()
        except UnicodeDecodeError:
            pytest.fail(f"File {filename} is not properly UTF-8 encoded.")

        assert content.strip() == expected_text.strip(), f"Content of {filename} is incorrect. Expected: {expected_text.strip()}, Got: {content.strip()}"


def test_final_dataset_symlinks():
    dir_path = "/home/user/final_dataset"
    assert os.path.isdir(dir_path), f"Directory {dir_path} does not exist."

    expected_files = ["alpha_data.txt", "beta_data.txt", "gamma_data.txt"]
    for f in expected_files:
        symlink_path = os.path.join(dir_path, f)
        assert os.path.islink(symlink_path), f"{symlink_path} is not a symbolic link."

        target = os.readlink(symlink_path)
        expected_target = os.path.join("/home/user/cleaned_texts", f)
        assert target == expected_target, f"Symlink {f} points to {target} instead of {expected_target}."


def test_summary_log():
    log_path = "/home/user/summary.log"
    assert os.path.isfile(log_path), f"Summary log {log_path} does not exist."

    with open(log_path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = ["alpha_data.txt", "beta_data.txt", "gamma_data.txt"]
    assert lines == expected_lines, f"Summary log contents are incorrect. Expected {expected_lines}, got {lines}."


def _python_script_candidates():
    candidates = []
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d not in {".cache", "__pycache__"}]
        for name in files:
            path = os.path.join(root, name)
            if os.path.islink(path) or not os.path.isfile(path):
                continue
            try:
                if os.path.getsize(path) > 1024 * 1024:
                    continue
                with open(path, "rb") as f:
                    data = f.read()
            except OSError:
                continue
            first_line = data.splitlines()[0] if data.splitlines() else b""
            if name.lower().endswith(".py") or (first_line.startswith(b"#!") and b"python" in first_line.lower()):
                candidates.append((path, data))

    def priority(item):
        lower = os.path.basename(item[0]).lower()
        preferred = any(word in lower for word in ("process", "clean", "convert", "text"))
        return (not preferred, item[0])

    return sorted(candidates, key=priority)


def test_python_processing_script_exists_and_processes_new_input():
    candidates = _python_script_candidates()
    assert candidates, "No Python processing script was written under /home/user."

    extracted = "/home/user/extracted_texts"
    cleaned = "/home/user/cleaned_texts"
    probe_name = f"verification_{uuid.uuid4().hex}.txt"
    source_text = "Café costs £5. [OBSOLETE_TAG] déjà.\n"
    expected_text = source_text.replace("[OBSOLETE_TAG]", "[UPDATED_TAG]")

    with tempfile.TemporaryDirectory(prefix="verify_processing_") as backup_root:
        extracted_backup = os.path.join(backup_root, "extracted_texts")
        cleaned_backup = os.path.join(backup_root, "cleaned_texts")
        os.replace(extracted, extracted_backup)
        os.replace(cleaned, cleaned_backup)
        try:
            errors = []
            for index, (original_path, source) in enumerate(candidates):
                shutil.rmtree(extracted, ignore_errors=True)
                shutil.rmtree(cleaned, ignore_errors=True)
                os.makedirs(extracted)
                os.makedirs(cleaned)
                with open(os.path.join(extracted, probe_name), "wb") as f:
                    f.write(source_text.encode("cp1252"))

                run_path = original_path
                if not os.path.exists(run_path):
                    run_path = os.path.join("/home/user", f".verifier_candidate_{index}.py")
                    with open(run_path, "wb") as f:
                        f.write(source)
                try:
                    result = subprocess.run(
                        ["python3", run_path],
                        cwd="/home/user",
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        timeout=15,
                        check=False,
                    )
                    output_path = os.path.join(cleaned, probe_name)
                    if result.returncode == 0 and os.path.isfile(output_path):
                        try:
                            with open(output_path, "r", encoding="utf-8") as f:
                                actual = f.read()
                            if actual == expected_text:
                                return
                            errors.append(f"{original_path}: produced incorrect text")
                        except UnicodeDecodeError:
                            errors.append(f"{original_path}: output was not UTF-8")
                    else:
                        errors.append(f"{original_path}: did not process the probe (exit {result.returncode})")
                except subprocess.TimeoutExpired:
                    errors.append(f"{original_path}: timed out")
                finally:
                    if run_path != original_path:
                        try:
                            os.remove(run_path)
                        except FileNotFoundError:
                            pass

            pytest.fail("No submitted Python script correctly processed a new Windows-1252 input: " + "; ".join(errors))
        finally:
            shutil.rmtree(extracted, ignore_errors=True)
            shutil.rmtree(cleaned, ignore_errors=True)
            os.replace(extracted_backup, extracted)
            os.replace(cleaned_backup, cleaned)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
