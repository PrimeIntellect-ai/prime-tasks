#!/bin/bash
mkdir -p /logs/verifier

cat > /tmp/rename_audit.c <<'C_EOF'
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void absolute_path(int dirfd, const char *path, char *out, size_t size) {
    if (!path) {
        snprintf(out, size, "(null)");
        return;
    }
    if (path[0] == '/') {
        snprintf(out, size, "%s", path);
        return;
    }

    char base[PATH_MAX] = {0};
    if (dirfd == AT_FDCWD) {
        if (!getcwd(base, sizeof(base))) snprintf(base, sizeof(base), ".");
    } else {
        char procpath[64];
        snprintf(procpath, sizeof(procpath), "/proc/self/fd/%d", dirfd);
        ssize_t n = readlink(procpath, base, sizeof(base) - 1);
        if (n < 0) snprintf(base, sizeof(base), ".");
        else base[n] = '\0';
    }
    snprintf(out, size, "%s/%s", base, path);
}

static void record_rename(int olddirfd, const char *oldpath, int newdirfd, const char *newpath) {
    const char *logpath = getenv("RENAME_AUDIT_LOG");
    if (!logpath) return;

    char oldabs[PATH_MAX * 2];
    char newabs[PATH_MAX * 2];
    absolute_path(olddirfd, oldpath, oldabs, sizeof(oldabs));
    absolute_path(newdirfd, newpath, newabs, sizeof(newabs));

    int fd = open(logpath, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd >= 0) {
        dprintf(fd, "%s\t%s\n", oldabs, newabs);
        close(fd);
    }
}

int rename(const char *oldpath, const char *newpath) {
    static int (*real_rename)(const char *, const char *);
    if (!real_rename) real_rename = dlsym(RTLD_NEXT, "rename");
    record_rename(AT_FDCWD, oldpath, AT_FDCWD, newpath);
    return real_rename(oldpath, newpath);
}

int renameat(int olddirfd, const char *oldpath, int newdirfd, const char *newpath) {
    static int (*real_renameat)(int, const char *, int, const char *);
    if (!real_renameat) real_renameat = dlsym(RTLD_NEXT, "renameat");
    record_rename(olddirfd, oldpath, newdirfd, newpath);
    return real_renameat(olddirfd, oldpath, newdirfd, newpath);
}

int renameat2(int olddirfd, const char *oldpath, int newdirfd, const char *newpath, unsigned int flags) {
    static int (*real_renameat2)(int, const char *, int, const char *, unsigned int);
    if (!real_renameat2) real_renameat2 = dlsym(RTLD_NEXT, "renameat2");
    record_rename(olddirfd, oldpath, newdirfd, newpath);
    return real_renameat2(olddirfd, oldpath, newdirfd, newpath, flags);
}
C_EOF

cat > /tmp/test_final_state.py <<'PY_EOF'
import json
import os
import shutil
import subprocess

import pytest

INVENTORY_PATH = "/home/user/organized_elfs/inventory.json"
ORGANIZED_DIR = "/home/user/organized_elfs"
MESSY_DIR = "/home/user/messy_project"
AUDIT_SO = "/tmp/rename_audit.so"
AUDIT_LOG = "/tmp/rename_audit.log"


