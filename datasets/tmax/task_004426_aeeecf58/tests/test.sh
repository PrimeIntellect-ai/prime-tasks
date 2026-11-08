#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import uuid

import pytest


def test_no_oldconf_files_exist():
    base_dir = "/home/user/configs"
    oldconf_files = []
    for root, dirs, files in os.walk(base_dir):
        for file in files:
            if file.endswith(".oldconf"):
                oldconf_files.append(os.path.join(root, file))
    assert len(oldconf_files) == 0, f"Found .oldconf files that should have been deleted: {oldconf_files}"


def test_app1_settings_newconf():
    file_path = "/home/user/configs/app1/settings.newconf"
    assert os.path.isfile(file_path), f"File {file_path} does not exist. The script failed to create it."

    try:
        with open(file_path, "r", encoding="UTF-8") as f:
            content = f.read()
    except UnicodeDecodeError:
        pytest.fail(f"File {file_path} is not properly UTF-8 encoded.")

    assert "DEBUG_LEVEL=3" in content, f"DEBUG_LEVEL=3 not found in {file_path}"
    assert "DEBUG_LEVEL=1" not in content, f"DEBUG_LEVEL=1 should have been replaced in {file_path}"
    assert "ENVIRONMENT=production" in content, f"ENVIRONMENT=production not found in {file_path}"
    assert "ENVIRONMENT=staging" not in content, f"ENVIRONMENT=staging should have been replaced in {file_path}"
    assert "Café" in content, f"'Café' not found in {file_path}. Ensure it was decoded from ISO-8859-1 and encoded to UTF-8 correctly."
    assert content == "# Config\nDEBUG_LEVEL=3\nPORT=8080\nENVIRONMENT=production\nNOTES=Café\n"


def test_app2_main_newconf():
    file_path = "/home/user/configs/app2/main.newconf"
    assert os.path.isfile(file_path), f"File {file_path} does not exist. The script failed to create it."

    try:
        with open(file_path, "r", encoding="UTF-8") as f:
            content = f.read()
    except UnicodeDecodeError:
        pytest.fail(f"File {file_path} is not properly UTF-8 encoded.")

    assert "DEBUG_LEVEL=3" in content, f"DEBUG_LEVEL=3 not found in {file_path}"
    assert "DEBUG_LEVEL=1" not in content, f"DEBUG_LEVEL=1 should have been replaced in {file_path}"
    assert "ENVIRONMENT=production" in content, f"ENVIRONMENT=production not found in {file_path}"
    assert "ENVIRONMENT=staging" not in content, f"ENVIRONMENT=staging should have been replaced in {file_path}"
    assert content == "DEBUG_LEVEL=3\nENVIRONMENT=production\nDB_HOST=localhost\nUSER=admin\n"


def test_app2_ignore_me_txt_unchanged():
    file_path = "/home/user/configs/app2/ignore_me.txt"
    assert os.path.isfile(file_path), f"File {file_path} does not exist. It should not have been deleted."

    with open(file_path, "r", encoding="UTF-8") as f:
        content = f.read()

    assert "DEBUG_LEVEL=1" in content, f"File {file_path} was incorrectly modified."
    assert "DEBUG_LEVEL=3" not in content, f"File {file_path} was incorrectly modified."
    assert content == "DEBUG_LEVEL=1\n"


def test_symlink_loop_exists():
    symlink_path = "/home/user/configs/app1/backup_loop"
    assert os.path.islink(symlink_path), f"Symlink {symlink_path} does not exist. It should not have been removed."
    target = os.readlink(symlink_path)
    assert target == "/home/user/configs", f"Symlink {symlink_path} points to the wrong target."


def test_script_exists_and_processes_unseen_tree_safely():
    script = "/home/user/update_configs.py"
    assert os.path.exists(script), f"Required script {script} does not exist."
    assert not os.path.islink(script), f"Required script {script} must not be a symlink."
    assert stat.S_ISREG(os.lstat(script).st_mode), f"Required script {script} is not a regular file."

    base = "/home/user/configs"
    token = uuid.uuid4().hex
    test_dir = tempfile.mkdtemp(prefix=f"verify_{token}_", dir=base)
    outside_dir = tempfile.mkdtemp(prefix=f"verify_outside_{token}_", dir="/tmp")

    try:
        nested = os.path.join(test_dir, "one", "two")
        os.makedirs(nested)
        old_path = os.path.join(nested, f"generated_{token}.oldconf")
        new_path = os.path.join(nested, f"generated_{token}.newconf")
        original = (
            f"TOKEN={token}\n"
            "DEBUG_LEVEL=1\n"
            "TEXT=Crème brûlée\n"
            "ENVIRONMENT=staging\n"
            "PAIR=DEBUG_LEVEL=1 ENVIRONMENT=staging\n"
            "UNCHANGED=DEBUG_LEVEL=10\n"
        )
        expected = original.replace("DEBUG_LEVEL=1", "DEBUG_LEVEL=3").replace(
            "ENVIRONMENT=staging", "ENVIRONMENT=production"
        )
        with open(old_path, "wb") as f:
            f.write(original.encode("ISO-8859-1"))

        unrelated = os.path.join(test_dir, f"unchanged_{token}.txt")
        unrelated_bytes = b"DEBUG_LEVEL=1\nENVIRONMENT=staging\n"
        with open(unrelated, "wb") as f:
            f.write(unrelated_bytes)

        outside_file = os.path.join(outside_dir, f"outside_{token}.oldconf")
        outside_bytes = "DEBUG_LEVEL=1\nENVIRONMENT=staging\nÉtranger\n".encode("ISO-8859-1")
        with open(outside_file, "wb") as f:
            f.write(outside_bytes)

        directory_link = os.path.join(test_dir, "linked_directory")
        os.symlink(outside_dir, directory_link)
        file_link = os.path.join(test_dir, f"linked_{token}.oldconf")
        os.symlink(outside_file, file_link)
        loop_link = os.path.join(nested, "loop_to_configs")
        os.symlink(base, loop_link)

        result = subprocess.run(
            [sys.executable, script],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, (
            f"Script failed on an unseen directory tree. stdout={result.stdout!r}, "
            f"stderr={result.stderr!r}"
        )

        assert not os.path.lexists(old_path), "A newly introduced .oldconf file was not deleted."
        assert os.path.isfile(new_path), "The corresponding .newconf file was not created."
        with open(new_path, "rb") as f:
            output_bytes = f.read()
        try:
            output = output_bytes.decode("UTF-8")
        except UnicodeDecodeError:
            pytest.fail("Generated .newconf content is not valid UTF-8.")
        assert output == expected, "Generated content was not the complete required transformation."

        with open(unrelated, "rb") as f:
            assert f.read() == unrelated_bytes, "A non-.oldconf file was modified."

        assert os.path.islink(file_link), "A symlink ending in .oldconf was not ignored."
        assert os.readlink(file_link) == outside_file
        assert not os.path.exists(os.path.splitext(file_link)[0] + ".newconf")
        assert os.path.islink(directory_link), "A symlinked directory was not ignored."
        assert os.path.islink(loop_link), "A recursive symlink was not ignored."
        with open(outside_file, "rb") as f:
            assert f.read() == outside_bytes, "Content reached through a symlink was modified."
        assert not os.path.exists(os.path.splitext(outside_file)[0] + ".newconf")

        original_loop = "/home/user/configs/app1/backup_loop"
        assert os.path.islink(original_loop)
        assert os.readlink(original_loop) == "/home/user/configs"
    finally:
        shutil.rmtree(test_dir, ignore_errors=True)
        shutil.rmtree(outside_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
