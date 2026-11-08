#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import stat


def expected_mtime_ns(year, month, day, hour, minute=0, second=0):
    dt = datetime.datetime(year, month, day, hour, minute, second)
    return int(dt.timestamp()) * 1_000_000_000


def assert_binary(path, expected_size, expected_mtime):
    assert os.path.exists(path), f"Expected {path} to exist"
    st = os.stat(path, follow_symlinks=False)
    assert stat.S_ISREG(st.st_mode), f"{path} must be a regular file"
    assert st.st_size == expected_size, f"{path} has incorrect size: expected {expected_size}, got {st.st_size}"
    assert st.st_mtime_ns == expected_mtime, f"{path} has incorrect modification timestamp"
    with open(path, "rb") as f:
        data = f.read()
    assert len(data) == expected_size, f"{path} contents do not match its expected size"
    assert any(data), f"{path} must contain binary artifact data, not an empty/zero-filled substitute"


def test_renamed_binaries():
    """
    Test that binary files meeting both criteria (>100KB, <2023-01-01) were renamed,
    and those that don't were left untouched, preserving their metadata and data.
    """
    assert os.path.exists("/home/user/repo/groupA/legacy_artifact1.bin"), "Expected legacy_artifact1.bin to exist"
    assert not os.path.exists("/home/user/repo/groupA/artifact1.bin"), "Expected artifact1.bin to have been renamed"

    assert os.path.exists("/home/user/repo/groupC/deep/legacy_module.bin"), "Expected legacy_module.bin to exist"
    assert not os.path.exists("/home/user/repo/groupC/deep/module.bin"), "Expected module.bin to have been renamed"

    assert os.path.exists("/home/user/repo/groupA/artifact2.bin"), "Expected artifact2.bin to remain unchanged (fails size criteria)"
    assert not os.path.exists("/home/user/repo/groupA/legacy_artifact2.bin"), "artifact2.bin should not be renamed"

    assert os.path.exists("/home/user/repo/groupB/artifact3.bin"), "Expected artifact3.bin to remain unchanged (fails date criteria)"
    assert not os.path.exists("/home/user/repo/groupB/legacy_artifact3.bin"), "artifact3.bin should not be renamed"

    assert_binary(
        "/home/user/repo/groupA/legacy_artifact1.bin",
        150 * 1024,
        expected_mtime_ns(2022, 12, 1, 12),
    )
    assert_binary(
        "/home/user/repo/groupC/deep/legacy_module.bin",
        200 * 1024,
        expected_mtime_ns(2020, 5, 15, 8, 30),
    )
    assert_binary(
        "/home/user/repo/groupA/artifact2.bin",
        50 * 1024,
        expected_mtime_ns(2022, 12, 1, 12),
    )
    assert_binary(
        "/home/user/repo/groupB/artifact3.bin",
        150 * 1024,
        expected_mtime_ns(2023, 6, 1, 12),
    )


def test_config_files_updated():
    """
    Test that all .conf files have the requested replacement while preserving all
    other original content.
    """
    expected_contents = {
        "/home/user/repo/groupA/config.conf": "id: alpha-99\nbackend: cloud-storage\nversion: 1.0\n",
        "/home/user/repo/groupB/settings.conf": "name: module_b\nid: beta-42\nbackend: cloud-storage\nversion: 2.1\n",
        "/home/user/repo/groupC/deep/app.conf": "id: delta-05\ndescription: core app\nbackend: cloud-storage\n",
    }

    for conf_file, expected in expected_contents.items():
        assert os.path.exists(conf_file), f"Config file {conf_file} is missing"
        assert os.path.isfile(conf_file), f"Config file {conf_file} is not a regular file"
        with open(conf_file, "r") as f:
            content = f.read()
            assert "backend: cloud-storage" in content, f"File {conf_file} was not updated to cloud-storage"
            assert "backend: legacy-storage" not in content, f"File {conf_file} still contains legacy-storage"
            assert content == expected, f"File {conf_file} did not preserve its non-backend contents"


def test_txt_file_ignored():
    """
    Test that non-.conf files were ignored during the text transformation.
    """
    txt_file = "/home/user/repo/groupB/ignore.txt"
    assert os.path.exists(txt_file), f"File {txt_file} is missing"
    assert os.path.isfile(txt_file), f"File {txt_file} is not a regular file"
    with open(txt_file, "r") as f:
        content = f.read()
        assert "backend: legacy-storage" in content, f"File {txt_file} should not have been modified"
        assert "backend: cloud-storage" not in content, f"File {txt_file} should not contain cloud-storage"
        assert content == "id: gamma-00\nbackend: legacy-storage\n", f"File {txt_file} should be completely unchanged"


def test_extracted_ids_manifest():
    """
    Test that the manifest file is generated correctly, sorted, and contains only IDs from .conf files.
    """
    manifest_path = "/home/user/extracted_ids.txt"
    assert os.path.exists(manifest_path), f"Manifest file {manifest_path} was not created"
    assert os.path.isfile(manifest_path), f"Manifest file {manifest_path} is not a regular file"

    with open(manifest_path, "r") as f:
        content = f.read()
        lines = [line.strip() for line in content.splitlines() if line.strip()]

    expected_ids = ["alpha-99", "beta-42", "delta-05"]

    assert lines == expected_ids, f"Manifest contents are incorrect or not sorted properly. Expected {expected_ids}, got {lines}"
    assert "gamma-00" not in lines, "Manifest should not contain IDs from non-.conf files"
    assert content == "alpha-99\nbeta-42\ndelta-05\n", "Manifest must contain exactly one sorted ID per line"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
