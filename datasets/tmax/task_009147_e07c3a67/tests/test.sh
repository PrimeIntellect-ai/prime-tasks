#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import shutil
import stat
import subprocess
import tarfile
import tempfile
from pathlib import Path

import pytest

REPO = "/home/user/repo"
CATALOG = "/home/user/elf_catalog.json"
CLEAN_ARCHIVE = "/home/user/clean_artifacts.tar.gz"
EXPECTED_BINARIES = {
    "app1": "/bin/ls",
    "app2": "/bin/bash",
}


def file_digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.digest()


def get_elf_machine(filepath):
    """Helper to get the Machine string from an ELF file using readelf."""
    try:
        output = subprocess.check_output(
            ["readelf", "-h", filepath], text=True, stderr=subprocess.DEVNULL
        )
        for line in output.splitlines():
            if "Machine:" in line:
                return line.split("Machine:", 1)[1].strip()
    except Exception:
        pass
    return None


def expected_catalog():
    return {
        os.path.join(REPO, name): get_elf_machine(source)
        for name, source in EXPECTED_BINARIES.items()
    }


def find_python_scripts():
    scripts = []
    for root, dirs, files in os.walk("/home/user", followlinks=False):
        dirs[:] = [d for d in dirs if d not in {"__pycache__", ".pytest_cache"}]
        for name in files:
            path = os.path.join(root, name)
            try:
                st = os.lstat(path)
                if not stat.S_ISREG(st.st_mode):
                    continue
                is_script = name.endswith(".py")
                if not is_script:
                    with open(path, "rb") as f:
                        first_line = f.readline(256).lower()
                    is_script = first_line.startswith(b"#!") and b"python" in first_line
                if is_script:
                    with open(path, "rb") as f:
                        scripts.append((path, f.read(), stat.S_IMODE(st.st_mode)))
            except OSError:
                continue
    return scripts


SCRIPT_SNAPSHOTS = find_python_scripts()


def assert_catalog_correct():
    assert os.path.exists(CATALOG), f"{CATALOG} does not exist."
    with open(CATALOG, "r") as f:
        try:
            catalog = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{CATALOG} is not a valid JSON file.")

    assert isinstance(catalog, dict), "The JSON file must contain a single dictionary."
    expected = expected_catalog()
    assert all(expected.values()), "Could not determine expected ELF Machine values."
    assert set(catalog.keys()) == set(expected), f"Catalog keys must be exactly {set(expected)}."
    for path, machine in expected.items():
        assert catalog[path] == machine, f"Incorrect Machine type for {path}."


def assert_clean_archive_correct():
    assert os.path.exists(CLEAN_ARCHIVE), f"{CLEAN_ARCHIVE} does not exist."
    assert tarfile.is_tarfile(CLEAN_ARCHIVE), f"{CLEAN_ARCHIVE} is not a valid tar archive."

    with tarfile.open(CLEAN_ARCHIVE, "r:gz") as tar:
        members = tar.getmembers()
        names = [member.name for member in members]
        expected_members = {"app1", "app2"}
        assert set(names) == expected_members, (
            f"Archive must contain exactly {expected_members} at the root, but contains {names}."
        )
        assert len(members) == 2, "Archive must not contain duplicate members."

        for member in members:
            assert member.isfile(), f"Archive member {member.name} is not a regular file."
            assert "/" not in member.name and member.name not in {".", ".."}, (
                f"Archive member {member.name} is not at the archive root."
            )
            extracted = tar.extractfile(member)
            assert extracted is not None
            data = extracted.read()
            with open(EXPECTED_BINARIES[member.name], "rb") as expected_file:
                expected_data = expected_file.read()
            assert data == expected_data, (
                f"Archive member {member.name} does not match the curated repository binary."
            )
            with tempfile.NamedTemporaryFile() as temp:
                temp.write(data)
                temp.flush()
                assert get_elf_machine(temp.name) is not None, (
                    f"Archive member {member.name} is not a valid ELF file."
                )


