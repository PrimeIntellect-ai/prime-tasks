#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import secrets
import subprocess
import urllib.request
import urllib.error


def test_approved_users_csv():
    path = "/home/user/approved_users.csv"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        content = f.read().strip().splitlines()

    expected = [
        "bob,bob@example.com",
        "david,david@example.com",
        "eve,eve@example.com"
    ]

    assert content == expected, f"Content of {path} does not match expected output."


def test_cpp_files_exist():
    cpp_path = "/home/user/json_generator.cpp"
    exe_path = "/home/user/json_generator"

    assert os.path.isfile(cpp_path), f"C++ source file {cpp_path} does not exist."
    assert os.path.isfile(exe_path), f"Executable {exe_path} does not exist."
    assert os.access(exe_path, os.X_OK), f"File {exe_path} is not executable."

    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {exe_path} is not a compiled executable."


def test_public_html_json():
    path = "/home/user/public_html/users.json"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {path} does not contain valid JSON."

    expected = [
        {"username": "bob", "email": "bob@example.com"},
        {"username": "david", "email": "david@example.com"},
        {"username": "eve", "email": "eve@example.com"}
    ]

    assert data == expected, f"JSON content in {path} does not match expected output."


def test_final_output_json():
    path = "/home/user/final_output.json"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {path} does not contain valid JSON."

    expected = [
        {"username": "bob", "email": "bob@example.com"},
        {"username": "david", "email": "david@example.com"},
        {"username": "eve", "email": "eve@example.com"}
    ]

    assert data == expected, f"JSON content in {path} does not match expected output."


def test_port_forwarding():
    url = "http://127.0.0.1:9090/users.json"
    try:
        req = urllib.request.urlopen(url, timeout=2)
        content = req.read().decode('utf-8')
        data = json.loads(content)
    except urllib.error.URLError:
        assert False, f"Could not connect to {url}. Port forwarding or HTTP server might not be running."
    except json.JSONDecodeError:
        assert False, f"Response from {url} is not valid JSON."

    expected = [
        {"username": "bob", "email": "bob@example.com"},
        {"username": "david", "email": "david@example.com"},
        {"username": "eve", "email": "eve@example.com"}
    ]

    assert data == expected, f"JSON content fetched from {url} does not match expected output."


def test_cpp_utility_transforms_unseen_input():
    csv_path = "/home/user/approved_users.csv"
    json_path = "/home/user/public_html/users.json"
    source_path = "/home/user/json_generator.cpp"
    submitted_exe = "/home/user/json_generator"
    rebuilt_exe = "/tmp/json_generator_rebuilt"

    with open(csv_path, "rb") as f:
        original_csv = f.read()
    with open(json_path, "rb") as f:
        original_json = f.read()

    token = secrets.token_hex(8)

    def exercise(executable, suffix):
        records = [
            (f"user_{token}_{suffix}_a", f"{token}.{suffix}.a@example.net"),
            (f"user_{token}_{suffix}_b", f"{token}.{suffix}.b@example.org"),
            (f"user_{token}_{suffix}_c", f"{token}.{suffix}.c@example.com"),
        ]
        with open(csv_path, "w") as f:
            for username, email in records:
                f.write(f"{username},{email}\n")

        if os.path.exists(json_path):
            os.remove(json_path)
        subprocess.run([executable], check=True, timeout=10)
        assert os.path.isfile(json_path), f"{executable} did not create {json_path}."
        with open(json_path, "r") as f:
            try:
                actual = json.load(f)
            except json.JSONDecodeError as exc:
                assert False, f"{executable} produced invalid JSON: {exc}"
        expected = [
            {"username": username, "email": email}
            for username, email in records
        ]
        assert actual == expected, f"{executable} did not transform the supplied CSV correctly."

    try:
        exercise(submitted_exe, "submitted")
        compile_result = subprocess.run(
            ["g++", source_path, "-o", rebuilt_exe],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, (
            "json_generator.cpp does not compile successfully: " + compile_result.stderr
        )
        exercise(rebuilt_exe, "rebuilt")
    finally:
        with open(csv_path, "wb") as f:
            f.write(original_csv)
        with open(json_path, "wb") as f:
            f.write(original_json)
        if os.path.exists(rebuilt_exe):
            os.remove(rebuilt_exe)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
