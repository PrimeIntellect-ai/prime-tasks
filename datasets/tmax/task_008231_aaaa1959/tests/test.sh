#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import tarfile
import tempfile

FINAL_ARCHIVE = "/home/user/final_archive.tar.gz"
RAW_DIR = "/home/user/docs_raw"
PROCESSED_DIR = "/home/user/docs_processed"
RELEASE_DIR = "/home/user/release"
VERSIONS = ("v1.0", "v1.1", "v2.0-draft")


def archive_payload(version, filename):
    archive = os.path.join(RAW_DIR, version + ".tar.gz")
    assert os.path.isfile(archive), f"Source archive {archive} is missing."
    wanted = f"{version}/{filename}"
    with tarfile.open(archive, "r:gz") as tar:
        matches = [m for m in tar.getmembers() if m.name.lstrip("./") == wanted]
        assert len(matches) == 1, f"{archive} must contain exactly one {wanted}."
        member = matches[0]
        assert member.isfile(), f"{wanted} in {archive} is not a regular file."
        source = tar.extractfile(member)
        assert source is not None
        return source.read()


def assert_regular_file(path):
    mode = os.lstat(path).st_mode
    assert stat.S_ISREG(mode), f"{path} is not a regular file."


def test_final_archive_exists():
    assert os.path.isfile(FINAL_ARCHIVE), f"Final archive {FINAL_ARCHIVE} does not exist."
    assert tarfile.is_tarfile(FINAL_ARCHIVE), f"{FINAL_ARCHIVE} is not a valid tar file."


def test_final_archive_contents():
    with tempfile.TemporaryDirectory() as tmpdir:
        with tarfile.open(FINAL_ARCHIVE, "r:gz") as tar:
            tar.extractall(path=tmpdir)

        release_dir = os.path.join(tmpdir, "release")
        assert os.path.isdir(release_dir), "The archive must contain a 'release' directory at its root."

        # Keep the original checks for api.bin.
        api_bin_path = os.path.join(release_dir, "api.bin")
        assert os.path.isfile(api_bin_path), "'api.bin' is missing in the release directory."
        with open(api_bin_path, "rb") as f:
            api_content = f.read()
        assert api_content == b'\x05\x06\x07', "The 'api.bin' file does not contain the expected bytes from v2.0-draft."
        assert api_content == archive_payload("v2.0-draft", "api.bin")

        # Keep the original checks for README.md.
        readme_path = os.path.join(release_dir, "README.md")
        assert os.path.isfile(readme_path), "'README.md' is missing in the release directory."
        with open(readme_path, "r", encoding="utf-8") as f:
            readme_content = f.read().strip()
        expected_readme = "Version 1.1 docs\nCONFIDENTIAL - DRAFT STATUS"
        assert readme_content == expected_readme, "The 'README.md' file does not contain the expected updated text."
        source_readme = archive_payload("v1.1", "README.md").decode("utf-8").rstrip("\n")
        assert readme_content == source_readme + "\nCONFIDENTIAL - DRAFT STATUS"

        # Keep the original symlink checks.
        symlink_path = os.path.join(release_dir, "latest_api")
        assert os.path.islink(symlink_path), "'latest_api' is not a symbolic link."
        link_target = os.readlink(symlink_path)
        assert link_target == "api.bin", f"'latest_api' should point to 'api.bin', but points to '{link_target}'."

        # A successful mv must not leave the temporary file in the archived release.
        assert not os.path.lexists(os.path.join(release_dir, ".README.md.tmp")), \
            "The temporary README file was not moved away."


def test_intermediate_directories_and_extractions():
    assert os.path.isdir(PROCESSED_DIR), "The docs_processed directory was not created."
    assert os.path.isdir(RELEASE_DIR), "The release directory was not created."

    # Verify that every archive's complete payload was actually materialized under
    # docs_processed, rather than accepting an empty placeholder directory.
    for version in VERSIONS:
        version_dir = os.path.join(PROCESSED_DIR, version)
        assert stat.S_ISDIR(os.lstat(version_dir).st_mode), \
            f"Extracted directory {version_dir} is missing or is not a real directory."
        for filename in ("README.md", "api.bin"):
            path = os.path.join(version_dir, filename)
            assert_regular_file(path)
            with open(path, "rb") as f:
                actual = f.read()
            assert actual == archive_payload(version, filename), \
                f"{path} does not match the corresponding source archive entry."


def test_live_release_matches_required_workflow():
    api_path = os.path.join(RELEASE_DIR, "api.bin")
    readme_path = os.path.join(RELEASE_DIR, "README.md")
    link_path = os.path.join(RELEASE_DIR, "latest_api")
    temp_path = os.path.join(RELEASE_DIR, ".README.md.tmp")

    assert_regular_file(api_path)
    with open(api_path, "rb") as f:
        assert f.read() == archive_payload("v2.0-draft", "api.bin")

    assert_regular_file(readme_path)
    with open(readme_path, "r", encoding="utf-8") as f:
        actual_readme = f.read().strip()
    source_readme = archive_payload("v1.1", "README.md").decode("utf-8").rstrip("\n")
    assert actual_readme == source_readme + "\nCONFIDENTIAL - DRAFT STATUS"

    assert os.path.islink(link_path), "The live release/latest_api is not a symbolic link."
    assert os.readlink(link_path) == "api.bin", "The live latest_api link is not relative to api.bin."
    assert not os.path.lexists(temp_path), "The temporary README file remains after the required mv."
TEST_EOF

set +e
python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
set -e
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
