#!/bin/bash
set +e
mkdir -p /logs/verifier

run_verification() {
    cat > /tmp/test_final_state.py <<'PY'
import os
import gzip
import pytest


def test_merged_archive_exists_and_valid():
    merged_path = "/home/user/workspace/merged.tar.gz"
    assert os.path.exists(merged_path), f"Merged archive {merged_path} does not exist."
    assert os.path.isfile(merged_path), f"Path {merged_path} is not a file."
    try:
        with gzip.open(merged_path, 'rb') as f:
            f.read(1)
    except Exception as e:
        pytest.fail(f"Merged archive is not a valid gzip file: {e}")


def test_valid_file_extracted():
    yaml_path = "/home/user/workspace/safe_configs/config/server.yaml"
    assert os.path.exists(yaml_path), f"Valid file {yaml_path} was not extracted."
    assert os.path.isfile(yaml_path), f"Path {yaml_path} is not a regular file."
    with open(yaml_path, 'r') as f:
        content = f.read()
    assert "host: localhost" in content, "The extracted server.yaml does not contain the expected content."
    assert "port: 8080" in content, "The extracted server.yaml does not contain the expected content."


def test_valid_symlink_extracted():
    symlink_path = "/home/user/workspace/safe_configs/config/link_to_server"
    assert os.path.lexists(symlink_path), f"Symlink {symlink_path} was not extracted."
    assert os.path.islink(symlink_path), f"Path {symlink_path} is not a symlink."
    target = os.readlink(symlink_path)
    assert target == "server.yaml", f"Symlink target is {target}, expected 'server.yaml'."


def test_extraction_log_contains_skipped_entries():
    log_path = "/home/user/workspace/extraction.log"
    assert os.path.exists(log_path), f"Extraction log {log_path} does not exist."
    assert os.path.isfile(log_path), f"Path {log_path} is not a file."
    with open(log_path, 'r') as f:
        log_content = f.read().splitlines()
    expected_skipped = [
        "SKIPPED: ../escaped_secret.txt",
        "SKIPPED: /etc/fake_passwd",
        "SKIPPED: config/link_to_root"
    ]
    for expected in expected_skipped:
        assert expected in log_content, f"Expected log entry '{expected}' not found in {log_path}."


def test_malicious_files_not_extracted():
    escaped_secret_path = "/home/user/workspace/escaped_secret.txt"
    assert not os.path.exists(escaped_secret_path), "Path traversal vulnerability: escaped_secret.txt was extracted outside the safe_configs directory."
    fake_passwd_path = "/etc/fake_passwd"
    assert not os.path.exists(fake_passwd_path), "Absolute path vulnerability: fake_passwd was extracted to /etc."
    malicious_symlink_path = "/home/user/workspace/safe_configs/config/link_to_root"
    assert not os.path.lexists(malicious_symlink_path), "Malicious symlink was extracted despite pointing outside the destination directory."
PY

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1

    python3 - <<'PY' || return 1
import glob
import hashlib
import os

chunk_dir = "/home/user/incoming/chunks"
checksum_path = "/home/user/incoming/checksums.sha256"
merged_path = "/home/user/workspace/merged.tar.gz"

chunks = sorted(glob.glob(os.path.join(chunk_dir, "backup.tar.gz.part-*")))
assert chunks, "No backup chunks were found"
assert os.path.isfile(checksum_path), "checksums.sha256 is missing"

listed = []
with open(checksum_path, "r", encoding="utf-8") as f:
    for raw in f:
        line = raw.rstrip("\n")
        if not line:
            continue
        digest, name = line.split(None, 1)
        name = name.lstrip("*")
        assert len(digest) == 64 and all(c in "0123456789abcdefABCDEF" for c in digest)
        path = os.path.join(chunk_dir, name)
        assert os.path.isfile(path), f"Checksum references missing chunk: {name}"
        with open(path, "rb") as part:
            actual = hashlib.sha256(part.read()).hexdigest()
        assert actual.lower() == digest.lower(), f"Checksum mismatch for {name}"
        listed.append(os.path.realpath(path))

assert listed == [os.path.realpath(p) for p in chunks], "Checksum file must list every chunk exactly once in merge order"
with open(merged_path, "rb") as f:
    merged = f.read()
concatenated = b"".join(open(path, "rb").read() for path in chunks)
assert merged == concatenated, "merged.tar.gz is not the byte-for-byte concatenation of the verified chunks"
PY

    project=/home/user/workspace/secure_extractor
    test -f "$project/Cargo.toml" || return 1
    test -f "$project/src/main.rs" || return 1

    python3 - <<'PY' || return 1
import re
from pathlib import Path
source = Path('/home/user/workspace/secure_extractor/src/main.rs').read_text(encoding='utf-8')
assert re.search(r'\bflate2\b', source), "Rust source does not use flate2"
assert re.search(r'\btar\b', source), "Rust source does not use tar"
PY

    export HOME=/home/user
    export CARGO_HOME=/home/user/.cargo
    export CARGO_TARGET_DIR=/tmp/verifier-cargo-target
    rm -rf "$CARGO_TARGET_DIR"

    cargo metadata --offline --no-deps --format-version 1 --manifest-path "$project/Cargo.toml" > /tmp/secure_extractor_metadata.json || return 1
    python3 - <<'PY' || return 1
import json
m = json.load(open('/tmp/secure_extractor_metadata.json'))
assert m['packages'], "Cargo project has no package"
p = m['packages'][0]
deps = {d['name'] for d in p['dependencies']}
assert 'tar' in deps, "Cargo project must directly depend on tar"
assert 'flate2' in deps, "Cargo project must directly depend on flate2"
bins = [t['name'] for t in p['targets'] if 'bin' in t['kind']]
assert bins, "Cargo project has no binary target"
name = 'secure_extractor' if 'secure_extractor' in bins else bins[0]
open('/tmp/secure_extractor_bin_name', 'w').write(name)
PY

    cargo build --offline --manifest-path "$project/Cargo.toml" || return 1
    bin_name=$(cat /tmp/secure_extractor_bin_name) || return 1
    extractor="$CARGO_TARGET_DIR/debug/$bin_name"
    test -f "$extractor" -a -x "$extractor" || return 1

    rm -f /home/user/workspace/extraction.log
    python3 - "$extractor" <<'PY' || return 1
import gzip
import io
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import uuid

extractor = sys.argv[1]
token = uuid.uuid4().hex
prefix = "case_" + token
base = tempfile.mkdtemp(prefix="secure-extractor-verifier-")
archive = os.path.join(base, "challenge.tar.gz")
dest = os.path.join(base, "dest")
os.mkdir(dest)
traversal_out = os.path.join(base, "escape_" + token)
absolute_out = os.path.join("/tmp", "absolute_" + token)
log_path = "/home/user/workspace/extraction.log"

expected_skips = [
    "../escape_" + token,
    absolute_out,
    prefix + "/a/../../dotdot_" + token,
    prefix + "/bad_sym",
    prefix + "/bad_hard",
]

def regular(tar, name, data):
    info = tarfile.TarInfo(name)
    info.size = len(data)
    tar.addfile(info, io.BytesIO(data))

try:
    with tarfile.open(archive, "w:gz") as tar:
        regular(tar, prefix + "/good.txt", b"dynamic verifier content\n")

        good_sym = tarfile.TarInfo(prefix + "/good_sym")
        good_sym.type = tarfile.SYMTYPE
        good_sym.linkname = "good.txt"
        tar.addfile(good_sym)

        good_hard = tarfile.TarInfo(prefix + "/good_hard")
        good_hard.type = tarfile.LNKTYPE
        good_hard.linkname = prefix + "/good.txt"
        tar.addfile(good_hard)

        regular(tar, expected_skips[0], b"traversal\n")
        regular(tar, expected_skips[1], b"absolute\n")
        regular(tar, expected_skips[2], b"dotdot\n")

        bad_sym = tarfile.TarInfo(expected_skips[3])
        bad_sym.type = tarfile.SYMTYPE
        bad_sym.linkname = "../../outside_sym_" + token
        tar.addfile(bad_sym)

        bad_hard = tarfile.TarInfo(expected_skips[4])
        bad_hard.type = tarfile.LNKTYPE
        bad_hard.linkname = "../outside_hard_" + token
        tar.addfile(bad_hard)

    result = subprocess.run([extractor, archive, dest], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, timeout=30)
    assert result.returncode == 0, f"Extractor failed: {result.stderr}"

    good = os.path.join(dest, prefix, "good.txt")
    assert os.path.isfile(good)
    assert open(good, "rb").read() == b"dynamic verifier content\n"

    good_sym = os.path.join(dest, prefix, "good_sym")
    assert os.path.islink(good_sym)
    assert os.readlink(good_sym) == "good.txt"
    assert open(good_sym, "rb").read() == b"dynamic verifier content\n"

    good_hard = os.path.join(dest, prefix, "good_hard")
    assert os.path.isfile(good_hard) and not os.path.islink(good_hard)
    assert open(good_hard, "rb").read() == b"dynamic verifier content\n"

    assert not os.path.lexists(traversal_out), "Traversal entry escaped the destination"
    assert not os.path.lexists(absolute_out), "Absolute entry was extracted"
    assert not os.path.lexists(os.path.join(dest, prefix, "bad_sym")), "Unsafe symlink was extracted"
    assert not os.path.lexists(os.path.join(dest, prefix, "bad_hard")), "Unsafe hard link was extracted"
    assert not os.path.lexists(os.path.join(dest, "dotdot_" + token)), "Path containing .. was extracted"

    assert os.path.isfile(log_path), "Extractor did not create extraction.log"
    lines = open(log_path, encoding="utf-8").read().splitlines()
    for path in expected_skips:
        assert "SKIPPED: " + path in lines, f"Missing dynamic skip log for {path}"
finally:
    if os.path.lexists(absolute_out):
        if os.path.isdir(absolute_out) and not os.path.islink(absolute_out):
            shutil.rmtree(absolute_out)
        else:
            os.unlink(absolute_out)
    shutil.rmtree(base, ignore_errors=True)
PY
}

if run_verification; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
