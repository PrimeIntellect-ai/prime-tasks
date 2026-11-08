#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess


def run_program():
    result = subprocess.run(
        ["go", "run", "/home/user/process.go"],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"process.go failed to run:\n{result.stderr}"
    return result.stdout


def test_source_files_extracted():
    """Test that the source files were successfully extracted to the correct directory."""
    source_dir = "/home/user/source_files"
    assert os.path.isdir(source_dir), f"Directory {source_dir} does not exist."

    server_go = os.path.join(source_dir, "server.go")
    style_css = os.path.join(source_dir, "style.css")

    assert os.path.isfile(server_go), f"File {server_go} is missing. Archive extraction may have failed."
    assert os.path.isfile(style_css), f"File {style_css} is missing. Archive extraction may have failed."


def test_go_program_exists():
    """Test that the Go program was created at the correct location."""
    go_prog = "/home/user/process.go"
    assert os.path.isfile(go_prog), f"Go program {go_prog} is missing."


def test_final_report_content():
    """Test that the final report log contains the correctly formatted output."""
    report_path = "/home/user/final_report.log"
    assert os.path.isfile(report_path), f"Log file {report_path} is missing."

    expected_content = """[backend/server.go]
package main

import "fmt"

func main() {
\tfmt.Println("Hello World")
}
[frontend/style.css]
body {
  background-color: #f0f0f0;
  margin: 0;
}
"""
    with open(report_path, "r") as f:
        actual_content = f.read()

    assert actual_content.strip() == expected_content.strip(), "The contents of final_report.log do not match the expected format and data."


def test_program_generates_report():
    """Compile and run process.go and ensure it actually generates the submitted report."""
    with open("/home/user/final_report.log", "r") as f:
        report = f.read()
    assert run_program().strip() == report.strip(), "Running process.go does not reproduce final_report.log."


def test_program_reads_layout_and_source_files_dynamically():
    """Use unpredictable mappings and contents to reject hardcoded implementations."""
    source_dir = "/home/user/source_files"
    token = secrets.token_hex(8)
    entries = [
        {
            "name": f"dynamic_{token}.go",
            "category": f"backend_{secrets.token_hex(5)}",
            "content": f"package dynamic_{token}\n\nconst Value = \"{secrets.token_hex(16)}\"",
        },
        {
            "name": f"dynamic_{token}.css",
            "category": f"frontend_{secrets.token_hex(5)}",
            "content": f".item-{token} {{\n  color: #{secrets.token_hex(3)};\n}}",
        },
    ]

    layout_paths = []
    for root, dirs, files in os.walk("/home/user"):
        if "layout.json" in files:
            layout_paths.append(os.path.join(root, "layout.json"))
    assert layout_paths, "The extracted layout.json could not be found under /home/user."

    backups = {}
    created_files = []
    try:
        for entry in entries:
            path = os.path.join(source_dir, entry["name"])
            assert not os.path.exists(path)
            with open(path, "w") as f:
                f.write(entry["content"])
            created_files.append(path)

        dynamic_layout = {
            "files": [
                {"name": entry["name"], "category": entry["category"]}
                for entry in entries
            ]
        }
        encoded_layout = json.dumps(dynamic_layout, indent=2).encode()
        for path in layout_paths:
            with open(path, "rb") as f:
                backups[path] = f.read()
            with open(path, "wb") as f:
                f.write(encoded_layout)

        expected = "".join(
            f"[{entry['category']}/{entry['name']}]\n{entry['content']}\n"
            for entry in entries
        )
        assert run_program() == expected, "process.go did not dynamically honor layout.json and source-file contents."
    finally:
        for path, data in backups.items():
            with open(path, "wb") as f:
                f.write(data)
        for path in created_files:
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