def reset_repo_for_script(script_path, script_data, script_mode):
    shutil.rmtree(REPO, ignore_errors=True)
    os.makedirs(REPO)
    for name, source in EXPECTED_BINARIES.items():
        shutil.copy2(source, os.path.join(REPO, name))
    with open(os.path.join(REPO, "readme.txt"), "w") as f:
        f.write("Some release notes\n")
    os.symlink("loopB", os.path.join(REPO, "loopA"))
    os.symlink("loopA", os.path.join(REPO, "loopB"))
    os.symlink("app1", os.path.join(REPO, "valid_link"))

    if os.path.commonpath([os.path.abspath(script_path), REPO]) == REPO:
        os.makedirs(os.path.dirname(script_path), exist_ok=True)
        with open(script_path, "wb") as f:
            f.write(script_data)
        os.chmod(script_path, script_mode)


def outputs_are_correct():
    try:
        assert_catalog_correct()
        assert_clean_archive_correct()
        return True
    except (AssertionError, OSError, ValueError, tarfile.TarError, json.JSONDecodeError):
        return False


def test_00_repo_directory_exists_and_backup_is_completely_extracted():
    """Check all supplied regular files and symlinks before executing the submitted script."""
    assert os.path.exists(REPO), f"Directory {REPO} does not exist."
    assert os.path.isdir(REPO), f"{REPO} is not a directory."
    assert os.path.exists(os.path.join(REPO, "app1")), "app1 is missing from the extracted repo."
    assert os.path.exists(os.path.join(REPO, "app2")), "app2 is missing from the extracted repo."

    for name, source in EXPECTED_BINARIES.items():
        path = os.path.join(REPO, name)
        st = os.lstat(path)
        assert stat.S_ISREG(st.st_mode), f"{name} must be an extracted regular file."
        assert file_digest(path) == file_digest(source), f"{name} does not match the supplied binary."
        assert get_elf_machine(path) is not None, f"{name} is not a valid ELF file."

    readme = os.path.join(REPO, "readme.txt")
    assert os.path.isfile(readme) and not os.path.islink(readme), "readme.txt was not extracted correctly."
    with open(readme, "rb") as f:
        assert f.read() == b"Some release notes\n"

    expected_links = {"loopA": "loopB", "loopB": "loopA", "valid_link": "app1"}
    for name, target in expected_links.items():
        path = os.path.join(REPO, name)
        assert os.path.islink(path), f"{name} must be an extracted symlink."
        assert os.readlink(path) == target, f"{name} has the wrong symlink target."
    assert os.path.realpath(os.path.join(REPO, "valid_link")) == os.path.join(REPO, "app1")


def test_01_python_script_exists_runs_and_handles_the_loop():
    """Execute the submitted Python script and require it to regenerate correct outputs."""
    assert SCRIPT_SNAPSHOTS, "No Python scanning script was written under /home/user."

    failures = []
    for script_path, script_data, script_mode in SCRIPT_SNAPSHOTS:
        reset_repo_for_script(script_path, script_data, script_mode)
        for output in (CATALOG, CLEAN_ARCHIVE):
            try:
                os.unlink(output)
            except FileNotFoundError:
                pass

        try:
            result = subprocess.run(
                ["python3", script_path],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=15,
            )
        except subprocess.TimeoutExpired:
            failures.append(f"{script_path}: timed out (possible symlink-loop hang)")
            continue

        if result.returncode == 0 and outputs_are_correct():
            return
        failures.append(f"{script_path}: exited {result.returncode} or produced incorrect outputs")

    pytest.fail("No submitted Python script regenerated the required artifacts: " + "; ".join(failures))


def test_elf_catalog_json():
    """Test that elf_catalog.json is correct and based on the supplied binaries."""
    assert_catalog_correct()

    machine_app1 = get_elf_machine(os.path.join(REPO, "app1"))
    machine_app2 = get_elf_machine(os.path.join(REPO, "app2"))
    assert machine_app1 is not None, "Could not determine Machine type for app1."
    assert machine_app2 is not None, "Could not determine Machine type for app2."
    with open(CATALOG) as f:
        catalog = json.load(f)
    assert catalog[os.path.join(REPO, "app1")] == machine_app1, "Incorrect Machine type for app1."
    assert catalog[os.path.join(REPO, "app2")] == machine_app2, "Incorrect Machine type for app2."


def test_clean_artifacts_archive():
    """Test archive names, types, ELF validity, and exact curated binary contents."""
    assert_clean_archive_correct()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
