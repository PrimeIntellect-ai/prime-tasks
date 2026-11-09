#!/bin/bash
mkdir -p /logs/verifier

if (
set -e

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import tarfile
import pytest

ARTIFACTS_DIR = "/home/user/artifacts"
CSV_PATH = "/home/user/curated_summary.csv"
TAR_PATH = "/home/user/stable_artifacts.tar.gz"
RELEASE_LIST_PATH = "/home/user/release_list.txt"

EXPECTED_META = {
    "alpha": {
        "version": "1.0",
        "expected": {"name": "alpha", "version": "1.0", "status": "stable", "curated_at": 1700000000}
    },
    "beta": {
        "version": "2.1",
        "expected": {"name": "beta", "version": "2.1", "status": "stable"}
    },
    "gamma": {
        "version": "0.9",
        "expected": {"name": "gamma", "version": "0.9", "status": "stable", "curated_at": 1700000000}
    }
}

@pytest.mark.parametrize("pkg_name, pkg_info", EXPECTED_META.items())
def test_meta_json_updated(pkg_name, pkg_info):
    version = pkg_info["version"]
    meta_file = os.path.join(ARTIFACTS_DIR, pkg_name, version, "meta.json")
    assert os.path.isfile(meta_file), f"Metadata file {meta_file} is missing."
    with open(meta_file, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {meta_file} is not valid JSON.")
    assert data == pkg_info["expected"], f"Metadata in {meta_file} does not match expected final state."

def test_curated_summary_csv():
    assert os.path.isfile(CSV_PATH), f"CSV file {CSV_PATH} is missing."
    with open(CSV_PATH, "r", newline="") as f:
        rows = list(csv.reader(f))
    assert len(rows) > 0, f"CSV file {CSV_PATH} is empty."
    assert rows[0] == ["name", "version", "status"], f"CSV header is incorrect: {rows[0]}"
    data_rows = sorted(rows[1:])
    expected_rows = sorted([
        ["alpha", "1.0", "stable"],
        ["beta", "2.1", "stable"],
        ["gamma", "0.9", "stable"]
    ])
    assert data_rows == expected_rows, f"CSV data rows do not match expected. Found: {data_rows}"

def test_stable_artifacts_tarball():
    assert os.path.isfile(TAR_PATH), f"Tarball {TAR_PATH} is missing."
    try:
        with tarfile.open(TAR_PATH, "r:gz") as tar:
            members = tar.getnames()
            expected_files = {
                "alpha/1.0/bin.dat", "alpha/1.0/meta.json",
                "beta/2.1/bin.dat", "beta/2.1/meta.json",
                "gamma/0.9/bin.dat", "gamma/0.9/meta.json"
            }
            actual_files = {m for m in members if not m.endswith("/") and m in expected_files}
            missing = expected_files - set(members)
            assert not missing, f"Tarball is missing expected files: {missing}"
            extra = {m for m in members if not any(m.startswith(d) for d in ["alpha", "beta", "gamma"])}
            assert not extra, f"Tarball contains unexpected files: {extra}"

            regular_files = {m.name for m in tar.getmembers() if m.isfile()}
            assert regular_files == expected_files, f"Tarball regular-file set is incorrect: {regular_files}"
            for name in expected_files:
                archived = tar.extractfile(name)
                assert archived is not None, f"Cannot read archived file {name}"
                with open(os.path.join(ARTIFACTS_DIR, name), "rb") as current:
                    assert archived.read() == current.read(), f"Archived content differs for {name}"
    except tarfile.TarError:
        pytest.fail(f"File {TAR_PATH} is not a valid gzip-compressed tarball.")

def test_release_list_txt():
    assert os.path.isfile(RELEASE_LIST_PATH), f"Release list file {RELEASE_LIST_PATH} is missing."
    assert os.path.isfile(CSV_PATH), f"Cannot verify release list order because {CSV_PATH} is missing."
    with open(CSV_PATH, "r", newline="") as f:
        csv_rows = list(csv.reader(f))[1:]
    expected_lines = [f"Package: {row[0]} v{row[1]}" for row in csv_rows]
    with open(RELEASE_LIST_PATH, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    assert actual_lines == expected_lines, f"Release list content or order is incorrect. Expected: {expected_lines}, Found: {actual_lines}"
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short

test -d /home/user/curator
test -f /home/user/curator/Cargo.toml
find /home/user/curator -type f -name '*.rs' -print -quit | grep -q .

cargo build --release --manifest-path /home/user/curator/Cargo.toml --message-format=json-render-diagnostics > /tmp/cargo-build.json
python3 - <<'PY'
import json
executables = []
with open('/tmp/cargo-build.json') as f:
    for line in f:
        try:
            item = json.loads(line)
        except json.JSONDecodeError:
            continue
        exe = item.get('executable')
        target = item.get('target', {})
        if exe and 'bin' in target.get('kind', []):
            executables.append(exe)
assert executables, 'Cargo build produced no Rust binary executable'
with open('/tmp/curator_bin', 'w') as f:
    f.write(executables[-1])
PY
CURATOR_BIN="$(cat /tmp/curator_bin)"
test -x "$CURATOR_BIN"

cat <<'C_EOF' > /tmp/rename_trace.c
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>

static void record(const char *op, const char *oldpath, const char *newpath) {
    char cwd[4096];
    if (!getcwd(cwd, sizeof(cwd))) cwd[0] = '\0';
    int fd = open("/tmp/rename-events.log", O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd >= 0) {
        dprintf(fd, "%s\t%s\t%s\t%s\n", op, cwd,
                oldpath ? oldpath : "", newpath ? newpath : "");
        close(fd);
    }
}

int rename(const char *oldpath, const char *newpath) {
    static int (*real_fn)(const char *, const char *);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "rename");
    int rc = real_fn(oldpath, newpath);
    if (rc == 0) record("rename", oldpath, newpath);
    return rc;
}

int renameat(int olddirfd, const char *oldpath, int newdirfd, const char *newpath) {
    static int (*real_fn)(int, const char *, int, const char *);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "renameat");
    int rc = real_fn(olddirfd, oldpath, newdirfd, newpath);
    if (rc == 0) record("renameat", oldpath, newpath);
    return rc;
}

int renameat2(int olddirfd, const char *oldpath, int newdirfd, const char *newpath, unsigned int flags) {
    static int (*real_fn)(int, const char *, int, const char *, unsigned int);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "renameat2");
    int rc = real_fn(olddirfd, oldpath, newdirfd, newpath, flags);
    if (rc == 0) record("renameat2", oldpath, newpath);
    return rc;
}
C_EOF
cc -shared -fPIC -o /tmp/rename_trace.so /tmp/rename_trace.c -ldl

