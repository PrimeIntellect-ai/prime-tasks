#!/bin/bash
set -e
mkdir -p /logs/verifier
export PATH="/opt/cargo/bin:$PATH"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import subprocess
import tempfile
import uuid

PROJECT = "/home/user/loc_tool/Cargo.toml"


def test_rust_project_exists():
    assert os.path.isfile(PROJECT), "Rust project 'loc_tool' was not created in /home/user/loc_tool or missing Cargo.toml"


def test_makefile_exists():
    makefile_path = "/home/user/Makefile"
    assert os.path.isfile(makefile_path), f"Makefile is missing at {makefile_path}."

    with open(makefile_path, "r", encoding="utf-8") as f:
        content = f.read()

    assert re.search(r'^process:', content, re.MULTILINE), "Makefile does not contain a 'process' target."


def test_make_process_and_output_json():
    output_path = "/home/user/output.json"
    if os.path.exists(output_path):
        os.remove(output_path)

    result = subprocess.run(
        ["make", "process"],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
    )
    assert result.returncode == 0, f"make process failed:\n{result.stdout}"
    assert os.path.isfile(output_path), f"Output file {output_path} is missing after running make process."

    with open(output_path, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{output_path} is not valid JSON."

    expected_data = [
        {
            "key": "error_not_found",
            "en": "Item {item_name} was not found.",
            "de": "Artikel {item_name} nicht gefunden."
        },
        {
            "key": "logout_btn",
            "en": "Log out",
            "es": "Log out",
            "fr": "Se déconnecter"
        },
        {
            "key": "welcome_msg",
            "en": "Welcome, {user}!",
            "es": "Bienvenido, {user}!",
            "fr": "Welcome, {user}!"
        }
    ]

    assert data == expected_data, "The contents of output.json do not match the expected normalized and imputed translations."


def normalize_placeholders(value):
    if not isinstance(value, str):
        return value
    value = re.sub(r"\{\{([^{}]+)\}\}", r"{\1}", value)
    value = re.sub(r"\[([^\[\]]+)\]", r"{\1}", value)
    return value


def derive_expected(source):
    result = []
    for item in source:
        key_field = next(k for k in item if k.strip().lower() == "key")
        normalized_key = item[key_field].strip().lower().replace(" ", "_")
        english = normalize_placeholders(item.get("en"))
        out = {"key": normalized_key}
        for language, value in item.items():
            if language == key_field:
                continue
            if language != "en" and (value is None or value == ""):
                value = english
            out[language] = normalize_placeholders(value)
        result.append(out)
    return sorted(result, key=lambda entry: entry["key"])


def test_rust_program_on_unseen_input():
    token = uuid.uuid4().hex[:12]
    source = [
        {
            "kEy": f" Zeta {token} Entry ",
            "en": f"Hello {{{{name}}}}, [{token}] and {{single}}.",
            "es": None,
            "fr": ""
        },
        {
            "KEY": f" Alpha {token} ",
            "en": "Base [who]",
            "de": "Hallo {{who}}",
            "ja": ""
        }
    ]
    expected = derive_expected(source)

    with tempfile.TemporaryDirectory() as tmpdir:
        input_path = os.path.join(tmpdir, "input.json")
        output_path = os.path.join(tmpdir, "output.json")
        with open(input_path, "w", encoding="utf-8") as f:
            json.dump(source, f)

        result = subprocess.run(
            ["/opt/cargo/bin/cargo", "run", "--quiet", "--manifest-path", PROJECT, "--", input_path, output_path],
            cwd="/home/user/loc_tool",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=180,
        )
        assert result.returncode == 0, f"Rust program failed on an unseen input:\n{result.stdout}"
        assert os.path.isfile(output_path), "Rust program did not create the requested output file."

        with open(output_path, "r", encoding="utf-8") as f:
            try:
                actual = json.load(f)
            except json.JSONDecodeError:
                assert False, "Rust program produced invalid JSON on an unseen input."

    assert actual == expected, "Rust program did not correctly normalize, impute, preserve language keys, and sort an unseen input."


def test_cronjob_exists():
    cronjob_path = "/home/user/cronjob"
    assert os.path.isfile(cronjob_path), f"Cronjob file is missing at {cronjob_path}."

    with open(cronjob_path, "r", encoding="utf-8") as f:
        content = f.read().strip()

    pattern = r"^15\s+3\s+\*\s+\*\s+2\s+cd\s+/home/user\s*&&\s*make\s+process$"
    assert re.match(pattern, content), f"Cronjob file does not match the required schedule and command. Found: {content}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
