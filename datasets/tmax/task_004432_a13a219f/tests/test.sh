#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import shutil
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path

import pytest
from packaging.version import Version

SCRIPT_PATH = Path("/home/user/evaluate_deployments.py")
REPORT_PATH = Path("/home/user/deployment_report.json")
STATE_PATH = Path("/home/user/system_state.txt")
MANIFEST_DIR = Path("/home/user/manifests")


def run_script():
    result = subprocess.run(
        [sys.executable, str(SCRIPT_PATH)],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"The script exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def load_report():
    assert REPORT_PATH.is_file(), f"The output file {REPORT_PATH} was not found."
    try:
        with REPORT_PATH.open("r") as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"The file {REPORT_PATH} does not contain valid JSON: {exc}")


def test_script_exists():
    assert SCRIPT_PATH.is_file(), f"The script {SCRIPT_PATH} was not found."


def test_deployment_report_exists():
    assert REPORT_PATH.is_file(), f"The output file {REPORT_PATH} was not found."


def test_script_executes_on_original_inputs():
    run_script()


def test_deployment_report_content():
    results = load_report()
    expected = {
        "core-update-v2": True,
        "ui-hotfix": True,
        "legacy-db-rollback": False,
        "complex-gateway": True,
    }

    assert isinstance(results, dict), (
        f"Expected a JSON object (dictionary), got {type(results).__name__}"
    )

    for key, expected_val in expected.items():
        assert key in results, f"Manifest ID '{key}' is missing from the report."
        assert results[key] == expected_val, (
            f"Expected manifest '{key}' to evaluate to {expected_val}, "
            f"but got {results[key]}."
        )

    extra_keys = set(results.keys()) - set(expected.keys())
    assert not extra_keys, f"Found unexpected manifest IDs in the report: {extra_keys}"


def test_parser_and_evaluator_on_fresh_inputs():
    rng = random.SystemRandom()
    token = uuid.uuid4().hex[:10]
    a = f"alpha-{token}"
    b = f"beta-{token}"
    c = f"gamma-{token}"
    missing = f"missing-{token}"

    a_parts = (rng.randint(2, 8), rng.randint(1, 8), rng.randint(2, 8))
    b_parts = (rng.randint(2, 8), rng.randint(1, 8), rng.randint(2, 8))
    c_parts = (rng.randint(2, 8), rng.randint(1, 8), rng.randint(2, 8))

    va = ".".join(map(str, a_parts))
    vb = ".".join(map(str, b_parts))
    vc = ".".join(map(str, c_parts))
    a_lower = f"{a_parts[0]}.{a_parts[1]}.{a_parts[2] - 1}"
    a_upper = f"{a_parts[0]}.{a_parts[1]}.{a_parts[2] + 1}"
    b_lower = f"{b_parts[0]}.{b_parts[1]}.{b_parts[2] - 1}"
    b_upper = f"{b_parts[0]}.{b_parts[1]}.{b_parts[2] + 1}"

    cases = [
        (f"eq-{token}", f"{a} == {va}", Version(va) == Version(va)),
        (
            f"range-{token}",
            f"({a} > {a_lower} & {a} < {a_upper})",
            Version(va) > Version(a_lower) and Version(va) < Version(a_upper),
        ),
        (
            f"bounds-{token}",
            f"({b} >= {vb} & {b} <= {vb})",
            Version(vb) >= Version(vb) and Version(vb) <= Version(vb),
        ),
        (
            f"or-false-{token}",
            f"({a} < {a_lower} | {b} > {b_upper})",
            Version(va) < Version(a_lower) or Version(vb) > Version(b_upper),
        ),
        (
            f"missing-not-{token}",
            f"!({missing} == 1.0.0) & ({c} == {vc})",
            (not False) and Version(vc) == Version(vc),
        ),
        (
            f"nested-{token}",
            f"({missing} >= 0.0.0 | ({a} >= {a_upper} & !({b} < {b_lower})))",
            False or (
                Version(va) >= Version(a_upper)
                and not (Version(vb) < Version(b_lower))
            ),
        ),
    ]
    expected = {manifest_id: bool(value) for manifest_id, _, value in cases}

    state_backup = STATE_PATH.read_bytes()
    report_existed = REPORT_PATH.exists()
    report_backup = REPORT_PATH.read_bytes() if report_existed else None
    backup_root = Path(tempfile.mkdtemp(prefix="deployment-verifier-"))
    manifest_backup = backup_root / "original_manifests"
    MANIFEST_DIR.rename(manifest_backup)

    try:
        MANIFEST_DIR.mkdir()
        STATE_PATH.write_text(
            f"Module: {a} Version: {va}\n"
            f"Module: {b} Version: {vb}\n"
            f"Module: {c} Version: {vc}\n"
        )
        for index, (manifest_id, constraint, _) in enumerate(cases, start=1):
            path = MANIFEST_DIR / f"manifest_{index}.json"
            path.write_text(json.dumps({
                "manifest_id": manifest_id,
                "constraint": constraint,
            }))

        if REPORT_PATH.exists():
            REPORT_PATH.unlink()
        run_script()
        results = load_report()

        assert isinstance(results, dict), (
            f"Expected a JSON object (dictionary), got {type(results).__name__}"
        )
        assert set(results) == set(expected), (
            f"Report keys differ from generated manifest IDs: "
            f"expected {set(expected)}, got {set(results)}"
        )
        for manifest_id, expected_value in expected.items():
            assert type(results[manifest_id]) is bool, (
                f"Manifest '{manifest_id}' must map to a JSON boolean."
            )
            assert results[manifest_id] is expected_value, (
                f"Expected manifest '{manifest_id}' to evaluate to "
                f"{expected_value}, but got {results[manifest_id]}."
            )
    finally:
        if MANIFEST_DIR.exists():
            shutil.rmtree(MANIFEST_DIR)
        manifest_backup.rename(MANIFEST_DIR)
        STATE_PATH.write_bytes(state_backup)
        if report_existed:
            REPORT_PATH.write_bytes(report_backup)
        elif REPORT_PATH.exists():
            REPORT_PATH.unlink()
        shutil.rmtree(backup_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
