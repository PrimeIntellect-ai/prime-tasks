#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import stat
import subprocess

SCRIPT_PATH = "/home/user/export_backup_metadata.py"
GRAPH_PATH = "/home/user/infrastructure.ttl"
MANIFEST_PATH = "/home/user/backup_manifest.json"


def run_export():
    subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        check=True,
        timeout=30,
    )


def test_export_script_exists_and_runs():
    assert os.path.exists(SCRIPT_PATH), f"File {SCRIPT_PATH} is missing."
    mode = os.stat(SCRIPT_PATH, follow_symlinks=False).st_mode
    assert stat.S_ISREG(mode), f"File {SCRIPT_PATH} must be a regular Python script."

    if os.path.lexists(MANIFEST_PATH):
        os.remove(MANIFEST_PATH)
    run_export()
    assert os.path.isfile(MANIFEST_PATH), "The script did not materialize backup_manifest.json."


def test_backup_manifest_exists():
    file_path = MANIFEST_PATH
    assert os.path.isfile(file_path), f"File {file_path} is missing. Did you run the script?"


def test_backup_manifest_content():
    file_path = MANIFEST_PATH
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    with open(file_path, "r") as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {file_path} does not contain valid JSON."

    expected_manifest = [
        {
            "database": "logs_db",
            "policy": "weekly_full"
        },
        {
            "database": "payments_db",
            "policy": "daily_incremental"
        },
        {
            "database": "users_db",
            "policy": "hourly_snapshot"
        }
    ]

    assert isinstance(manifest, list), f"Expected the JSON in {file_path} to be a list of objects."
    assert len(manifest) == len(expected_manifest), f"Expected exactly {len(expected_manifest)} entries in the manifest, found {len(manifest)}."

    # The task specifies it must be sorted alphabetically by database name
    assert manifest == expected_manifest, f"The content of {file_path} does not match the expected output. Make sure the SPARQL query is fixed to avoid cross joins and the output is sorted."


def test_script_traverses_database_host_policy_relationships():
    token = secrets.token_hex(8)
    relationships = [
        (f"zeta_{token}_db", f"nightly_{token}"),
        (f"alpha_{token}_db", f"hourly_{token}"),
        (f"middle_{token}_db", f"weekly_{token}"),
    ]
    expected = [
        {"database": database, "policy": policy}
        for database, policy in sorted(relationships, key=lambda pair: pair[0])
    ]

    ttl_lines = ["@prefix ex: <http://example.org/> .", ""]
    for index, (database, policy) in enumerate(relationships):
        ttl_lines.extend([
            f'ex:DynamicDB{index}_{token} a ex:Database ;',
            f'    ex:name "{database}" ;',
            f'    ex:hostedOn ex:DynamicHost{index}_{token} .',
            "",
            f'ex:DynamicHost{index}_{token} a ex:Host ;',
            f'    ex:hasPolicy ex:DynamicPolicy{index}_{token} .',
            "",
            f'ex:DynamicPolicy{index}_{token} a ex:BackupPolicy ;',
            f'    ex:name "{policy}" .',
            "",
        ])

    # Decoys expose a disconnected graph pattern: neither should produce a row.
    ttl_lines.extend([
        f'ex:NoPolicyDB_{token} a ex:Database ;',
        f'    ex:name "decoy_database_{token}" ;',
        f'    ex:hostedOn ex:NoPolicyHost_{token} .',
        "",
        f'ex:UnusedHost_{token} a ex:Host ;',
        f'    ex:hasPolicy ex:UnusedPolicy_{token} .',
        "",
        f'ex:UnusedPolicy_{token} a ex:BackupPolicy ;',
        f'    ex:name "decoy_policy_{token}" .',
        "",
    ])

    with open(GRAPH_PATH, "rb") as f:
        original_graph = f.read()
    with open(MANIFEST_PATH, "rb") as f:
        original_manifest = f.read()

    try:
        with open(GRAPH_PATH, "w") as f:
            f.write("\n".join(ttl_lines))
        os.remove(MANIFEST_PATH)

        run_export()
        assert os.path.isfile(MANIFEST_PATH), "The script did not materialize the dynamic manifest."
        with open(MANIFEST_PATH, "r") as f:
            manifest = json.load(f)

        assert isinstance(manifest, list), "The generated manifest must be a JSON list."
        assert all(isinstance(item, dict) and set(item) == {"database", "policy"} for item in manifest), \
            "Every manifest entry must be an object with exactly database and policy keys."
        assert manifest == expected, \
            "The script must follow each database's hostedOn host to that host's hasPolicy policy and sort by database."
    finally:
        with open(GRAPH_PATH, "wb") as f:
            f.write(original_graph)
        with open(MANIFEST_PATH, "wb") as f:
            f.write(original_manifest)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
