#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import io
import os
import shutil
import subprocess
import tarfile
import zipfile

HOME = "/home/user"
RAW_ARCHIVE = os.path.join(HOME, "raw_docs.tar.gz")
EXTRACTED = os.path.join(HOME, "extracted_docs")
PUBLIC = os.path.join(HOME, "public_docs")
SCRIPT = os.path.join(HOME, "organize_docs.py")
CONFIG = os.path.join(HOME, "docs_config.ini")
LOG = os.path.join(HOME, "build_errors.log")
MANIFEST = os.path.join(HOME, "success_manifest.txt")


def archive_files():
    result = {}
    with tarfile.open(RAW_ARCHIVE, "r:gz") as outer:
        members = {os.path.basename(m.name): m for m in outer.getmembers() if m.isfile()}
        assert "core.tar.gz" in members, "raw_docs.tar.gz does not contain core.tar.gz"
        assert "api.zip" in members, "raw_docs.tar.gz does not contain api.zip"

        core_data = outer.extractfile(members["core.tar.gz"]).read()
        with tarfile.open(fileobj=io.BytesIO(core_data), mode="r:gz") as core:
            for member in core.getmembers():
                if member.isfile():
                    result[os.path.basename(member.name)] = core.extractfile(member).read()

        api_data = outer.extractfile(members["api.zip"]).read()
        with zipfile.ZipFile(io.BytesIO(api_data)) as api:
            for name in api.namelist():
                if not name.endswith("/"):
                    result[os.path.basename(name)] = api.read(name)
    return result


def extracted_sources():
    expected = archive_files()
    found = {}
    for root, _, files in os.walk(EXTRACTED):
        for name in files:
            if name in expected:
                path = os.path.abspath(os.path.join(root, name))
                assert name not in found, f"Extracted source appears more than once: {name}"
                with open(path, "rb") as f:
                    assert f.read() == expected[name], f"Extracted file content differs from archive: {path}"
                found[name] = path
    assert set(found) == set(expected), f"Extracted archive files are incomplete: expected {sorted(expected)}, got {sorted(found)}"
    return found


def reset_public():
    if os.path.islink(PUBLIC):
        os.unlink(PUBLIC)
    elif os.path.exists(PUBLIC):
        shutil.rmtree(PUBLIC)
    os.makedirs(PUBLIC)


def run_script():
    subprocess.run(
        ["python3", SCRIPT],
        cwd=HOME,
        check=True,
        timeout=20,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def parse_expected():
    loop_files = set()
    with open(LOG, "r") as f:
        blocks = f.read().split("---")
    for block in blocks:
        fields = {}
        for line in block.splitlines():
            if ":" in line:
                key, value = line.split(":", 1)
                fields[key.strip()] = value.strip()
        if fields.get("Error") == "Infinite Symlink Loop" and fields.get("File"):
            loop_files.add(fields["File"])

    parser = configparser.ConfigParser(interpolation=None)
    parser.optionxform = str
    with open(CONFIG, "r") as f:
        parser.read_file(f)

    sources = extracted_sources()
    expected = {}
    for section in parser.sections():
        for source_name, destination in parser.items(section):
            destination = destination.strip()
            if source_name not in loop_files:
                assert source_name in sources, f"Configured source was not extracted: {source_name}"
                expected[destination] = sources[source_name]
    return expected


def assert_tree_matches(expected):
    actual_paths = set()
    for root, _, files in os.walk(PUBLIC):
        for name in files:
            actual_paths.add(os.path.join(root, name))

    assert actual_paths == set(expected), f"Public documentation tree differs: expected {sorted(expected)}, got {sorted(actual_paths)}"
    for destination, target in expected.items():
        assert os.path.islink(destination), f"Expected symlink not found: {destination}"
        actual_target = os.readlink(destination)
        assert os.path.isabs(actual_target), f"Symlink target must be absolute: {destination} -> {actual_target}"
        assert actual_target == target, f"Wrong target for {destination}: expected {target}, got {actual_target}"


def test_00_extraction_is_authentic_and_script_executes():
    assert os.path.isfile(SCRIPT), f"Script missing: {SCRIPT}"
    extracted_sources()
    reset_public()
    run_script()
    assert_tree_matches(parse_expected())


def test_10_manifest_file_contents():
    manifest_path = "/home/user/success_manifest.txt"
    assert os.path.isfile(manifest_path), f"Manifest file missing: {manifest_path}"

    with open(manifest_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "/home/user/public_docs/api_ref.md",
        "/home/user/public_docs/architecture.md",
        "/home/user/public_docs/introduction.md"
    ]

    assert lines == expected_lines, f"Manifest contents incorrect. Expected {expected_lines}, got {lines}"


def test_20_symlinks_created_correctly():
    expected_links = {
        "/home/user/public_docs/api_ref.md": "reference.md",
        "/home/user/public_docs/architecture.md": "arch.md",
        "/home/user/public_docs/introduction.md": "intro.md"
    }

    for link_path, target_name in expected_links.items():
        assert os.path.islink(link_path), f"Expected symlink not found: {link_path}"

        target_path = os.readlink(link_path)
        assert os.path.isabs(target_path), f"Symlink target must be absolute: {link_path} -> {target_path}"
        assert target_path.startswith("/home/user/extracted_docs/"), f"Symlink target not in extracted_docs: {target_path}"
        assert target_path.endswith(target_name), f"Symlink target incorrect. Expected it to end with {target_name}, got {target_path}"
        assert os.path.isfile(target_path), f"Symlink target does not exist as a file: {target_path}"


def test_30_symlinks_excluded_correctly():
    excluded_links = [
        "/home/user/public_docs/core_loop.md",
        "/home/user/public_docs/api_loop.md"
    ]

    for link_path in excluded_links:
        assert not os.path.exists(link_path) and not os.path.islink(link_path), f"Symlink for excluded file was created: {link_path}"


def test_40_script_exists():
    script_path = "/home/user/organize_docs.py"
    assert os.path.isfile(script_path), f"Script missing: {script_path}"


def test_90_script_reads_multiline_log_and_configuration():
    with open(CONFIG, "r") as f:
        original_config = f.read()
    with open(LOG, "r") as f:
        original_log = f.read()

    probe_config = original_config.replace(
        "/home/user/public_docs/introduction.md",
        "/home/user/public_docs/probe_introduction.md",
    )
    probe_log = original_log.replace(
        "File: bad_loop.md\nError: Infinite Symlink Loop",
        "File: bad_loop.md\nError: Recovered Build Error",
    ).replace(
        "File: intro.md\nError: Missing Image Reference",
        "File: intro.md\nError: Infinite Symlink Loop",
    )
    assert probe_config != original_config
    assert probe_log != original_log

    try:
        with open(CONFIG, "w") as f:
            f.write(probe_config)
        with open(LOG, "w") as f:
            f.write(probe_log)
        reset_public()
        run_script()
        assert_tree_matches(parse_expected())
    finally:
        with open(CONFIG, "w") as f:
            f.write(original_config)
        with open(LOG, "w") as f:
            f.write(original_log)
        reset_public()
        run_script()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
