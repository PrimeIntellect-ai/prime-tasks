#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import re
import secrets
import subprocess
import zipfile

import pytest
import yaml

SCRIPT = "/home/user/apply_update.py"
CONFIG = "/home/user/config.json"
SUMMARY = "/home/user/summary.yaml"
ARCHIVE = "/home/user/update.zip"
CHECKSUM = "/home/user/update.zip.sha256"


def get_elf_info(filepath):
    out_h = subprocess.check_output(['readelf', '-h', filepath], text=True)
    entry_point = None
    for line in out_h.splitlines():
        if 'Entry point address:' in line:
            entry_point = hex(int(line.split(':')[1].strip(), 16))
            break

    out_s = subprocess.check_output(['readelf', '-W', '-S', filepath], text=True)
    text_size = None
    for line in out_s.splitlines():
        if '.text' in line:
            parts = line.split()
            try:
                idx = parts.index('.text')
                text_size = int(parts[idx + 4], 16)
                break
            except (ValueError, IndexError):
                continue

    return entry_point, text_size


def test_config_json_updated():
    config_path = "/home/user/config.json"
    assert os.path.isfile(config_path), f"Missing configuration file at {config_path}"

    with open(config_path, 'r') as f:
        try:
            config = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {config_path} does not contain valid JSON"

    assert config.get('host') == 'localhost', "config.json 'host' should be 'localhost'"
    assert config.get('retries') == '5', "config.json 'retries' should be '5' (applied from WAL txn 1)"
    assert config.get('timeout') == '30', "config.json 'timeout' should be '30' (applied from WAL txn 3)"
    assert 'debug' not in config, "config.json 'debug' should be deleted (applied from WAL txn 4)"

    expected_keys = {'host', 'retries', 'timeout'}
    assert set(config.keys()) == expected_keys, f"config.json contains unexpected keys: {set(config.keys()) - expected_keys}"


def test_summary_yaml_created_and_correct():
    summary_path = "/home/user/summary.yaml"
    assert os.path.isfile(summary_path), f"Missing summary file at {summary_path}"

    with open(summary_path, 'r') as f:
        content = f.read()

    ep_match = re.search(r'entry_point:\s*["\']?(0x[0-9a-fA-F]+)["\']?', content)
    assert ep_match, "Could not find valid 'entry_point' in summary.yaml"
    actual_entry_point = ep_match.group(1)

    ts_match = re.search(r'text_size:\s*(\d+)', content)
    assert ts_match, "Could not find valid 'text_size' in summary.yaml"
    actual_text_size = int(ts_match.group(1))

    keys_section = re.search(r'config_keys:\s*\n(\s*-\s*\w+\s*\n?)+', content)
    assert keys_section, "Could not find 'config_keys' list in summary.yaml"
    actual_keys = re.findall(r'-\s*(\w+)', keys_section.group(0))

    firmware_path = "/tmp/firmware.elf"
    assert os.path.isfile(firmware_path), f"Missing firmware at {firmware_path} to verify against"

    expected_entry_point, expected_text_size = get_elf_info(firmware_path)
    assert expected_entry_point is not None, "Failed to determine expected entry point from firmware"
    assert expected_text_size is not None, "Failed to determine expected .text size from firmware"

    assert int(actual_entry_point, 16) == int(expected_entry_point, 16), \
        f"Expected entry_point {expected_entry_point}, but got {actual_entry_point}"
    assert actual_text_size == expected_text_size, \
        f"Expected text_size {expected_text_size}, but got {actual_text_size}"

    expected_keys = ['host', 'retries', 'timeout']
    assert actual_keys == expected_keys, \
        f"Expected config_keys {expected_keys}, but got {actual_keys}"


def build_atomic_monitor():
    source = r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static void record(const char *oldpath, const char *newpath) {
    const char *log = getenv("ATOMIC_LOG");
    if (!log || !oldpath || !newpath) return;
    FILE *f = fopen(log, "a");
    if (f) {
        fprintf(f, "%s|%s\n", oldpath, newpath);
        fclose(f);
    }
}

int rename(const char *oldpath, const char *newpath) {
    static int (*real_fn)(const char *, const char *) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "rename");
    int result = real_fn(oldpath, newpath);
    if (result == 0) record(oldpath, newpath);
    return result;
}

int renameat(int olddirfd, const char *oldpath, int newdirfd, const char *newpath) {
    static int (*real_fn)(int, const char *, int, const char *) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "renameat");
    int result = real_fn(olddirfd, oldpath, newdirfd, newpath);
    if (result == 0) record(oldpath, newpath);
    return result;
}

