#!/bin/bash
set +e
mkdir -p /logs/verifier

# Recreate the original archive with fresh binary contents so preconstructed output
# cannot satisfy the verifier, then run the submitted script from a clean state.
python3 - <<'PY'
import hashlib
import json
import os
import shutil
import tarfile

src = "/tmp/verifier_source_docs"
shutil.rmtree(src, ignore_errors=True)
os.makedirs(os.path.join(src, "nested"))

legacy_utf8 = "This is legacy documentation with some special chars: résumé, façade."
with open(os.path.join(src, "legacy.txt"), "wb") as f:
    f.write(legacy_utf8.encode("iso-8859-1"))
with open(os.path.join(src, "nested", "modern.txt"), "wb") as f:
    f.write(b"Standard modern doc.\n")

binary = os.urandom(1024)
with open(os.path.join(src, "image_data"), "wb") as f:
    f.write(binary)

os.symlink("../legacy.txt", os.path.join(src, "nested", "safe_link.txt"))
os.symlink("/etc/passwd", os.path.join(src, "evil_link"))
os.symlink("../../../../../../etc/hosts", os.path.join(src, "nested", "evil_link2"))

with tarfile.open("/home/user/docs.tar", "w", dereference=False) as tf:
    for name in sorted(os.listdir(src)):
        tf.add(os.path.join(src, name), arcname=name, recursive=True)

with open("/tmp/verifier_expected.json", "w", encoding="utf-8") as f:
    json.dump({
        "binary_sha256": hashlib.sha256(binary).hexdigest(),
        "legacy": legacy_utf8,
        "modern": "Standard modern doc.\n"
    }, f)
PY
prep_rc=$?

script_ok=0
if [ -f /home/user/process_docs.sh ] && [ ! -L /home/user/process_docs.sh ] && /bin/bash -n /home/user/process_docs.sh; then
    script_ok=1
fi

rm -rf /home/user/workspace /home/user/assets /home/user/manifest.txt
mkdir -p /home/user/assets
chmod 777 /home/user/assets

run_rc=127
if [ "$script_ok" -eq 1 ] && [ "$prep_rc" -eq 0 ]; then
    timeout 60s /bin/bash /home/user/process_docs.sh
    run_rc=$?
fi
printf '%s\n' "$script_ok" > /tmp/verifier_script_ok
printf '%s\n' "$run_rc" > /tmp/verifier_run_rc

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import re
import stat
import pytest

WORKSPACE = "/home/user/workspace"
ASSETS = "/home/user/assets"
EXPECTED_FILES = {
    "/home/user/assets/image_data.bin",
    "/home/user/workspace/legacy.md",
    "/home/user/workspace/nested/modern.md",
}
EXPECTED_LINKS = {
    "/home/user/workspace/nested/safe_link.txt",
}

with open("/tmp/verifier_expected.json", encoding="utf-8") as f:
    EXPECTED = json.load(f)


def get_sha256(filepath):
    h = hashlib.sha256()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            h.update(chunk)
    return h.hexdigest()


def inventory(root):
    regular = set()
    links = set()
    special = set()
    if not os.path.isdir(root):
        return regular, links, special
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        for name in dirnames + filenames:
            path = os.path.join(dirpath, name)
            mode = os.lstat(path).st_mode
            if stat.S_ISLNK(mode):
                links.add(path)
            elif stat.S_ISREG(mode):
                regular.add(path)
            elif not stat.S_ISDIR(mode):
                special.add(path)
    return regular, links, special


def test_script_exists_and_was_successfully_executed():
    assert os.path.isfile("/home/user/process_docs.sh"), "The required process_docs.sh script does not exist."
    assert not os.path.islink("/home/user/process_docs.sh"), "process_docs.sh must be a regular Bash script, not a symlink."
    assert open("/tmp/verifier_script_ok").read().strip() == "1", "process_docs.sh is not a valid Bash script."
    assert open("/tmp/verifier_run_rc").read().strip() == "0", "process_docs.sh did not execute successfully."


def test_workspace_exists():
    assert os.path.isdir(WORKSPACE), "The directory /home/user/workspace was not created."


