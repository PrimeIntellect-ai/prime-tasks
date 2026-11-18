#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import json
import os
import pathlib
import shutil
import subprocess
import tarfile
import tempfile
import zipfile

import pytest

GO_FILE = "/home/user/rename_elfs.go"
EXTRACTED = "/home/user/extracted"
ARCH_HELPER = "/tmp/verifier_elf_machine"


def build_arch_helper():
    if os.path.exists(ARCH_HELPER):
        return
    source = r'''
package main

import (
    "debug/elf"
    "fmt"
    "os"
)

func main() {
    if len(os.Args) != 2 {
        os.Exit(2)
    }
    f, err := elf.Open(os.Args[1])
    if err != nil {
        os.Exit(1)
    }
    defer f.Close()
    fmt.Print(f.FileHeader.Machine.String())
}
'''
    src = "/tmp/verifier_elf_machine.go"
    pathlib.Path(src).write_text(source)
    subprocess.run(["go", "build", "-o", ARCH_HELPER, src], check=True)


def machine_for(path):
    build_arch_helper()
    result = subprocess.run(
        [ARCH_HELPER, str(path)], capture_output=True, text=True, check=True
    )
    return result.stdout


def archive_members():
    with tarfile.open("/home/user/project_files.tar.gz", "r:gz") as outer:
        member = outer.getmember("inner.zip")
        nested = outer.extractfile(member).read()
    with zipfile.ZipFile(io.BytesIO(nested)) as inner:
        return {name: inner.read(name) for name in inner.namelist()}


def test_go_program_exists():
    go_file = "/home/user/rename_elfs.go"
    assert os.path.exists(go_file), f"The Go program {go_file} does not exist."
    assert os.path.isfile(go_file), f"{go_file} is not a file."


def test_go_program_compiles_and_imports_debug_elf():
    env = os.environ.copy()
    env["GO111MODULE"] = "off"
    listed = subprocess.run(
        ["go", "list", "-f={{json .Imports}}", "rename_elfs.go"],
        cwd="/home/user",
        env=env,
        capture_output=True,
        text=True,
        check=True,
    )
    imports = json.loads(listed.stdout)
    assert "debug/elf" in imports, "rename_elfs.go must directly import the standard debug/elf package."
    subprocess.run(
        ["go", "build", "-o", "/tmp/submitted_rename_elfs", GO_FILE],
        env=env,
        check=True,
    )


def test_extracted_directory_contents():
    extracted_dir = "/home/user/extracted"
    assert os.path.exists(extracted_dir), f"The extracted directory {extracted_dir} does not exist."
    assert os.path.isdir(extracted_dir), f"{extracted_dir} is not a directory."

    files = os.listdir(extracted_dir)

    # Check notes.txt
    assert "notes.txt" in files, "notes.txt is missing from the extracted directory."

    # Check inner.zip is deleted
    assert "inner.zip" not in files, "inner.zip was not deleted from the extracted directory."

    # Find renamed ELF files
    sys_ls_renamed = [f for f in files if f.startswith("sys_ls_EM_") and f.endswith(".elf")]
    sys_cat_renamed = [f for f in files if f.startswith("sys_cat_EM_") and f.endswith(".elf")]

    assert len(sys_ls_renamed) == 1, "sys_ls was not properly renamed with its ELF architecture."
    assert len(sys_cat_renamed) == 1, "sys_cat was not properly renamed with its ELF architecture."

    # Check that the original sys_ls and sys_cat files do not exist
    assert "sys_ls" not in files, "The original sys_ls file was not renamed/removed."
    assert "sys_cat" not in files, "The original sys_cat file was not renamed/removed."

    original = archive_members()
    ls_path = pathlib.Path(extracted_dir, sys_ls_renamed[0])
    cat_path = pathlib.Path(extracted_dir, sys_cat_renamed[0])
    notes_path = pathlib.Path(extracted_dir, "notes.txt")

    assert ls_path.is_file() and ls_path.read_bytes() == original["sys_ls"]
    assert cat_path.is_file() and cat_path.read_bytes() == original["sys_cat"]
    assert notes_path.is_file() and notes_path.read_bytes() == original["notes.txt"]

    ls_machine = machine_for(ls_path)
    cat_machine = machine_for(cat_path)
    assert sys_ls_renamed[0] == f"sys_ls_{ls_machine}.elf"
    assert sys_cat_renamed[0] == f"sys_cat_{cat_machine}.elf"
    assert set(files) == {
        "notes.txt",
        f"sys_ls_{ls_machine}.elf",
        f"sys_cat_{cat_machine}.elf",
    }, "The extracted directory contains missing, extra, or incorrectly named files."


def test_program_behaviour_on_independent_elf_inputs():
    # Build a foreign-architecture ELF so the program must inspect each file's
    # Machine field rather than assuming the host architecture.
    root = pathlib.Path(tempfile.mkdtemp(prefix="rename_elf_test_"))
    saved = root / "saved_extracted"
    arm_src = root / "arm.go"
    arm_bin = root / "arm_binary"
    arm_src.write_text("package main\nfunc main() {}\n")
    env = os.environ.copy()
    env.update({"GO111MODULE": "off", "GOOS": "linux", "GOARCH": "arm64", "CGO_ENABLED": "0"})
    subprocess.run(["go", "build", "-o", str(arm_bin), str(arm_src)], env=env, check=True)

    host_bytes = pathlib.Path("/bin/true").read_bytes()
    arm_bytes = arm_bin.read_bytes()
    host_machine = machine_for("/bin/true")
    arm_machine = machine_for(arm_bin)
    assert host_machine != arm_machine

    os.rename(EXTRACTED, saved)
    try:
        os.mkdir(EXTRACTED)
        pathlib.Path(EXTRACTED, "probe_host").write_bytes(host_bytes)
        pathlib.Path(EXTRACTED, "probe_arm").write_bytes(arm_bytes)
        pathlib.Path(EXTRACTED, "plain.txt").write_text("not an ELF file\n")

        subprocess.run(["/tmp/submitted_rename_elfs"], cwd="/home/user", check=True, timeout=30)

        expected = {
            f"probe_host_{host_machine}.elf",
            f"probe_arm_{arm_machine}.elf",
            "plain.txt",
        }
        assert set(os.listdir(EXTRACTED)) == expected
        assert pathlib.Path(EXTRACTED, f"probe_host_{host_machine}.elf").read_bytes() == host_bytes
        assert pathlib.Path(EXTRACTED, f"probe_arm_{arm_machine}.elf").read_bytes() == arm_bytes
        assert pathlib.Path(EXTRACTED, "plain.txt").read_text() == "not an ELF file\n"
    finally:
        if os.path.isdir(EXTRACTED):
            shutil.rmtree(EXTRACTED)
        elif os.path.exists(EXTRACTED):
            os.unlink(EXTRACTED)
        os.rename(saved, EXTRACTED)
        shutil.rmtree(root, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
