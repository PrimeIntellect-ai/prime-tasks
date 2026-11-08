#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pathlib
import resource
import secrets
import struct
import subprocess

import pytest

BASE_DIR = "/home/user"
BACKUPS_DIR = os.path.join(BASE_DIR, "backups")
INVENTORY_CSV = os.path.join(BASE_DIR, "inventory.csv")
REPORT_JSON = os.path.join(BASE_DIR, "audit_report.json")


def get_inventory():
    inventory = {}
    if not os.path.exists(INVENTORY_CSV):
        return inventory
    with open(INVENTORY_CSV, "r", encoding="utf-8") as f:
        lines = f.read().strip().splitlines()
        for line in lines[1:]:  # skip header
            if "," in line:
                orig_name, days = line.split(",", 1)
                try:
                    inventory[orig_name.strip()] = int(days.strip())
                except ValueError:
                    pass
    return inventory


def get_expected_report():
    inventory = get_inventory()
    report = []

    if not os.path.exists(BACKUPS_DIR):
        return report

    for filename in os.listdir(BACKUPS_DIR):
        if not filename.endswith(".bkp"):
            continue
        filepath = os.path.join(BACKUPS_DIR, filename)
        with open(filepath, "rb") as f:
            magic = f.read(4)
            if magic != b"BKP1":
                continue

            ts_bytes = f.read(8)
            if len(ts_bytes) < 8:
                continue
            creation_timestamp = struct.unpack("<Q", ts_bytes)[0]

            len_bytes = f.read(2)
            if len(len_bytes) < 2:
                continue
            name_len = struct.unpack("<H", len_bytes)[0]

            orig_name_bytes = f.read(name_len)
            if len(orig_name_bytes) < name_len:
                continue
            original_filename = orig_name_bytes.decode("utf-8")

            retention_days = inventory.get(original_filename, 30)
            expiration_timestamp = creation_timestamp + (retention_days * 86400)

            report.append({
                "archive_filename": filename,
                "original_filename": original_filename,
                "creation_timestamp": creation_timestamp,
                "expiration_timestamp": expiration_timestamp,
            })

    report.sort(key=lambda x: x["archive_filename"])
    return report


def find_manifests():
    manifests = []
    for root, dirs, files in os.walk(BASE_DIR):
        dirs[:] = [d for d in dirs if d not in {"target", ".cargo", ".rustup"}]
        if "Cargo.toml" in files:
            manifests.append(os.path.join(root, "Cargo.toml"))
    return sorted(manifests)


def memory_limit():
    limit = 128 * 1024 * 1024
    resource.setrlimit(resource.RLIMIT_AS, (limit, limit))


