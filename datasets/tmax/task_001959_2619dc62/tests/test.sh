#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import shutil
import subprocess
import tempfile
import time
import pytest

CJSON_DIR = "/app/cJSON-1.7.15"
LIB_PATH = os.path.join(CJSON_DIR, "libcjson.so")
EXE_PATH = "/home/user/parser_app/semver_parser"
JSON_PATH = "/home/user/parser_app/versions.json"
OUTPUT_PATH = "/home/user/highest_version.txt"
PATCH_PATH = "/home/user/cjson-fix.patch"


def get_max_semver(versions):
    def parse_version(v):
        v = v.lstrip('v')
        parts = v.split('.')
        return tuple(int(p) if p.isdigit() else 0 for p in parts)
    return max(versions, key=parse_version)


def parser_env():
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = CJSON_DIR + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
    return env


def apply_reverse_patch_to_copy():
    patch_text = open(PATCH_PATH, "r", encoding="utf-8", errors="replace").read()
    assert re.search(r"^---\s+.*Makefile", patch_text, re.MULTILINE), "Patch is not a unified diff for the Makefile."
    assert re.search(r"^\+[^+].*-fPIC(?:\s|$)", patch_text, re.MULTILINE), "Patch does not add the required -fPIC flag."

    for strip_level in (0, 1, 2, 3):
        parent = tempfile.mkdtemp(prefix="cjson-unpatched-")
        candidate = os.path.join(parent, "tree")
        shutil.copytree(CJSON_DIR, candidate, symlinks=True)
        dry = subprocess.run(
            ["patch", "--batch", "--reverse", "--dry-run", f"-p{strip_level}", "-i", PATCH_PATH],
            cwd=candidate, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
        )
        if dry.returncode == 0:
            applied = subprocess.run(
                ["patch", "--batch", "--reverse", f"-p{strip_level}", "-i", PATCH_PATH],
                cwd=candidate, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
            )
            assert applied.returncode == 0, applied.stdout
            return parent, candidate
        shutil.rmtree(parent)
    pytest.fail("The patch cannot be reverse-applied to the submitted Makefile.")


def test_patch_exists():
    assert os.path.isfile(PATCH_PATH), f"Patch file {PATCH_PATH} does not exist."
    assert os.path.getsize(PATCH_PATH) > 0, f"Patch file {PATCH_PATH} is empty."


