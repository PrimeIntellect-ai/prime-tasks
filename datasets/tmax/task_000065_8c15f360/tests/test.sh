#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pytest


def test_clean_docs_intro():
    path = "/home/user/clean_docs/docs/intro.txt"
    assert os.path.exists(path), f"File {path} does not exist."
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    assert "GlobalTech" in content, f"'GlobalTech' not found in {path}."
    assert "AcmeCorp" not in content, f"'AcmeCorp' still found in {path}."
    assert "Welcome to the GlobalTech documentation." in content
    assert "GlobalTech provides the best widgets." in content


def test_clean_docs_finance():
    path = "/home/user/clean_docs/docs/manuals/finance.txt"
    assert os.path.exists(path), f"File {path} does not exist."
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    assert "GlobalTech" in content, f"'GlobalTech' not found in {path}."
    assert "AcmeCorp" not in content, f"'AcmeCorp' still found in {path}."
    assert "GlobalTech financial report for the café." in content


def test_clean_docs_api():
    path = "/home/user/clean_docs/docs/api/index.txt"
    assert os.path.exists(path), f"File {path} does not exist."
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    assert "GlobalTech" in content, f"'GlobalTech' not found in {path}."
    assert "AcmeCorp" not in content, f"'AcmeCorp' still found in {path}."
    assert "GlobalTech API résumé." in content


def test_symlink_skipped():
    path = "/home/user/clean_docs/docs/manuals/loop_back"
    assert not os.path.exists(path), f"Symlink directory {path} should have been skipped and not copied."
    assert not os.path.islink(path), f"Symlink {path} should not exist."


def test_migration_log():
    path = "/home/user/migration.log"
    assert os.path.exists(path), f"Log file {path} does not exist."
    with open(path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 3, f"Expected 3 lines in {path}, got {len(lines)}."
    assert lines == sorted(lines), "Log file lines are not sorted alphabetically."

    assert "docs/api/index.txt" in lines[0]
    assert any(enc in lines[0].lower() for enc in ["iso-8859-1", "iso8859-1", "latin-1", "latin1", "windows-1252"]), f"Incorrect encoding for index.txt in log: {lines[0]}"

    assert "docs/intro.txt" in lines[1]
    assert "utf-8" in lines[1].lower() or "utf8" in lines[1].lower(), f"Incorrect encoding for intro.txt in log: {lines[1]}"

    assert "docs/manuals/finance.txt" in lines[2]
    assert any(enc in lines[2].lower() for enc in ["iso-8859-1", "iso8859-1", "latin-1", "latin1", "windows-1252"]), f"Incorrect encoding for finance.txt in log: {lines[2]}"


def test_archive_was_extracted():
    intro = "/home/user/raw_docs/docs/intro.txt"
    finance = "/home/user/raw_docs/docs/manuals/finance.txt"
    api = "/home/user/raw_docs/docs/api/index.txt"
    loop = "/home/user/raw_docs/docs/manuals/loop_back"
    assert os.path.isfile(intro)
    assert os.path.isfile(finance)
    assert os.path.isfile(api)
    assert os.path.islink(loop)
    with open(intro, "rb") as f:
        assert f.read() == b"Welcome to the AcmeCorp documentation.\nAcmeCorp provides the best widgets.\n"
    with open(finance, "rb") as f:
        assert f.read() == "AcmeCorp financial report for the café.\n".encode("iso-8859-1")
    with open(api, "rb") as f:
        assert f.read() == "AcmeCorp API résumé.\n".encode("iso-8859-1")
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_dynamic_migration.py
import os
import secrets
import shutil
import subprocess
import sys

HOME = "/home/user"
RAW = os.path.join(HOME, "raw_docs")
CLEAN = os.path.join(HOME, "clean_docs")
LOG = os.path.join(HOME, "migration.log")


def find_python_scripts():
    scripts = []
    excluded = {RAW, CLEAN}
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if not d.startswith(".") and os.path.join(root, d) not in excluded]
        for name in files:
            path = os.path.join(root, name)
            if path in {LOG, os.path.join(HOME, "legacy_docs.tar.gz")} or os.path.islink(path):
                continue
            try:
                if os.path.getsize(path) > 1024 * 1024:
                    continue
                with open(path, "rb") as f:
                    data = f.read()
                text = data.decode("utf-8")
                compile(text, path, "exec")
            except (OSError, UnicodeDecodeError, SyntaxError, ValueError):
                continue
            scripts.append(path)
    return sorted(set(scripts))


