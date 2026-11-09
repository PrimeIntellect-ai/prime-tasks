#!/bin/bash
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_task.py
import hashlib
import os
import secrets
import shutil
import subprocess
import zipfile

HOME = "/home/user"
SOURCE = os.path.join(HOME, "extract.go")
ARCHIVE = os.path.join(HOME, "update.zip")
DEST = os.path.join(HOME, "configs")
ESCAPED = os.path.join(HOME, "escaped.json")
BINARY = "/tmp/extract_submission"


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(4096), b""):
            h.update(block)
    return h.hexdigest()


def run_extractor():
    result = subprocess.run(
        [BINARY], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=30
    )
    assert result.returncode == 0, (
        "Extractor did not run cleanly.\nstdout:\n%s\nstderr:\n%s"
        % (result.stdout, result.stderr)
    )


def clean_destination():
    if os.path.lexists(DEST):
        if os.path.islink(DEST) or not os.path.isdir(DEST):
            os.unlink(DEST)
        else:
            shutil.rmtree(DEST)


def assert_safe_tree(expected):
    assert os.path.isdir(DEST) and not os.path.islink(DEST), \
        "Extractor did not create a real configs directory"

    found = set()
    root_real = os.path.realpath(DEST)
    for root, dirs, files in os.walk(DEST):
        for name in dirs + files:
            path = os.path.join(root, name)
            assert not os.path.islink(path), f"Unexpected symlink in extraction tree: {path}"
            resolved = os.path.realpath(path)
            assert os.path.commonpath([root_real, resolved]) == root_real, \
                f"Extracted path resolves outside configs: {path}"
        for name in files:
            found.add(os.path.relpath(os.path.join(root, name), DEST))

    assert found == set(expected), f"Unexpected extracted files: {sorted(found)}"
    for relative, content in expected.items():
        path = os.path.join(DEST, relative)
        assert os.path.isfile(path), f"Expected extracted file missing: {path}"
        with open(path, "rb") as f:
            assert f.read() == content, f"Content mismatch in {path}"


# The submitted artifact itself must exist, be source code, compile, and execute.
assert os.path.isfile(SOURCE) and not os.path.islink(SOURCE), \
    f"Missing regular Go source file: {SOURCE}"
assert not os.path.exists(ESCAPED), \
    f"Vulnerability not patched: {ESCAPED} already exists"

build = subprocess.run(
    ["go", "build", "-o", BINARY, SOURCE], cwd=HOME,
    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
)
assert build.returncode == 0, (
    "extract.go does not compile cleanly.\nstdout:\n%s\nstderr:\n%s"
    % (build.stdout, build.stderr)
)

# Exercise the compiled extractor on unpredictable safe and traversal paths.
token = secrets.token_hex(12)
safe_top = f"generated-{token}.json"
safe_nested = f"nested-{token}/value.txt"
outside_home = os.path.join(HOME, f"escaped-{token}.txt")
outside_sibling = os.path.join(HOME, f"configs-evil-{token}", "payload.txt")
for path in (outside_home, outside_sibling):
    if os.path.lexists(path):
        raise AssertionError(f"Unexpected pre-existing test path: {path}")

clean_destination()
with zipfile.ZipFile(ARCHIVE, "w") as z:
    z.writestr(safe_top, b"dynamic top-level content\n")
    z.writestr(safe_nested, b"dynamic nested content\n")
    z.writestr(f"../../../home/user/escaped-{token}.txt", b"must not escape\n")
    z.writestr(f"../configs-evil-{token}/payload.txt", b"must not escape sibling\n")

run_extractor()
assert not os.path.exists(outside_home), "Zip Slip wrote outside configs"
assert not os.path.exists(outside_sibling), "Zip Slip wrote into a sibling directory"
assert_safe_tree({
    safe_top: b"dynamic top-level content\n",
    safe_nested: b"dynamic nested content\n",
})

# Recreate the task archive and run the submitted extractor on it so the original
# final-state assertions inspect output produced by the Go program.
clean_destination()
assert not os.path.exists(ESCAPED), "Traversal test created escaped.json"
with zipfile.ZipFile(ARCHIVE, "w") as z:
    z.writestr("main.json", b'{"version": 1}\n')
    z.writestr("sub/db.json", b'{"db": "mysql"}\n')
    z.writestr("../../../home/user/escaped.json", b'{"pwned": true}\n')

run_extractor()

# Preserve the original verifier's final-state assertions.
assert not os.path.exists(ESCAPED), (
    f"Vulnerability not patched: The file {ESCAPED} was extracted outside the intended directory."
)

main_json = os.path.join(DEST, "main.json")
sub_db_json = os.path.join(DEST, "sub", "db.json")
assert os.path.isfile(main_json), f"Expected extracted file missing: {main_json}"
assert os.path.isfile(sub_db_json), f"Expected extracted file missing: {sub_db_json}"
with open(main_json, "r") as f:
    assert '{"version": 1}' in f.read(), f"Content mismatch in {main_json}"
with open(sub_db_json, "r") as f:
    assert '{"db": "mysql"}' in f.read(), f"Content mismatch in {sub_db_json}"

manifest_path = os.path.join(HOME, "manifest.txt")
assert os.path.isfile(manifest_path), f"Manifest file missing at {manifest_path}"
expected_main_hash = sha256(main_json) if os.path.exists(main_json) else "MISSING"
expected_sub_hash = sha256(sub_db_json) if os.path.exists(sub_db_json) else "MISSING"
with open(manifest_path, "r") as f:
    lines = [line.strip() for line in f if line.strip()]

assert len(lines) == 2, f"Manifest should contain exactly 2 entries, found {len(lines)}"
parsed_manifest = {}
for line in lines:
    parts = line.split(None, 1)
    assert len(parts) == 2, f"Invalid manifest line format: '{line}'"
    hash_val, filename = parts
    if filename.startswith("./"):
        filename = filename[2:]
    parsed_manifest[filename] = hash_val

assert "main.json" in parsed_manifest, "Manifest is missing entry for main.json"
assert "sub/db.json" in parsed_manifest, "Manifest is missing entry for sub/db.json"
assert parsed_manifest["main.json"] == expected_main_hash, \
    "Hash mismatch for main.json in manifest"
assert parsed_manifest["sub/db.json"] == expected_sub_hash, \
    "Hash mismatch for sub/db.json in manifest"
assert lines[0].endswith("main.json"), \
    "Manifest is not sorted alphabetically by filename (expected main.json first)"
assert lines[1].endswith("db.json"), \
    "Manifest is not sorted alphabetically by filename (expected sub/db.json second)"
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