def test_makefile_patch_and_fresh_shared_build():
    parent, unpatched_tree = apply_reverse_patch_to_copy()
    try:
        subprocess.run(["make", "clean"], cwd=unpatched_tree, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        old_build = subprocess.run(["make", "shared"], cwd=unpatched_tree, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        assert old_build.returncode != 0, "Reversing the submitted patch still builds the shared library; the patch does not represent the required linking fix."
    finally:
        shutil.rmtree(parent)

    subprocess.run(["make", "clean"], cwd=CJSON_DIR, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    build = subprocess.run(["make", "shared"], cwd=CJSON_DIR, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    assert build.returncode == 0, f"A clean shared-library build failed:\n{build.stdout}"


def test_libcjson_built():
    assert os.path.isfile(LIB_PATH), f"Shared library {LIB_PATH} does not exist. Did you fix the Makefile and build it?"
    elf = subprocess.run(["readelf", "-h", LIB_PATH], capture_output=True, text=True)
    assert elf.returncode == 0 and re.search(r"Type:\s+DYN", elf.stdout), "libcjson.so is not an ELF shared object."
    symbols = subprocess.run(["nm", "-D", LIB_PATH], capture_output=True, text=True)
    assert symbols.returncode == 0 and re.search(r"\bcJSON_Parse\b", symbols.stdout), "libcjson.so does not export cJSON_Parse."


def test_semver_parser_executable():
    assert os.path.isfile(EXE_PATH), f"Executable {EXE_PATH} does not exist."
    assert os.access(EXE_PATH, os.X_OK), f"File {EXE_PATH} is not executable."
    elf = subprocess.run(["readelf", "-h", EXE_PATH], capture_output=True, text=True)
    assert elf.returncode == 0, "semver_parser is not an ELF executable."

    dynamic = subprocess.run(["readelf", "-d", EXE_PATH], capture_output=True, text=True)
    assert dynamic.returncode == 0 and re.search(r"NEEDED.*libcjson\.so", dynamic.stdout), "semver_parser is not dynamically linked to libcjson."

    symbols = subprocess.run(["nm", "-D", EXE_PATH], capture_output=True, text=True)
    assert symbols.returncode == 0, symbols.stderr
    assert re.search(r"\bU\s+cJSON_Parse\b", symbols.stdout), "semver_parser does not call the shared cJSON parser."
    assert re.search(r"\bU\s+cJSON_Delete\b", symbols.stdout), "semver_parser does not call cJSON_Delete to release the parsed JSON tree."


def test_highest_version_output():
    assert os.path.isfile(JSON_PATH), f"Input JSON {JSON_PATH} missing."
    with open(JSON_PATH, 'r') as f:
        try:
            versions = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Could not parse {JSON_PATH} as JSON.")

    expected_max = get_max_semver(versions)
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist."
    with open(OUTPUT_PATH, 'r') as f:
        actual_output = f.read().strip()
    assert actual_output == expected_max, f"Expected highest version {expected_max}, but got {actual_output}"


def test_parser_on_fresh_derived_inputs():
    old_output = open(OUTPUT_PATH, "rb").read() if os.path.exists(OUTPUT_PATH) else None
    try:
        for _ in range(3):
            versions = [f"{random.randint(0, 30)}.{random.randint(0, 999)}.{random.randint(0, 999)}" for _ in range(150)]
            winner = f"{random.randint(50, 90)}.{random.randint(100, 900)}.{random.randint(100, 900)}"
            versions.append(winner)
            random.shuffle(versions)

            fd, input_path = tempfile.mkstemp(prefix="semver-input-", suffix=".json")
            os.close(fd)
            try:
                with open(input_path, "w") as f:
                    json.dump(versions, f)
                if os.path.exists(OUTPUT_PATH):
                    os.unlink(OUTPUT_PATH)
                result = subprocess.run([EXE_PATH, input_path], env=parser_env(), capture_output=True, text=True, timeout=15)
                assert result.returncode == 0, f"semver_parser failed on a fresh input: {result.stderr}"
                assert os.path.isfile(OUTPUT_PATH), "semver_parser did not create highest_version.txt when executed."
                with open(OUTPUT_PATH) as f:
                    actual = f.read().strip()
                expected = max(versions, key=lambda v: tuple(map(int, v.split('.'))))
                assert actual == expected, f"Fresh-input result was {actual!r}; expected {expected!r}."
            finally:
                os.unlink(input_path)
    finally:
        if old_output is None:
            if os.path.exists(OUTPUT_PATH):
                os.unlink(OUTPUT_PATH)
        else:
            with open(OUTPUT_PATH, "wb") as f:
                f.write(old_output)


def test_valgrind_memory_leak():
    log_path = "/tmp/valgrind.log"
    cmd = [
        "valgrind", "--leak-check=full", "--show-leak-kinds=definite",
        "--error-exitcode=97", f"--log-file={log_path}", EXE_PATH, JSON_PATH
    ]
    result = subprocess.run(cmd, env=parser_env(), capture_output=True, text=True, timeout=120)
    assert result.returncode == 0, f"Running semver_parser under valgrind failed. Stderr: {result.stderr}"
    assert os.path.isfile(log_path), "Valgrind log file was not generated."
    with open(log_path, "r") as f:
        log_content = f.read()
    match = re.search(r"definitely lost:\s+([0-9,]+)\s+bytes", log_content)
    assert match is not None, "Could not find 'definitely lost' metric in valgrind output."
    lost_bytes = int(match.group(1).replace(",", ""))
    assert lost_bytes <= 0, f"Memory leak detected: {lost_bytes} bytes definitely lost. Threshold is 0."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
