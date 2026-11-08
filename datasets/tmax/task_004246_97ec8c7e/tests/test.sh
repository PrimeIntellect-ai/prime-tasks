#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest

HOME = Path("/home/user")
SCRIPT = HOME / "audit_configs.py"
REPORT = HOME / "audit_report.html"
TEMPLATE = HOME / "report_template.html"
CONFIG_ROOT = HOME / "config_data"


def run_script():
    result = subprocess.run(
        ["python3", str(SCRIPT)],
        cwd=str(HOME),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"audit_configs.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert REPORT.is_file(), f"The audit report was not found at {REPORT}."


def flatten(value, prefix=""):
    result = {}
    for key, item in value.items():
        name = f"{prefix}.{key}" if prefix else key
        if isinstance(item, dict):
            result.update(flatten(item, name))
        else:
            result[name] = item
    return result


def drift(previous, current):
    previous = flatten(previous)
    current = flatten(current)
    score = 0
    for key in previous.keys() | current.keys():
        if key not in previous or key not in current:
            score += 10
            continue
        left, right = previous[key], current[key]
        if type(left) is not type(right):
            score += 20
        elif isinstance(left, bool):
            if left != right:
                score += 5
        elif isinstance(left, (int, float)):
            score += abs(left - right)
        elif isinstance(left, str):
            if left != right:
                score += 5
        elif left != right:
            score += 5
    return score


def expected_stats(root):
    expected = {}
    for server_dir in sorted(path for path in root.iterdir() if path.is_dir()):
        snapshots = []
        for path in sorted(server_dir.glob("config_*.json")):
            with path.open("r", encoding="utf-8") as handle:
                snapshots.append(json.load(handle))
        scores = [drift(a, b) for a, b in zip(snapshots, snapshots[1:])]
        expected[server_dir.name] = {
            "total_anomalies": sum(score > 50 for score in scores),
            "average_drift": round(sum(scores) / len(scores), 1) if scores else 0.0,
        }
    return expected


def write_snapshot(server, date, data):
    directory = CONFIG_ROOT / server
    directory.mkdir(parents=True, exist_ok=True)
    with (directory / f"config_{date}.json").open("w", encoding="utf-8") as handle:
        json.dump(data, handle)


def test_audit_script_exists():
    assert SCRIPT.is_file(), f"The script was not found at {SCRIPT}."
    assert SCRIPT.stat().st_size > 0, "The audit script is empty."


def test_script_executes_and_handles_unseen_data_with_jinja():
    backup_root = Path(tempfile.mkdtemp(prefix="audit-verifier-"))
    backup_configs = backup_root / "config_data"
    backup_template = backup_root / "report_template.html"
    shutil.copytree(CONFIG_ROOT, backup_configs)
    shutil.copy2(TEMPLATE, backup_template)

    try:
        shutil.rmtree(CONFIG_ROOT)
        CONFIG_ROOT.mkdir(parents=True)

        # Deliberately create files out of chronological order. The nested values
        # exercise flattening, missing keys, type changes, numeric differences,
        # string/boolean changes, averaging, and the strict > 50 threshold.
        write_snapshot("server_alpha", "2024-01-03", {
            "nested": {"number": 10, "text": "b", "flag": False},
            "added": 0,
            "typed": "1",
        })
        write_snapshot("server_alpha", "2024-01-01", {
            "nested": {"number": 1, "text": "a", "flag": True},
            "gone": 1,
            "typed": 1,
        })
        write_snapshot("server_alpha", "2024-01-02", {
            "nested": {"number": 4, "text": "b", "flag": False},
            "added": 0,
            "typed": "1",
        })

        write_snapshot("server_beta", "2024-01-03", {"limit": 70})
        write_snapshot("server_beta", "2024-01-01", {"limit": 10})
        write_snapshot("server_beta", "2024-01-02", {"limit": 20})

        write_snapshot("server_gamma", "2024-01-03", {})
        write_snapshot("server_gamma", "2024-01-01", {"value": "x"})
        write_snapshot("server_gamma", "2024-01-02", {"value": 1})

        TEMPLATE.write_text(
            "<html><body>VERIFIER_DYNAMIC_TEMPLATE\n"
            "{% for srv, data in servers.items() %}"
            "RESULT {{ srv }} {{ data.total_anomalies }} {{ data.average_drift }}\n"
            "{% endfor %}</body></html>\n",
            encoding="utf-8",
        )

        expected = expected_stats(CONFIG_ROOT)
        run_script()
        content = REPORT.read_text(encoding="utf-8")
        assert "VERIFIER_DYNAMIC_TEMPLATE" in content, (
            "The supplied Jinja2 template was not rendered."
        )

        matches = re.findall(r"RESULT\s+(\S+)\s+(\d+)\s+(-?[0-9]+(?:\.[0-9]+)?)", content)
        actual = {
            server: {
                "total_anomalies": int(anomalies),
                "average_drift": float(average),
            }
            for server, anomalies, average in matches
        }
        assert actual == expected, (
            f"Unexpected results for verifier-generated snapshots.\n"
            f"Expected: {expected}\nActual: {actual}\nReport:\n{content}"
        )
    finally:
        if CONFIG_ROOT.exists():
            shutil.rmtree(CONFIG_ROOT)
        shutil.copytree(backup_configs, CONFIG_ROOT)
        shutil.copy2(backup_template, TEMPLATE)
        shutil.rmtree(backup_root)

    # Re-execute on the original task inputs so the original report assertions
    # remain enforced and the requested final artifact is left in place.
    run_script()


def test_audit_report_exists():
    report_path = "/home/user/audit_report.html"
    assert os.path.isfile(report_path), f"The audit report was not found at {report_path}."


def test_audit_report_content():
    report_path = "/home/user/audit_report.html"
    assert os.path.isfile(report_path), f"The audit report was not found at {report_path}."

    with open(report_path, "r", encoding="utf-8") as f:
        content = f.read()

    expected_alpha = "server_alpha: Anomalies=1, AvgDrift=483.0"
    expected_beta = "server_beta: Anomalies=0, AvgDrift=2.5"
    expected_gamma = "server_gamma: Anomalies=2, AvgDrift=100.0"

    assert expected_alpha in content, f"Expected '{expected_alpha}' to be in the audit report. Report content:\n{content}"
    assert expected_beta in content, f"Expected '{expected_beta}' to be in the audit report. Report content:\n{content}"
    assert expected_gamma in content, f"Expected '{expected_gamma}' to be in the audit report. Report content:\n{content}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
