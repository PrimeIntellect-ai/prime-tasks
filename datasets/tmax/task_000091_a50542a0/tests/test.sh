#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import tarfile
import tempfile
import zipfile
from pathlib import Path


def run_sanitizer(path):
    return subprocess.run(
        ["python3", "/home/user/sanitizer.py", str(path)],
        capture_output=True,
        timeout=20,
    ).returncode


def test_final_docs_archive_exists_and_correct():
    archive_path = "/home/user/final_docs.tar.gz"
    assert os.path.isfile(archive_path), f"Missing archive: {archive_path}"

    with tarfile.open(archive_path, "r:gz") as tar:
        members = tar.getmembers()

        has_release_v2 = any(m.name.endswith("release_v2") and m.isdir() for m in members)
        assert has_release_v2, "Missing 'release_v2' directory in archive."

        index_json_member = next((m for m in members if m.name.endswith("release_v2/index.json")), None)
        assert index_json_member is not None, "Missing 'index.json' in release_v2."

        intro_json_member = next((m for m in members if m.name.endswith("release_v2/intro.json")), None)
        assert intro_json_member is not None, "Missing 'intro.json' in release_v2."

        expected = b'{"intro": "Welcome"}\n'
        assert tar.extractfile(index_json_member).read() == expected, "index.json has incorrect content."
        assert tar.extractfile(intro_json_member).read() == expected, "intro.json has incorrect content."

        hardlink_ok = (
            index_json_member.islnk() and index_json_member.linkname.endswith("release_v2/intro.json")
        ) or (
            intro_json_member.islnk() and intro_json_member.linkname.endswith("release_v2/index.json")
        )
        assert hardlink_ok, "index.json and intro.json are not represented as hard links in the archive."

        symlink_member = next((m for m in members if m.name.endswith("attachments/firmware.elf")), None)
        assert symlink_member is not None, "Missing 'attachments/firmware.elf' in archive."
        assert symlink_member.issym(), "attachments/firmware.elf is not a symlink."
        assert symlink_member.linkname == "bin/main.elf" or symlink_member.linkname.endswith("bin/main.elf"), \
            f"Symlink points to wrong target: {symlink_member.linkname}"


def test_organized_docs_links_are_correct():
    release = Path("/home/user/organized_docs/release_v2")
    intro = release / "intro.json"
    index = release / "index.json"
    firmware = release / "attachments" / "firmware.elf"

    assert intro.is_file(), "Missing organized intro.json."
    assert index.is_file(), "Missing organized index.json."
    assert os.stat(intro).st_ino == os.stat(index).st_ino, "index.json is not a hard link to intro.json."
    assert intro.read_bytes() == b'{"intro": "Welcome"}\n', "Organized JSON content is incorrect."
    assert firmware.is_symlink(), "Organized firmware.elf is not a symlink."
    assert os.readlink(firmware) == "bin/main.elf", "Organized firmware.elf has the wrong target."


def test_sanitizer_exists():
    script_path = "/home/user/sanitizer.py"
    assert os.path.isfile(script_path), f"Missing sanitizer script: {script_path}"


def test_sanitizer_clean_corpus():
    clean_corpus_dir = "/app/corpus/clean"
    assert os.path.isdir(clean_corpus_dir), "Clean corpus directory missing."
    assert run_sanitizer(clean_corpus_dir) == 0, "Clean corpus was rejected."


def test_sanitizer_evil_corpus():
    evil_corpus_dir = "/app/corpus/evil"
    assert os.path.isdir(evil_corpus_dir), "Evil corpus directory missing."

    # evil_5 is a malformed ELF, which is outside the required validation scope.
    evil_subdirs = [os.path.join(evil_corpus_dir, d) for d in ("evil_1", "evil_2", "evil_3", "evil_4")]
    failed_evil = []
    for subdir in evil_subdirs:
        result = run_sanitizer(subdir)
        if result != 1:
            failed_evil.append(os.path.basename(subdir))

    assert not failed_evil, f"{len(failed_evil)} of {len(evil_subdirs)} evil bypassed: {', '.join(failed_evil)}"


def test_sanitizer_generated_inputs():
    with tempfile.TemporaryDirectory(prefix="sanitizer-tests-") as tmp:
        root = Path(tmp)

        clean = root / "clean"
        clean.mkdir()
        (clean / "doc.json").write_text(json.dumps({"ok": [1, 2, 3]}))
        (clean / "doc.xml").write_text("<root><item>ok</item></root>")
        (clean / "doc.csv").write_text("name,value\nalpha,1\n")
        (clean / "target.txt").write_text("safe")
        (clean / "internal-link").symlink_to("target.txt")
        with zipfile.ZipFile(clean / "safe.zip", "w", zipfile.ZIP_DEFLATED) as archive:
            archive.writestr("nested/readme.txt", "safe archive content")
        assert run_sanitizer(clean) == 0, "Generated clean submission was rejected."

        bad_json = root / "bad-json"
        bad_json.mkdir()
        (bad_json / "random.json").write_text('{"broken": }')
        assert run_sanitizer(bad_json) == 1, "Malformed generated JSON was accepted."

        bad_xml = root / "bad-xml"
        bad_xml.mkdir()
        (bad_xml / "random.xml").write_text("<root><item></root>")
        assert run_sanitizer(bad_xml) == 1, "Malformed generated XML was accepted."

        bad_link = root / "bad-link"
        bad_link.mkdir()
        (bad_link / "escape").symlink_to("../../outside-target")
        assert run_sanitizer(bad_link) == 1, "Escaping generated symlink was accepted."

        bad_zip = root / "bad-zip"
        bad_zip.mkdir()
        with zipfile.ZipFile(bad_zip / "traversal.zip", "w") as archive:
            archive.writestr("../../escaped.txt", "escape")
        assert run_sanitizer(bad_zip) == 1, "Generated path-traversal archive was accepted."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
