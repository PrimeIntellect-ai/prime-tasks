#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import tarfile
import zipfile
import tempfile
import re
import pytest

EXPECTED_ALPHA = {
    "v1.gcode": (
        "G21 ; metric values\n"
        "G90 ; absolute positioning\n"
        "M82 ; set extruder to absolute mode\n"
        "M92 X80.0 Y80.0 Z400.0 E90.0 ; Set axis steps per unit\n"
    ).encode("utf-8"),
    "v2.gcode": (
        "G21\n"
        "G90\n"
        "M82\n"
        "M92 X80.0 Y80.0 Z400.0 E92.5 ; Set axis steps per unit\n"
    ).encode("utf-8"),
    "v3.gcode": (
        "G21\n"
        "G90\n"
        "M82\n"
        "M92 X80.0 Y80.0 Z400.0 E104.5 ; Set axis steps per unit\n"
    ).encode("utf-8"),
}

EXPECTED_BETA = {
    "v1.gcode": (
        "G21\n"
        "G90\n"
        "M82\n"
        "M92 X100.0 Y100.0 Z400.0 E100.0 ; Set axis steps per unit\n"
    ).encode("utf-8"),
    "v2.gcode": (
        "G21\n"
        "G90\n"
        "M82\n"
        "M92 X100.0 Y100.0 Z400.0 E98.5 ; Set axis steps per unit\n"
    ).encode("utf-8"),
    "v3.gcode": (
        "G21\n"
        "G90\n"
        "M82\n"
        "M92 X100.0 Y100.0 Z400.0 E109.5 ; Set axis steps per unit\n"
    ).encode("utf-8"),
}


def test_extruder_history_csv():
    csv_path = "/home/user/extruder_history.csv"
    assert os.path.exists(csv_path), f"Expected CSV file not found at {csv_path}"

    expected_rows = [
        ["Node", "Version", "E_Value"],
        ["node_alpha", "v1", "90.0"],
        ["node_alpha", "v2", "92.5"],
        ["node_alpha", "v3", "94.0"],
        ["node_beta", "v1", "100.0"],
        ["node_beta", "v2", "98.5"],
        ["node_beta", "v3", "99.0"]
    ]

    with open(csv_path, "r", newline="") as f:
        reader = csv.reader(f)
        actual_rows = list(reader)

    assert actual_rows == expected_rows, f"CSV contents do not match expected. Got: {actual_rows}"


def test_updated_tarball_structure_and_contents():
    tarball_path = "/home/user/updated_cnc_configs.tar.gz"
    assert os.path.exists(tarball_path), f"Expected updated tarball not found at {tarball_path}"

    with tempfile.TemporaryDirectory() as tmpdir:
        with tarfile.open(tarball_path, "r:gz") as tar:
            members = tar.getnames()
            assert "node_alpha.zip" in members, "node_alpha.zip missing from updated tarball"
            assert "node_beta.zip" in members, "node_beta.zip missing from updated tarball"

            # The tarball must contain exactly the two regular zip files and no
            # directories, duplicate names, links, or additional entries.
            assert sorted(members) == ["node_alpha.zip", "node_beta.zip"], \
                f"Unexpected tarball structure: {members}"
            assert all(member.isfile() for member in tar.getmembers()), \
                "All tarball entries must be regular files"

            # Extract to check zip contents. Exact safe names were validated above.
            tar.extractall(path=tmpdir)

        # Check node_alpha.zip
        alpha_zip_path = os.path.join(tmpdir, "node_alpha.zip")
        assert os.path.exists(alpha_zip_path), "node_alpha.zip failed to extract"

        with zipfile.ZipFile(alpha_zip_path, "r") as z:
            alpha_files = z.namelist()
            assert "v1.gcode" in alpha_files, "v1.gcode missing from node_alpha.zip"
            assert "v2.gcode" in alpha_files, "v2.gcode missing from node_alpha.zip"
            assert "v3.gcode" in alpha_files, "v3.gcode missing from node_alpha.zip"
            assert sorted(alpha_files) == ["v1.gcode", "v2.gcode", "v3.gcode"], \
                f"Unexpected node_alpha.zip structure: {alpha_files}"
            assert all(not info.is_dir() for info in z.infolist()), \
                "node_alpha.zip must contain only files"

            v3_content = z.read("v3.gcode").decode("utf-8")
            assert re.search(r"M92 X80\.0 Y80\.0 Z400\.0 E104\.5\s*; Set axis steps per unit", v3_content), \
                "node_alpha/v3.gcode does not contain the correctly updated M92 line"

            v1_content = z.read("v1.gcode").decode("utf-8")
            assert "E90.0" in v1_content, "node_alpha/v1.gcode was incorrectly modified"

            for name, expected_content in EXPECTED_ALPHA.items():
                assert z.read(name) == expected_content, \
                    f"node_alpha/{name} was not preserved exactly apart from the required v3 E update"

        # Check node_beta.zip
        beta_zip_path = os.path.join(tmpdir, "node_beta.zip")
        assert os.path.exists(beta_zip_path), "node_beta.zip failed to extract"

        with zipfile.ZipFile(beta_zip_path, "r") as z:
            beta_files = z.namelist()
            assert "v1.gcode" in beta_files, "v1.gcode missing from node_beta.zip"
            assert "v2.gcode" in beta_files, "v2.gcode missing from node_beta.zip"
            assert "v3.gcode" in beta_files, "v3.gcode missing from node_beta.zip"
            assert sorted(beta_files) == ["v1.gcode", "v2.gcode", "v3.gcode"], \
                f"Unexpected node_beta.zip structure: {beta_files}"
            assert all(not info.is_dir() for info in z.infolist()), \
                "node_beta.zip must contain only files"

            v3_content = z.read("v3.gcode").decode("utf-8")
            assert re.search(r"M92 X100\.0 Y100\.0 Z400\.0 E109\.5\s*; Set axis steps per unit", v3_content), \
                "node_beta/v3.gcode does not contain the correctly updated M92 line"

            v2_content = z.read("v2.gcode").decode("utf-8")
            assert "E98.5" in v2_content, "node_beta/v2.gcode was incorrectly modified"

            for name, expected_content in EXPECTED_BETA.items():
                assert z.read(name) == expected_content, \
                    f"node_beta/{name} was not preserved exactly apart from the required v3 E update"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
