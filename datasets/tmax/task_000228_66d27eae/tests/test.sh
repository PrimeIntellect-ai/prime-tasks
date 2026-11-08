#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile


def test_profile_exports_fstab():
    profile_path = "/home/user/.profile"
    assert os.path.isfile(profile_path), f"File {profile_path} does not exist."

    with open(profile_path, "r") as f:
        content = f.read()

    match = re.search(r'export\s+USERS_FSTAB=[\'\"]?/home/user/conf/fstab[\'\"]?', content)
    assert match is not None, f"USERS_FSTAB is not correctly exported in {profile_path}"


def test_crontab_entry_exists():
    try:
        result = subprocess.run(
            ["crontab", "-l"],
            capture_output=True,
            text=True,
            check=True,
            user="user" if os.geteuid() == 0 else None
        )
        crontab_content = result.stdout
    except subprocess.CalledProcessError:
        crontab_content = ""

    pattern = r'\*\s+\*\s+\*\s+\*\s+\*\s+/home/user/scripts/get_socket_path\s+>\s+/home/user/socket_path\.log'
    assert re.search(pattern, crontab_content), "Crontab does not contain the expected cronjob entry."


def test_rust_source_exists():
    source_path = "/home/user/scripts/get_socket_path.rs"
    assert os.path.isfile(source_path), f"Rust source file {source_path} does not exist."


def test_rust_binary_exists_and_executable():
    binary_path = "/home/user/scripts/get_socket_path"
    assert os.path.isfile(binary_path), f"Compiled binary {binary_path} does not exist."
    assert os.access(binary_path, os.X_OK), f"Binary {binary_path} is not executable."
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{binary_path} is not a compiled ELF binary."


def test_rust_binary_output():
    binary_path = "/home/user/scripts/get_socket_path"
    env = os.environ.copy()
    env["USERS_FSTAB"] = "/home/user/conf/fstab"

    result = subprocess.run(
        [binary_path],
        env=env,
        capture_output=True,
        text=True,
        check=True,
        timeout=10
    )
    output = result.stdout.strip()
    expected_output = "/home/user/run/sockets/auth.sock"
    assert output == expected_output, f"Expected output '{expected_output}', but got '{output}'"


def run_and_check(program, fstab_path, expected):
    env = os.environ.copy()
    env["USERS_FSTAB"] = fstab_path
    result = subprocess.run(
        [program],
        env=env,
        capture_output=True,
        text=True,
        check=True,
        timeout=10
    )
    assert result.stdout in (expected, expected + "\n"), (
        f"Expected only '{expected}' on stdout, but got {result.stdout!r}"
    )


def test_installed_binary_and_rust_source_on_alternate_fstabs():
    source_path = "/home/user/scripts/get_socket_path.rs"
    installed_binary = "/home/user/scripts/get_socket_path"

    with tempfile.TemporaryDirectory() as td:
        rebuilt_binary = os.path.join(td, "rebuilt_get_socket_path")
        compile_result = subprocess.run(
            ["rustc", source_path, "-o", rebuilt_binary],
            capture_output=True,
            text=True,
            timeout=30
        )
        assert compile_result.returncode == 0, (
            "The submitted Rust source does not compile:\n" + compile_result.stderr
        )
        assert os.path.isfile(rebuilt_binary) and os.access(rebuilt_binary, os.X_OK)

        cases = []
        for index in range(2):
            token = secrets.token_hex(12)
            mount_point = f"/var/tmp/auth_mount_{token}"
            fstab_path = os.path.join(td, f"fstab_{index}_{secrets.token_hex(8)}")
            with open(fstab_path, "w") as f:
                f.write("# generated verifier input\n")
                f.write("proc /proc proc defaults 0 0\n")
                f.write(f"user_data_backup /wrong/{token} tmpfs rw 0 0\n")
                f.write("tmpfs /tmp tmpfs rw 0 0\n")
                f.write(f"  user_data\t{mount_point}   tmpfs rw,nodev 0 0\n")
            cases.append((fstab_path, mount_point + "/auth.sock"))

        for program in (installed_binary, rebuilt_binary):
            for fstab_path, expected in cases:
                run_and_check(program, fstab_path, expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
