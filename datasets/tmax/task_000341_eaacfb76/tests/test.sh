#!/bin/bash
set -e
mkdir -p /logs/verifier

SCRIPT_RUN_OK=0
rm -rf /home/user/repo
if [[ -f /home/user/curate.sh ]]; then
    if timeout 30s bash /home/user/curate.sh > /tmp/curate.stdout 2> /tmp/curate.stderr; then
        SCRIPT_RUN_OK=1
    fi
fi
export SCRIPT_RUN_OK

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import json
import os
import tarfile
import zipfile

import pytest

REPO_DIR = "/home/user/repo"
MANIFEST_PATH = os.path.join(REPO_DIR, "manifest.json")


def test_script_exists_and_was_executed():
    assert os.path.isfile("/home/user/curate.sh"), "/home/user/curate.sh is missing."
    assert os.environ.get("SCRIPT_RUN_OK") == "1", "/home/user/curate.sh did not execute successfully."


def test_repo_directory_exists():
    assert os.path.isdir(REPO_DIR), f"The repository directory {REPO_DIR} was not created."


def test_curated_archives_exist():
    expected_files = [
        "arm64/alphatools-2.1.tar.gz",
        "x86_64/gammacore-3.0.1.zip"
    ]
    for rel_path in expected_files:
        full_path = os.path.join(REPO_DIR, rel_path)
        assert os.path.isfile(full_path), f"Expected curated artifact {full_path} is missing."


def test_curated_archives_match_sources_and_are_valid():
    alpha_src = "/home/user/incoming/alpha_release.tar.gz"
    alpha_dst = "/home/user/repo/arm64/alphatools-2.1.tar.gz"
    gamma_src = "/home/user/incoming/gamma_core.zip"
    gamma_dst = "/home/user/repo/x86_64/gammacore-3.0.1.zip"

    assert filecmp.cmp(alpha_src, alpha_dst, shallow=False), "Curated AlphaTools archive is not an exact copy of the incoming archive."
    assert filecmp.cmp(gamma_src, gamma_dst, shallow=False), "Curated GammaCore archive is not an exact copy of the incoming archive."

    try:
        with tarfile.open(alpha_dst, "r:gz") as archive:
            member = archive.getmember("build.txt")
            assert member.isfile(), "AlphaTools build.txt is not a regular file."
            extracted = archive.extractfile(member)
            assert extracted is not None
            assert extracted.read().decode("utf-8").strip() == "ID=alpha-992"
    except (tarfile.TarError, KeyError, UnicodeDecodeError) as exc:
        pytest.fail(f"Curated AlphaTools file is not the required valid archive: {exc}")

    try:
        with zipfile.ZipFile(gamma_dst, "r") as archive:
            info = archive.getinfo("build.txt")
            assert not info.is_dir(), "GammaCore build.txt is not a regular file."
            assert archive.read(info).decode("utf-8").strip() == "ID=gamma-777"
            bad_member = archive.testzip()
            assert bad_member is None, f"GammaCore ZIP has a corrupt member: {bad_member}"
    except (zipfile.BadZipFile, KeyError, UnicodeDecodeError) as exc:
        pytest.fail(f"Curated GammaCore file is not the required valid archive: {exc}")


def test_ignored_artifacts_not_present():
    # BetaApp was 'testing' so it should not be in the repo
    # Check if any betaapp files exist in the repo
    for root, dirs, files in os.walk(REPO_DIR):
        for file in files:
            assert "beta" not in file.lower(), f"Artifact {file} should have been ignored (status was testing)."


def test_manifest_json():
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file {MANIFEST_PATH} is missing."

    with open(MANIFEST_PATH, 'r') as f:
        try:
            manifest_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Manifest file {MANIFEST_PATH} is not valid JSON.")

    assert isinstance(manifest_data, list), "Manifest JSON root should be a list."
    assert len(manifest_data) == 2, f"Manifest should contain exactly 2 items, found {len(manifest_data)}."

    expected_items = [
        {
            "name": "alphatools",
            "version": "2.1",
            "arch": "arm64",
            "build_id": "alpha-992",
            "file": "alphatools-2.1.tar.gz"
        },
        {
            "name": "gammacore",
            "version": "3.0.1",
            "arch": "x86_64",
            "build_id": "gamma-777",
            "file": "gammacore-3.0.1.zip"
        }
    ]

    for expected in expected_items:
        found = False
        for item in manifest_data:
            if item.get("name") == expected["name"]:
                found = True
                assert item.get("version") == expected["version"], f"Version mismatch for {expected['name']}"
                assert item.get("arch") == expected["arch"], f"Arch mismatch for {expected['name']}"
                assert item.get("build_id") == expected["build_id"], f"Build ID mismatch for {expected['name']}"
                assert item.get("file") == expected["file"], f"File mismatch for {expected['name']}"
                break
        assert found, f"Expected artifact {expected['name']} not found in manifest.json."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
