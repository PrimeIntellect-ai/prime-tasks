#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import os
import pwd
import secrets
import stat
import subprocess
import time


def test_snapshot_log_exists():
    assert os.path.isfile("/home/user/snapshot.log"), "/home/user/snapshot.log does not exist."


def test_snapshot_tmp_does_not_exist():
    assert not os.path.exists("/home/user/snapshot.tmp"), "/home/user/snapshot.tmp should not exist (must be atomically renamed)."


def test_snapshot_log_content():
    configs_dir = "/home/user/configs"
    conf_files = []

    # Recursively find all .conf files
    for root, _, files in os.walk(configs_dir):
        for file in files:
            if file.endswith(".conf"):
                conf_files.append(os.path.join(root, file))

    # Sort lexicographically by absolute path
    conf_files.sort()

    expected_content = ""
    for conf_file in conf_files:
        with open(conf_file, "r") as f:
            content = f.read()

        expected_content += f"FILE: {conf_file}\n"
        expected_content += "CONTENT:\n"
        expected_content += content
        if not expected_content.endswith("\n"):
            expected_content += "\n"
        expected_content += "EOF\n"

    with open("/home/user/snapshot.log", "r") as f:
        actual_content = f.read()

    # Standardize newlines for comparison
    actual_content = actual_content.strip() + "\n"
    expected_content = expected_content.strip() + "\n"

    assert actual_content == expected_content, "The contents of /home/user/snapshot.log do not match the expected format and data."


def test_c_source_code_requirements():
    source_file = "/home/user/config_snapshot.c"
    assert os.path.isfile(source_file), f"Source file {source_file} is missing."

    with open(source_file, "r") as f:
        source_code = f.read()

    assert "mmap" in source_code, "The C program must use 'mmap' for memory-mapped I/O."
    assert "flock" in source_code or "fcntl" in source_code, "The C program must use 'flock' or 'fcntl' for file locking."
    assert "rename" in source_code, "The C program must use 'rename' for atomic file replacement."


def _expected_snapshot():
    paths = []
    for root, _, files in os.walk("/home/user/configs"):
        for name in files:
            if name.endswith(".conf"):
                paths.append(os.path.join(root, name))
    paths.sort()

    result = bytearray()
    for path in paths:
        with open(path, "rb") as f:
            content = f.read()
        result.extend(f"FILE: {path}\nCONTENT:\n".encode())
        result.extend(content)
        if not content.endswith(b"\n"):
            result.extend(b"\n")
        result.extend(b"EOF\n")
    return bytes(result)


def _remove_outputs():
    for path in ("/home/user/snapshot.log", "/home/user/snapshot.tmp"):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass


def _run_as_user(program, timeout=10):
    account = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    return subprocess.Popen(
        [program],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        preexec_fn=demote,
    )


def test_compiled_artifact_and_source_generate_dynamic_snapshot():
    binary = "/home/user/snapshot"
    assert os.path.isfile(binary), "/home/user/snapshot does not exist or is not a regular file."
    mode = os.stat(binary).st_mode
    assert mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH), "/home/user/snapshot is not executable."
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/snapshot must be a compiled executable."

    rebuilt = "/tmp/snapshot_from_submitted_source"
    compile_result = subprocess.run(
        ["gcc", "/home/user/config_snapshot.c", "-o", rebuilt],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        "The submitted C source does not compile:\n" +
        compile_result.stderr.decode(errors="replace")
    )

    token = secrets.token_hex(12)
    locked_path = f"/home/user/configs/000_verifier_{token}.conf"
    nested_dir = f"/home/user/configs/verifier_{token}/nested"
    nested_path = os.path.join(nested_dir, f"dynamic_{token}.conf")
    ignored_path = os.path.join(nested_dir, f"dynamic_{token}.txt")
    os.makedirs(nested_dir, mode=0o777, exist_ok=True)
    os.chmod(os.path.dirname(nested_dir), 0o777)
    os.chmod(nested_dir, 0o777)

    with open(locked_path, "wb") as f:
        f.write(f"locked_value={secrets.token_hex(20)}\nsecond=true".encode())
    with open(nested_path, "wb") as f:
        f.write(f"dynamic_value={secrets.token_hex(24)}".encode())
    with open(ignored_path, "wb") as f:
        f.write(b"this non-conf file must not appear")
    os.chmod(locked_path, 0o666)
    os.chmod(nested_path, 0o666)
    os.chmod(ignored_path, 0o666)

    # Hold an exclusive lock on the lexicographically first configuration file.
    # A correct executable must block on flock rather than reading through it.
    _remove_outputs()
    lock_file = open(locked_path, "r+b")
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
    proc = _run_as_user(binary)
    try:
        time.sleep(1.0)
        assert proc.poll() is None, "The executable did not wait for a locked configuration file."
        assert not os.path.exists("/home/user/snapshot.log"), "The final log appeared before all locked files were processed."
    finally:
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
        lock_file.close()

    stdout, stderr = proc.communicate(timeout=10)
    assert proc.returncode == 0, (
        f"/home/user/snapshot exited with status {proc.returncode}.\n" +
        stderr.decode(errors="replace")
    )
    assert os.path.isfile("/home/user/snapshot.log"), "Executing /home/user/snapshot did not create snapshot.log."
    assert not os.path.exists("/home/user/snapshot.tmp"), "snapshot.tmp remained after executing /home/user/snapshot."
    with open("/home/user/snapshot.log", "rb") as f:
        assert f.read() == _expected_snapshot(), "The executable produced incorrect output for verifier-generated inputs."

    # Run a binary rebuilt from the submitted source after changing an input, so
    # keyword-only source paired with an unrelated executable cannot pass.
    with open(nested_path, "wb") as f:
        f.write(f"changed_after_first_run={secrets.token_hex(28)}\n".encode())
    os.chmod(nested_path, 0o666)
    _remove_outputs()
    rebuilt_proc = _run_as_user(rebuilt)
    stdout, stderr = rebuilt_proc.communicate(timeout=10)
    assert rebuilt_proc.returncode == 0, (
        f"The program rebuilt from config_snapshot.c exited with status {rebuilt_proc.returncode}.\n" +
        stderr.decode(errors="replace")
    )
    assert os.path.isfile("/home/user/snapshot.log"), "The rebuilt C program did not create snapshot.log."
    assert not os.path.exists("/home/user/snapshot.tmp"), "The rebuilt C program left snapshot.tmp behind."
    with open("/home/user/snapshot.log", "rb") as f:
        assert f.read() == _expected_snapshot(), "The rebuilt C program produced incorrect output for changed inputs."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