int renameat2(int olddirfd, const char *oldpath, int newdirfd, const char *newpath, unsigned int flags) {
    static int (*real_fn)(int, const char *, int, const char *, unsigned int) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "renameat2");
    int result = real_fn(olddirfd, oldpath, newdirfd, newpath, flags);
    if (result == 0) record(oldpath, newpath);
    return result;
}
'''
    src = "/tmp/atomic_monitor.c"
    library = "/tmp/atomic_monitor.so"
    with open(src, "w") as f:
        f.write(source)
    subprocess.run(["gcc", "-shared", "-fPIC", "-o", library, src, "-ldl"], check=True)
    return library


def write_archive(wal_text, firmware_path):
    with zipfile.ZipFile(ARCHIVE, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("changes.wal", wal_text)
        archive.write(firmware_path, "firmware.elf")
    with open(ARCHIVE, "rb") as f:
        digest = hashlib.sha256(f.read()).hexdigest()
    with open(CHECKSUM, "w") as f:
        f.write(digest + "\n")


def test_script_exists_and_handles_fresh_inputs_atomically():
    assert os.path.isfile(SCRIPT), f"Missing required script at {SCRIPT}"
    assert os.path.getsize(SCRIPT) > 0, f"Script at {SCRIPT} is empty"

    token = secrets.token_hex(6)
    base_key = "base_" + token
    target_key = "target_" + token
    added_key = "added_" + token
    deleted_key = "deleted_" + token
    first_value = "first_" + token
    final_value = "final_" + token
    added_value = "value_" + token

    initial = {
        base_key: "keep_" + token,
        target_key: "old_" + token,
        deleted_key: "remove_" + token,
    }
    with open(CONFIG, "w") as f:
        json.dump(initial, f)

    wal = "\n".join([
        f"30:SET:{target_key}:{final_value}",
        f"40:DELETE:{deleted_key}",
        f"10:SET:{target_key}:{first_value}",
        f"20:SET:{added_key}:{added_value}",
    ]) + "\n"

    # A valid archive with an intentionally wrong checksum must be rejected before
    # its WAL can change the configuration.
    write_archive(wal, "/bin/ls")
    with open(CHECKSUM, "w") as f:
        f.write("0" * 64 + "\n")
    before = open(CONFIG, "rb").read()
    failed = subprocess.run(
        ["python3", SCRIPT], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=30
    )
    assert failed.returncode == 1, "Checksum mismatch must make the script exit with code 1"
    assert (failed.stdout + failed.stderr).strip(), "Checksum failure must print an error"
    assert open(CONFIG, "rb").read() == before, "Configuration changed despite checksum failure"

    # Run again with a correct checksum and a firmware/WAL chosen by the verifier.
    write_archive(wal, "/bin/ls")
    expected_entry, expected_text_size = get_elf_info("/bin/ls")
    monitor = build_atomic_monitor()
    atomic_log = "/tmp/atomic_replacements.log"
    open(atomic_log, "w").close()
    env = os.environ.copy()
    env["LD_PRELOAD"] = monitor
    env["ATOMIC_LOG"] = atomic_log
    completed = subprocess.run(
        ["python3", SCRIPT], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=30, env=env
    )
    assert completed.returncode == 0, \
        f"Script failed on valid verifier-generated input: {completed.stdout}{completed.stderr}"

    with open(CONFIG) as f:
        actual_config = json.load(f)
    expected_config = {
        base_key: "keep_" + token,
        target_key: final_value,
        added_key: added_value,
    }
    assert actual_config == expected_config, \
        "Script did not parse and apply the shuffled WAL in ascending transaction order"

    with open(SUMMARY) as f:
        summary = yaml.safe_load(f)
    assert isinstance(summary, dict), "summary.yaml must contain a YAML mapping"
    assert set(summary) == {"firmware", "config_keys"}, "summary.yaml has the wrong top-level structure"
    assert isinstance(summary["firmware"], dict), "firmware must be a mapping"
    assert set(summary["firmware"]) == {"entry_point", "text_size"}, "firmware metadata structure is incorrect"
    assert isinstance(summary["firmware"]["entry_point"], str), "entry_point must be a hexadecimal string"
    assert re.fullmatch(r"0x[0-9a-fA-F]+", summary["firmware"]["entry_point"]), "Invalid entry_point format"
    assert int(summary["firmware"]["entry_point"], 16) == int(expected_entry, 16), \
        "Entry point was not extracted from the archived verifier-selected firmware"
    assert type(summary["firmware"]["text_size"]) is int, "text_size must be an integer"
    assert summary["firmware"]["text_size"] == expected_text_size, \
        ".text size was not extracted from the archived verifier-selected firmware"
    assert summary["config_keys"] == sorted(expected_config), "config_keys must include all keys in alphabetical order"

    with open(atomic_log) as f:
        replacements = [line.strip().split("|", 1) for line in f if "|" in line]
    config_replacements = [(src, dst) for src, dst in replacements if dst == CONFIG]
    assert config_replacements, "config.json was not installed using an atomic rename/replace operation"
    assert any(src != CONFIG and os.path.dirname(src) == "/home/user" for src, _ in config_replacements), \
        "Atomic replacement must use a temporary file in the same directory as config.json"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
