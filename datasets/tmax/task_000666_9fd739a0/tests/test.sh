#!/bin/bash
mkdir -p /logs/verifier
status=0

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import gzip
import stat
import pytest

def test_script_exists_and_executable():
    script_path = "/home/user/pack_docs.sh"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"The script {script_path} is not executable."

def test_archive_exists():
    archive_path = "/home/user/archive/docs_custom.gz"
    assert os.path.isfile(archive_path), f"The archive {archive_path} does not exist."

def test_archive_contents():
    archive_path = "/home/user/archive/docs_custom.gz"
    assert os.path.isfile(archive_path), f"The archive {archive_path} does not exist."

    expected_content = """===FILE: endpoints.md===
# API Endpoints
These are the endpoints.
Copyright 2024 Acme Global
===FILE: setup.txt===
Setup Guide
Please follow these steps.
Copyright 2024 Acme Global
===FILE: readme.md===
# Main Readme
Welcome to the docs.
Copyright 2024 Acme Global. All rights reserved.
"""

    with gzip.open(archive_path, 'rt', encoding='utf-8') as f:
        actual_content = f.read()

    assert actual_content == expected_content, "The decompressed content of the archive does not match the expected output."
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || status=1

if [ "$status" -eq 0 ]; then
    python3 - <<'PY' || status=1
import os
import re
import shutil
import secrets

script = "/home/user/pack_docs.sh"
with open(script, "r", encoding="utf-8") as f:
    source = f.read()
assert source.startswith("#!") and "bash" in source.splitlines()[0], "pack_docs.sh must be a Bash script"
assert re.search(r"\bfind\b", source), "The script must find the documentation files"
assert re.search(r"\bgzip\b", source), "The script must invoke gzip"
assert re.search(r"\b(?:sed|awk|gawk)\b", source), "The script must use sed or awk stream processing"

root = "/home/user/docs_raw"
shutil.rmtree(root)
os.makedirs(os.path.join(root, "a"))
os.makedirs(os.path.join(root, "b", "nested"))
token = secrets.token_hex(24)
files = {
    "a/first doc.txt": (
        "first " + token + "\n"
        "Copyright 2018 Acme Corp and Copyright 2018 Acme Corp\n"
    ).encode(),
    "a/zeta.md": ("zeta\nCopyright 2018 Acme Corporation\n" + token).encode(),
    "b/alpha.txt": ("duplicate basename\n" + token + "\n").encode(),
    "b/nested/alpha.txt": b"nested file without a final newline",
    "root.md": b"Copyright 2018 Acme Corp. All rights reserved.\n",
}
for rel, data in files.items():
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)

with open(os.path.join(root, "ignored.bin"), "wb") as f:
    f.write(("MUST_NOT_APPEAR_" + token).encode())
with open(os.path.join(root, "ignored.MD"), "wb") as f:
    f.write(b"MUST_NOT_APPEAR_UPPERCASE")

# A large input makes whole-output buffering fail under the verifier's memory
# limit while remaining cheap for a genuine find/sed-or-awk/gzip pipeline.
stress = os.path.join(root, "b", "nested", "stress.txt")
chunk = ("bulk Copyright 2018 Acme Corp " + token + "\n").encode()
target = 64 * 1024 * 1024
with open(stress, "wb") as f:
    written = 0
    while written + len(chunk) <= target:
        f.write(chunk)
        written += len(chunk)
    f.write(b"FINAL Copyright 2018 Acme Corp")
PY
fi

if [ "$status" -eq 0 ]; then
    # Permit only the required pre-existing output file to be written. This
    # prevents temporary transformed-text files while allowing direct gzip
    # redirection to docs_custom.gz.
    find /home/user -type f -exec chmod a-w {} +
    find /home/user -type d -exec chmod a-w {} +
    chmod 555 /home/user/pack_docs.sh
    chmod 555 /home/user/archive
    chmod 666 /home/user/archive/docs_custom.gz
    chmod 755 /tmp /var/tmp /dev/shm 2>/dev/null || true

    timeout 90s runuser -u user -- bash -c 'ulimit -v 32768; export LC_ALL=C HOME=/home/user; exec /home/user/pack_docs.sh' || status=1
fi

if [ "$status" -eq 0 ]; then
    python3 - <<'PY' || status=1
import gzip
import hashlib
import os
import stat

root = "/home/user/docs_raw"
archive = "/home/user/archive/docs_custom.gz"
assert os.path.isfile(archive), "The executed script did not produce docs_custom.gz"
assert stat.S_ISREG(os.stat(archive).st_mode), "docs_custom.gz is not a regular file"

paths = []
for base, dirs, names in os.walk(root):
    for name in names:
        if name.endswith(".md") or name.endswith(".txt"):
            paths.append(os.path.join(base, name))
paths.sort()

expected_hash = hashlib.sha256()
expected_size = 0
old = b"Copyright 2018 Acme Corp"
new = b"Copyright 2024 Acme Global"
for path in paths:
    header = b"===FILE: " + os.path.basename(path).encode() + b"===\n"
    with open(path, "rb") as f:
        data = f.read()
    transformed = data.replace(old, new)
    expected_hash.update(header)
    expected_hash.update(transformed)
    expected_size += len(header) + len(transformed)
    if not data.endswith(b"\n"):
        expected_hash.update(b"\n")
        expected_size += 1

actual_hash = hashlib.sha256()
actual_size = 0
with gzip.open(archive, "rb") as f:
    while True:
        block = f.read(1024 * 1024)
        if not block:
            break
        actual_hash.update(block)
        actual_size += len(block)

assert actual_size == expected_size, "The generated archive has the wrong decompressed length"
assert actual_hash.digest() == expected_hash.digest(), "The generated archive does not match the dynamically derived output"
PY
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