@pytest.fixture(scope="session", autouse=True)
def build_and_execute_rust_program():
    os.makedirs(BACKUPS_DIR, exist_ok=True)

    # Add an unpredictable fixture after the agent has finished. Its large sparse
    # payload makes implementations that load or map the whole archive exceed the
    # execution limit, while header-only streaming or a small mmap window succeeds.
    token = secrets.token_hex(8)
    archive_name = f"zz_probe_{token}.bkp"
    original_name = f"probe_{token}.dat"
    creation_timestamp = 1800000000 + secrets.randbelow(10000000)
    retention_days = 31 + secrets.randbelow(300)

    inventory_needs_header = not os.path.exists(INVENTORY_CSV) or os.path.getsize(INVENTORY_CSV) == 0
    with open(INVENTORY_CSV, "a", encoding="utf-8") as f:
        if inventory_needs_header:
            f.write("original_filename,retention_days\n")
        elif os.path.getsize(INVENTORY_CSV) and not pathlib.Path(INVENTORY_CSV).read_bytes().endswith(b"\n"):
            f.write("\n")
        f.write(f"{original_name},{retention_days}\n")

    probe_path = os.path.join(BACKUPS_DIR, archive_name)
    encoded_name = original_name.encode("utf-8")
    with open(probe_path, "wb") as f:
        f.write(b"BKP1")
        f.write(struct.pack("<Q", creation_timestamp))
        f.write(struct.pack("<H", len(encoded_name)))
        f.write(encoded_name)
        f.seek(512 * 1024 * 1024 - 1)
        f.write(b"\0")

    manifests = find_manifests()
    assert manifests, "No Rust Cargo project was found under /home/user."

    executables = []
    build_errors = []
    for manifest in manifests:
        project_dir = os.path.dirname(manifest)
        rust_sources = [
            p for p in pathlib.Path(project_dir).rglob("*.rs")
            if "target" not in p.parts
        ]
        if not rust_sources:
            build_errors.append(f"{manifest}: no Rust source files")
            continue

        result = subprocess.run(
            ["cargo", "build", "--manifest-path", manifest, "--bins", "--examples", "--message-format=json"],
            cwd=project_dir,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=180,
        )
        if result.returncode != 0:
            build_errors.append(f"{manifest}: cargo build failed\n{result.stderr}")
            continue

        for line in result.stdout.splitlines():
            try:
                message = json.loads(line)
            except json.JSONDecodeError:
                continue
            executable = message.get("executable")
            kinds = message.get("target", {}).get("kind", [])
            if executable and any(kind in {"bin", "example"} for kind in kinds):
                executables.append((executable, project_dir))

    assert executables, "No executable Rust target could be built.\n" + "\n".join(build_errors)

    expected = get_expected_report()
    run_errors = []
    generated_correct_report = False
    for executable, project_dir in executables:
        if os.path.exists(REPORT_JSON):
            os.remove(REPORT_JSON)
        try:
            result = subprocess.run(
                [executable],
                cwd=project_dir,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=30,
                preexec_fn=memory_limit,
            )
        except (subprocess.TimeoutExpired, OSError) as exc:
            run_errors.append(f"{executable}: {exc}")
            continue

        if result.returncode != 0:
            run_errors.append(f"{executable}: exited {result.returncode}\n{result.stderr}")
            continue
        if not os.path.isfile(REPORT_JSON):
            run_errors.append(f"{executable}: did not generate {REPORT_JSON}")
            continue
        try:
            with open(REPORT_JSON, "r", encoding="utf-8") as f:
                candidate = json.load(f)
        except (OSError, json.JSONDecodeError) as exc:
            run_errors.append(f"{executable}: generated an invalid report: {exc}")
            continue
        if candidate == expected:
            generated_correct_report = True
            break
        run_errors.append(f"{executable}: generated a report with incorrect content")

    assert generated_correct_report, (
        "No built Rust executable generated the correct report under the header-only memory limit.\n"
        + "\n".join(run_errors)
    )


def test_audit_report_exists():
    assert os.path.isfile(REPORT_JSON), f"File {REPORT_JSON} does not exist. The Rust program must generate this file."


def test_audit_report_content():
    assert os.path.isfile(REPORT_JSON), f"File {REPORT_JSON} does not exist."

    with open(REPORT_JSON, "r", encoding="utf-8") as f:
        try:
            actual_report = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse {REPORT_JSON} as JSON: {e}")

    assert isinstance(actual_report, list), f"Expected the JSON root to be an array, got {type(actual_report).__name__}"

    expected_report = get_expected_report()

    assert len(actual_report) == len(expected_report), f"Expected {len(expected_report)} items in the report, got {len(actual_report)}"

    # Check sorting
    actual_filenames = [item.get("archive_filename") for item in actual_report]
    expected_filenames = [item["archive_filename"] for item in expected_report]
    assert actual_filenames == expected_filenames, "The JSON array must be sorted by 'archive_filename' alphabetically."

    for actual, expected in zip(actual_report, expected_report):
        assert actual == expected, f"Mismatch in report item.\nExpected: {expected}\nGot: {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
