#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import stat
import subprocess
import uuid
from pathlib import Path

import pytest

PIPELINE = Path("/home/user/pipeline")
REPORT_JSON = PIPELINE / "report.json"
ORCHESTRATOR_PY = PIPELINE / "orchestrator.py"
PACKAGES_JSON = PIPELINE / "packages.json"
BUILDER_SH = PIPELINE / "mock_builder.sh"


def run_orchestrator():
    try:
        result = subprocess.run(
            [str(ORCHESTRATOR_PY)],
            cwd=str(PIPELINE),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        pytest.fail(f"Could not execute {ORCHESTRATOR_PY}: {exc}")

    assert result.returncode == 0, (
        f"Orchestrator exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def load_report():
    assert REPORT_JSON.is_file(), f"Expected output file {REPORT_JSON} does not exist."
    try:
        with REPORT_JSON.open("r") as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"File {REPORT_JSON} is not valid JSON: {exc}")


def test_orchestrator_exists_and_is_executable():
    assert ORCHESTRATOR_PY.is_file(), f"Expected script {ORCHESTRATOR_PY} does not exist."
    mode = ORCHESTRATOR_PY.stat().st_mode
    assert stat.S_ISREG(mode), f"Expected {ORCHESTRATOR_PY} to be a regular file."
    assert mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH), \
        f"Expected {ORCHESTRATOR_PY} to be executable."


def test_original_pipeline_report_content():
    # A stale or fabricated report must not satisfy the verifier.
    if REPORT_JSON.exists():
        REPORT_JSON.unlink()
    run_orchestrator()
    data = load_report()

    assert "packages" in data, "Report JSON is missing the 'packages' top-level key."
    packages = data["packages"]

    expected_packages = {
        "libcore": {"version": "1.2.5", "compile_warnings": 2},
        "py-bindings": {"version": "1.0.1", "compile_warnings": 3},
        "rust-service": {"version": "3.1.0", "compile_warnings": 0},
    }

    for pkg, expected_info in expected_packages.items():
        assert pkg in packages, f"Package '{pkg}' is missing from the report."
        actual_info = packages[pkg]

        assert "version" in actual_info, f"Missing 'version' for package '{pkg}'."
        assert actual_info["version"] == expected_info["version"], \
            f"Expected version {expected_info['version']} for '{pkg}', but got {actual_info['version']}."

        assert "compile_warnings" in actual_info, \
            f"Missing 'compile_warnings' for package '{pkg}'."
        assert actual_info["compile_warnings"] == expected_info["compile_warnings"], \
            f"Expected {expected_info['compile_warnings']} compile_warnings for '{pkg}', but got {actual_info['compile_warnings']}."

    for pkg in packages:
        assert pkg in expected_packages, f"Unexpected package '{pkg}' found in the report."


def test_dynamic_resolution_topological_build_and_log_parsing():
    token = uuid.uuid4().hex[:10]
    base = f"base_{token}"
    util = f"util_{token}"
    app = f"app_{token}"
    leaf = f"leaf_{token}"
    invocation_log = PIPELINE / f"builder_invocations_{token}.log"

    package_data = {
        base: {
            "versions": ["1.9.0", "2.0.0", "1.4.5", "1.10.0"],
            "dependencies": {},
        },
        util: {
            "versions": ["3.0.0", "2.0.0", "2.10.0"],
            "dependencies": {base: ">=1.4.0, <2.0.0"},
        },
        app: {
            "versions": ["4.0.0", "4.0.2"],
            "dependencies": {
                base: ">=1.9.0, <2.0.0",
                util: ">=2.0.0, <3.0.0",
            },
        },
        leaf: {
            "versions": ["0.1.0", "0.2.0"],
            "dependencies": {app: ">=4.0.0, <5.0.0"},
        },
    }
    warning_counts = {base: 1, util: 2, app: 0, leaf: 3}
    expected_versions = {
        base: "1.10.0",
        util: "2.10.0",
        app: "4.0.2",
        leaf: "0.2.0",
    }
    expected_report = {
        "packages": {
            name: {
                "version": expected_versions[name],
                "compile_warnings": warning_counts[name],
            }
            for name in package_data
        }
    }

    original_packages = PACKAGES_JSON.read_bytes()
    original_builder = BUILDER_SH.read_bytes()
    original_builder_mode = BUILDER_SH.stat().st_mode
    original_report = REPORT_JSON.read_bytes() if REPORT_JSON.exists() else None

    cases = "\n".join(
        f'  "{name}") COUNT={count} ;;' for name, count in warning_counts.items()
    )
    builder = f'''#!/bin/bash
set -e
PKG="$1"
VER="$2"
printf '%s %s\\n' "$PKG" "$VER" >> "{invocation_log}"
COUNT=0
case "$PKG" in
{cases}
  *) echo "unknown package: $PKG" >&2; exit 9 ;;
esac
echo "[STATE: INIT] Starting build for $PKG $VER"
echo "[WARN: INIT] ignored init warning"
echo "[STATE: COMPILING]"
i=0
while [ "$i" -lt "$COUNT" ]; do
  echo "[WARN: COMPILING] generated compile warning $i"
  i=$((i + 1))
done
echo "[STATE: LINKING]"
echo "[WARN: LINKING] ignored link warning"
echo "[STATE: DONE]"
'''

    try:
        PACKAGES_JSON.write_text(json.dumps(package_data, indent=2))
        BUILDER_SH.write_text(builder)
        BUILDER_SH.chmod(0o755)
        if invocation_log.exists():
            invocation_log.unlink()
        if REPORT_JSON.exists():
            REPORT_JSON.unlink()

        run_orchestrator()
        assert load_report() == expected_report

        assert invocation_log.is_file(), "The orchestrator did not invoke mock_builder.sh."
        calls = []
        for line in invocation_log.read_text().splitlines():
            parts = line.split()
            assert len(parts) == 2, f"Malformed builder invocation record: {line!r}"
            calls.append((parts[0], parts[1]))

        assert len(calls) == len(package_data), \
            "Each package must be built exactly once."
        assert {name for name, _ in calls} == set(package_data), \
            "Builder invocations did not include exactly all packages."
        assert len({name for name, _ in calls}) == len(calls), \
            "A package was built more than once."

        for name, version in calls:
            assert version == expected_versions[name], \
                f"Builder received incorrect resolved version for {name}."

        order = {name: index for index, (name, _) in enumerate(calls)}
        assert order[base] < order[util]
        assert order[base] < order[app]
        assert order[util] < order[app]
        assert order[app] < order[leaf]
    finally:
        PACKAGES_JSON.write_bytes(original_packages)
        BUILDER_SH.write_bytes(original_builder)
        BUILDER_SH.chmod(stat.S_IMODE(original_builder_mode))
        if original_report is None:
            if REPORT_JSON.exists():
                REPORT_JSON.unlink()
        else:
            REPORT_JSON.write_bytes(original_report)
        if invocation_log.exists():
            invocation_log.unlink()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
