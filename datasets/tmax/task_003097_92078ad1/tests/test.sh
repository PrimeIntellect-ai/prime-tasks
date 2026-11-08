#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess

import pytest

TRACKER = "/home/user/tracker"


def rle(content):
    if not content:
        return ""
    parts = []
    current = content[0]
    count = 1
    for char in content[1:]:
        if char == current:
            count += 1
        else:
            parts.append(f"{count}{current}")
            current = char
            count = 1
    parts.append(f"{count}{current}")
    return "".join(parts)


def run_tracker(base, target):
    result = subprocess.run(
        [TRACKER, str(base), str(target)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=False,
    )
    assert result.returncode == 0, (
        f"tracker exited with {result.returncode}: "
        f"{result.stderr.decode('utf-8', errors='replace')}"
    )
    return result.stdout.decode("ascii")


def parse_nonempty_records(output):
    lines = output.splitlines()
    assert len(lines) % 2 == 0, f"Output does not contain header/content pairs: {output!r}"
    records = {}
    for index in range(0, len(lines), 2):
        header = lines[index]
        assert header.startswith("FILE: "), f"Invalid file header: {header!r}"
        path = header[len("FILE: "):]
        assert path and path not in records, f"Missing or duplicate path: {path!r}"
        records[path] = lines[index + 1]
    return records


def random_content():
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz!@#$%^&*"
    chars = []
    previous = None
    for _ in range(secrets.randbelow(5) + 4):
        choices = alphabet.replace(previous, "") if previous else alphabet
        char = secrets.choice(choices)
        chars.append(char * (secrets.randbelow(14) + 1))
        previous = char
    return "".join(chars)


def test_tracker_source_exists():
    assert os.path.isfile("/home/user/tracker.rs"), "/home/user/tracker.rs does not exist."


def test_tracker_executable_exists():
    assert os.path.isfile(TRACKER), "/home/user/tracker executable does not exist."
    assert os.access(TRACKER, os.X_OK), "/home/user/tracker is not executable."
    with open(TRACKER, "rb") as executable:
        assert executable.read(4) == b"\x7fELF", "/home/user/tracker is not a compiled executable."


def test_config_diff_out_exists():
    assert os.path.isfile("/home/user/config_diff.out"), "/home/user/config_diff.out does not exist."


def test_config_diff_out_contents():
    with open("/home/user/config_diff.out", "r") as f:
        content = f.read().strip()

    lines = [line.strip() for line in content.splitlines() if line.strip()]

    # Check that db.conf and cache.conf are not in the output
    assert "FILE: db.conf" not in lines, "db.conf should not be in the output as it is unchanged."
    assert "FILE: nested/cache.conf" not in lines, "nested/cache.conf should not be in the output as it is unchanged."
    assert "FILE: cache.conf" not in lines, "cache.conf should not be in the output as it is unchanged."

    # Verify app.conf
    assert "FILE: app.conf" in lines, "app.conf is missing from the output."
    app_idx = lines.index("FILE: app.conf")
    assert app_idx + 1 < len(lines), "Missing RLE content for app.conf."
    assert lines[app_idx + 1] == "5A5C", f"Incorrect RLE content for app.conf. Expected '5A5C', got '{lines[app_idx + 1]}'"

    # Verify new.conf
    assert "FILE: new.conf" in lines, "new.conf is missing from the output."
    new_idx = lines.index("FILE: new.conf")
    assert new_idx + 1 < len(lines), "Missing RLE content for new.conf."
    assert lines[new_idx + 1] == "3X3Y", f"Incorrect RLE content for new.conf. Expected '3X3Y', got '{lines[new_idx + 1]}'"

    # Ensure no extra files are reported
    file_lines = [line for line in lines if line.startswith("FILE:")]
    assert len(file_lines) == 2, f"Expected exactly 2 files in output, but found {len(file_lines)}: {file_lines}"


def test_tracker_on_randomized_directory_tree(tmp_path):
    base = tmp_path / "base"
    target = tmp_path / "target"
    base.mkdir()
    target.mkdir()

    token = secrets.token_hex(6)
    nested = f"nested_{token}"
    deep = f"deep_{secrets.token_hex(4)}"
    (base / nested / deep).mkdir(parents=True)
    (target / nested / deep).mkdir(parents=True)

    unchanged_name = f"unchanged_{secrets.token_hex(4)}.cfg"
    unchanged = random_content()
    (base / unchanged_name).write_text(unchanged, encoding="ascii")
    (target / unchanged_name).write_text(unchanged, encoding="ascii")

    modified_name = f"modified_{secrets.token_hex(4)}.cfg"
    old_content = random_content()
    new_content = random_content()
    while new_content == old_content:
        new_content = random_content()
    (base / modified_name).write_text(old_content, encoding="ascii")
    (target / modified_name).write_text(new_content, encoding="ascii")

    nested_modified_name = f"changed_{secrets.token_hex(4)}.txt"
    nested_old = random_content()
    nested_new = random_content()
    while nested_new == nested_old:
        nested_new = random_content()
    (base / nested / deep / nested_modified_name).write_text(nested_old, encoding="ascii")
    (target / nested / deep / nested_modified_name).write_text(nested_new, encoding="ascii")

    new_name = f"new_{secrets.token_hex(4)}.conf"
    new_file_content = random_content()
    (target / nested / new_name).write_text(new_file_content, encoding="ascii")

    base_only_name = f"removed_{secrets.token_hex(4)}.cfg"
    (base / base_only_name).write_text(random_content(), encoding="ascii")

    expected = {
        modified_name: rle(new_content),
        f"{nested}/{deep}/{nested_modified_name}": rle(nested_new),
        f"{nested}/{new_name}": rle(new_file_content),
    }
    assert parse_nonempty_records(run_tracker(base, target)) == expected


def test_tracker_encodes_empty_new_file(tmp_path):
    base = tmp_path / "empty_base"
    target = tmp_path / "empty_target"
    base.mkdir()
    target.mkdir()
    name = f"empty_{secrets.token_hex(6)}.txt"
    (target / name).write_bytes(b"")
    assert run_tracker(base, target) == f"FILE: {name}\n\n"


def test_tracker_runtime_on_provided_directories():
    output = run_tracker("/home/user/etc_backup", "/home/user/etc_mock")
    assert parse_nonempty_records(output) == {
        "app.conf": "5A5C",
        "new.conf": "3X3Y",
    }


def test_tracker_requires_exactly_two_arguments(tmp_path):
    cases = [
        [TRACKER],
        [TRACKER, str(tmp_path)],
        [TRACKER, str(tmp_path), str(tmp_path), "extra"],
    ]
    for command in cases:
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
        assert result.returncode != 0, f"Invalid invocation unexpectedly succeeded: {command!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
