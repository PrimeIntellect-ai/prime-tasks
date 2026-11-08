#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pathlib
import shutil
import stat
import subprocess
import tempfile
import uuid


def read_nonempty_lines(path):
    with open(path, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def test_text_transformation():
    md_files = [
        "/home/user/docs/intro.md",
        "/home/user/docs/setup.md",
        "/home/user/docs/sub/advanced.md"
    ]
    for md_file in md_files:
        assert os.path.isfile(md_file), f"Markdown file {md_file} is missing."
        with open(md_file, 'r') as f:
            content = f.read()
            assert "DEPRECATED" not in content, f"File {md_file} still contains 'DEPRECATED'."
            assert "OBSOLETE" in content, f"File {md_file} does not contain 'OBSOLETE'."

    for md_file in pathlib.Path("/home/user/docs").rglob("*.md"):
        content = md_file.read_text(encoding="utf-8")
        assert "DEPRECATED" not in content, f"File {md_file} still contains 'DEPRECATED'."


def test_api_reference_generated():
    api_ref_path = "/home/user/docs/api_reference.md"
    assert os.path.isfile(api_ref_path), f"File {api_ref_path} was not generated."

    with open(api_ref_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_symbols = [
        "ApiDeleteUser",
        "ApiGetUser",
        "ApiUpdateSystem"
    ]

    assert lines == expected_symbols, f"Contents of {api_ref_path} do not match expected symbols or are not sorted."


def test_nav_index_generated():
    nav_index_path = "/home/user/docs/nav_index.txt"
    assert os.path.isfile(nav_index_path), f"File {nav_index_path} was not generated."

    with open(nav_index_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "advanced.md - LastTX: NONE",
        "intro.md - LastTX: 1009",
        "setup.md - LastTX: 1005"
    ]

    assert lines == expected_lines, f"Contents of {nav_index_path} do not match expected navigation index or are not sorted."


def test_go_script_exists():
    script_path = "/home/user/build_nav.go"
    assert os.path.isfile(script_path), f"Go script {script_path} does not exist."
    assert not os.path.islink(script_path), f"Go script {script_path} must be a regular source file."
    assert stat.S_ISREG(os.lstat(script_path).st_mode), f"Go script {script_path} must be a regular source file."


def test_go_program_builds_and_handles_unseen_inputs():
    source = "/home/user/build_nav.go"
    token = uuid.uuid4().hex[:12]
    executable = f"/tmp/build_nav_{token}"

    build = subprocess.run(
        ["go", "build", "-o", executable, source],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert build.returncode == 0, f"build_nav.go did not build:\n{build.stdout}\n{build.stderr}"

    listing = subprocess.run(
        ["go", "list", "-json", "build_nav.go"],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert listing.returncode == 0, f"Could not inspect build_nav.go imports: {listing.stderr}"
    package_info = json.loads(listing.stdout)
    assert "debug/elf" in package_info.get("Imports", []), "build_nav.go must use Go's debug/elf package."

    root = pathlib.Path("/home/user")
    docs = root / "docs"
    backend = root / "bin" / "backend_srv"
    wal = root / "logs" / "system.wal"
    backup_root = pathlib.Path(tempfile.mkdtemp(prefix="nav_verifier_"))
    backup_docs = backup_root / "docs"
    backup_backend = backup_root / "backend_srv"
    backup_wal = backup_root / "system.wal"

    shutil.move(str(docs), str(backup_docs))
    shutil.copy2(backend, backup_backend)
    shutil.copy2(wal, backup_wal)

    try:
        docs.mkdir(parents=True)
        (docs / "nested" / "deep").mkdir(parents=True)

        doc_a = f"alpha_{token}.md"
        doc_b = f"middle_{token}.md"
        doc_c = f"zeta_{token}.md"
        (docs / doc_a).write_text("clean alpha documentation\n", encoding="utf-8")
        (docs / "nested" / doc_b).write_text("clean middle documentation\n", encoding="utf-8")
        (docs / "nested" / "deep" / doc_c).write_text("clean zeta documentation\n", encoding="utf-8")
        (docs / "nested" / "ignored.txt").write_text("not markdown\n", encoding="utf-8")

        symbol_a = f"ApiAlpha{token}"
        symbol_b = f"ApiMiddle{token}"
        symbol_c = f"ApiZeta{token}"
        c_source = backup_root / "fixture.c"
        c_source.write_text(
            f'''__attribute__((visibility("default"))) void {symbol_c}(void) {{}}\n'''
            f'''__attribute__((visibility("default"))) int {symbol_a} = 17;\n'''
            f'''__attribute__((visibility("default"))) void {symbol_b}(void) {{}}\n'''
            f'''__attribute__((visibility("default"))) void Internal{token}(void) {{}}\n''',
            encoding="utf-8",
        )
        compiled = subprocess.run(
            ["gcc", "-shared", "-fPIC", "-o", str(backend), str(c_source)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert compiled.returncode == 0, f"Failed to create verifier ELF fixture: {compiled.stderr}"

        first_id = str(20000 + int(token[:3], 16) % 10000)
        latest_id = str(int(first_id) + 11)
        second_id = str(int(first_id) + 23)
        wal.write_text(
            f"BEGIN TX\nTX_ID: {first_id}\nAUTHOR: first\nAFFECTED_DOC: {doc_a}\nEND TX\n"
            f"BEGIN TX\nTX_ID: {second_id}\nAUTHOR: second\nAFFECTED_DOC: {doc_b}\nEND TX\n"
            f"BEGIN TX\nTX_ID: {latest_id}\nAUTHOR: latest\nAFFECTED_DOC: {doc_a}\nEND TX\n",
            encoding="utf-8",
        )

        run = subprocess.run(
            [executable],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert run.returncode == 0, f"Built Go program failed on verifier fixtures:\n{run.stdout}\n{run.stderr}"

        api_path = docs / "api_reference.md"
        nav_path = docs / "nav_index.txt"
        assert api_path.is_file(), "The executed Go program did not generate api_reference.md."
        assert nav_path.is_file(), "The executed Go program did not generate nav_index.txt."

        assert read_nonempty_lines(api_path) == sorted([symbol_a, symbol_b, symbol_c]), \
            "api_reference.md was not derived correctly from the unseen ELF fixture."

        expected_nav = sorted([
            f"{doc_a} - LastTX: {latest_id}",
            f"{doc_b} - LastTX: {second_id}",
            f"{doc_c} - LastTX: NONE",
        ])
        assert read_nonempty_lines(nav_path) == expected_nav, \
            "nav_index.txt was not derived correctly from recursive docs and the unseen WAL fixture."
    finally:
        if docs.exists() or docs.is_symlink():
            if docs.is_dir() and not docs.is_symlink():
                shutil.rmtree(docs)
            else:
                docs.unlink()
        shutil.move(str(backup_docs), str(docs))
        shutil.copy2(backup_backend, backend)
        shutil.copy2(backup_wal, wal)
        if os.path.exists(executable):
            os.remove(executable)
        shutil.rmtree(backup_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