scripts = find_python_scripts()
assert scripts, "No Python migration script was found under /home/user."

token = secrets.token_hex(10)
utf_rel = f"docs/section_{token}/zeta_{token}.txt"
latin_rel = f"docs/section_{token}/nested/alpha_{token}.txt"
loop_rel = f"docs/section_{token}/nested/loop_{token}"
utf_source = f"Snowman ☃ belongs to AcmeCorp; AcmeCorp-{token} stays otherwise intact.\n"
latin_source = f"AcmeCorp serves the café numéro {token}.\n"
expected = {
    utf_rel: utf_source.replace("AcmeCorp", "GlobalTech"),
    latin_rel: latin_source.replace("AcmeCorp", "GlobalTech"),
}


def prepare_input():
    shutil.rmtree(RAW, ignore_errors=True)
    shutil.rmtree(CLEAN, ignore_errors=True)
    try:
        os.remove(LOG)
    except FileNotFoundError:
        pass

    for rel in expected:
        os.makedirs(os.path.dirname(os.path.join(RAW, rel)), exist_ok=True)
    with open(os.path.join(RAW, utf_rel), "wb") as f:
        f.write(utf_source.encode("utf-8"))
    with open(os.path.join(RAW, latin_rel), "wb") as f:
        f.write(latin_source.encode("iso-8859-1"))
    os.symlink("..", os.path.join(RAW, loop_rel))


def validate_result():
    found = set()
    if not os.path.isdir(CLEAN):
        return False
    for root, dirs, files in os.walk(CLEAN, followlinks=False):
        for name in dirs + files:
            if os.path.islink(os.path.join(root, name)):
                return False
        for name in files:
            found.add(os.path.relpath(os.path.join(root, name), CLEAN).replace(os.sep, "/"))
    if found != set(expected):
        return False

    for rel, wanted in expected.items():
        try:
            with open(os.path.join(CLEAN, rel), "rb") as f:
                raw = f.read()
            if raw.decode("utf-8") != wanted or b"AcmeCorp" in raw:
                return False
        except (OSError, UnicodeDecodeError):
            return False

    if os.path.lexists(os.path.join(CLEAN, loop_rel)):
        return False

    try:
        with open(LOG, "r", encoding="utf-8") as f:
            lines = [line.rstrip("\n") for line in f if line.strip()]
    except (OSError, UnicodeDecodeError):
        return False
    if lines != sorted(lines) or len(lines) != 2:
        return False

    entries = {}
    for line in lines:
        if line.count(" - ") != 1:
            return False
        rel, encoding = line.split(" - ")
        entries[rel] = encoding.lower().replace("_", "-")
    if set(entries) != set(expected):
        return False
    if entries[utf_rel] not in {"utf-8", "utf8"}:
        return False
    if entries[latin_rel] not in {"iso-8859-1", "iso8859-1", "latin-1", "latin1", "windows-1252", "cp1252"}:
        return False
    return True


for script in scripts:
    prepare_input()
    try:
        result = subprocess.run(
            [sys.executable, script],
            cwd=HOME,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=12,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        continue
    if result.returncode == 0 and validate_result():
        sys.exit(0)

raise AssertionError("No submitted Python script correctly migrated the randomized input tree.")
DYNAMIC_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 && python3 /tmp/test_dynamic_migration.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
