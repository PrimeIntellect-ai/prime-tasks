#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import subprocess
from pathlib import Path

import pytest

MANIFEST_PATH = "/home/user/backup_manifest.jsonl"
REPO_PATH = Path("/home/user/artifact_repo")


def test_manifest_exists():
    assert os.path.exists(MANIFEST_PATH), f"The output file {MANIFEST_PATH} does not exist."
    assert os.path.isfile(MANIFEST_PATH), f"The path {MANIFEST_PATH} is not a file."


def test_manifest_is_utf8():
    try:
        with open(MANIFEST_PATH, "rb") as f:
            content = f.read()
        content.decode("utf-8")
    except UnicodeDecodeError as e:
        pytest.fail(f"The file {MANIFEST_PATH} is not strictly UTF-8 encoded: {e}")


def test_manifest_content_and_format():
    expected_records = [
        {
            "filepath": "/home/user/artifact_repo/legacy_gamma/metadata.csv",
            "artifact_id": "gamma-legacy",
            "version": "0.9.9",
            "checksum": "sha1:111222333444",
        },
        {
            "filepath": "/home/user/artifact_repo/project_alpha/v1/metadata.json",
            "artifact_id": "alpha-core",
            "version": "1.0.4",
            "checksum": "sha256:abc123def456",
        },
        {
            "filepath": "/home/user/artifact_repo/project_beta/v2/metadata.xml",
            "artifact_id": "beta-utils-déjà",
            "version": "2.1.0",
            "checksum": "md5:9876543210",
        },
    ]

    records = []
    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()
        for i, line in enumerate(lines):
            if not line.strip():
                continue
            try:
                record = json.loads(line)
                records.append(record)
            except json.JSONDecodeError as e:
                pytest.fail(f"Line {i+1} in {MANIFEST_PATH} is not valid JSON: {e}")

    assert len(records) == len(expected_records), (
        f"Expected {len(expected_records)} records in the manifest, but found {len(records)}."
    )

    for i, record in enumerate(records):
        for key in ["filepath", "artifact_id", "version", "checksum"]:
            assert key in record, f"Record {i+1} is missing required key: '{key}'"

    filepaths = [r["filepath"] for r in records]
    assert filepaths == sorted(filepaths), (
        "The output lines are not sorted alphabetically by the 'filepath' key."
    )

    for expected in expected_records:
        assert expected in records, f"Expected record {expected} not found in the manifest."


def _find_candidate_scripts():
    candidates = []
    excluded = {Path("/tmp/test_final_state.py").resolve()}
    for root in (Path("/home/user"), Path("/root"), Path("/tmp")):
        if not root.exists():
            continue
        for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
            dirnames[:] = [
                d for d in dirnames
                if d not in {"__pycache__", ".cache", ".local", "site-packages", ".git"}
            ]
            for filename in filenames:
                path = Path(dirpath) / filename
                try:
                    if path.resolve() in excluded or path.is_symlink() or not path.is_file():
                        continue
                    if path.stat().st_size > 1024 * 1024:
                        continue
                    data = path.read_bytes()
                    text = data.decode("utf-8")
                except (OSError, UnicodeError):
                    continue
                looks_python = filename.endswith(".py") or text.startswith("#!") and "python" in text.splitlines()[0]
                references_task = "artifact_repo" in text and "backup_manifest" in text
                if looks_python and references_task:
                    candidates.append(path)
    return sorted(set(candidates), key=lambda p: str(p))


def _read_manifest():
    raw = Path(MANIFEST_PATH).read_bytes()
    text = raw.decode("utf-8")
    records = []
    for line_number, line in enumerate(text.splitlines(), 1):
        if not line.strip():
            raise AssertionError(f"Blank line {line_number} is not a JSON object")
        record = json.loads(line)
        assert isinstance(record, dict)
        assert set(record) == {"filepath", "artifact_id", "version", "checksum"}
        records.append(record)
    return records


def test_script_retraverses_and_parses_changed_repository_without_following_loops():
    candidates = _find_candidate_scripts()
    assert candidates, "No Python traversal/parsing script was found."

    token = secrets.token_hex(12)
    alpha = {
        "artifact_id": f"alpha-动态-{token}",
        "version": f"10.{token[:4]}",
        "checksum": f"sha256:{token}a",
    }
    beta = {
        "artifact_id": f"beta-café-{token}",
        "version": f"20.{token[4:8]}",
        "checksum": f"md5:{token}b",
    }
    gamma = {
        "artifact_id": f"gamma-{token}",
        "version": f"30.{token[8:12]}",
        "checksum": f"sha1:{token}c",
    }
    extra = {
        "artifact_id": f"new-nested-{token}",
        "version": f"40.{token[12:16]}",
        "checksum": f"sha512:{token}d",
    }

    alpha_path = REPO_PATH / "project_alpha/v1/metadata.json"
    beta_path = REPO_PATH / "project_beta/v2/metadata.xml"
    gamma_path = REPO_PATH / "legacy_gamma/metadata.csv"
    extra_path = REPO_PATH / f"generated_{token}/deep/tree/metadata.json"
    extra_path.parent.mkdir(parents=True, exist_ok=True)

    alpha_path.write_text(json.dumps(alpha, ensure_ascii=False), encoding="utf-8")
    beta_xml = (
        '<?xml version="1.0" encoding="ISO-8859-1"?>\n'
        "<metadata>"
        f"<artifact_id>{beta['artifact_id']}</artifact_id>"
        f"<version>{beta['version']}</version>"
        f"<checksum>{beta['checksum']}</checksum>"
        "</metadata>"
    )
    beta_path.write_bytes(beta_xml.encode("iso-8859-1"))
    gamma_text = "artifact_id,version,checksum\n" + ",".join(
        [gamma["artifact_id"], gamma["version"], gamma["checksum"]]
    ) + "\n"
    gamma_path.write_bytes(gamma_text.encode("utf-16"))
    extra_path.write_text(json.dumps(extra, ensure_ascii=False), encoding="utf-8")

    loop_target = extra_path.parent
    loop_link = loop_target / "back_to_repo"
    if not loop_link.exists() and not loop_link.is_symlink():
        loop_link.symlink_to(REPO_PATH, target_is_directory=True)

    expected = [
        {"filepath": str(gamma_path), **gamma},
        {"filepath": str(alpha_path), **alpha},
        {"filepath": str(beta_path), **beta},
        {"filepath": str(extra_path), **extra},
    ]
    expected.sort(key=lambda record: record["filepath"])

    failures = []
    for script in candidates:
        try:
            Path(MANIFEST_PATH).unlink(missing_ok=True)
            result = subprocess.run(
                ["python3", str(script)],
                cwd=str(script.parent),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
            if result.returncode != 0:
                failures.append(f"{script}: exited {result.returncode}: {result.stderr[-300:]}")
                continue
            if not Path(MANIFEST_PATH).is_file():
                failures.append(f"{script}: did not create the manifest")
                continue
            records = _read_manifest()
            assert [r["filepath"] for r in records] == sorted(r["filepath"] for r in records)
            if records == expected:
                return
            failures.append(f"{script}: generated records did not match the live repository")
        except subprocess.TimeoutExpired:
            failures.append(f"{script}: timed out, possibly by following a symlink loop")
        except Exception as exc:
            failures.append(f"{script}: {type(exc).__name__}: {exc}")

    pytest.fail("No discovered script correctly regenerated the manifest. " + " | ".join(failures))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