python3 - <<'PY'
import json, os, uuid
root = '/home/user/artifacts/nested-' + uuid.uuid4().hex
cases = []
for status in ('testing', 'stable', 'deprecated'):
    name = status + '-' + uuid.uuid4().hex
    version = str(int(uuid.uuid4().hex[:6], 16)) + '.7'
    directory = os.path.join(root, 'branch', name, version)
    os.makedirs(directory)
    metadata = {'name': name, 'version': version, 'status': status, 'marker': uuid.uuid4().hex}
    with open(os.path.join(directory, 'meta.json'), 'w') as f:
        json.dump(metadata, f)
    with open(os.path.join(directory, 'bin.dat'), 'wb') as f:
        f.write(os.urandom(31))
    cases.append({'directory': directory, 'before': metadata})
with open('/tmp/dynamic-cases.json', 'w') as f:
    json.dump(cases, f)
PY

rm -f /tmp/rename-events.log
(
  cd /home/user/curator
  LD_PRELOAD=/tmp/rename_trace.so "$CURATOR_BIN"
)

python3 - <<'PY'
import csv, json, os

with open('/tmp/dynamic-cases.json') as f:
    cases = json.load(f)

testing_meta = None
for case in cases:
    path = os.path.join(case['directory'], 'meta.json')
    with open(path) as f:
        actual = json.load(f)
    expected = dict(case['before'])
    if expected['status'] == 'testing':
        expected['status'] = 'stable'
        expected['curated_at'] = 1700000000
        testing_meta = os.path.abspath(path)
    assert actual == expected, f'dynamic metadata mismatch for {path}: {actual}'
    assert not os.path.exists(path + '.tmp'), f'temporary metadata file was left behind: {path}.tmp'

expected_rows = []
for root, dirs, files in os.walk('/home/user/artifacts'):
    if 'meta.json' not in files:
        continue
    with open(os.path.join(root, 'meta.json')) as f:
        data = json.load(f)
    if data.get('status') == 'stable':
        expected_rows.append([str(data['name']), str(data['version']), 'stable'])

with open('/home/user/curated_summary.csv', newline='') as f:
    rows = list(csv.reader(f))
assert rows and rows[0] == ['name', 'version', 'status'], 'CSV header changed after executing curator'
assert sorted(rows[1:]) == sorted(expected_rows), f'curator did not derive CSV from all recursive metadata: {rows[1:]}'

assert testing_meta is not None
wanted_old = testing_meta + '.tmp'
wanted_new = testing_meta
found = False
with open('/tmp/rename-events.log') as f:
    for line in f:
        fields = line.rstrip('\n').split('\t')
        if len(fields) != 4:
            continue
        _, cwd, old, new = fields
        if not os.path.isabs(old):
            old = os.path.abspath(os.path.join(cwd, old))
        if not os.path.isabs(new):
            new = os.path.abspath(os.path.join(cwd, new))
        if old == wanted_old and new == wanted_new:
            found = True
            break
assert found, 'testing metadata was not installed by atomically renaming meta.json.tmp to meta.json'
PY
) then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
