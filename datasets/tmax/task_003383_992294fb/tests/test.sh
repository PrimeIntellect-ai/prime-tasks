#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
from collections import Counter


def test_source_code_and_executable():
    assert os.path.isfile("/home/user/archiver.c"), "/home/user/archiver.c is missing"
    assert os.path.isfile("/home/user/archiver"), "/home/user/archiver executable is missing"
    assert os.access("/home/user/archiver", os.X_OK), "/home/user/archiver is not executable"
    with open("/home/user/archiver", "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/archiver is not a compiled ELF executable"


def test_backup_dir_contents():
    backup_dir = "/home/user/backup_dir"
    assert os.path.isdir(backup_dir), f"{backup_dir} directory is missing"

    # Get inodes of the resolved files
    ls_inode = os.stat("/home/user/app_tree/dirA/utility_ls").st_ino
    cat_inode = os.stat("/home/user/app_tree/dirC/utility_cat").st_ino

    expected_files = {
        f"utility_ls_{ls_inode}.bak",
        f"utility_cat_{cat_inode}.bak",
        f"link_ls_{ls_inode}.bak"
    }

    actual_files = set(os.listdir(backup_dir))

    for ef in expected_files:
        assert ef in actual_files, f"Expected file {ef} is missing from {backup_dir}"

    for f in actual_files:
        assert "readme" not in f.lower(), "Non-ELF file readme.txt was incorrectly backed up"
        assert "random" not in f.lower(), "Non-ELF file random.bin was incorrectly backed up"


def test_backup_log():
    log_file = "/home/user/backup_log.txt"
    assert os.path.isfile(log_file), f"{log_file} is missing"

    with open(log_file, "r") as f:
        log_contents = f.read()

    ls_inode = os.stat("/home/user/app_tree/dirA/utility_ls").st_ino
    cat_inode = os.stat("/home/user/app_tree/dirC/utility_cat").st_ino

    ls_real = os.path.realpath("/home/user/app_tree/dirA/utility_ls")
    cat_real = os.path.realpath("/home/user/app_tree/dirC/utility_cat")
    link_ls_real = os.path.realpath("/home/user/app_tree/dirC/link_ls")

    expected_lines = [
        f"COPIED: {ls_real} -> /home/user/backup_dir/utility_ls_{ls_inode}.bak",
        f"COPIED: {cat_real} -> /home/user/backup_dir/utility_cat_{cat_inode}.bak",
        f"COPIED: {link_ls_real} -> /home/user/backup_dir/link_ls_{ls_inode}.bak"
    ]

    for line in expected_lines:
        assert line in log_contents, f"Expected log entry missing or malformed: {line}"


def test_archiver_on_fresh_tree(tmp_path):
    src = tmp_path / "source"
    nested = src / "nested" / "deep"
    external = tmp_path / "directory_symlink_target"
    destination = tmp_path / "archive"
    log_file = tmp_path / "archive.log"

    nested.mkdir(parents=True)
    external.mkdir()
    destination.mkdir()

    alpha = src / "alpha_exec"
    beta = nested / "beta_exec"
    gamma = external / "gamma_exec"
    shutil.copyfile("/bin/echo", alpha)
    shutil.copyfile("/bin/cat", beta)
    shutil.copyfile("/bin/true", gamma)

    (src / "plain_text.txt").write_text("not an ELF file\n")
    (nested / "random_payload.bin").write_bytes(os.urandom(257))

    # Exercise both regular-file symlink resolution and directory symlink traversal.
    alias = src / "alpha_alias"
    alias.symlink_to(alpha)
    (src / "linked_directory").symlink_to(external, target_is_directory=True)

    # A naive recursive traversal that follows directory symlinks will loop forever.
    (nested / "loop_to_source").symlink_to(src, target_is_directory=True)

    result = subprocess.run(
        ["/home/user/archiver", str(src), str(destination), str(log_file)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        text=True,
    )
    assert result.returncode == 0, (
        f"archiver failed with status {result.returncode}\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )

    sources = {
        f"alpha_exec_{os.stat(alpha).st_ino}.bak": alpha,
        f"alpha_alias_{os.stat(alias).st_ino}.bak": alias,
        f"beta_exec_{os.stat(beta).st_ino}.bak": beta,
        f"gamma_exec_{os.stat(gamma).st_ino}.bak": gamma,
    }

    actual_names = {p.name for p in destination.iterdir()}
    assert actual_names == set(sources), (
        f"archive contents differ: expected {set(sources)}, got {actual_names}"
    )

    for archived_name, original in sources.items():
        archived = destination / archived_name
        assert archived.is_file(), f"{archived} is not a regular file"
        assert archived.read_bytes() == original.read_bytes(), (
            f"{archived_name} does not contain an exact copy of its source"
        )

    assert log_file.is_file(), "archiver did not create the requested log file"
    expected_lines = []
    for archived_name, original in sources.items():
        expected_lines.append(
            f"COPIED: {os.path.realpath(original)} -> "
            f"{os.path.abspath(destination / archived_name)}"
        )

    actual_lines = log_file.read_text().splitlines()
    assert Counter(actual_lines) == Counter(expected_lines), (
        f"log records differ: expected {expected_lines}, got {actual_lines}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
