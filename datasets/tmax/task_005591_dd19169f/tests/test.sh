#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import stat
import string
import subprocess
import tempfile


def test_parser_c_exists_and_uses_mmap():
    """Verify that parser.c exists and contains 'mmap'."""
    parser_path = "/home/user/parser.c"
    assert os.path.isfile(parser_path), f"C parser source file {parser_path} is missing."

    with open(parser_path, "r") as f:
        content = f.read()

    assert "mmap" in content, "The C parser must use mmap as per the requirements."


def test_fatal_errors_hard_links():
    """Verify that FATAL errors resulted in correct hard links."""
    expected_links = {
        "/home/user/fatal_errors/main.c": "/home/user/src/app/main.c",
        "/home/user/fatal_errors/socket.c": "/home/user/src/network/socket.c",
    }

    for link_path, target_path in expected_links.items():
        assert os.path.exists(link_path), f"Hard link {link_path} is missing."
        assert os.path.exists(target_path), f"Target file {target_path} is missing."

        link_stat = os.stat(link_path)
        target_stat = os.stat(target_path)

        assert link_stat.st_ino == target_stat.st_ino, f"{link_path} is not a hard link to {target_path}."
        assert not os.path.islink(link_path), f"{link_path} should be a hard link, not a symbolic link."


def test_warn_errors_symlinks():
    """Verify that WARN errors resulted in correct symbolic links."""
    expected_links = {
        "/home/user/warn_errors/math.c": "/home/user/src/lib/math.c",
        "/home/user/warn_errors/missing.c": "/home/user/src/app/missing.c",
    }

    for link_path, target_path in expected_links.items():
        assert os.path.islink(link_path), f"{link_path} is missing or is not a symbolic link."

        actual_target = os.readlink(link_path)
        assert actual_target == target_path, f"Symlink {link_path} points to {actual_target}, expected {target_path}."


def test_parser_compiles_and_parses_fresh_log():
    """Compile the submitted source and exercise it on unpredictable records."""
    source = "/home/user/parser.c"
    binary = "/home/user/parser"
    build_log = "/home/user/build.log"
    fatal_dir = "/home/user/fatal_errors"
    warn_dir = "/home/user/warn_errors"

    assert os.path.isfile(binary), "Compiled parser /home/user/parser is missing."
    assert os.access(binary, os.X_OK), "/home/user/parser is not executable."
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/parser is not a compiled executable."

    compile_result = subprocess.run(
        ["gcc", source, "-o", binary],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, f"parser.c did not compile:\n{compile_result.stderr}"

    token = "".join(random.SystemRandom().choices(string.ascii_lowercase, k=12))
    dynamic_src = f"/home/user/dynamic_sources_{token}"
    backup_root = tempfile.mkdtemp(prefix="parser_verify_", dir="/home/user")
    original_log = open(build_log, "rb").read()

    fatal_sources = [
        os.path.join(dynamic_src, f"fatal_{token}_{i}.c") for i in range(3)
    ]
    warn_sources = [
        os.path.join(dynamic_src, f"warn_{token}_{i}.c") for i in range(3)
    ]
    info_source = os.path.join(dynamic_src, f"info_{token}.c")
    missing_fatal = os.path.join(dynamic_src, f"absent_fatal_{token}.c")
    missing_warn = os.path.join(dynamic_src, f"absent_warn_{token}.c")

    records = []
    for path in fatal_sources:
        records.append(("FATAL", path, f"fatal detail for {os.path.basename(path)}"))
    for path in warn_sources:
        records.append(("WARN", path, f"warning detail for {os.path.basename(path)}"))
    records.extend([
        ("INFO", info_source, "informational record must not create a link"),
        ("FATAL", missing_fatal, "missing fatal source must be skipped"),
        ("WARN", missing_warn, "missing warning source must be skipped"),
    ])
    random.SystemRandom().shuffle(records)

    try:
        os.makedirs(dynamic_src)
        for path in fatal_sources + warn_sources + [info_source]:
            with open(path, "w") as f:
                f.write(f"/* unique verification file: {path} */\n")

        if os.path.lexists(fatal_dir):
            os.rename(fatal_dir, os.path.join(backup_root, "fatal_errors"))
        if os.path.lexists(warn_dir):
            os.rename(warn_dir, os.path.join(backup_root, "warn_errors"))

        with open(build_log, "w") as f:
            for record_type, src, details in records:
                f.write(
                    "BEGIN_RECORD\n"
                    f"TYPE: {record_type}\n"
                    f"SRC: {src}\n"
                    f"DETAILS: {details}\n"
                    "END_RECORD\n"
                )

        run_result = subprocess.run(
            [binary],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert run_result.returncode == 0, (
            f"parser exited with {run_result.returncode}\n"
            f"stdout:\n{run_result.stdout}\nstderr:\n{run_result.stderr}"
        )

        assert os.path.isdir(fatal_dir), "Parser did not create fatal_errors."
        assert os.path.isdir(warn_dir), "Parser did not create warn_errors."

        expected_fatal_names = {os.path.basename(p) for p in fatal_sources}
        expected_warn_names = {os.path.basename(p) for p in warn_sources}
        assert set(os.listdir(fatal_dir)) == expected_fatal_names
        assert set(os.listdir(warn_dir)) == expected_warn_names

        for target in fatal_sources:
            link_path = os.path.join(fatal_dir, os.path.basename(target))
            assert os.path.exists(link_path), f"Missing hard link {link_path}."
            assert not os.path.islink(link_path), f"{link_path} must not be a symlink."
            assert os.stat(link_path).st_ino == os.stat(target).st_ino, (
                f"{link_path} is not a hard link to {target}."
            )

        for target in warn_sources:
            link_path = os.path.join(warn_dir, os.path.basename(target))
            assert os.path.islink(link_path), f"Missing symlink {link_path}."
            assert os.readlink(link_path) == target, (
                f"{link_path} does not point directly to {target}."
            )

        assert not os.path.lexists(os.path.join(fatal_dir, os.path.basename(missing_fatal)))
        assert not os.path.lexists(os.path.join(warn_dir, os.path.basename(missing_warn)))
        assert not os.path.lexists(os.path.join(fatal_dir, os.path.basename(info_source)))
        assert not os.path.lexists(os.path.join(warn_dir, os.path.basename(info_source)))
    finally:
        with open(build_log, "wb") as f:
            f.write(original_log)
        if os.path.lexists(fatal_dir):
            shutil.rmtree(fatal_dir)
        if os.path.lexists(warn_dir):
            shutil.rmtree(warn_dir)
        saved_fatal = os.path.join(backup_root, "fatal_errors")
        saved_warn = os.path.join(backup_root, "warn_errors")
        if os.path.lexists(saved_fatal):
            os.rename(saved_fatal, fatal_dir)
        if os.path.lexists(saved_warn):
            os.rename(saved_warn, warn_dir)
        shutil.rmtree(dynamic_src, ignore_errors=True)
        shutil.rmtree(backup_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