def parse_elf(path):
    try:
        proc = subprocess.run(
            ["/usr/bin/readelf", "-h", path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if proc.returncode != 0:
        return None

    machine = None
    elf_type = None
    for line in proc.stdout.splitlines():
        stripped = line.strip()
        if stripped.startswith("Machine:"):
            machine = stripped.split(":", 1)[1].strip()
        elif stripped.startswith("Type:"):
            elf_type = stripped.split(":", 1)[1].strip()
    if not machine or not elf_type:
        return None
    return machine, elf_type


def expected_elfs():
    result = {}
    for root, dirs, files in os.walk(MESSY_DIR, followlinks=False):
        for name in files:
            path = os.path.abspath(os.path.join(root, name))
            if not os.path.isfile(path):
                continue
            header = parse_elf(path)
            if header is not None:
                result[path] = header
    return result


def load_inventory():
    assert os.path.isfile(INVENTORY_PATH), f"{INVENTORY_PATH} does not exist."
    with open(INVENTORY_PATH, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{INVENTORY_PATH} is not valid JSON.")
    assert isinstance(data, list), "Inventory JSON should be a list of objects."
    return data


def validate_inventory():
    data = load_inventory()
    expected = expected_elfs()
    expected_files = {"app_64", "app_32", "libtest.so"}
    found_files = set()
    seen_originals = set()

    for entry in data:
        assert isinstance(entry, dict), "Each inventory entry must be an object."
        assert "original_path" in entry, "Missing original_path in entry"
        assert "linked_path" in entry, "Missing linked_path in entry"
        assert "machine" in entry, "Missing machine in entry"
        assert "type" in entry, "Missing type in entry"

        orig_path = entry["original_path"]
        linked_path = entry["linked_path"]
        machine = entry["machine"]
        elf_type = entry["type"]
        assert all(isinstance(v, str) for v in (orig_path, linked_path, machine, elf_type))

        orig_abs = os.path.abspath(orig_path)
        assert orig_path == orig_abs, "original_path must be absolute and normalized."
        assert os.path.commonpath([MESSY_DIR, orig_abs]) == MESSY_DIR, \
            f"Original path {orig_path} is not under {MESSY_DIR}."
        assert os.path.commonpath([os.path.realpath(MESSY_DIR), os.path.realpath(orig_path)]) == os.path.realpath(MESSY_DIR), \
            f"Original path {orig_path} resolves outside {MESSY_DIR}."
        assert orig_path in expected, f"Original path {orig_path} is not a valid ELF file found in the project."
        assert orig_path not in seen_originals, f"Duplicate inventory entry for {orig_path}."
        seen_originals.add(orig_path)

        parsed_machine, parsed_type = expected[orig_path]
        assert machine == parsed_machine, f"Incorrect machine for {orig_path}: expected {parsed_machine!r}."
        assert elf_type == parsed_type, f"Incorrect type for {orig_path}: expected {parsed_type!r}."

        assert os.path.isfile(orig_path), f"Original path {orig_path} does not exist."
        assert os.path.isfile(linked_path), f"Linked path {linked_path} does not exist."
        assert parse_elf(linked_path) == expected[orig_path], f"Linked file {linked_path} is not the expected ELF."

        orig_stat = os.stat(orig_path)
        link_stat = os.stat(linked_path)
        assert (orig_stat.st_dev, orig_stat.st_ino) == (link_stat.st_dev, link_stat.st_ino), \
            f"File {linked_path} is not a hardlink to {orig_path}."
        assert not os.path.islink(linked_path), f"File {linked_path} must not be a symbolic link."

        filename = os.path.basename(orig_path)
        found_files.add(filename)
        machine_clean = machine.replace(" ", "_").replace("(", "").replace(")", "")
        type_clean = elf_type.replace(" ", "_").replace("(", "").replace(")", "")
        expected_linked_path = os.path.join(ORGANIZED_DIR, machine_clean, type_clean, filename)
        assert linked_path == expected_linked_path, \
            f"Linked path {linked_path} does not match expected {expected_linked_path}"

    assert seen_originals == set(expected), \
        f"Inventory must contain every and only valid ELF file. Expected {set(expected)}, found {seen_originals}"
    assert expected_files.issubset(found_files), \
        f"Missing ELF files in inventory. Expected {expected_files}, found {found_files}"
    assert "main.c" not in found_files, "main.c should not be in the inventory"
    assert "build.log" not in found_files, "build.log should not be in the inventory"


def candidate_scripts():
    candidates = []
    script_found = False
    found_atomic = False
    for root, dirs, files in os.walk("/home/user"):
        if "organized_elfs" in root or "messy_project" in root:
            dirs[:] = []
            continue
        for name in files:
            if not name.endswith((".py", ".sh", ".rb")):
                continue
            path = os.path.join(root, name)
            try:
                with open(path, "r", encoding="utf-8") as f:
                    content = f.read()
            except Exception:
                continue
            if "inventory.json" in content:
                script_found = True
                if "replace" in content or "rename" in content or "mv " in content:
                    found_atomic = True
                    candidates.append(path)

    assert script_found, "No submitted script mentioning inventory.json was found."
    assert found_atomic, "Script found but does not appear to use atomic write (rename/replace/mv)."
    return sorted(candidates)


def atomic_rename_observed():
    if not os.path.isfile(AUDIT_LOG):
        return False
    destination = os.path.normpath(INVENTORY_PATH)
    with open(AUDIT_LOG, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t", 1)
            if len(parts) != 2:
                continue
            source = os.path.normpath(parts[0])
            target = os.path.normpath(parts[1])
            if (target == destination and source != target and
                    os.path.dirname(source) == os.path.dirname(target)):
                return True
    return False


@pytest.fixture(scope="session", autouse=True)
def execute_submitted_solution():
    failures = []
    for script in candidate_scripts():
        shutil.rmtree(ORGANIZED_DIR, ignore_errors=True)
        try:
            os.unlink(AUDIT_LOG)
        except FileNotFoundError:
            pass

        if script.endswith(".py"):
            command = ["python3", script]
        elif script.endswith(".rb"):
            ruby = shutil.which("ruby")
            if not ruby:
                failures.append(f"{script}: ruby is unavailable")
                continue
            command = [ruby, script]
        else:
            command = ["bash", script]

        env = os.environ.copy()
        env["HOME"] = "/home/user"
        env["PATH"] = "/usr/local/bin:/usr/bin:/bin"
        env["LD_PRELOAD"] = AUDIT_SO
        env["RENAME_AUDIT_LOG"] = AUDIT_LOG
        try:
            proc = subprocess.run(
                command,
                cwd=os.path.dirname(script),
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=120,
            )
            assert proc.returncode == 0, f"exit status {proc.returncode}: {proc.stderr[-1000:]}"
            assert atomic_rename_observed(), \
                "no rename of a temporary file in organized_elfs to inventory.json was observed"
            validate_inventory()
            return
        except Exception as exc:
            failures.append(f"{script}: {exc}")

    pytest.fail("No submitted script successfully recreated the required output atomically. " + " | ".join(failures))


def test_inventory_exists_and_valid():
    validate_inventory()


def test_atomic_write_logic_in_scripts():
    # Preserve the source-level assertion and also require observed atomic behavior.
    assert candidate_scripts()
    assert atomic_rename_observed(), \
        "The executed script did not atomically rename a same-directory temporary file to inventory.json."
PY_EOF

if gcc -shared -fPIC -O2 -o /tmp/rename_audit.so /tmp/rename_audit.c -ldl >/tmp/audit_build.log 2>&1 && \
   python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
