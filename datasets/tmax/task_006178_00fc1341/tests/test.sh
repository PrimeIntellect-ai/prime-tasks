#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import io
import os
import re
import shutil
import stat
import subprocess
import tarfile
import uuid

PROCESSED_CONFIGS_DIR = "/home/user/processed_configs"
CONFIG_BACKUPS_DIR = "/home/user/config_backups"
SCRIPT_PATH = "/home/user/process_configs.sh"

EXPECTED_FILES = {
    "production_database_config_a.txt.conf": "# ENV: production\n# SERVICE: database\nparam=1\n",
    "staging_web_server_config_b.txt.conf": "# ENV: staging\n# SERVICE: web server\nparam=2\n",
    "qa_auth_config_c.txt.conf": "Random data\n# ENV: qa\n# SERVICE: auth\nparam=3\n"
}


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."


def test_processed_files_exist_and_content_correct():
    assert os.path.isdir(PROCESSED_CONFIGS_DIR), f"Directory {PROCESSED_CONFIGS_DIR} does not exist."

    for filename, expected_content in EXPECTED_FILES.items():
        filepath = os.path.join(PROCESSED_CONFIGS_DIR, filename)
        assert os.path.isfile(filepath), f"Expected processed file {filename} is missing."

        with open(filepath, 'r') as f:
            content = f.read()

        assert content.strip() == expected_content.strip(), f"Content of {filename} does not match expected."


def test_no_extra_files_processed():
    files_in_dir = set(f for f in os.listdir(PROCESSED_CONFIGS_DIR) if os.path.isfile(os.path.join(PROCESSED_CONFIGS_DIR, f)))
    expected_filenames = set(EXPECTED_FILES.keys())
    expected_filenames.add("manifest.sha256")

    extra_files = files_in_dir - expected_filenames
    assert not extra_files, f"Found unexpected files in processed configs directory: {extra_files}"


def test_manifest_correctness():
    manifest_path = os.path.join(PROCESSED_CONFIGS_DIR, "manifest.sha256")
    assert os.path.isfile(manifest_path), f"Manifest file {manifest_path} is missing."

    with open(manifest_path, 'r') as f:
        manifest_lines = f.read().strip().splitlines()

    assert len(manifest_lines) == len(EXPECTED_FILES), f"Manifest should contain exactly {len(EXPECTED_FILES)} entries, found {len(manifest_lines)}."

    manifest_dict = {}
    for line in manifest_lines:
        parts = line.strip().split(None, 1)
        assert len(parts) == 2, f"Invalid manifest line format: {line}"
        hash_val, filename = parts
        assert os.path.basename(filename) == filename, f"Manifest should only contain basenames, found path: {filename}"
        filename = filename.lstrip('*')
        manifest_dict[filename] = hash_val

    for filename, expected_content in EXPECTED_FILES.items():
        assert filename in manifest_dict, f"File {filename} is missing from manifest."

        filepath = os.path.join(PROCESSED_CONFIGS_DIR, filename)
        with open(filepath, 'rb') as f:
            actual_hash = hashlib.sha256(f.read()).hexdigest()

        assert manifest_dict[filename] == actual_hash, f"Manifest hash for {filename} is incorrect. Expected {actual_hash}, got {manifest_dict[filename]}."


def _clear_directory(path):
    os.makedirs(path, exist_ok=True)
    for name in os.listdir(path):
        item = os.path.join(path, name)
        if os.path.islink(item) or not os.path.isdir(item):
            os.unlink(item)
        else:
            shutil.rmtree(item)


def _make_archive(path, members):
    with tarfile.open(path, "w:gz") as archive:
        for member_name, content in members.items():
            data = content.encode("utf-8")
            info = tarfile.TarInfo(member_name)
            info.size = len(data)
            info.mode = 0o644
            archive.addfile(info, io.BytesIO(data))


