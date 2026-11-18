#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import tempfile
import pytest

OUTPUT = "/home/user/output.json"

EXPECTED_ORIGINAL = [
    {
        "manager_id": "U1",
        "department": "Engineering",
        "team_size": 3,
        "combined_roles": ["admin", "deploy", "read", "write"]
    },
    {
        "manager_id": "U4",
        "department": "Marketing",
        "team_size": 2,
        "combined_roles": ["analytics", "content", "social"]
    }
]


def load_output():
    try:
        with open(OUTPUT, "r", encoding="utf-8") as f:
            raw = f.read()
        return raw, json.loads(raw)
    except Exception as e:
        pytest.fail(f"Failed to parse {OUTPUT} as JSON: {e}")


def assert_strict_output(expected):
    raw, data = load_output()
    assert isinstance(data, list), "Output JSON must be a JSON array."
    assert len(data) == len(expected), f"Expected {len(expected)} managers, got {len(data)}"

    for actual, wanted in zip(data, expected):
        assert isinstance(actual, dict), "Every array element must be a JSON object."
        assert set(actual.keys()) == {"manager_id", "department", "team_size", "combined_roles"}, \
            f"Object has missing or extra fields: {actual}"
        assert type(actual["manager_id"]) is str
        assert type(actual["department"]) is str
        assert type(actual["team_size"]) is int
        assert isinstance(actual["combined_roles"], list)
        assert all(type(role) is str for role in actual["combined_roles"])
        assert actual == wanted, f"Expected {wanted}, got {actual}"

    assert [x["manager_id"] for x in data] == sorted(x["manager_id"] for x in data), \
        "Managers must be sorted alphabetically by manager_id."
    for obj in data:
        assert obj["combined_roles"] == sorted(obj["combined_roles"]), \
            f"Roles for {obj['manager_id']} must be sorted alphabetically."
        assert len(obj["combined_roles"]) == len(set(obj["combined_roles"])), \
            f"Roles for {obj['manager_id']} must be deduplicated."

    # Permit either no terminal newline or one terminal newline, but otherwise
    # require the exact two-space pretty-printed representation.
    formatted = raw[:-1] if raw.endswith("\n") else raw
    assert not formatted.endswith("\n"), "Output may contain at most one terminal newline."
    canonical = json.dumps(data, ensure_ascii=False, indent=2)
    assert formatted == canonical, "Output JSON must use exactly 2-space indentation."


def test_aggregator_source_exists():
    """Test that the C++ source file exists."""
    assert os.path.isfile("/home/user/aggregator.cpp"), "/home/user/aggregator.cpp is missing. Did you write the source code?"


def test_aggregator_executable_exists():
    """Test that the compiled executable exists."""
    assert os.path.isfile("/home/user/aggregator"), "/home/user/aggregator is missing. Did you compile the program?"
    assert os.access("/home/user/aggregator", os.X_OK), "/home/user/aggregator is not executable."


def test_output_json_exists():
    """Test that the output JSON file exists."""
    assert os.path.isfile(OUTPUT), "/home/user/output.json is missing. Did you run the program?"


def test_output_json_content():
    """Preserve the original fixture assertions."""
    _, data = load_output()
    assert isinstance(data, list), "Output JSON must be a JSON array."

    try:
        data_sorted = sorted(data, key=lambda x: x.get("manager_id", ""))
        expected_sorted = sorted(EXPECTED_ORIGINAL, key=lambda x: x["manager_id"])
    except Exception as e:
        pytest.fail(f"Output JSON is missing expected keys or has invalid structure: {e}")

    assert len(data_sorted) == len(expected_sorted), f"Expected {len(expected_sorted)} managers in output, got {len(data_sorted)}"
    for actual, expected in zip(data_sorted, expected_sorted):
        assert actual.get("manager_id") == expected["manager_id"]
        assert actual.get("department") == expected["department"]
        assert actual.get("team_size") == expected["team_size"]
        actual_roles = actual.get("combined_roles", [])
        assert isinstance(actual_roles, list)
        assert sorted(actual_roles) == sorted(expected["combined_roles"])


def test_original_output_strict_schema_order_and_format():
    assert_strict_output(EXPECTED_ORIGINAL)


def derive_expected(users, permission_docs, report_edges):
    departments = {uid: department for uid, _name, department in users}
    roles_by_uid = {doc["uid"]: doc["roles"] for doc in permission_docs}
    result = []
    for manager, reports in report_edges:
        team = [manager] + reports
        roles = sorted({role for uid in team for role in roles_by_uid.get(uid, [])})
        result.append({
            "manager_id": manager,
            "department": departments[manager],
            "team_size": len(team),
            "combined_roles": roles,
        })
    return sorted(result, key=lambda x: x["manager_id"])


def test_compiled_program_on_changed_inputs():
    token = secrets.token_hex(6)
    manager_z = f"MZ_{token}"
    manager_a = f"MA_{token}"
    report_1 = f"R1_{token}"
    report_2 = f"R2_{token}"
    report_3 = f"R3_{token}"

    users = [
        (report_2, "PersonTwo", f"DeptR_{token}"),
        (manager_z, "ManagerZ", f"Engineering_{token}"),
        (report_1, "PersonOne", f"DeptR_{token}"),
        (manager_a, "ManagerA", f"Marketing_{token}"),
        (report_3, "PersonThree", f"DeptR_{token}"),
    ]
    permissions = [
        {"uid": report_3, "roles": [f"zeta_{token}", f"alpha_{token}"]},
        {"uid": manager_z, "roles": [f"deploy_{token}", f"admin_{token}"]},
        {"uid": report_1, "roles": [f"read_{token}", f"admin_{token}"]},
        {"uid": manager_a, "roles": [f"zeta_{token}", f"middle_{token}"]},
        {"uid": report_2, "roles": [f"write_{token}", f"read_{token}"]},
    ]
    # Deliberately place managers and reports in non-sorted order.
    edges = [
        (manager_z, [report_2, report_1]),
        (manager_a, [report_3]),
    ]
    expected = derive_expected(users, permissions, edges)

    with tempfile.TemporaryDirectory(prefix="aggregator_test_") as td:
        users_path = os.path.join(td, "users.csv")
        permissions_path = os.path.join(td, "permissions.json")
        reports_path = os.path.join(td, "reports_to.txt")
        rebuilt = os.path.join(td, "aggregator_rebuilt")

        with open(users_path, "w", encoding="utf-8") as f:
            for uid, name, department in users:
                f.write(f"{uid},{name},{department}\n")
        with open(permissions_path, "w", encoding="utf-8") as f:
            json.dump(permissions, f)
        with open(reports_path, "w", encoding="utf-8") as f:
            for manager, reports in edges:
                f.write(f"{manager}:{','.join(reports)}\n")

        compile_result = subprocess.run(
            ["g++", "-std=c++11", "-I/home/user/include", "/home/user/aggregator.cpp", "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, f"aggregator.cpp failed to compile:\n{compile_result.stderr}"

        # Exercise both the submitted executable and a verifier-built executable,
        # proving that the executable works and that aggregator.cpp implements it.
        for executable in ["/home/user/aggregator", rebuilt]:
            if os.path.exists(OUTPUT):
                os.unlink(OUTPUT)
            result = subprocess.run(
                [executable, users_path, permissions_path, reports_path],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
            assert result.returncode == 0, \
                f"{executable} exited with {result.returncode}:\n{result.stderr}"
            assert os.path.isfile(OUTPUT), f"{executable} did not create {OUTPUT}"
            assert_strict_output(expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
