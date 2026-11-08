#!/bin/bash
mkdir -p /logs/verifier

ORIGINAL_ARCHIVE=/tmp/verifier_original_data.tar.gz
cp -f /home/user/data.tar.gz "$ORIGINAL_ARCHIVE"

restore_archive() {
    if [ -f "$ORIGINAL_ARCHIVE" ]; then
        cp -f "$ORIGINAL_ARCHIVE" /home/user/data.tar.gz
    fi
}
trap restore_archive EXIT

run_all_tests() {
    # Verify the requested artifact before executing it.
    [ -f /home/user/organize.sh ] || return 1
    [ -x /home/user/organize.sh ] || return 1

    # Remove all possible precomputed outputs, then execute the submission on
    # the original archive.
    rm -rf /home/user/raw_data /home/user/organized /home/user/summary.txt || return 1
    timeout 30 /home/user/organize.sh || return 1

    cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat


def test_summary_txt():
    summary_path = "/home/user/summary.txt"
    assert os.path.isfile(summary_path), f"Summary file {summary_path} does not exist."

    with open(summary_path, 'r') as f:
        content = f.read().strip()

    expected_content = "Apollo_Lunar: 1\nArtemis_Base: 1\nGemini: 2"

    # Compare lines ignoring trailing whitespace or empty lines
    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]
    expected_lines = [line.strip() for line in expected_content.splitlines() if line.strip()]

    assert actual_lines == expected_lines, f"Summary file content is incorrect. Expected:\n{expected_content}\nGot:\n{content}"


def test_symlinks():
    expected_symlinks = {
        "/home/user/organized/json/Apollo_Lunar_meta1.json": "/home/user/raw_data/dir1/meta1.json",
        "/home/user/organized/json/Gemini_meta3.json": "/home/user/raw_data/dir3/meta3.json",
        "/home/user/organized/xml/Gemini_meta2.xml": "/home/user/raw_data/dir1/dir2/meta2.xml",
        "/home/user/organized/csv/Artemis_Base_data.csv": "/home/user/raw_data/dir3/data.csv"
    }

    for symlink_path, target_path in expected_symlinks.items():
        assert os.path.islink(symlink_path), f"Expected symlink at {symlink_path} does not exist or is not a symlink."
        actual_target = os.readlink(symlink_path)
        assert actual_target == target_path, f"Symlink {symlink_path} points to {actual_target}, expected {target_path}."
        assert os.path.isfile(target_path), f"Symlink target {target_path} was not extracted as a file."


def test_script_exists_and_executable():
    script_path = "/home/user/organize.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1

    # Build a second, independent archive so fixed output and dangling-link
    # implementations cannot pass. The checker derives its expectations by
    # parsing this archive independently.
    rm -rf /tmp/verifier_case_src /tmp/verifier_expected
    python3 - << 'PY_EOF' || return 1
import json
import os
import tarfile

root = "/tmp/verifier_case_src"
os.makedirs(os.path.join(root, "level", "deeper"), exist_ok=True)
os.makedirs(os.path.join(root, "another"), exist_ok=True)

with open(os.path.join(root, "level", "alpha.json"), "w") as f:
    json.dump({"project_name": "Nova Prime", "version": 7}, f)

with open(os.path.join(root, "level", "deeper", "details.xml"), "w") as f:
    f.write("<?xml version=\"1.0\"?><metadata><project_name>Orion</project_name><state>active</state></metadata>\n")

with open(os.path.join(root, "another", "record.csv"), "w") as f:
    f.write("version,project_name,date\n2.1,Nova Prime,2026-01-02\n")

with open(os.path.join(root, "another", "last.json"), "w") as f:
    json.dump({"project_name": "Zenith", "nested": {"project_name": "Wrong Value"}}, f)

with tarfile.open("/home/user/data.tar.gz", "w:gz") as archive:
    for dirpath, _, filenames in os.walk(root):
        for filename in filenames:
            path = os.path.join(dirpath, filename)
            archive.add(path, arcname=os.path.relpath(path, root))
PY_EOF

    rm -rf /home/user/raw_data /home/user/organized /home/user/summary.txt || return 1
    timeout 30 /home/user/organize.sh || return 1

    cat << 'DYNAMIC_EOF' > /tmp/test_dynamic_processing.py
import csv
import json
import os
import tarfile
import xml.etree.ElementTree as ET
from collections import Counter

ARCHIVE = "/home/user/data.tar.gz"
EXPECTED_ROOT = "/tmp/verifier_expected"
RAW_ROOT = "/home/user/raw_data"
ORGANIZED_ROOT = "/home/user/organized"


def derive_expected():
    os.makedirs(EXPECTED_ROOT, exist_ok=True)
    with tarfile.open(ARCHIVE, "r:gz") as archive:
        archive.extractall(EXPECTED_ROOT)

    expected_links = {}
    counts = Counter()

    for dirpath, _, filenames in os.walk(EXPECTED_ROOT):
        for filename in filenames:
            extension = os.path.splitext(filename)[1]
            if extension not in (".json", ".xml", ".csv"):
                continue

            source = os.path.join(dirpath, filename)
            if extension == ".json":
                with open(source) as f:
                    project = json.load(f)["project_name"]
            elif extension == ".xml":
                project = ET.parse(source).getroot().find(".//project_name").text
            else:
                with open(source, newline="") as f:
                    project = next(csv.DictReader(f))["project_name"]

            normalized = project.replace(" ", "_")
            relative = os.path.relpath(source, EXPECTED_ROOT)
            target = os.path.join(RAW_ROOT, relative)
            link = os.path.join(
                ORGANIZED_ROOT,
                extension[1:],
                normalized + "_" + filename,
            )
            expected_links[link] = (target, source)
            counts[normalized] += 1

    return expected_links, counts


def test_processing_of_independent_archive():
    expected_links, counts = derive_expected()

    for link, (target, expected_source) in expected_links.items():
        assert os.path.islink(link), f"Missing symbolic link {link}"
        assert os.readlink(link) == target, (
            f"Symbolic link {link} points to {os.readlink(link)!r}, expected {target!r}"
        )
        assert os.path.isfile(target), f"Extracted target {target} does not exist"
        with open(target, "rb") as actual, open(expected_source, "rb") as expected:
            assert actual.read() == expected.read(), f"Extracted file {target} has incorrect content"

    assert os.path.isfile("/home/user/summary.txt"), "Summary file was not generated"
    with open("/home/user/summary.txt") as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    expected_lines = [f"{name}: {counts[name]}" for name in sorted(counts)]
    assert actual_lines == expected_lines, (
        f"Summary is incorrect: expected {expected_lines!r}, got {actual_lines!r}"
    )
DYNAMIC_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_dynamic_processing.py -x --tb=short || return 1
    return 0
}

if run_all_tests; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
