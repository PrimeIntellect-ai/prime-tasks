#!/bin/bash
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_organizer.py
import hashlib
import os
import re
import secrets
import shutil
import subprocess

SCRIPT = "/home/user/organizer.sh"
PROJECT = "/home/user/project_files"
LIBS = os.path.join(PROJECT, "libs")
ROUTES = os.path.join(PROJECT, "routes.conf")
OUTPUT = "/home/user/organized_routes"


def reset_output():
    shutil.rmtree(OUTPUT, ignore_errors=True)
    os.makedirs(OUTPUT, mode=0o777)
    os.chmod(OUTPUT, 0o777)


def run_script():
    result = subprocess.run(
        [SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"organizer.sh exited with {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result.stdout + result.stderr


def test_organizer_script_exists_and_executable():
    """Test that the organizer.sh script exists and is executable."""
    script_path = "/home/user/organizer.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."
    with open(script_path, "rb") as f:
        first_line = f.readline(256).decode("utf-8", "replace").strip()
    assert re.match(r"^#!.*\bbash(?:\s|$)", first_line), (
        "organizer.sh must be an executable Bash script with a Bash shebang."
    )


def test_valid_route_organized_correctly():
    """Test that libauth.so is correctly organized."""
    lib_path = "/home/user/organized_routes/api/v1/auth/libauth.so"
    status_path = "/home/user/organized_routes/api/v1/auth/status.txt"

    assert os.path.isfile(lib_path), f"Expected valid library at {lib_path} but it was not found."
    assert os.path.isfile(status_path), f"Expected status file at {status_path} but it was not found."

    with open(status_path, "r") as f:
        content = f.read().strip()
    assert content == "VALID", f"Expected status.txt to contain 'VALID', but got '{content}'."


def test_invalid_abi_route_skipped():
    """Test that libdata.so (invalid ABI) is skipped."""
    dir_path = "/home/user/organized_routes/api/v1/data"
    assert not os.path.exists(dir_path), f"Directory {dir_path} should not exist because libdata.so has an invalid ABI."


def test_invalid_checksum_route_skipped():
    """Test that libuser.so (invalid checksum) is skipped."""
    dir_path = "/home/user/organized_routes/api/v2/user"
    assert not os.path.exists(dir_path), f"Directory {dir_path} should not exist because libuser.so has an invalid checksum."


def test_missing_file_route_skipped():
    """Test that libmiss.so (missing file) is skipped."""
    dir_path = "/home/user/organized_routes/api/v2/settings"
    assert not os.path.exists(dir_path), f"Directory {dir_path} should not exist because libmiss.so is missing."


def compile_shared(source, destination):
    source_path = destination + ".c"
    with open(source_path, "w") as f:
        f.write(source)
    result = subprocess.run(
        ["gcc", "-shared", "-fPIC", source_path, "-o", destination],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, result.stderr


def md5(path):
    digest = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def dynamic_behavior_test():
    token = secrets.token_hex(6)
    shutil.rmtree(LIBS, ignore_errors=True)
    os.makedirs(LIBS, mode=0o777)
    os.chmod(LIBS, 0o777)

    valid_name = f"libvalid_{token}.so"
    abi_name = f"libbadabi_{token}.so"
    checksum_name = f"libbadhash_{token}.so"
    missing_name = f"libmissing_{token}.so"

    valid_src = os.path.join(LIBS, valid_name)
    abi_src = os.path.join(LIBS, abi_name)
    checksum_src = os.path.join(LIBS, checksum_name)

    compile_shared("void route_handler(void) {}\n", valid_src)
    compile_shared("void unrelated_handler(void) {}\n", abi_src)
    compile_shared("void route_handler(void) {}\n", checksum_src)

    valid_parts = [f"audit_{token}", "v9", f"item_{token}"]
    abi_parts = [f"audit_{token}", "v9", f"abi_{token}"]
    checksum_parts = [f"audit_{token}", "v9", f"checksum_{token}"]
    missing_parts = [f"audit_{token}", "v9", f"missing_{token}"]

    with open(ROUTES, "w") as f:
        f.write(
            f"ROUTE /{'/'.join(valid_parts)}?token=str&count=int => "
            f"{valid_name} : {md5(valid_src)}\n"
        )
        f.write(
            f"ROUTE /{'/'.join(abi_parts)}?id=int => "
            f"{abi_name} : {md5(abi_src)}\n"
        )
        f.write(
            f"ROUTE /{'/'.join(checksum_parts)} => "
            f"{checksum_name} : 00000000000000000000000000000000\n"
        )
        f.write(
            f"ROUTE /{'/'.join(missing_parts)}?x=str => "
            f"{missing_name} : 11111111111111111111111111111111\n"
        )

    os.chmod(ROUTES, 0o666)
    reset_output()
    output = run_script()

    valid_dir = os.path.join(OUTPUT, *valid_parts)
    copied_lib = os.path.join(valid_dir, valid_name)
    status = os.path.join(valid_dir, "status.txt")
    assert os.path.isfile(copied_lib), f"Valid library was not copied to {copied_lib}"
    assert not os.path.islink(copied_lib), "The organized library must be an actual copied file."
    assert os.path.isfile(status), f"Missing status file {status}"
    with open(status, "r") as f:
        assert f.read().strip() == "VALID", "Dynamic valid route status is not VALID."
    with open(valid_src, "rb") as source, open(copied_lib, "rb") as copied:
        assert source.read() == copied.read(), "The organized library is not a genuine copy of the source library."

    for parts, reason in (
        (abi_parts, "invalid ABI"),
        (checksum_parts, "invalid checksum"),
        (missing_parts, "missing library"),
    ):
        path = os.path.join(OUTPUT, *parts)
        assert not os.path.exists(path), f"Route directory {path} exists despite {reason}."

    assert f"ABI FAILED: {abi_name}" in output, "Missing ABI failure message."
    assert f"CHECKSUM FAILED: {checksum_name}" in output, "Missing checksum failure message."
    assert f"CHECKSUM FAILED: {missing_name}" in output, "Missing missing-library checksum failure message."


def main():
    test_organizer_script_exists_and_executable()

    # Re-run against the supplied inputs from a clean destination, then retain
    # every assertion made by the original verifier.
    reset_output()
    run_script()
    test_valid_route_organized_correctly()
    test_invalid_abi_route_skipped()
    test_invalid_checksum_route_skipped()
    test_missing_file_route_skipped()

    # Replace the fixed fixture with unpredictable libraries, checksums, names,
    # and URL paths, and execute the submitted artifact again.
    dynamic_behavior_test()


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_organizer.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
