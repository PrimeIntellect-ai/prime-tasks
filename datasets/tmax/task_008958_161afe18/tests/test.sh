#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import gzip
import os
import shutil
import subprocess
import tarfile
import tempfile
import zipfile

EXPECTED_NAMES = {"app_bin", "echo_tool.dat", "ls_exe"}
EXPECTED_DIRS = {"src", "scripts", "bin_hidden"}


def safe_extract(tar, destination):
    destination = os.path.realpath(destination)
    for member in tar.getmembers():
        name = member.name.replace("\\", "/")
        parts = [p for p in name.split("/") if p not in ("", ".")]
        assert not os.path.isabs(name), f"Unsafe absolute tar member: {name}"
        assert ".." not in parts, f"Unsafe parent traversal in tar member: {name}"
        assert not member.issym() and not member.islnk(), f"Links are not expected in tarball: {name}"
        target = os.path.realpath(os.path.join(destination, *parts))
        assert target == destination or target.startswith(destination + os.sep), f"Unsafe tar member: {name}"
    tar.extractall(destination)


def compile_expected_app():
    with tempfile.TemporaryDirectory() as tmp:
        output = os.path.join(tmp, "app_bin")
        subprocess.run(
            ["gcc", "-xc", "-", "-o", output],
            input=b"int main(){}\n",
            check=True,
        )
        with open(output, "rb") as f:
            return f.read()


def read_bytes(path):
    with open(path, "rb") as f:
        return f.read()


def tree_inventory(root):
    files = {}
    dirs = set()
    for current, dirnames, filenames in os.walk(root, followlinks=False):
        rel_current = os.path.relpath(current, root)
        if rel_current != ".":
            dirs.add(rel_current.replace(os.sep, "/"))
        for dirname in dirnames:
            path = os.path.join(current, dirname)
            assert not os.path.islink(path), f"Unexpected symlink: {path}"
        for filename in filenames:
            path = os.path.join(current, filename)
            assert os.path.isfile(path) and not os.path.islink(path), f"Unexpected non-regular file: {path}"
            rel = os.path.relpath(path, root).replace(os.sep, "/")
            files[rel] = read_bytes(path)
    return dirs, files


def expected_state():
    app = compile_expected_app()
    echo_binary = read_bytes("/bin/echo")
    ls_binary = read_bytes("/bin/ls")

    pristine_plain = {
        "src/app_bin": app,
        "src/main.c": b"#include <stdio.h>\nint main() {\n  OLD_MACRO_XYZ();\n  return 0;\n}\n",
        "scripts/test.py": b"def test():\n    print('OLD_MACRO_XYZ()')\n",
        "bin_hidden/echo_tool.dat": echo_binary,
        "ls_exe": ls_binary,
        "logs.txt": b"Log entry: OLD_MACRO_XYZ() executed.\n",
    }

    # Validate that the supplied archive itself is still the original fixture.
    archive = "/home/user/messy_project.tar.gz"
    assert os.path.isfile(archive), f"Source archive {archive} is missing."
    with tempfile.TemporaryDirectory() as tmp:
        with tarfile.open(archive, "r:gz") as t:
            safe_extract(t, tmp)
        dirs, files = tree_inventory(tmp)
        assert dirs == EXPECTED_DIRS, f"Unexpected source archive directories: {dirs}"
        assert set(files) == {
            "src/app_bin", "src/main.c", "scripts/test.py",
            "bin_hidden/echo_tool.dat", "ls_exe", "logs.txt.gz"
        }, f"Unexpected source archive files: {set(files)}"
        assert files["src/app_bin"] == app, "The source app_bin does not match the supplied fixture."
        assert files["src/main.c"] == pristine_plain["src/main.c"]
        assert files["scripts/test.py"] == pristine_plain["scripts/test.py"]
        assert files["bin_hidden/echo_tool.dat"] == echo_binary
        assert files["ls_exe"] == ls_binary
        assert gzip.decompress(files["logs.txt.gz"]) == pristine_plain["logs.txt"]

    binaries = {
        "app_bin": app,
        "echo_tool.dat": echo_binary,
        "ls_exe": ls_binary,
    }
    clean_files = {
        path: data.replace(b"OLD_MACRO_XYZ()", b"NEW_MACRO_ABC()")
        for path, data in pristine_plain.items()
        if path not in {"src/app_bin", "bin_hidden/echo_tool.dat", "ls_exe"}
    }
    return binaries, clean_files