def test_evil_links_deleted():
    evil1 = "/home/user/workspace/evil_link"
    evil2 = "/home/user/workspace/nested/evil_link2"
    assert not os.path.exists(evil1) and not os.path.islink(evil1), f"External symlink {evil1} was not deleted."
    assert not os.path.exists(evil2) and not os.path.islink(evil2), f"External symlink {evil2} was not deleted."


def test_safe_link_kept():
    safe_link = "/home/user/workspace/nested/safe_link.txt"
    assert os.path.islink(safe_link), f"Safe internal symlink {safe_link} was deleted or is not a symlink."
    assert os.readlink(safe_link) == "../legacy.txt", "The safe symlink was changed instead of being left intact."
    resolved = os.path.abspath(os.path.join(os.path.dirname(safe_link), os.readlink(safe_link)))
    assert os.path.commonpath([WORKSPACE, resolved]) == WORKSPACE


def test_binary_moved_and_renamed():
    binary_file = "/home/user/assets/image_data.bin"
    assert os.path.isfile(binary_file), f"Binary file was not moved to {binary_file}."
    assert get_sha256(binary_file) == EXPECTED["binary_sha256"], "The moved binary does not match the fresh archive input."
    assert not os.path.lexists("/home/user/workspace/image_data"), "The binary was copied rather than moved out of the workspace."


def test_text_files_renamed_and_converted():
    legacy_md = "/home/user/workspace/legacy.md"
    modern_md = "/home/user/workspace/nested/modern.md"
    assert os.path.isfile(legacy_md), f"Text file not renamed properly to {legacy_md}."
    assert os.path.isfile(modern_md), f"Text file not renamed properly to {modern_md}."
    assert not os.path.lexists("/home/user/workspace/legacy.txt")
    assert not os.path.lexists("/home/user/workspace/nested/modern.txt")

    try:
        with open(legacy_md, "r", encoding="utf-8") as f:
            content = f.read()
            assert "résumé, façade" in content, "Content of legacy file was lost or corrupted during conversion."
            assert content == EXPECTED["legacy"], "Legacy text content changed during conversion."
        with open(modern_md, "r", encoding="utf-8") as f:
            assert f.read() == EXPECTED["modern"], "Modern UTF-8 text content changed."
    except UnicodeDecodeError as exc:
        pytest.fail(f"A processed text file is not valid UTF-8: {exc}")


def test_complete_final_inventory():
    workspace_regular, workspace_links, workspace_special = inventory(WORKSPACE)
    assets_regular, assets_links, assets_special = inventory(ASSETS)
    assert workspace_regular | assets_regular == EXPECTED_FILES, "Final regular-file inventory contains missing or extra files."
    assert workspace_links | assets_links == EXPECTED_LINKS, "Final symlink inventory contains missing or extra links."
    assert not workspace_special and not assets_special, "Unexpected special filesystem entries remain after processing."


def test_manifest():
    manifest_path = "/home/user/manifest.txt"
    assert os.path.isfile(manifest_path), f"Manifest file {manifest_path} was not created."

    with open(manifest_path, "r", encoding="utf-8") as f:
        raw_lines = f.read().splitlines()
    assert raw_lines, "Manifest is empty."
    assert all(line and line == line.strip() for line in raw_lines), "Manifest contains blank lines or surrounding whitespace."

    line_re = re.compile(r"^(/[^|]*) \| ([0-9a-f]{64})$")
    entries = []
    for line in raw_lines:
        match = line_re.fullmatch(line)
        assert match, f"Manifest line improperly formatted: {line}"
        entries.append((match.group(1), match.group(2)))

    paths_in_manifest = [path for path, _ in entries]
    assert paths_in_manifest == sorted(paths_in_manifest), "Manifest lines are not sorted alphabetically by absolute path."
    assert len(paths_in_manifest) == len(set(paths_in_manifest)), "Manifest contains duplicate paths."
    assert set(paths_in_manifest) == EXPECTED_FILES, "Manifest is incomplete or contains extra files."

    manifest_dict = dict(entries)
    for expected_file in EXPECTED_FILES:
        actual_hash = get_sha256(expected_file)
        assert manifest_dict[expected_file] == actual_hash, f"Hash mismatch in manifest for {expected_file}."

    safe_link = "/home/user/workspace/nested/safe_link.txt"
    assert safe_link not in manifest_dict, f"Symlink {safe_link} should not be included in the manifest."
TEST_EOF

if [ "$prep_rc" -eq 0 ] && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