def test_script_processes_mutated_inputs_without_following_symlinks():
    token = uuid.uuid4().hex[:12]
    _clear_directory(CONFIG_BACKUPS_DIR)
    _clear_directory(PROCESSED_CONFIGS_DIR)
    os.chmod(CONFIG_BACKUPS_DIR, 0o777)
    os.chmod(PROCESSED_CONFIGS_DIR, 0o777)

    first_name = f"data_{token}.txt"
    second_name = f"other_{token}.txt"
    skipped_name = f"late_{token}.txt"
    missing_name = f"missing_{token}.txt"

    first_content = f"# ENV: prod {token}\n# SERVICE: api cluster\nvalue={token}\n"
    second_content = f"comment\n# ENV: qa {token}\n\n# SERVICE: auth service\nvalue=second\n"
    skipped_content = "one\ntwo\nthree\nfour\nfive\n# ENV: too late\n# SERVICE: ignored\n"
    missing_content = "# ENV: dev\nno service metadata here\n"

    _make_archive(
        os.path.join(CONFIG_BACKUPS_DIR, f"valid_a_{token}.tar.gz"),
        {first_name: first_content, skipped_name: skipped_content},
    )
    _make_archive(
        os.path.join(CONFIG_BACKUPS_DIR, f"valid_b_{token}.tar.gz"),
        {second_name: second_content, missing_name: missing_content},
    )

    # This archive has a complete tar payload but a truncated gzip trailer.
    # Listing and extraction return failure, while an unchecked extraction can
    # still materialize the member, so its output must never be processed.
    corrupt_complete = os.path.join(CONFIG_BACKUPS_DIR, f"corrupt_source_{token}")
    rogue_name = f"rogue_{token}.txt"
    _make_archive(
        corrupt_complete,
        {rogue_name: "# ENV: corrupt\n# SERVICE: must skip\nvalue=bad\n"},
    )
    with open(corrupt_complete, "rb") as f:
        corrupt_data = f.read()
    os.unlink(corrupt_complete)
    with open(os.path.join(CONFIG_BACKUPS_DIR, f"00_corrupt_{token}.tar.gz"), "wb") as f:
        f.write(corrupt_data[:-8])
    with open(os.path.join(CONFIG_BACKUPS_DIR, f"plain_corrupt_{token}.tar.gz"), "wb") as f:
        f.write(b"not a gzip or tar archive\n")

    # Both a directly linked archive and an archive below a linked directory
    # contain otherwise valid metadata. Neither may be followed.
    external_dir = os.path.join("/tmp", f"config_verifier_external_{token}")
    os.makedirs(external_dir, mode=0o755)
    outside_archive = os.path.join(external_dir, f"outside_{token}.tar.gz")
    forbidden_name = f"forbidden_{token}.txt"
    forbidden_content = "# ENV: linked\n# SERVICE: forbidden\nvalue=bad\n"
    _make_archive(outside_archive, {forbidden_name: forbidden_content})
    os.chmod(outside_archive, 0o644)
    os.symlink(outside_archive, os.path.join(CONFIG_BACKUPS_DIR, f"linked_{token}.tar.gz"))
    os.symlink(external_dir, os.path.join(CONFIG_BACKUPS_DIR, f"linked_tree_{token}"))
    os.symlink("loop_b", os.path.join(CONFIG_BACKUPS_DIR, "loop_a"))
    os.symlink("loop_a", os.path.join(CONFIG_BACKUPS_DIR, "loop_b"))
    os.symlink(".", os.path.join(CONFIG_BACKUPS_DIR, "self_loop"))

    try:
        result = subprocess.run(
            ["runuser", "-u", "user", "--", SCRIPT_PATH],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"Script failed on mutated inputs with exit code {result.returncode}. "
            f"stdout={result.stdout!r} stderr={result.stderr!r}"
        )

        expected = {
            f"prod_{token}_api_cluster_{first_name}.conf": first_content,
            f"qa_{token}_auth_service_{second_name}.conf": second_content,
        }
        actual_regular = {
            name for name in os.listdir(PROCESSED_CONFIGS_DIR)
            if os.path.isfile(os.path.join(PROCESSED_CONFIGS_DIR, name))
        }
        assert actual_regular == set(expected) | {"manifest.sha256"}, (
            f"Unexpected processed output set: {actual_regular}"
        )

        for name, content in expected.items():
            with open(os.path.join(PROCESSED_CONFIGS_DIR, name), "r") as f:
                assert f.read() == content, f"Incorrect extracted content for {name}"

        manifest_path = os.path.join(PROCESSED_CONFIGS_DIR, "manifest.sha256")
        with open(manifest_path, "r") as f:
            lines = f.read().splitlines()
        assert len(lines) == len(expected), "Manifest must contain exactly the dynamically processed files"

        entries = {}
        for line in lines:
            match = re.fullmatch(r"([0-9a-fA-F]{64}) ([ *])(.+)", line)
            assert match, f"Non-standard SHA256 manifest line: {line!r}"
            digest, _, filename = match.groups()
            assert os.path.basename(filename) == filename, f"Manifest contains a path: {filename}"
            assert filename not in entries, f"Duplicate manifest entry: {filename}"
            entries[filename] = digest.lower()

        assert set(entries) == set(expected), f"Incorrect manifest filenames: {set(entries)}"
        for filename in expected:
            with open(os.path.join(PROCESSED_CONFIGS_DIR, filename), "rb") as f:
                digest = hashlib.sha256(f.read()).hexdigest()
            assert entries[filename] == digest, f"Incorrect manifest checksum for {filename}"
    finally:
        shutil.rmtree(external_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
