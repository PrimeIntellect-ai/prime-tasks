#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import shutil
import stat
import subprocess
import sys

import pytest

RAW_DIR = "/home/user/raw_files"
ORGANIZED_DIR = "/home/user/organized"
ORGANIZER = "/home/user/organizer.py"
E2E = "/home/user/test_e2e.sh"
LOG = "/home/user/allocation.log"
EXPECTED_FILES = {"a.c", "b.c", "c.py", "d.c", "e.c", "f.py"}
BIN_RE = re.compile(r"^bin_[1-9][0-9]*$")


def raw_files():
    names = {name for name in os.listdir(RAW_DIR)
             if os.path.isfile(os.path.join(RAW_DIR, name))}
    assert names == EXPECTED_FILES, f"Unexpected raw source set: {names}"
    return names


def architecture(path):
    with open(path, "r", encoding="utf-8") as f:
        first_line = f.readline()
    if "ARCH: x86" in first_line:
        return "x86"
    if "ARCH: arm" in first_line:
        return "arm"
    if "ARCH: any" in first_line:
        return "any"
    pytest.fail(f"No recognized ARCH header in {path}")


def minimum_bin_count():
    items = [(os.path.getsize(os.path.join(RAW_DIR, name)),
              architecture(os.path.join(RAW_DIR, name)))
             for name in sorted(raw_files())]
    items.sort(reverse=True)

    def feasible(limit):
        bins = []

        def place(index):
            if index == len(items):
                return True
            size, arch = items[index]
            seen = set()
            for i, (used, bin_arch) in enumerate(bins):
                state = (used, bin_arch)
                if state in seen:
                    continue
                seen.add(state)
                compatible = arch == "any" or bin_arch in (None, arch)
                if used + size <= 100 and compatible:
                    new_arch = bin_arch if arch == "any" else arch
                    bins[i] = (used + size, new_arch)
                    if place(index + 1):
                        return True
                    bins[i] = (used, bin_arch)
            if len(bins) < limit and size <= 100:
                bins.append((size, None if arch == "any" else arch))
                if place(index + 1):
                    return True
                bins.pop()
            return False

        return place(0)

    for count in range(1, len(items) + 1):
        if feasible(count):
            return count
    pytest.fail("Raw files cannot be packed")


def inspect_organized(expected_allocation=None):
    assert os.path.isdir(ORGANIZED_DIR), f"{ORGANIZED_DIR} does not exist."
    entries = os.listdir(ORGANIZED_DIR)
    bin_names = {name for name in entries
                 if os.path.isdir(os.path.join(ORGANIZED_DIR, name))}
    assert bin_names, "No bins were created"
    assert all(BIN_RE.fullmatch(name) for name in bin_names), \
        f"Non-numbered bin directories found: {bin_names}"

    found = {}
    for filename in raw_files():
        locations = [name for name in bin_names
                     if os.path.isfile(os.path.join(ORGANIZED_DIR, name, filename))]
        assert len(locations) == 1, \
            f"Expected exactly one organized copy of {filename}, found {locations}"
        found[filename] = locations[0]

    if expected_allocation is not None:
        assert found == expected_allocation, \
            f"allocation.log does not match organized files: {found}"
        assert bin_names == set(expected_allocation.values()), \
            "Organized bins do not match allocation.log"

    assert len(bin_names) == minimum_bin_count(), \
        f"Expected the minimum number of bins, found {len(bin_names)}"

    for bin_name in bin_names:
        members = [name for name, assigned in found.items() if assigned == bin_name]
        assert members, f"Empty bin {bin_name}"
        total_size = 0
        arches = set()
        for filename in members:
            source = os.path.join(RAW_DIR, filename)
            destination = os.path.join(ORGANIZED_DIR, bin_name, filename)
            with open(source, "rb") as src, open(destination, "rb") as dst:
                assert dst.read() == src.read(), \
                    f"Organized file {destination} differs from its source"
            total_size += os.path.getsize(destination)
            arches.add(architecture(source))

        assert total_size <= 100, f"Bin {bin_name} exceeds 100 bytes: {total_size} bytes."
        assert not ({"x86", "arm"} <= arches), \
            f"Bin {bin_name} contains both x86 and arm files."

        build_path = os.path.join(ORGANIZED_DIR, bin_name, "build.sh")
        assert os.path.isfile(build_path), f"build.sh missing in {bin_name}"
        assert os.stat(build_path).st_mode & stat.S_IXUSR, \
            f"build.sh in {bin_name} is not executable."
        with open(build_path, "r", encoding="utf-8") as f:
            content = f.read().strip()
        if "x86" in arches:
            assert "gcc -m64 -c *.c" in content, \
                f"build.sh in {bin_name} missing x86 command."
        elif "arm" in arches:
            assert "aarch64-linux-gnu-gcc -c *.c" in content, \
                f"build.sh in {bin_name} missing arm command."
        else:
            assert "python3 -m py_compile *.*" in content, \
                f"build.sh in {bin_name} missing any command."

        subprocess.run(["bash", build_path], cwd=os.path.join(ORGANIZED_DIR, bin_name),
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20,
                       check=False)
    return found


