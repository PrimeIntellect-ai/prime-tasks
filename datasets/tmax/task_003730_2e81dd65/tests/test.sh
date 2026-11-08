#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import pathlib
import shutil
import subprocess
import tarfile
import uuid

import pytest

SCRIPT = pathlib.Path("/home/user/config_restorer.py")


def remove_path(path):
    path = pathlib.Path(path)
    if os.path.lexists(path):
        if path.is_symlink() or path.is_file():
            path.unlink()
        else:
            shutil.rmtree(path)


@pytest.fixture(scope="session", autouse=True)
def run_submitted_tool():
    assert SCRIPT.is_file(), f"Expected restoration script {SCRIPT} does not exist."
    assert not SCRIPT.is_symlink(), f"Restoration script {SCRIPT} must be a regular file."

    remove_path("/home/user/config_root")
    remove_path("/home/user/security.log")
    remove_path("/home/user/evil1.txt")
    remove_path("/home/user/evil2.txt")
    remove_path("/home/evil2.txt")

    result = subprocess.run(
        [
            "python3",
            str(SCRIPT),
            "/home/user/updates.tar",
            "/home/user/config_root",
            "/home/user/security.log",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Restoration script failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_safe_files_extracted():
    config_root = pathlib.Path("/home/user/config_root")

    safe_config = config_root / "safe_config.ini"
    assert safe_config.is_file(), f"Expected safe file {safe_config} was not extracted."
    with open(safe_config, "rb") as f:
        assert f.read() == b"safe content", f"Content of {safe_config} is incorrect."

    safe_dir = config_root / "safe_dir"
    assert safe_dir.is_dir(), f"Expected safe directory {safe_dir} was not extracted."

    safe_symlink = config_root / "safe_symlink"
    assert safe_symlink.is_symlink(), f"Expected safe symlink {safe_symlink} was not extracted as a symlink."
    assert os.readlink(safe_symlink) == "safe_config.ini", f"Symlink {safe_symlink} has incorrect target."


def test_unsafe_files_not_extracted():
    # Check that zip slip files didn't escape
    evil1 = pathlib.Path("/home/user/evil1.txt")
    assert not evil1.exists(), f"Zip slip vulnerability! {evil1} was extracted outside the target directory."

    evil2 = pathlib.Path("/home/evil2.txt")
    assert not evil2.exists(), f"Zip slip vulnerability! {evil2} was extracted outside the target directory."

    # Check that unsafe symlink/hardlink weren't extracted
    config_root = pathlib.Path("/home/user/config_root")
    unsafe_sym = config_root / "unsafe_symlink"
    assert not unsafe_sym.exists(), f"Unsafe symlink {unsafe_sym} should not have been extracted."

    unsafe_hard = config_root / "unsafe_hardlink"
    assert not unsafe_hard.exists(), f"Unsafe hardlink {unsafe_hard} should not have been extracted."

    # exists() is false for dangling symlinks, so also reject any directory entry.
    assert not os.path.lexists(unsafe_sym), f"Unsafe symlink {unsafe_sym} should not exist, even as a dangling symlink."
    assert not os.path.lexists(unsafe_hard), f"Unsafe hardlink {unsafe_hard} should not exist."
    assert not os.path.lexists("/home/user/evil2.txt"), "Relative traversal escaped the target directory."


def test_security_log_contents():
    log_file = pathlib.Path("/home/user/security.log")
    assert log_file.is_file(), f"Log file {log_file} was not created."

    with open(log_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_skipped = {
        "/home/user/evil1.txt",
        "safe_dir/../../evil2.txt",
        "unsafe_symlink",
        "unsafe_hardlink"
    }

    actual_skipped = set(lines)

    missing = expected_skipped - actual_skipped
    extra = actual_skipped - expected_skipped

    assert not missing, f"Log file is missing entries for skipped files: {missing}"
    assert not extra, f"Log file contains unexpected entries: {extra}"
    assert len(lines) == len(expected_skipped), "Log file contains duplicate entries."


def test_generated_archive_and_argument_count():
    token = uuid.uuid4().hex
    base = pathlib.Path("/tmp") / ("restorer_verify_" + token)
    archive = base / "generated.tar"
    target = base / "target"
    log_file = base / "security.log"
    base.mkdir()

    abs_escape = pathlib.Path("/tmp") / ("restorer_abs_" + token)
    rel_escape = pathlib.Path("/tmp") / ("restorer_rel_" + token)
    dir_escape = pathlib.Path("/tmp") / ("restorer_dir_" + token)
    for path in (abs_escape, rel_escape, dir_escape):
        remove_path(path)

    relative_bad = "inside/../../../" + rel_escape.name
    directory_bad = "inside/../../../" + dir_escape.name
    expected_skipped = {
        str(abs_escape),
        relative_bad,
        directory_bad,
        "bad_symlink",
        "bad_hardlink",
    }

    with tarfile.open(archive, "w") as tar:
        directory = tarfile.TarInfo("inside")
        directory.type = tarfile.DIRTYPE
        tar.addfile(directory)

        text = b"generated safe text\n"
        member = tarfile.TarInfo("safe.txt")
        member.size = len(text)
        tar.addfile(member, io.BytesIO(text))

        binary = bytes(range(256)) + b"\x00\xffgenerated"
        member = tarfile.TarInfo("inside/data.bin")
        member.size = len(binary)
        tar.addfile(member, io.BytesIO(binary))

        safe_sym = tarfile.TarInfo("inside/text_link")
        safe_sym.type = tarfile.SYMTYPE
        safe_sym.linkname = "../safe.txt"
        tar.addfile(safe_sym)

        safe_hard = tarfile.TarInfo("safe_hardlink")
        safe_hard.type = tarfile.LNKTYPE
        safe_hard.linkname = "inside/data.bin"
        tar.addfile(safe_hard)

        payload = b"escape"
        bad_abs = tarfile.TarInfo(str(abs_escape))
        bad_abs.size = len(payload)
        tar.addfile(bad_abs, io.BytesIO(payload))

        bad_rel = tarfile.TarInfo(relative_bad)
        bad_rel.size = len(payload)
        tar.addfile(bad_rel, io.BytesIO(payload))

        bad_dir = tarfile.TarInfo(directory_bad)
        bad_dir.type = tarfile.DIRTYPE
        tar.addfile(bad_dir)

        bad_sym = tarfile.TarInfo("bad_symlink")
        bad_sym.type = tarfile.SYMTYPE
        bad_sym.linkname = "../outside-" + token
        tar.addfile(bad_sym)

        bad_hard = tarfile.TarInfo("bad_hardlink")
        bad_hard.type = tarfile.LNKTYPE
        bad_hard.linkname = "/etc/passwd"
        tar.addfile(bad_hard)

    result = subprocess.run(
        ["python3", str(SCRIPT), str(archive), str(target), str(log_file)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Script failed on generated archive.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    assert (target / "safe.txt").read_bytes() == b"generated safe text\n"
    assert (target / "inside").is_dir()
    assert (target / "inside/data.bin").read_bytes() == bytes(range(256)) + b"\x00\xffgenerated"
    assert (target / "inside/text_link").is_symlink()
    assert os.readlink(target / "inside/text_link") == "../safe.txt"
    assert (target / "safe_hardlink").is_file()
    assert (target / "safe_hardlink").read_bytes() == (target / "inside/data.bin").read_bytes()
    assert os.path.samefile(target / "safe_hardlink", target / "inside/data.bin")

    assert not os.path.lexists(abs_escape)
    assert not os.path.lexists(rel_escape)
    assert not os.path.lexists(dir_escape)
    assert not os.path.lexists(target / "bad_symlink")
    assert not os.path.lexists(target / "bad_hardlink")

    assert log_file.is_file()
    lines = [line.strip() for line in log_file.read_text().splitlines() if line.strip()]
    assert set(lines) == expected_skipped
    assert len(lines) == len(expected_skipped)

    too_few = subprocess.run(
        ["python3", str(SCRIPT), str(archive), str(base / "few-target")],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert too_few.returncode != 0, "Script accepted fewer than exactly three arguments."

    too_many = subprocess.run(
        ["python3", str(SCRIPT), str(archive), str(base / "many-target"), str(base / "many.log"), "extra"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert too_many.returncode != 0, "Script accepted more than exactly three arguments."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
