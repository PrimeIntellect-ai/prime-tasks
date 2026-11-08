#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import posixpath
import random
import re
import subprocess
import tarfile
import uuid

import pytest


def test_transcript_content():
    """Verify the audio transcription is reasonably accurate."""
    transcript_path = "/home/user/transcript.txt"
    assert os.path.isfile(transcript_path), f"Transcript file missing at {transcript_path}"

    with open(transcript_path, "r", encoding="utf-8") as f:
        content = f.read().strip().lower()

    expected_words = [
        "warning", "backup", "rotation", "system", "vulnerable",
        "path", "traversal", "attacks", "check", "symlink", "targets", "immediately"
    ]

    clean_content = re.sub(r'[^\w\s]', '', content)
    matched_words = sum(1 for word in expected_words if word in clean_content)
    assert matched_words >= len(expected_words) - 2, \
        f"Transcript does not sufficiently match the expected audio content. Found: '{content}'"


def test_tar_sanitizer_evil_corpus():
    """Verify the Go sanitizer correctly rejects all evil tar files."""
    go_script = "/home/user/tar_sanitizer.go"
    assert os.path.isfile(go_script), f"Go script missing at {go_script}"

    evil_dir = "/app/corpora/evil"
    evil_files = glob.glob(os.path.join(evil_dir, "*.tar"))
    assert evil_files, f"No tar files found in {evil_dir}"

    bypassed = []
    for tar_file in evil_files:
        result = subprocess.run(
            ["go", "run", go_script, tar_file],
            capture_output=True,
            text=True
        )
        stdout = result.stdout.strip()
        if result.returncode != 1 or stdout != "REJECT":
            bypassed.append((os.path.basename(tar_file), result.returncode, stdout))

    if bypassed:
        details = ", ".join([f"{f} (code: {c}, out: '{o}')" for f, c, o in bypassed])
        pytest.fail(f"{len(bypassed)} of {len(evil_files)} evil bypassed: {details}")


def test_tar_sanitizer_clean_corpus():
    """Verify the Go sanitizer correctly accepts all clean tar files."""
    go_script = "/home/user/tar_sanitizer.go"
    assert os.path.isfile(go_script), f"Go script missing at {go_script}"

    clean_dir = "/app/corpora/clean"
    clean_files = glob.glob(os.path.join(clean_dir, "*.tar"))
    assert clean_files, f"No tar files found in {clean_dir}"

    rejected = []
    for tar_file in clean_files:
        result = subprocess.run(
            ["go", "run", go_script, tar_file],
            capture_output=True,
            text=True
        )
        stdout = result.stdout.strip()
        if result.returncode != 0 or stdout != "ACCEPT":
            rejected.append((os.path.basename(tar_file), result.returncode, stdout))

    if rejected:
        details = ", ".join([f"{f} (code: {c}, out: '{o}')" for f, c, o in rejected])
        pytest.fail(f"{len(rejected)} of {len(clean_files)} clean modified/rejected: {details}")


def _escapes_root(path):
    if posixpath.isabs(path):
        return True
    normalized = posixpath.normpath(path)
    return normalized == ".." or normalized.startswith("../")


def _expected_reject(entries):
    for kind, name, target in entries:
        if _escapes_root(name):
            return True
        if kind in ("symlink", "hardlink") and posixpath.isabs(target):
            return True
        if kind == "symlink":
            resolved = posixpath.join(posixpath.dirname(name), target)
            if _escapes_root(resolved):
                return True
    return False


def _write_tar(path, entries):
    with tarfile.open(path, "w", format=tarfile.GNU_FORMAT) as archive:
        for kind, name, target in entries:
            info = tarfile.TarInfo(name)
            info.mode = 0o644
            if kind == "file":
                info.size = 0
            elif kind == "symlink":
                info.type = tarfile.SYMTYPE
                info.linkname = target
            elif kind == "hardlink":
                info.type = tarfile.LNKTYPE
                info.linkname = target
            else:
                raise AssertionError(f"unknown entry kind: {kind}")
            archive.addfile(info)


def test_tar_sanitizer_generated_corpus(tmp_path):
    """Exercise randomized paths so directory-name classification cannot pass."""
    go_script = "/home/user/tar_sanitizer.go"
    assert os.path.isfile(go_script), f"Go script missing at {go_script}"

    binary = tmp_path / ("runner_" + uuid.uuid4().hex)
    built = subprocess.run(
        ["go", "build", "-o", str(binary), go_script],
        capture_output=True,
        text=True,
    )
    assert built.returncode == 0, f"Go sanitizer did not compile: {built.stderr}"
    assert binary.is_file(), "Go build did not produce an executable"

    rng = random.SystemRandom()

    def word():
        return uuid.uuid4().hex[:rng.randint(7, 15)]

    cases = []
    # Safe archives, including normalized '..' components that stay in root.
    for _ in range(5):
        a, b, c = word(), word(), word()
        cases.append([
            ("file", f"{a}/{b}.log", ""),
            ("file", f"{a}/sub/../{c}.log", ""),
            ("symlink", f"{a}/link-{word()}", f"../{c}.log"),
        ])
    for _ in range(4):
        a, b = word(), word()
        cases.append([
            ("file", f"{b}.log", ""),
            ("symlink", f"{a}/nested/link-{word()}", f"../../{b}.log"),
            ("hardlink", f"{a}/hard-{word()}", f"{b}.log"),
        ])

    # Member names which normalize outside the archive root.
    for template in ("../{}", "{}/../../{}", "{}/{}/../../../{}"):
        for _ in range(3):
            values = [word() for _ in range(template.count("{}"))]
            bad_name = template.format(*values)
            cases.append([
                ("file", f"{word()}/{word()}.log", ""),
                ("file", bad_name, ""),
            ])

    # Absolute member names.
    for _ in range(3):
        cases.append([("file", "/" + word() + "/" + word(), "")])

    # Symlinks whose targets escape after resolving from the link's directory.
    for _ in range(4):
        a, b, c = word(), word(), word()
        cases.append([
            ("file", f"{a}/{b}.log", ""),
            ("symlink", f"{a}/{c}/link-{word()}", f"../../../{word()}"),
        ])

    # Absolute symlink and hardlink targets, both required to be rejected.
    for kind in ("symlink", "hardlink"):
        for _ in range(4):
            cases.append([
                ("file", f"{word()}.log", ""),
                (kind, f"{word()}/link-{word()}", "/" + word() + "/" + word()),
            ])

    # All archives share one neutral randomized directory and opaque filenames.
    corpus_dir = tmp_path / ("batch_" + uuid.uuid4().hex)
    corpus_dir.mkdir()
    generated = []
    for entries in cases:
        tar_path = corpus_dir / (uuid.uuid4().hex + ".tar")
        _write_tar(tar_path, entries)
        generated.append((tar_path, _expected_reject(entries)))

    assert any(expected for _, expected in generated)
    assert any(not expected for _, expected in generated)
    rng.shuffle(generated)

    failures = []
    for tar_path, should_reject in generated:
        result = subprocess.run([str(binary), str(tar_path)], capture_output=True, text=True)
        expected_code = 1 if should_reject else 0
        expected_output = "REJECT" if should_reject else "ACCEPT"
        if result.returncode != expected_code or result.stdout.strip() != expected_output:
            failures.append(
                f"{tar_path.name}: expected ({expected_code}, {expected_output}), "
                f"got ({result.returncode}, {result.stdout.strip()!r})"
            )

    assert not failures, "Generated corpus failures:\n" + "\n".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
