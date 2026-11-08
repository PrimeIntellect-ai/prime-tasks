#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path

import pytest

SCRIPT_PATH = "/home/user/waf_analyzer.py"
OUTPUT_PATH = "/home/user/vulnerabilities.json"


def run_analyzer(rules_dir, packages_path):
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    result = subprocess.run(
        [sys.executable, SCRIPT_PATH, str(rules_dir), str(packages_path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Analyzer exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT_PATH), "Analyzer did not generate /home/user/vulnerabilities.json"
    with open(OUTPUT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"Analyzer generated invalid JSON: {exc}")
    assert isinstance(data, dict), "Analyzer output must be a JSON object"
    return data


def test_00_execute_analyzer_on_provided_inputs():
    assert os.path.isfile(SCRIPT_PATH), f"Python script {SCRIPT_PATH} does not exist. Please create it."
    run_analyzer("/home/user/rules", "/home/user/packages.json")


def test_waf_analyzer_exists():
    script_path = "/home/user/waf_analyzer.py"
    assert os.path.isfile(script_path), f"Python script {script_path} does not exist. Please create it."


def test_vulnerabilities_json_exists_and_valid():
    output_path = "/home/user/vulnerabilities.json"
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist. Did the script run and generate it?"

    with open(output_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{output_path} does not contain valid JSON.")

    assert isinstance(data, dict), f"The root of {output_path} must be a JSON object (dictionary)."


def test_vulnerabilities_json_content():
    output_path = "/home/user/vulnerabilities.json"
    if not os.path.isfile(output_path):
        pytest.skip(f"{output_path} missing.")

    with open(output_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.skip("Invalid JSON.")

    # Check Auth_Bypass
    assert "Auth_Bypass" in data, "Rule 'Auth_Bypass' is missing from the output."
    auth = data["Auth_Bypass"]
    assert auth.get("affected_package") == "auth_lib", "Auth_Bypass affected_package is incorrect."
    assert auth.get("installed_version") == "2.1.4", "Auth_Bypass installed_version is incorrect."
    assert auth.get("is_vulnerable") is True, "Auth_Bypass should be vulnerable."

    # Check Parser_Crash
    assert "Parser_Crash" in data, "Rule 'Parser_Crash' is missing from the output."
    parser = data["Parser_Crash"]
    assert parser.get("affected_package") == "parser_core", "Parser_Crash affected_package is incorrect."
    assert parser.get("installed_version") == "1.5.0", "Parser_Crash installed_version is incorrect."
    assert parser.get("is_vulnerable") is False, "Parser_Crash should NOT be vulnerable."

    # Check Data_Leak
    assert "Data_Leak" in data, "Rule 'Data_Leak' is missing from the output."
    data_leak = data["Data_Leak"]
    assert data_leak.get("affected_package") == "data_utils", "Data_Leak affected_package is incorrect."
    assert data_leak.get("installed_version") == "0.9.5", "Data_Leak installed_version is incorrect."
    assert data_leak.get("is_vulnerable") is True, "Data_Leak should be vulnerable."


def version_tuple(version):
    return tuple(int(part) for part in version.split("."))


def satisfies(installed, conditions):
    current = version_tuple(installed)
    for condition in conditions.split(","):
        op, target_text = condition.strip().split()
        target = version_tuple(target_text)
        result = {
            ">=": current >= target,
            "<=": current <= target,
            ">": current > target,
            "<": current < target,
            "==": current == target,
        }[op]
        if not result:
            return False
    return True


def test_dynamic_parsing_and_semantic_version_behavior():
    token = uuid.uuid4().hex
    rng = random.SystemRandom()
    n = rng.randint(20, 70)

    specs = [
        (f"Window_{token}", f"window_pkg_{token}", f"{n}.10.3", f">= {n}.10.0, <= {n}.10.3"),
        (f"LexicalTrap_{token}", f"lex_pkg_{token}", "2.10.3", "< 2.9.99"),
        (f"MajorOrder_{token}", f"major_pkg_{token}", "10.0.0", "> 2.99.99"),
        (f"StrictBoundary_{token}", f"strict_pkg_{token}", "4.5.6", "> 4.5.6"),
        (f"Exact_{token}", f"exact_pkg_{token}", "7.8.9", "== 7.8.9"),
        (f"AllConditions_{token}", f"all_pkg_{token}", "3.4.5", ">= 3.0.0, > 3.4.4, < 4.0.0"),
        (f"OneConditionFails_{token}", f"fail_pkg_{token}", "3.4.5", ">= 3.0.0, <= 3.4.4"),
    ]

    with tempfile.TemporaryDirectory(prefix="waf_verify_") as temp_dir:
        base = Path(temp_dir)
        rules_dir = base / "rules"
        rules_dir.mkdir()
        packages = {package: installed for _, package, installed, _ in specs}
        packages_path = base / "packages.json"
        packages_path.write_text(json.dumps(packages))

        expected = {}
        for index, (name, package, installed, conditions) in enumerate(specs):
            # Leading unrelated lines are ignored in IDLE, while indented fields are
            # recognized after stripping, matching the legacy state machine.
            content = (
                "ignored text before the rule\n"
                f"RULE \"{name}\" {{\n"
                f"    AFFECTS: \"{package}\"\n"
                f"    VULN_VERSIONS: \"{conditions}\"\n"
                "}\n"
                "RULE \"Ignored_After_Done\" {\n"
                "}\n"
            )
            (rules_dir / f"case_{index}.wafr").write_text(content)
            expected[name] = {
                "affected_package": package,
                "installed_version": installed,
                "is_vulnerable": satisfies(installed, conditions),
            }

        # A rule without a closing brace never reaches DONE and must be omitted.
        (rules_dir / "unfinished.wafr").write_text(
            f'RULE "Unfinished_{token}" {{\n'
            f'    AFFECTS: "window_pkg_{token}"\n'
            f'    VULN_VERSIONS: ">= 0.0.0"\n'
        )
        # Files outside the requested rule format must not become output records.
        (rules_dir / "not_a_rule.txt").write_text(
            f'RULE "WrongExtension_{token}" {{\n'
            f'    AFFECTS: "window_pkg_{token}"\n'
            f'    VULN_VERSIONS: ">= 0.0.0"\n'
            '}\n'
        )

        actual = run_analyzer(rules_dir, packages_path)
        assert actual == expected, (
            "Analyzer output did not exactly match the records parsed from the "
            "dynamic rule set or its semantic-version results."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
