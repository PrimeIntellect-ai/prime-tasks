#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import stat
import zipfile

RAW_DIR = "/home/user/raw_docs"
COMPILED_DIR = "/home/user/compiled_docs"

SOURCE_BYTES = {
    "folder_a/api_v1_endpoints.md": "# API v1\nEndpoints list.".encode("utf-8"),
    "folder_a/subfolder/legacy_notes.txt": "Old notes from 2015.".encode("utf-16le"),
    "folder_b/Setup_guide.md": "# Setup\nHow to install.".encode("utf-8"),
    "folder_b/random_thoughts.txt": "Just some random notes.".encode("utf-16le"),
    "folder_b/AUTH_flow.txt": "OAuth2 flow details.".encode("utf-8"),
    "folder_a/ignore_me.jpg": bytes.fromhex("ffd8ffe000104a4649460001"),
}

EXPECTED_OUTPUTS = {
    "/home/user/compiled_docs/api_reference/api_v1_endpoints.md": (
        "/home/user/raw_docs/folder_a/api_v1_endpoints.md",
        False,
        "# API v1\nEndpoints list.".encode("utf-8"),
    ),
    "/home/user/compiled_docs/archive/legacy_notes.txt": (
        "/home/user/raw_docs/folder_a/subfolder/legacy_notes.txt",
        True,
        "Old notes from 2015.".encode("utf-8"),
    ),
    "/home/user/compiled_docs/installation/Setup_guide.md": (
        "/home/user/raw_docs/folder_b/Setup_guide.md",
        False,
        "# Setup\nHow to install.".encode("utf-8"),
    ),
    "/home/user/compiled_docs/security/AUTH_flow.txt": (
        "/home/user/raw_docs/folder_b/AUTH_flow.txt",
        False,
        "OAuth2 flow details.".encode("utf-8"),
    ),
    "/home/user/compiled_docs/uncategorized/random_thoughts.txt": (
        "/home/user/raw_docs/folder_b/random_thoughts.txt",
        True,
        "Just some random notes.".encode("utf-8"),
    ),
}


def regular_files_under(root):
    result = set()
    for current, dirs, files in os.walk(root, followlinks=False):
        for name in files:
            path = os.path.join(current, name)
            result.add(os.path.relpath(path, root).replace(os.sep, "/"))
    return result


def assert_regular_file(path):
    assert os.path.exists(path), f"Expected file missing: {path}"
    assert stat.S_ISREG(os.lstat(path).st_mode), f"Expected a regular file: {path}"


def test_raw_docs_extracted():
    assert os.path.exists(RAW_DIR), "/home/user/raw_docs directory does not exist. Extraction failed."
    assert os.path.isdir(RAW_DIR), "/home/user/raw_docs is not a directory."

    actual_files = regular_files_under(RAW_DIR)
    assert actual_files == set(SOURCE_BYTES), (
        f"Extracted file set is incorrect. Expected {sorted(SOURCE_BYTES)}, got {sorted(actual_files)}"
    )
    for relpath, expected_bytes in SOURCE_BYTES.items():
        path = os.path.join(RAW_DIR, *relpath.split("/"))
        assert_regular_file(path)
        with open(path, "rb") as f:
            assert f.read() == expected_bytes, f"Extracted content differs from the source archive: {path}"


