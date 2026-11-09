#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import tarfile
import tempfile

import pytest


def test_converter_c_exists():
    path = "/home/user/converter.c"
    assert os.path.isfile(path), f"{path} does not exist."
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()
    assert "#include" in content, f"{path} does not seem to contain C code (#include missing)."


def test_converter_compiles_and_processes_fresh_inputs():
    source = "/home/user/converter.c"
    token = secrets.token_hex(8)

    with tempfile.TemporaryDirectory() as tmpdir:
        executable = os.path.join(tmpdir, "converter")
        compile_result = subprocess.run(
            ["gcc", source, "-o", executable],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, (
            "converter.c failed to compile:\n" + compile_result.stderr
        )

        input_dir = os.path.join(tmpdir, "input")
        output_dir = os.path.join(tmpdir, "output")
        os.mkdir(input_dir)
        os.mkdir(output_dir)

        cases = {
            f"fresh_{token}.conf": {
                f"General_{token}": {
                    f"Name_{token}": 'Café "été" \\ serveur',
                    f"Location_{token}": "Montréal",
                },
                f"Network_{token}": {
                    f"Host_{token}": "españa.local",
                },
            },
            f"users_{token}.conf": {
                f"Users_{token}": {
                    f"Admin_{token}": "François",
                    f"Guest_{token}": "Jürgen",
                },
                f"Access_{token}": {
                    f"Role_{token}": "Naïve",
                },
            },
        }

        for filename, sections in cases.items():
            lines = []
            for section, pairs in sections.items():
                lines.append(f"[{section}]")
                for key, value in pairs.items():
                    lines.append(f"{key}={value}")
            content = "\n".join(lines) + "\n"
            with open(os.path.join(input_dir, filename), "wb") as f:
                f.write(content.encode("iso-8859-1"))

        with open(os.path.join(input_dir, f"ignored_{token}.txt"), "wb") as f:
            f.write(b"[NotAConfig]\nKey=Value\n")

        run_result = subprocess.run(
            [executable, input_dir, output_dir],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert run_result.returncode == 0, (
            "compiled converter failed when run:\n" + run_result.stderr
        )

        for input_name, expected in cases.items():
            output_name = os.path.splitext(input_name)[0] + ".json"
            output_path = os.path.join(output_dir, output_name)
            assert os.path.isfile(output_path), f"Converter did not create {output_name}."
            try:
                with open(output_path, "r", encoding="utf-8") as f:
                    actual = json.load(f)
            except Exception as e:
                pytest.fail(f"Converter output {output_name} is not valid UTF-8 JSON: {e}")
            assert actual == expected, f"Converter produced incorrect data for {input_name}."


def test_modern_configs_archive():
    archive_path = "/home/user/modern_configs.tar.gz"
    assert os.path.isfile(archive_path), f"The archive {archive_path} does not exist."

    with tempfile.TemporaryDirectory() as tmpdir:
        try:
            with tarfile.open(archive_path, "r:gz") as tar:
                tar.extractall(path=tmpdir)
        except Exception as e:
            pytest.fail(f"Failed to extract {archive_path}: {e}")

        app1_path = None
        app2_path = None
        for root, _, files in os.walk(tmpdir):
            if "app1.json" in files:
                app1_path = os.path.join(root, "app1.json")
            if "app2.json" in files:
                app2_path = os.path.join(root, "app2.json")

        assert app1_path is not None, "app1.json is missing from the modern_configs.tar.gz archive."
        assert app2_path is not None, "app2.json is missing from the modern_configs.tar.gz archive."

        try:
            with open(app1_path, "r", encoding="utf-8") as f:
                app1_data = json.load(f)
        except Exception as e:
            pytest.fail(f"Failed to parse app1.json as JSON: {e}")

        assert app1_data.get("General", {}).get("Name") == "Café", "app1.json: General.Name is incorrect."
        assert app1_data.get("General", {}).get("Location") == "Montréal", "app1.json: General.Location is incorrect."
        assert app1_data.get("Network", {}).get("Host") == "españa.local", "app1.json: Network.Host is incorrect."

        try:
            with open(app2_path, "r", encoding="utf-8") as f:
                app2_data = json.load(f)
        except Exception as e:
            pytest.fail(f"Failed to parse app2.json as JSON: {e}")

        assert app2_data.get("Users", {}).get("Admin") == "François", "app2.json: Users.Admin is incorrect."
        assert app2_data.get("Users", {}).get("Guest") == "Jürgen", "app2.json: Users.Guest is incorrect."
        assert app2_data.get("Access", {}).get("Role") == "Naïve", "app2.json: Access.Role is incorrect."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
