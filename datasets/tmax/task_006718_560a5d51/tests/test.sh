#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import shutil
import struct
import subprocess
import tempfile
import uuid

SOURCE = "/home/user/extractor.c"
BINARY = "/home/user/extractor"
PROJECT = "/home/user/project.caz"
OUTPUT = "/home/user/safe_output"


def run_as_user(command, timeout=10):
    account = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    result = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        preexec_fn=demote,
    )
    assert result.returncode == 0, (
        f"Extractor exited with status {result.returncode}.\n"
        f"stdout: {result.stdout!r}\nstderr: {result.stderr!r}"
    )


def write_archive(path, entries):
    with open(path, "wb") as archive:
        archive.write(b"CAZ1")
        archive.write(struct.pack("<I", len(entries)))
        for entry_path, data in entries:
            archive.write(struct.pack("<H", len(entry_path)))
            archive.write(entry_path)
            archive.write(struct.pack("<I", len(data)))
            archive.write(data)


def exercise_extractor(executable):
    base = tempfile.mkdtemp(prefix="caz_verify_")
    try:
        os.chmod(base, 0o777)
        destination = os.path.join(base, "destination")
        os.mkdir(destination)
        os.chmod(destination, 0o777)

        token = uuid.uuid4().hex
        valid_nested = f"nested/{token}/data.bin".encode("ascii")
        valid_dots = f"ordinary..name-{token}.txt".encode("ascii")
        traversal_name = f"escaped-{token}.txt"
        traversal_path = f"../{traversal_name}".encode("ascii")
        escaped_target = os.path.join(base, traversal_name)
        embedded_traversal = f"docs/../secret-{token}.txt".encode("ascii")
        embedded_target = os.path.join(destination, f"secret-{token}.txt")

        absolute_target = os.path.join(base, f"absolute-{token}.txt")
        sentinel = os.urandom(37)
        with open(absolute_target, "wb") as target:
            target.write(sentinel)
        os.chmod(absolute_target, 0o666)
        absolute_path = absolute_target.encode("ascii")

        nested_data = os.urandom(91) + b"\x00\xff\n"
        dots_data = os.urandom(43)
        entries = [
            (valid_nested, nested_data),
            (valid_dots, dots_data),
            (traversal_path, b"must not escape"),
            (absolute_path, b"must not overwrite absolute target"),
            (embedded_traversal, b"must be rejected"),
        ]

        archive_path = os.path.join(base, f"archive-{uuid.uuid4().hex}.caz")
        write_archive(archive_path, entries)
        os.chmod(archive_path, 0o644)
        run_as_user([executable, archive_path, destination])

        with open(os.path.join(destination, valid_nested.decode("ascii")), "rb") as extracted:
            assert extracted.read() == nested_data
        with open(os.path.join(destination, valid_dots.decode("ascii")), "rb") as extracted:
            assert extracted.read() == dots_data

        assert not os.path.lexists(escaped_target), "A ../ path escaped the destination directory."
        assert not os.path.lexists(embedded_target), "A path containing ../ was extracted."
        with open(absolute_target, "rb") as target:
            assert target.read() == sentinel, "An absolute archive path was written."

        expected_log = b"".join(
            (b"EXTRACTED: " if index < 2 else b"REJECTED: ") + entry_path + b"\n"
            for index, (entry_path, _) in enumerate(entries)
        )
        log_path = os.path.join(destination, "extraction.log")
        assert os.path.isfile(log_path), "The extractor did not create extraction.log."
        with open(log_path, "rb") as log:
            assert log.read() == expected_log, "Dynamic archive log was incorrect."
    finally:
        shutil.rmtree(base, ignore_errors=True)


def test_extractor_files_exist_and_execute():
    assert os.path.exists(SOURCE), "Source file /home/user/extractor.c does not exist."
    assert os.path.exists(BINARY), "Compiled binary /home/user/extractor does not exist."
    assert os.path.isfile(BINARY), "/home/user/extractor is not a regular file."
    assert os.access(BINARY, os.X_OK), "/home/user/extractor is not executable."
    with open(BINARY, "rb") as executable:
        assert executable.read(4) == b"\x7fELF", "/home/user/extractor is not a compiled ELF binary."

    build_dir = tempfile.mkdtemp(prefix="caz_build_")
    try:
        os.chmod(build_dir, 0o755)
        rebuilt = os.path.join(build_dir, "extractor_from_source")
        compile_result = subprocess.run(
            ["gcc", SOURCE, "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert compile_result.returncode == 0, (
            f"extractor.c did not compile successfully:\n{compile_result.stderr.decode(errors='replace')}"
        )
        exercise_extractor(BINARY)
        exercise_extractor(rebuilt)
    finally:
        shutil.rmtree(build_dir, ignore_errors=True)


def test_run_on_provided_archive():
    assert not os.path.exists("/home/user/hacked.txt"), "/home/user/hacked.txt already exists."
    shutil.rmtree(OUTPUT, ignore_errors=True)
    os.mkdir(OUTPUT)
    os.chmod(OUTPUT, 0o777)
    run_as_user([BINARY, PROJECT, OUTPUT])


def test_extracted_files():
    readme_path = "/home/user/safe_output/README.md"
    main_c_path = "/home/user/safe_output/src/main.c"

    assert os.path.exists(readme_path), f"{readme_path} was not extracted."
    with open(readme_path, "r") as f:
        assert f.read() == "Project info here.", f"Incorrect contents in {readme_path}."

    assert os.path.exists(main_c_path), f"{main_c_path} was not extracted."
    with open(main_c_path, "r") as f:
        assert f.read() == "int main() { return 0; }", f"Incorrect contents in {main_c_path}."


def test_zip_slip_prevented():
    hacked_path = "/home/user/hacked.txt"
    assert not os.path.exists(hacked_path), f"Zip slip vulnerability exploited! {hacked_path} was created."


def test_extraction_log():
    log_path = "/home/user/safe_output/extraction.log"
    assert os.path.exists(log_path), f"Log file {log_path} does not exist."

    expected_log = (
        "EXTRACTED: README.md\n"
        "EXTRACTED: src/main.c\n"
        "REJECTED: ../../../home/user/hacked.txt\n"
        "REJECTED: /etc/shadow\n"
        "REJECTED: docs/../secret.txt\n"
    )

    with open(log_path, "r") as f:
        actual_log = f.read()

    assert actual_log.strip() == expected_log.strip(), f"Log file contents do not match expected output.\nExpected:\n{expected_log}\nGot:\n{actual_log}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