def test_manifest_json():
    manifest_path = "/home/user/manifest.json"
    assert os.path.exists(manifest_path), f"Missing {manifest_path}"

    with open(manifest_path, "r", encoding="utf-8") as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            assert False, "manifest.json is not valid JSON."

    assert isinstance(manifest, list), "Manifest must be a JSON array."

    # Check sorting
    new_paths = [item.get("new_path", "") if isinstance(item, dict) else "" for item in manifest]
    assert new_paths == sorted(new_paths), "Manifest array is not sorted alphabetically by new_path."

    # Check expected files
    expected_files = {
        path: values[1] for path, values in EXPECTED_OUTPUTS.items()
    }
    actual_files = {
        item.get("new_path"): item.get("was_converted")
        for item in manifest if isinstance(item, dict)
    }
    for path, was_converted in expected_files.items():
        assert path in actual_files, f"Missing expected file in manifest: {path}"
        assert actual_files[path] == was_converted, (
            f"Expected was_converted={was_converted} for {path}, got {actual_files[path]}"
        )

    expected_manifest = [
        {
            "original_path": EXPECTED_OUTPUTS[path][0],
            "new_path": path,
            "was_converted": EXPECTED_OUTPUTS[path][1],
        }
        for path in sorted(EXPECTED_OUTPUTS)
    ]
    assert len(manifest) == len(expected_manifest), "Manifest has missing, duplicate, or extra entries."
    for item in manifest:
        assert isinstance(item, dict), "Every manifest entry must be an object."
        assert set(item.keys()) == {"original_path", "new_path", "was_converted"}, (
            "Every manifest object must contain exactly original_path, new_path, and was_converted."
        )
        assert type(item["was_converted"]) is bool, "was_converted must be a JSON boolean."
    assert manifest == expected_manifest, "Manifest paths, conversion flags, entries, or ordering are incorrect."


def test_compiled_docs_content_and_encoding():
    assert os.path.exists(COMPILED_DIR), f"{COMPILED_DIR} does not exist."
    assert os.path.isdir(COMPILED_DIR), f"{COMPILED_DIR} is not a directory."

    expected_paths = list(EXPECTED_OUTPUTS)
    expected_relative = {
        os.path.relpath(path, COMPILED_DIR).replace(os.sep, "/") for path in expected_paths
    }
    assert regular_files_under(COMPILED_DIR) == expected_relative, (
        "compiled_docs contains missing, misplaced, or extra files."
    )

    for path in expected_paths:
        assert os.path.exists(path), f"Expected file missing in compiled_docs: {path}"
        assert_regular_file(path)

        # Check encoding by reading as utf-8
        try:
            with open(path, "r", encoding="utf-8") as f:
                content = f.read()
            assert "\x00" not in content, f"File {path} appears to still be UTF-16 encoded (contains null bytes)."
        except UnicodeDecodeError:
            assert False, f"File {path} is not valid UTF-8."

        with open(path, "rb") as f:
            actual = f.read()
        assert actual == EXPECTED_OUTPUTS[path][2], f"Compiled file content is incorrect: {path}"


def test_final_docs_zip():
    zip_path = "/home/user/final_docs.zip"
    assert os.path.exists(zip_path), f"Missing {zip_path}"
    assert zipfile.is_zipfile(zip_path), f"{zip_path} is not a valid zip file."

    expected_zip_contents = {
        "compiled_docs/" + os.path.relpath(path, COMPILED_DIR).replace(os.sep, "/"): values[2]
        for path, values in EXPECTED_OUTPUTS.items()
    }
    allowed_directories = {"compiled_docs/"}
    for name in expected_zip_contents:
        parts = name.split("/")[:-1]
        for i in range(1, len(parts) + 1):
            allowed_directories.add("/".join(parts[:i]) + "/")

    with zipfile.ZipFile(zip_path, "r") as z:
        namelist = z.namelist()

        # Check if compiled_docs is in the zip
        compiled_docs_files = [n for n in namelist if "compiled_docs/" in n]
        assert len(compiled_docs_files) > 0, "Zip archive does not contain compiled_docs directory."

        # Ensure all expected files are in the zip
        expected_suffixes = list(expected_zip_contents)
        for suffix in expected_suffixes:
            found = any(n.endswith(suffix) for n in namelist)
            assert found, f"Expected file ending with {suffix} not found in zip archive."

        archived_files = [info.filename for info in z.infolist() if not info.is_dir()]
        assert sorted(archived_files) == sorted(expected_zip_contents), (
            "Zip archive contains missing, duplicate, misplaced, or extra files."
        )
        for info in z.infolist():
            if info.is_dir():
                assert info.filename in allowed_directories, f"Unexpected directory in zip: {info.filename}"
            else:
                expected = expected_zip_contents[info.filename]
                assert z.read(info) == expected, f"Archived content is incorrect: {info.filename}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
