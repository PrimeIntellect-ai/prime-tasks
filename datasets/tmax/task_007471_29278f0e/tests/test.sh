#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import subprocess
import tarfile


def expected_original_data():
    return [
        {
            "version": 101,
            "author": "Alice Admin",
            "changes": " - Updated firewall rules\n - Opened port 443\n - Closed port 80"
        },
        {
            "version": 102,
            "author": "Bob Backup",
            "changes": " - Configured symlink traversal\n - Added infinite loop detection"
        }
    ]


def test_symlink_deleted():
    loop_link = "/home/user/configs/dirA/dirB/loop_link"
    assert not os.path.exists(loop_link) and not os.path.islink(loop_link), \
        f"Symlink loop {loop_link} should have been deleted."


def test_archive_was_fully_extracted():
    archive = "/home/user/config_archive.tar.gz"
    destination = "/home/user/configs"

    with tarfile.open(archive, "r:gz") as tf:
        for member in tf.getmembers():
            target = os.path.join(destination, member.name)
            if member.issym() or member.islnk():
                # The archive's looping symlink is intentionally required to be absent.
                continue
            if member.isdir():
                assert os.path.isdir(target) and not os.path.islink(target), \
                    f"Archive directory {member.name} was not correctly extracted."
            elif member.isfile():
                assert os.path.isfile(target) and not os.path.islink(target), \
                    f"Archive file {member.name} was not correctly extracted."
                archived = tf.extractfile(member)
                assert archived is not None
                with open(target, "rb") as extracted:
                    assert extracted.read() == archived.read(), \
                        f"Extracted file {member.name} differs from the archive."


def test_parsed_logs_json():
    json_path = "/home/user/parsed_logs.json"
    assert os.path.isfile(json_path), f"File {json_path} does not exist."

    with open(json_path, 'r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{json_path} is not valid JSON."

    expected_data = expected_original_data()
    assert data == expected_data, "Parsed JSON data does not match the expected output."


def test_hard_link():
    json_path = "/home/user/parsed_logs.json"
    backup_path = "/home/user/logs_backup.json"

    assert os.path.isfile(backup_path), f"File {backup_path} does not exist."

    stat_json = os.stat(json_path)
    stat_backup = os.stat(backup_path)

    assert stat_json.st_ino == stat_backup.st_ino, \
        f"{backup_path} is not a hard link to {json_path}."


def test_go_parser_exists():
    parser_path = "/home/user/parser.go"
    assert os.path.isfile(parser_path), f"Go program {parser_path} does not exist."


def test_go_parser_executes_and_parses_fresh_utf16le_input():
    parser = "/home/user/parser.go"
    changelog = "/home/user/configs/changelog.txt"
    output = "/home/user/parsed_logs.json"
    backup = "/home/user/logs_backup.json"

    token = secrets.token_hex(10)
    records = [
        {
            "version": secrets.randbelow(800000) + 100000,
            "author": f"Renée Dynamic {token}",
            "lines": [f" first generated change {token}", " second change with café", " final generated line"]
        },
        {
            "version": secrets.randbelow(800000) + 100000,
            "author": f"Parser Test {token[::-1]}",
            "lines": [" αβγ unicode payload", f" randomized value {secrets.token_hex(8)}"]
        }
    ]

    text_parts = []
    expected = []
    for record in records:
        text_parts.extend([
            "--- RECORD START ---",
            f"Version: {record['version']}",
            f"Author: {record['author']}",
            "Changes:",
            *record["lines"],
            "--- RECORD END ---"
        ])
        expected.append({
            "version": record["version"],
            "author": record["author"],
            "changes": "\n".join(record["lines"])
        })
    generated_input = ("\n".join(text_parts) + "\n").encode("utf-16le")

    with open(changelog, "rb") as f:
        original_changelog = f.read()
    with open(output, "rb") as f:
        original_output = f.read()

    try:
        with open(changelog, "wb") as f:
            f.write(generated_input)

        # Remove prior products so the submitted program must create its output.
        if os.path.lexists(backup):
            os.unlink(backup)
        if os.path.lexists(output):
            os.unlink(output)

        result = subprocess.run(
            ["go", "run", parser],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30
        )
        assert result.returncode == 0, \
            f"Go parser failed to execute: {result.stderr}"
        assert os.path.isfile(output), "Go parser did not create parsed_logs.json."
        with open(output, "r", encoding="utf-8") as f:
            actual = json.load(f)
        assert actual == expected, \
            "Go parser did not correctly parse freshly generated UTF-16LE records."
    finally:
        with open(changelog, "wb") as f:
            f.write(original_changelog)
        if os.path.lexists(backup):
            os.unlink(backup)
        if os.path.lexists(output):
            os.unlink(output)
        with open(output, "wb") as f:
            f.write(original_output)
        os.link(output, backup)

    with open(output, "r", encoding="utf-8") as f:
        assert json.load(f) == expected_original_data()
    assert os.stat(output).st_ino == os.stat(backup).st_ino
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