def test_00_required_artifacts_execute_and_reproduce_sources():
    assert os.path.isfile(ORGANIZER), f"File {ORGANIZER} does not exist."
    assert os.path.isfile(E2E), f"File {E2E} does not exist."

    with open(ORGANIZER, "r", encoding="utf-8") as f:
        organizer_source = f.read()
    tree = ast.parse(organizer_source, ORGANIZER)
    class_names = {node.name for node in ast.walk(tree) if isinstance(node, ast.ClassDef)}
    assert class_names, "organizer.py must define a custom bin data structure"
    constructed = {
        node.func.id for node in ast.walk(tree)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
    }
    assert class_names & constructed, \
        "The custom bin data structure must be instantiated and used"

    with open(E2E, "r", encoding="utf-8") as f:
        e2e_source = f.read()
    assert "organizer.py" in e2e_source, "test_e2e.sh does not run organizer.py"
    assert "build.sh" in e2e_source, "test_e2e.sh does not execute bin build scripts"

    shutil.rmtree(ORGANIZED_DIR, ignore_errors=True)
    direct = subprocess.run([sys.executable, ORGANIZER], cwd="/home/user",
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, timeout=30)
    assert direct.returncode == 0, \
        f"organizer.py failed:\nstdout={direct.stdout}\nstderr={direct.stderr}"
    inspect_organized()

    os.makedirs(ORGANIZED_DIR, exist_ok=True)
    sentinel = os.path.join(ORGANIZED_DIR, "must_be_cleared")
    with open(sentinel, "w", encoding="utf-8") as f:
        f.write("stale")
    if os.path.exists(LOG):
        os.remove(LOG)

    result = subprocess.run(["bash", E2E], cwd="/home/user",
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, timeout=60)
    assert result.returncode == 0, \
        f"test_e2e.sh failed:\nstdout={result.stdout}\nstderr={result.stderr}"
    assert not os.path.exists(sentinel), "test_e2e.sh did not clear organized/"
    assert os.path.isfile(LOG), f"File {LOG} does not exist."
    with open(LOG, "r", encoding="utf-8") as f:
        allocation = json.load(f)
    inspect_organized(allocation)


def test_allocation_log_exists_and_valid():
    assert os.path.isfile(LOG), f"File {LOG} does not exist."
    with open(LOG, "r") as f:
        try:
            allocation = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{LOG} is not valid JSON.")
    assert set(allocation.keys()) == EXPECTED_FILES, \
        f"Allocation log keys do not match expected files: {EXPECTED_FILES}"
    bins = set(allocation.values())
    assert len(bins) == 2, \
        f"Expected exactly 2 bins to minimize bins, found {len(bins)}: {bins}"
    assert all(isinstance(name, str) and BIN_RE.fullmatch(name) for name in bins), \
        f"Invalid bin names: {bins}"


def test_conflict_constraint():
    with open(LOG, "r") as f:
        allocation = json.load(f)
    bin_a = allocation.get("a.c")
    bin_b = allocation.get("b.c")
    assert bin_a is not None and bin_b is not None, \
        "Missing allocation for a.c or b.c"
    assert bin_a != bin_b, \
        "Conflict constraint violated: a.c (x86) and b.c (arm) are in the same bin."


def test_build_scripts_and_capacity():
    with open(LOG, "r") as f:
        allocation = json.load(f)
    assert os.path.isdir(ORGANIZED_DIR), f"{ORGANIZED_DIR} does not exist."
    bins = set(allocation.values())
    for bin_name in bins:
        bin_dir = os.path.join(ORGANIZED_DIR, bin_name)
        assert os.path.isdir(bin_dir), f"Bin directory {bin_dir} does not exist."
        total_size = 0
        bin_files = [f for f, b in allocation.items() if b == bin_name]
        has_x86 = False
        has_arm = False
        for filename in bin_files:
            file_path = os.path.join(bin_dir, filename)
            assert os.path.isfile(file_path), f"File {filename} missing in {bin_dir}"
            total_size += os.path.getsize(file_path)
            with open(file_path, "r", encoding="utf-8") as file_obj:
                content = file_obj.read()
                if "ARCH: x86" in content:
                    has_x86 = True
                if "ARCH: arm" in content:
                    has_arm = True
        assert total_size <= 100, f"Bin {bin_name} exceeds 100 bytes: {total_size} bytes."
        assert not (has_x86 and has_arm), \
            f"Bin {bin_name} contains both x86 and arm files."
        build_script_path = os.path.join(bin_dir, "build.sh")
        assert os.path.isfile(build_script_path), f"build.sh missing in {bin_dir}"
        assert os.stat(build_script_path).st_mode & stat.S_IXUSR, \
            f"build.sh in {bin_dir} is not executable."
        with open(build_script_path, "r", encoding="utf-8") as build_obj:
            build_content = build_obj.read().strip()
        if has_x86:
            assert "gcc -m64 -c *.c" in build_content, \
                f"build.sh in {bin_dir} missing x86 command."
        elif has_arm:
            assert "aarch64-linux-gnu-gcc -c *.c" in build_content, \
                f"build.sh in {bin_dir} missing arm command."
        else:
            assert "python3 -m py_compile *.*" in build_content, \
                f"build.sh in {bin_dir} missing any command."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
