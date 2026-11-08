#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import time
import pytest

TRACKER_SOURCE = "/home/user/tracker.go"
TRACKER_BINARY = "/tmp/tracker_verified"
ACTIVE_OUTPUT = "/home/user/active_servers.txt"
CONFIG_DIR = "/home/user/configs"


def output_lines(data):
    text = data.decode("utf-8", errors="strict")
    return [line.strip() for line in text.splitlines() if line.strip()]


@pytest.fixture(scope="session")
def tracker_binary():
    assert os.path.isfile(TRACKER_SOURCE), f"Expected Go program at {TRACKER_SOURCE} does not exist."
    result = subprocess.run(
        ["go", "build", "-o", TRACKER_BINARY, TRACKER_SOURCE],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, (
        "tracker.go did not compile as a Go program:\n"
        + result.stderr.decode("utf-8", errors="replace")
    )
    assert os.path.isfile(TRACKER_BINARY) and os.access(TRACKER_BINARY, os.X_OK)
    return TRACKER_BINARY


def test_tracker_go_exists():
    filepath = "/home/user/tracker.go"
    assert os.path.isfile(filepath), f"Expected Go program at {filepath} does not exist."


def test_active_servers_txt_exists():
    filepath = "/home/user/active_servers.txt"
    assert os.path.isfile(filepath), f"Expected output file {filepath} does not exist."


def test_active_servers_txt_contents():
    filepath = "/home/user/active_servers.txt"
    assert os.path.isfile(filepath), f"Expected output file {filepath} does not exist."

    with open(filepath, 'r', encoding='utf-8') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = {
        "Système de test -> https://api.test.local/v1",
        "Déploiement avancé -> https://api.prod.local/v2"
    }

    unexpected_fragments = [
        "Vieux système",
        "https://api.old.local/v1",
        "Gros fichier",
        "https://api.big.local/v1"
    ]

    actual_lines_set = set(lines)

    for expected in expected_lines:
        assert expected in actual_lines_set, f"Missing expected output line: '{expected}'"

    for line in lines:
        for frag in unexpected_fragments:
            assert frag not in line, f"Found unexpected content from filtered files: '{line}'"

    assert len(lines) == len(expected_lines), f"Expected exactly {len(expected_lines)} lines, but found {len(lines)}."


def test_tracker_executes_on_runtime_iso_8859_1_inputs(tracker_binary, tmp_path):
    token = secrets.token_hex(8)
    first = tmp_path / "legacy file one.conf"
    second = tmp_path / "legacy-two.conf"

    first_name = f"Café système {token}"
    second_name = f"Déjà déployé {token}"
    first_url = f"https://runtime.invalid/{token}/one"
    second_url = f"https://runtime.invalid/{token}/two"

    first.write_bytes((
        "[general]\n"
        "ignored=value\n"
        f"name={first_name}\n"
        f"server_url={first_url}\n"
    ).encode("iso-8859-1"))
    second.write_bytes((
        "[service]\n"
        f"name={second_name}\n"
        f"server_url={second_url}\n"
    ).encode("iso-8859-1"))

    result = subprocess.run(
        [tracker_binary, str(first), str(second)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, result.stderr.decode("utf-8", errors="replace")
    assert sorted(output_lines(result.stdout)) == sorted([
        f"{first_name} -> {first_url}",
        f"{second_name} -> {second_url}",
    ])


def test_metadata_selected_files_generate_submitted_output(tracker_binary):
    now = time.time()
    selected = []
    for entry in os.scandir(CONFIG_DIR):
        if not entry.is_file(follow_symlinks=True) or not entry.name.endswith(".conf"):
            continue
        stat = entry.stat(follow_symlinks=True)
        if stat.st_mtime > now - (5 * 24 * 60 * 60) and stat.st_size < 10 * 1024:
            selected.append(entry.path)

    assert selected, "Expected at least one recent configuration file under 10 KB."
    selected.sort()
    result = subprocess.run(
        [tracker_binary] + selected,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, result.stderr.decode("utf-8", errors="replace")

    with open(ACTIVE_OUTPUT, "r", encoding="utf-8") as f:
        submitted = [line.strip() for line in f if line.strip()]

    assert sorted(output_lines(result.stdout)) == sorted(submitted), (
        "active_servers.txt does not match tracker.go output for the files "
        "meeting the required modification-time and size filters."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
