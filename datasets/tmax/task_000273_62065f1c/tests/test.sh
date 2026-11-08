#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import stat
import subprocess

MANIFEST_PATH = "/home/user/artifact_manifest.csv"
MOCK_DIR = "/home/user/mock_artifacts"
REPORT_PATH = "/home/user/security_report.json"
SCRIPT_PATH = "/home/user/process_artifacts.sh"


def get_manifest_data():
    if not os.path.exists(MANIFEST_PATH):
        return []
    data = []
    with open(MANIFEST_PATH, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(",")
            if len(parts) == 3:
                data.append({
                    "artifact": parts[0],
                    "size": int(parts[1]),
                    "octal": parts[2]
                })
    return data


def test_process_script_exists_and_is_executable_bash():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist or is not a regular file."
    mode = stat.S_IMODE(os.stat(SCRIPT_PATH).st_mode)
    assert mode & 0o111, f"Script {SCRIPT_PATH} is not executable."
    syntax = subprocess.run(
        ["bash", "-n", SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert syntax.returncode == 0, f"Script {SCRIPT_PATH} is not valid Bash: {syntax.stderr}"


def test_mock_artifacts_directory_exists():
    assert os.path.isdir(MOCK_DIR), f"Directory {MOCK_DIR} does not exist."


def test_mock_artifacts_files_created_correctly():
    manifest_data = get_manifest_data()
    assert manifest_data, f"Manifest file {MANIFEST_PATH} is empty or missing."

    for item in manifest_data:
        file_path = os.path.join(MOCK_DIR, item["artifact"])
        assert os.path.isfile(file_path), f"Artifact file {file_path} was not created."

        actual_size = os.path.getsize(file_path)
        assert actual_size == item["size"], f"File {file_path} has size {actual_size}, expected {item['size']}."

        st = os.stat(file_path)
        actual_mode = stat.S_IMODE(st.st_mode)
        expected_mode = int(item["octal"], 8)
        assert actual_mode == expected_mode, f"File {file_path} has mode {oct(actual_mode)}, expected {oct(expected_mode)}."


def test_security_report_json():
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} does not exist."

    with open(REPORT_PATH, "r") as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {REPORT_PATH} is not valid JSON."

    assert isinstance(report_data, list), f"JSON root in {REPORT_PATH} must be a list."

    manifest_data = get_manifest_data()
    assert manifest_data, f"Manifest file {MANIFEST_PATH} is empty or missing."

    expected_scores = {}
    for item in manifest_data:
        size = item["size"]
        decimal_mode = int(item["octal"], 8)
        score = ((size ^ decimal_mode) * 13) % 97
        expected_scores[item["artifact"]] = score

    actual_scores = {}
    for entry in report_data:
        assert isinstance(entry, dict), f"Report entry {entry} is not a JSON object."
        assert "artifact" in entry, f"Report entry {entry} missing 'artifact' key."
        assert "score" in entry, f"Report entry {entry} missing 'score' key."
        actual_scores[entry["artifact"]] = entry["score"]

    for artifact, expected_score in expected_scores.items():
        assert artifact in actual_scores, f"Artifact '{artifact}' missing from security report."
        assert actual_scores[artifact] == expected_score, f"Artifact '{artifact}' has score {actual_scores[artifact]}, expected {expected_score}."


def test_script_generates_outputs_for_fresh_manifest():
    with open(MANIFEST_PATH, "rb") as f:
        original_manifest = f.read()

    modes = ["0400", "0444", "0600", "0640", "0644", "0700", "0751", "0755"]
    probe = secrets.token_hex(8)
    generated = []
    for index in range(3 + secrets.randbelow(4)):
        generated.append({
            "artifact": f"probe_{probe}_{index}.bin",
            "size": 1 + secrets.randbelow(20000),
            "octal": modes[secrets.randbelow(len(modes))],
        })

    try:
        with open(MANIFEST_PATH, "w") as f:
            for item in generated:
                f.write(f"{item['artifact']},{item['size']},{item['octal']}\n")

        if os.path.lexists(MOCK_DIR):
            if os.path.isdir(MOCK_DIR) and not os.path.islink(MOCK_DIR):
                shutil.rmtree(MOCK_DIR)
            else:
                os.unlink(MOCK_DIR)
        if os.path.lexists(REPORT_PATH):
            if os.path.isdir(REPORT_PATH) and not os.path.islink(REPORT_PATH):
                shutil.rmtree(REPORT_PATH)
            else:
                os.unlink(REPORT_PATH)

        result = subprocess.run(
            [SCRIPT_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"Executing {SCRIPT_PATH} failed with status {result.returncode}. "
            f"stdout: {result.stdout} stderr: {result.stderr}"
        )

        assert os.path.isdir(MOCK_DIR), f"Script did not create directory {MOCK_DIR}."
        for item in generated:
            path = os.path.join(MOCK_DIR, item["artifact"])
            assert os.path.isfile(path), f"Script did not create artifact {path}."
            assert os.path.getsize(path) == item["size"], f"Artifact {path} has the wrong size."
            actual_mode = stat.S_IMODE(os.stat(path).st_mode)
            expected_mode = int(item["octal"], 8)
            assert actual_mode == expected_mode, f"Artifact {path} has mode {oct(actual_mode)}, expected {oct(expected_mode)}."

        assert os.path.isfile(REPORT_PATH), f"Script did not create report {REPORT_PATH}."
        with open(REPORT_PATH, "r") as f:
            report_data = json.load(f)
        assert isinstance(report_data, list), f"JSON root in {REPORT_PATH} must be a list."

        actual_scores = {}
        for entry in report_data:
            assert isinstance(entry, dict), f"Report entry {entry} is not a JSON object."
            assert "artifact" in entry, f"Report entry {entry} missing 'artifact' key."
            assert "score" in entry, f"Report entry {entry} missing 'score' key."
            actual_scores[entry["artifact"]] = entry["score"]

        for item in generated:
            expected = ((item["size"] ^ int(item["octal"], 8)) * 13) % 97
            assert item["artifact"] in actual_scores, f"Artifact '{item['artifact']}' missing from generated report."
            assert actual_scores[item["artifact"]] == expected, (
                f"Artifact '{item['artifact']}' has score {actual_scores[item['artifact']]}, expected {expected}."
            )
    finally:
        with open(MANIFEST_PATH, "wb") as f:
            f.write(original_manifest)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