EXPECTED_BINARIES, EXPECTED_CLEAN_FILES = expected_state()


def assert_exact_clean_tree(root):
    dirs, files = tree_inventory(root)
    assert dirs == EXPECTED_DIRS, f"Workspace directory structure differs: expected {EXPECTED_DIRS}, got {dirs}"
    assert set(files) == set(EXPECTED_CLEAN_FILES), (
        f"Workspace files differ: expected {set(EXPECTED_CLEAN_FILES)}, got {set(files)}"
    )
    for relpath, expected in EXPECTED_CLEAN_FILES.items():
        assert files[relpath] == expected, f"Incorrect content in workspace file {relpath}"


def test_elf_list_file():
    log_file = "/home/user/elf_list.txt"
    assert os.path.exists(log_file), f"Log file {log_file} does not exist."
    with open(log_file, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_binaries = sorted(["app_bin", "echo_tool.dat", "ls_exe"])
    assert lines == expected_binaries, f"Expected {expected_binaries} in {log_file}, but got {lines}."


def test_binaries_archive_zip():
    zip_path = "/home/user/binaries_archive.zip"
    assert os.path.exists(zip_path), f"Zip archive {zip_path} does not exist."
    assert zipfile.is_zipfile(zip_path), f"File {zip_path} is not a valid zip archive."

    with zipfile.ZipFile(zip_path, "r") as z:
        namelist = z.namelist()
        basenames = [os.path.basename(n) for n in namelist if not n.endswith('/')]
        expected_binaries = {"app_bin", "echo_tool.dat", "ls_exe"}
        assert expected_binaries.issubset(set(basenames)), f"Zip archive is missing some expected binaries. Found: {basenames}"
        for n in namelist:
            if n in expected_binaries:
                assert "/" not in n, f"File {n} should be at the root of the zip archive, not in a subdirectory."


def test_workspace_clean_tarball():
    tar_path = "/home/user/workspace_clean.tar.bz2"
    assert os.path.exists(tar_path), f"Tarball {tar_path} does not exist."
    assert tarfile.is_tarfile(tar_path), f"File {tar_path} is not a valid tar archive."

    with tempfile.TemporaryDirectory() as tmpdir:
        with tarfile.open(tar_path, "r:bz2") as t:
            safe_extract(t, tmpdir)

        logs_txt_found = False
        logs_txt_gz_found = False
        old_macro_found = False
        new_macro_found = False
        elf_found = False

        for root, dirs, files in os.walk(tmpdir):
            for file in files:
                filepath = os.path.join(root, file)
                if file == "logs.txt":
                    logs_txt_found = True
                if file == "logs.txt.gz":
                    logs_txt_gz_found = True
                try:
                    with open(filepath, "r", encoding="utf-8") as f:
                        content = f.read()
                        if "OLD_MACRO_XYZ()" in content:
                            old_macro_found = True
                        if "NEW_MACRO_ABC()" in content:
                            new_macro_found = True
                except UnicodeDecodeError:
                    with open(filepath, "rb") as f:
                        if f.read(4) == b"\x7fELF":
                            elf_found = True

        assert logs_txt_found, "logs.txt was not found in the extracted tarball (should have been decompressed)."
        assert not logs_txt_gz_found, "logs.txt.gz should have been decompressed and removed."
        assert not old_macro_found, "Found OLD_MACRO_XYZ() in the workspace tarball. It should have been replaced."
        assert new_macro_found, "Did not find NEW_MACRO_ABC() in the workspace tarball."
        assert not elf_found, "Found an ELF binary in the workspace tarball. They should have been moved."


def test_workspace_no_elfs_and_macros_replaced():
    workspace_path = "/home/user/workspace"
    assert os.path.isdir(workspace_path), f"Workspace directory {workspace_path} does not exist."

    for root, dirs, files in os.walk(workspace_path):
        for file in files:
            filepath = os.path.join(root, file)
            with open(filepath, "rb") as f:
                header = f.read(4)
                assert header != b"\x7fELF", f"Found ELF binary {filepath} still in workspace."
            try:
                with open(filepath, "r", encoding="utf-8") as f:
                    content = f.read()
                    assert "OLD_MACRO_XYZ()" not in content, f"File {filepath} still contains OLD_MACRO_XYZ()."
            except UnicodeDecodeError:
                pass


def test_binaries_directory_contains_elfs():
    binaries_path = "/home/user/binaries"
    assert os.path.exists(binaries_path), f"Directory {binaries_path} does not exist."

    found_files = set(os.listdir(binaries_path))
    expected_files = {"app_bin", "echo_tool.dat", "ls_exe"}
    assert expected_files.issubset(found_files), f"Expected {expected_files} in {binaries_path}, got {found_files}."

    for file in expected_files:
        filepath = os.path.join(binaries_path, file)
        with open(filepath, "rb") as f:
            header = f.read(4)
            assert header == b"\x7fELF", f"File {filepath} is not an ELF binary."


def test_exact_workspace_and_binary_contents():
    assert_exact_clean_tree("/home/user/workspace")

    dirs, files = tree_inventory("/home/user/binaries")
    assert dirs == set(), f"Unexpected directories in /home/user/binaries: {dirs}"
    assert set(files) == EXPECTED_NAMES, f"Unexpected binary directory contents: {set(files)}"
    for name, expected in EXPECTED_BINARIES.items():
        assert files[name] == expected, f"Binary {name} does not match the binary from the supplied archive."

    with open("/home/user/elf_list.txt", "r", encoding="utf-8") as f:
        assert f.read().splitlines() == sorted(EXPECTED_NAMES), "elf_list.txt must contain exactly the sorted binary names."


def test_exact_zip_contents():
    with zipfile.ZipFile("/home/user/binaries_archive.zip", "r") as z:
        assert z.namelist() == sorted(z.namelist()), "Zip entries should be deterministically ordered."
        assert set(z.namelist()) == EXPECTED_NAMES, f"Zip must contain only root-level binaries: {z.namelist()}"
        for name, expected in EXPECTED_BINARIES.items():
            assert z.read(name) == expected, f"Zip entry {name} has incorrect binary content."


def test_exact_clean_tar_tree():
    tar_path = "/home/user/workspace_clean.tar.bz2"
    with tempfile.TemporaryDirectory() as tmp:
        with tarfile.open(tar_path, "r:bz2") as t:
            safe_extract(t, tmp)

        candidates = [tmp]
        for root, dirs, files in os.walk(tmp):
            if os.path.basename(root) == "workspace":
                candidates.append(root)

        matched = False
        for candidate in candidates:
            try:
                assert_exact_clean_tree(candidate)
            except AssertionError:
                continue

            candidate_rel = os.path.relpath(candidate, tmp)
            candidate_rel = "" if candidate_rel == "." else candidate_rel.replace(os.sep, "/")
            actual_dirs, actual_files = tree_inventory(tmp)
            expected_global_files = {
                (candidate_rel + "/" + p).strip("/"): data
                for p, data in EXPECTED_CLEAN_FILES.items()
            }
            prefix_dirs = set()
            if candidate_rel:
                parts = candidate_rel.split("/")
                prefix_dirs = {"/".join(parts[:i]) for i in range(1, len(parts) + 1)}
            expected_global_dirs = prefix_dirs | {
                (candidate_rel + "/" + d).strip("/") for d in EXPECTED_DIRS
            }
            if actual_dirs == expected_global_dirs and actual_files == expected_global_files:
                matched = True
                break

        assert matched, "Clean tarball does not preserve the exact transformed workspace tree and file contents."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
