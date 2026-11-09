#!/bin/bash
set +e
mkdir -p /logs/verifier
rm -f /logs/verifier/reward.txt /tmp/normalize_renames.log

cat > /tmp/rename_audit.c <<'AUDIT_EOF'
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static void absolute_path(const char *path, char *out, size_t size) {
    if (path && path[0] == '/') {
        snprintf(out, size, "%s", path);
        return;
    }
    char cwd[PATH_MAX];
    if (!getcwd(cwd, sizeof(cwd))) snprintf(cwd, sizeof(cwd), "?");
    snprintf(out, size, "%s/%s", cwd, path ? path : "?");
}

int rename(const char *oldpath, const char *newpath) {
    static int (*real_rename)(const char *, const char *) = NULL;
    if (!real_rename) real_rename = dlsym(RTLD_NEXT, "rename");

    char old_abs[PATH_MAX * 2];
    char new_abs[PATH_MAX * 2];
    absolute_path(oldpath, old_abs, sizeof(old_abs));
    absolute_path(newpath, new_abs, sizeof(new_abs));

    int result = real_rename(oldpath, newpath);
    int saved_errno = errno;
    int fd = open("/tmp/normalize_renames.log", O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (fd >= 0) {
        dprintf(fd, "%d\t%s\t%s\n", result, old_abs, new_abs);
        close(fd);
    }
    errno = saved_errno;
    return result;
}
AUDIT_EOF

prereq_ok=1
if [ ! -f /home/user/normalize.cpp ]; then
    prereq_ok=0
elif ! gcc -shared -fPIC -O2 /tmp/rename_audit.c -o /tmp/rename_audit.so -ldl; then
    prereq_ok=0
elif ! g++ -std=c++17 -O2 /home/user/normalize.cpp -o /tmp/normalize_under_test; then
    prereq_ok=0
else
    mkdir -p /home/user/processed
    find /home/user/processed -maxdepth 1 -type f \( -name '*.json' -o -name '*.jc' -o -name '*.tmp' \) -delete
    if ! (cd /home/user && LD_PRELOAD=/tmp/rename_audit.so timeout 120 /tmp/normalize_under_test); then
        prereq_ok=0
    fi
fi

cat > /tmp/test_final_state.py <<'TEST_EOF'
import glob
import json
import os
import subprocess
import tempfile
import pytest

CONFIG_DIR = "/home/user/configs"
PROCESSED_DIR = "/home/user/processed"


def parse_conf(path):
    result = {}
    with open(path, "r", encoding="utf-8") as f:
        for raw_line in f:
            line = raw_line.split("#", 1)[0].strip()
            if not line:
                continue
            assert "=" in line, f"Malformed source configuration line in {path}: {raw_line!r}"
            key, value = line.split("=", 1)
            result[key.strip()] = value.strip()
    return sorted(result.items())


def json_for_conf(conf_path):
    base = os.path.basename(conf_path)
    stem = os.path.splitext(base)[0]
    candidates = [
        os.path.join(PROCESSED_DIR, stem + ".json"),
        os.path.join(PROCESSED_DIR, base + ".json"),
    ]
    found = [p for p in candidates if os.path.isfile(p)]
    assert len(found) == 1, f"Expected exactly one JSON output for {conf_path}; found {found}"
    return found[0]


def jc_for_json(json_path):
    base = os.path.basename(json_path)
    without_json = base[:-5] if base.endswith(".json") else base
    candidates = [
        os.path.join(PROCESSED_DIR, without_json + ".jc"),
        os.path.join(PROCESSED_DIR, base + ".jc"),
    ]
    found = [p for p in candidates if os.path.isfile(p)]
    assert len(found) == 1, f"Expected exactly one compressed output for {json_path}; found {found}"
    return found[0]


def test_program_used_atomic_renames():
    assert os.path.isfile("/home/user/normalize.cpp"), "Missing required C++ source /home/user/normalize.cpp"
    assert os.path.getsize("/home/user/normalize.cpp") > 0, "normalize.cpp is empty"
    assert os.path.isfile("/tmp/normalize_renames.log"), "No atomic rename operations were observed"

    successful_destinations = set()
    with open("/tmp/normalize_renames.log", "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t", 2)
            if len(parts) == 3 and parts[0] == "0" and parts[1] != parts[2]:
                successful_destinations.add(os.path.normpath(parts[2]))

    json_files = glob.glob(os.path.join(PROCESSED_DIR, "*.json"))
    missing = [p for p in json_files if os.path.normpath(p) not in successful_destinations]
    assert not missing, f"JSON files were not installed with successful atomic renames: {missing}"


def test_json_files_exist_and_valid():
    json_files = glob.glob(os.path.join(PROCESSED_DIR, "*.json"))
    assert len(json_files) == 200, f"Expected 200 .json files in {PROCESSED_DIR}, found {len(json_files)}"

    conf_files = sorted(glob.glob(os.path.join(CONFIG_DIR, "*.conf")))
    assert len(conf_files) == 200, f"Expected 200 original .conf files, found {len(conf_files)}"
    matched_json = set()

    for conf in conf_files:
        jf = json_for_conf(conf)
        assert jf not in matched_json, f"JSON output {jf} was matched to multiple configuration files"
        matched_json.add(jf)
        with open(jf, "r", encoding="utf-8") as f:
            try:
                pairs = json.load(f, object_pairs_hook=list)
            except json.JSONDecodeError:
                pytest.fail(f"File {jf} is not valid JSON.")

        assert isinstance(pairs, list), f"File {jf} does not contain a JSON object."
        keys = []
        for k, v in pairs:
            assert isinstance(v, str), f"Value for key '{k}' in {jf} is not a string."
            keys.append(k)
        assert keys == sorted(keys), f"Keys in {jf} are not sorted alphabetically. Found: {keys}"
        assert pairs == parse_conf(conf), f"JSON content in {jf} does not match parsed source {conf}"

    assert matched_json == set(json_files), "Some JSON files do not correspond to a source configuration"


def test_compressed_files_are_genuine_and_ratio_passes():
    orig_files = glob.glob(os.path.join(CONFIG_DIR, "*.conf"))
    comp_files = glob.glob(os.path.join(PROCESSED_DIR, "*.jc"))

    assert len(orig_files) == 200, f"Expected 200 original .conf files, found {len(orig_files)}"
    assert len(comp_files) == 200, f"Expected 200 compressed .jc files in {PROCESSED_DIR}, found {len(comp_files)}"

    matched_jc = set()
    for conf in orig_files:
        jf = json_for_conf(conf)
        jc = jc_for_json(jf)
        assert jc not in matched_jc, f"Compressed output {jc} was matched to multiple JSON files"
        matched_jc.add(jc)
        with tempfile.NamedTemporaryFile(suffix=".jc", delete=False) as tmp:
            expected_path = tmp.name
        try:
            result = subprocess.run(
                ["/app/json_compressor", jf, expected_path],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
            assert result.returncode == 0, f"Reference compressor failed for {jf}"
            with open(expected_path, "rb") as f:
                expected = f.read()
            with open(jc, "rb") as f:
                actual = f.read()
            assert actual == expected, f"File {jc} is not the compressor output for {jf}"
        finally:
            if os.path.exists(expected_path):
                os.unlink(expected_path)

    assert matched_jc == set(comp_files), "Some compressed files do not correspond to a JSON output"

    orig_size = sum(os.path.getsize(f) for f in orig_files)
    comp_size = sum(os.path.getsize(f) for f in comp_files)
    assert comp_size > 0, "Total size of compressed files is 0, compression failed."
    ratio = orig_size / comp_size
    assert ratio >= 2.8, f"Compression ratio {ratio:.2f} is below the threshold of 2.8. Ensure noise is removed and keys are sorted."
TEST_EOF

if [ "$prereq_ok" -eq 1 ] && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
