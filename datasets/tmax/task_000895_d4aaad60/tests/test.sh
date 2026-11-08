#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import tarfile
import pytest

def test_terminology_replaced():
    arch_path = "/home/user/docs/module_a/architecture.md"
    assert os.path.exists(arch_path), f"File {arch_path} is missing."
    with open(arch_path, "r") as f:
        content = f.read()
    assert "primary" in content, "Term 'master' was not replaced with 'primary' in architecture.md."
    assert "replica" in content, "Term 'slave' was not replaced with 'replica' in architecture.md."
    assert "master" not in content, "Old term 'master' is still present in architecture.md."
    assert "slave" not in content, "Old term 'slave' is still present in architecture.md."

    sec_path = "/home/user/docs/module_b/security.md"
    assert os.path.exists(sec_path), f"File {sec_path} is missing."
    with open(sec_path, "r") as f:
        content = f.read()
    assert "denylist" in content, "Term 'blacklist' was not replaced with 'denylist' in security.md."
    assert "allowlist" in content, "Term 'whitelist' was not replaced with 'allowlist' in security.md."
    assert "blacklist" not in content, "Old term 'blacklist' is still present in security.md."
    assert "whitelist" not in content, "Old term 'whitelist' is still present in security.md."

def test_tarball_contents():
    tarball_path = "/home/user/backups/diff_backup.tar.gz"
    assert os.path.exists(tarball_path), f"Tarball {tarball_path} is missing."

    try:
        with tarfile.open(tarball_path, "r:gz") as tar:
            members = tar.getmembers()
    except tarfile.ReadError:
        pytest.fail(f"File {tarball_path} is not a valid gzip-compressed tarball.")

    actual_files = set()
    for m in members:
        if m.isfile():
            # Normalize path (e.g., remove leading './')
            m_norm = m.name.lstrip("./")
            actual_files.add(m_norm)

    expected_files = {
        "module_a/architecture.md",
        "module_b/security.md",
        "new_guide.md"
    }

    missing_files = expected_files - actual_files
    assert not missing_files, f"Tarball is missing expected files: {missing_files}"

    assert "module_a/networking.md" not in actual_files, "Tarball incorrectly contains unchanged file 'networking.md'."

    extra_files = actual_files - expected_files
    assert not extra_files, f"Tarball contains unexpected files: {extra_files}"

def test_backup_summary():
    summary_path = "/home/user/backups/backup_summary.txt"
    assert os.path.exists(summary_path), f"Summary file {summary_path} is missing."

    with open(summary_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "module_a/architecture.md",
        "module_b/security.md",
        "new_guide.md"
    ]

    assert sorted(lines) == sorted(expected_lines), f"Summary file contents are incorrect. Expected {expected_lines}, but found {lines}"
TEST_EOF

cat << 'TEST_EOF' > /tmp/test_dynamic_behavior.py
import ast
import hashlib
import json
import os
from pathlib import Path
import secrets
import stat
import string
import subprocess
import tarfile

DOCS = Path("/home/user/docs")
SCRIPT = Path("/home/user/update_and_backup.py")
CONFIG = Path("/home/user/doc_config.ini")
SNAPSHOT = Path("/home/user/backups/snapshot.json")


def md5(path):
    return hashlib.md5(path.read_bytes()).hexdigest()


def test_script_end_to_end_on_derived_inputs():
    assert SCRIPT.exists(), "Required script /home/user/update_and_backup.py is missing"
    assert not SCRIPT.is_symlink(), "The submitted script must be a regular file"
    assert stat.S_ISREG(SCRIPT.stat().st_mode), "The submitted script must be a regular file"
    source = SCRIPT.read_text(encoding="utf-8")
    ast.parse(source, filename=str(SCRIPT))

    suffix = secrets.token_hex(8)
    obsolete = "obsolete" + suffix
    replacement = "current" + suffix
    fixture_rel = Path("verifier_dynamic_" + suffix) / "nested"
    fixture = DOCS / fixture_rel
    fixture.mkdir(parents=True)

    changed = fixture / "changed.md"
    stable = fixture / "stable.md"
    new_file = fixture / "new.md"
    changed.write_text(
        f"{obsolete} appears twice: {obsolete}.\n"
        f"Case-sensitive text must remain: {obsolete.upper()}.\n",
        encoding="utf-8",
    )
    stable.write_text("This markdown file is unchanged.\n", encoding="utf-8")
    new_file.write_text("A newly added markdown file.\n", encoding="utf-8")

    # Derive a fresh snapshot from every current Markdown file. The changed file
    # is recorded before replacement, the stable file is current, and the new
    # file is deliberately absent.
    snapshot = {}
    for path in DOCS.rglob("*.md"):
        rel = path.relative_to(DOCS).as_posix()
        if path != new_file:
            snapshot[rel] = md5(path)
    SNAPSHOT.write_text(json.dumps(snapshot, sort_keys=True, indent=2), encoding="utf-8")

    target = Path("/home/user/backups") / ("dynamic_" + suffix)
    target.mkdir()
    CONFIG.write_text(
        "[Terms]\n"
        f"{obsolete} = {replacement}\n\n"
        "[Backup]\n"
        f"target_dir = {target}\n",
        encoding="utf-8",
    )

    old_inode = changed.stat().st_ino
    result = subprocess.run(
        ["python3", str(SCRIPT)],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Script failed on dynamic inputs (exit {result.returncode}).\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    expected_changed = f"{replacement} appears twice: {replacement}.\nCase-sensitive text must remain: {obsolete.upper()}.\n"
    assert changed.read_text(encoding="utf-8") == expected_changed
    assert stable.read_text(encoding="utf-8") == "This markdown file is unchanged.\n"
    assert changed.stat().st_ino != old_inode, (
        "The modified file's inode did not change; modification was not performed "
        "by replacing it with an atomically written temporary file"
    )

    archive = target / "diff_backup.tar.gz"
    summary = target / "backup_summary.txt"
    assert archive.is_file(), "The configured target directory was not used for the archive"
    assert summary.is_file(), "The configured target directory was not used for the summary"

    expected = sorted([
        (fixture_rel / "changed.md").as_posix(),
        (fixture_rel / "new.md").as_posix(),
    ])
    assert summary.read_text(encoding="utf-8").splitlines() == expected, (
        "Summary must be a sorted list derived from MD5 changes and new files"
    )

    with tarfile.open(archive, "r:gz") as tar:
        regular = [m for m in tar.getmembers() if m.isfile()]
        names = [m.name[2:] if m.name.startswith("./") else m.name for m in regular]
        assert sorted(names) == expected, (
            f"Archive should contain exactly dynamically changed/new files; got {names}"
        )
        by_name = {
            (m.name[2:] if m.name.startswith("./") else m.name): tar.extractfile(m).read()
            for m in regular
        }

    assert by_name[expected[0]] == (DOCS / expected[0]).read_bytes()
    assert by_name[expected[1]] == (DOCS / expected[1]).read_bytes()
    assert (fixture_rel / "stable.md").as_posix() not in names
TEST_EOF

ok=1
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || ok=0
if [ "$ok" -eq 1 ]; then
    python3 -m pytest /tmp/test_dynamic_behavior.py -x --tb=short 2>&1 || ok=0
fi

if [ "$ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
