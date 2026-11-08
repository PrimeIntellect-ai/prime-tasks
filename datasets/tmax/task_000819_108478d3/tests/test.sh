#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import secrets
import shutil
import stat
import string
import subprocess


def test_executable_exists():
    executable_path = "/home/user/organizer"
    assert os.path.isfile(executable_path), f"Executable not found at {executable_path}"
    st = os.stat(executable_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File at {executable_path} is not executable"
    with open(executable_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{executable_path} is not a compiled executable"


def test_directories_exist():
    valid_dir = "/home/user/valid_packages"
    outdated_dir = "/home/user/outdated_packages"

    assert os.path.isdir(valid_dir), f"Directory {valid_dir} does not exist"
    assert os.path.isdir(outdated_dir), f"Directory {outdated_dir} does not exist"


def test_valid_packages():
    valid_dir = "/home/user/valid_packages"
    expected_files = [
        "libalpha_v1.10.0.meta",
        "libbeta_v2.0.0.meta",
        "libgamma_v0.10.0.meta"
    ]

    for filename in expected_files:
        file_path = os.path.join(valid_dir, filename)
        assert os.path.isfile(file_path), f"Expected valid package missing: {file_path}"


def test_outdated_packages():
    outdated_dir = "/home/user/outdated_packages"
    expected_files = [
        "libalpha_v1.0.5.meta",
        "libbeta_v1.9.9.meta"
    ]

    for filename in expected_files:
        file_path = os.path.join(outdated_dir, filename)
        assert os.path.isfile(file_path), f"Expected outdated package missing: {file_path}"


def test_ignored_packages():
    valid_dir = "/home/user/valid_packages"
    outdated_dir = "/home/user/outdated_packages"
    ignored_filename = "libdelta_v1.0.0.meta"

    valid_path = os.path.join(valid_dir, ignored_filename)
    outdated_path = os.path.join(outdated_dir, ignored_filename)

    assert not os.path.exists(valid_path), f"Ignored package {ignored_filename} should not be in {valid_dir}"
    assert not os.path.exists(outdated_path), f"Ignored package {ignored_filename} should not be in {outdated_dir}"


def test_run_log_exists():
    log_path = "/home/user/run.log"
    assert os.path.isfile(log_path), f"Run log not found at {log_path}"


def test_file_contents_copied_correctly():
    valid_dir = "/home/user/valid_packages"
    raw_dir = "/home/user/packages_raw"

    raw_path = os.path.join(raw_dir, "bGliYWxwaGFfdjEuMTAuMC5tZXRh")
    copied_path = os.path.join(valid_dir, "libalpha_v1.10.0.meta")

    if os.path.isfile(raw_path) and os.path.isfile(copied_path):
        with open(raw_path, 'r') as f1, open(copied_path, 'r') as f2:
            assert f1.read() == f2.read(), f"Content of {copied_path} does not match the original file"


def _encoded_filename(decoded):
    encoded = base64.b64encode(decoded.encode("ascii")).decode("ascii")
    assert "/" not in encoded
    return encoded


def test_organizer_on_generated_inputs():
    home = "/home/user"
    raw_dir = os.path.join(home, "packages_raw")
    valid_dir = os.path.join(home, "valid_packages")
    outdated_dir = os.path.join(home, "outdated_packages")
    requirements_path = os.path.join(home, "requirements.txt")
    log_path = os.path.join(home, "run.log")

    for path in (raw_dir, valid_dir, outdated_dir):
        shutil.rmtree(path, ignore_errors=True)
        os.makedirs(path, mode=0o777)

    alphabet = string.ascii_lowercase
    package_names = set()
    while len(package_names) < 4:
        package_names.add("".join(secrets.choice(alphabet) for _ in range(12)))

    requirements = {}
    for package in package_names:
        requirements[package] = (
            secrets.randbelow(7) + 1,
            secrets.randbelow(19) + 2,
            secrets.randbelow(19) + 2,
        )

    with open(requirements_path, "w", encoding="ascii") as req_file:
        for package, version in requirements.items():
            req_file.write(f"{package} >= {version[0]}.{version[1]}.{version[2]}\n")

    expected_valid = {}
    expected_outdated = {}

    def add_raw(package, version):
        decoded = f"{package}_v{version[0]}.{version[1]}.{version[2]}.meta"
        encoded = _encoded_filename(decoded)
        content = (
            f"generated payload {secrets.token_hex(20)} for "
            f"{package} {version[0]}.{version[1]}.{version[2]}\n"
        ).encode("ascii")
        with open(os.path.join(raw_dir, encoded), "wb") as f:
            f.write(content)

        minimum = requirements.get(package)
        if minimum is not None:
            if version >= minimum:
                expected_valid[decoded] = content
            else:
                expected_outdated[decoded] = content

    for package, (major, minor, patch) in requirements.items():
        versions = [
            (major, minor, patch),
            (major, minor, patch + secrets.randbelow(8) + 1),
            (major, minor, patch - 1),
            (major, minor + secrets.randbelow(8) + 1, 0),
            (major, minor - 1, 99),
            (major + 1, 0, 0),
            (major - 1, 99, 99),
        ]
        for version in versions:
            add_raw(package, version)

    unlisted = "".join(secrets.choice(alphabet) for _ in range(12))
    while unlisted in requirements:
        unlisted = "".join(secrets.choice(alphabet) for _ in range(12))
    add_raw(unlisted, (9, 8, 7))
    add_raw(unlisted, (0, 0, 1))

    with open(log_path, "wb") as log_file:
        result = subprocess.run(
            [os.path.join(home, "organizer")],
            stdout=log_file,
            stderr=subprocess.PIPE,
            timeout=15,
            check=False,
        )
    assert result.returncode == 0, (
        f"organizer exited with status {result.returncode}: "
        f"{result.stderr.decode(errors='replace')}"
    )

    actual_valid = set(os.listdir(valid_dir))
    actual_outdated = set(os.listdir(outdated_dir))
    assert actual_valid == set(expected_valid), (
        f"valid_packages mismatch: expected {sorted(expected_valid)}, "
        f"got {sorted(actual_valid)}"
    )
    assert actual_outdated == set(expected_outdated), (
        f"outdated_packages mismatch: expected {sorted(expected_outdated)}, "
        f"got {sorted(actual_outdated)}"
    )

    for filename, expected_content in expected_valid.items():
        path = os.path.join(valid_dir, filename)
        assert os.path.isfile(path), f"Expected regular file missing: {path}"
        with open(path, "rb") as f:
            assert f.read() == expected_content, f"Incorrect copied content in {path}"

    for filename, expected_content in expected_outdated.items():
        path = os.path.join(outdated_dir, filename)
        assert os.path.isfile(path), f"Expected regular file missing: {path}"
        with open(path, "rb") as f:
            assert f.read() == expected_content, f"Incorrect copied content in {path}"

    assert os.path.isfile(log_path), "run.log was not produced during generated-input run"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
