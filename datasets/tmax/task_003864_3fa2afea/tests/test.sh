#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import json
import os
import re
import subprocess
import tarfile
import tempfile
import uuid


def test_validator_script_exists():
    assert os.path.isfile("/home/user/validator.py"), "Validator script is missing at /home/user/validator.py"


def test_validator_classifies_corpora():
    validator_path = "/home/user/validator.py"
    evil_input = "/app/test_corpora/evil"
    clean_input = "/app/test_corpora/clean"
    evil_output = "/tmp/evil_res.json"
    clean_output = "/tmp/clean_res.json"

    if os.path.exists(evil_output):
        os.remove(evil_output)
    if os.path.exists(clean_output):
        os.remove(clean_output)

    evil_run = subprocess.run(
        ["python3", validator_path, "--input", evil_input, "--output", evil_output],
        capture_output=True, text=True, timeout=20
    )
    assert evil_run.returncode == 0, f"Validator failed on evil corpus. Stderr: {evil_run.stderr}"
    assert os.path.isfile(evil_output), f"Validator did not produce output at {evil_output}"

    clean_run = subprocess.run(
        ["python3", validator_path, "--input", clean_input, "--output", clean_output],
        capture_output=True, text=True, timeout=20
    )
    assert clean_run.returncode == 0, f"Validator failed on clean corpus. Stderr: {clean_run.stderr}"
    assert os.path.isfile(clean_output), f"Validator did not produce output at {clean_output}"

    with open(evil_output, "r") as f:
        evil_res = json.load(f)
    with open(clean_output, "r") as f:
        clean_res = json.load(f)

    expected_evil_files = [f for f in os.listdir(evil_input) if f.endswith(".tar") or f.endswith(".tar.gz")]
    evil_bypassed = []
    for f in expected_evil_files:
        if evil_res.get(f) != "EVIL":
            evil_bypassed.append(f)

    expected_clean_files = [f for f in os.listdir(clean_input) if f.endswith(".tar") or f.endswith(".tar.gz")]
    clean_modified = []
    for f in expected_clean_files:
        if clean_res.get(f) != "CLEAN":
            clean_modified.append(f)

    error_msg = ""
    if evil_bypassed:
        error_msg += f"{len(evil_bypassed)} of {len(expected_evil_files)} evil bypassed: {', '.join(evil_bypassed)}. "
    if clean_modified:
        error_msg += f"{len(clean_modified)} of {len(expected_clean_files)} clean modified/rejected: {', '.join(clean_modified)}."

    assert not evil_bypassed and not clean_modified, error_msg.strip()


def _image_token():
    run = subprocess.run(
        ["tesseract", "/app/docs/auth_stamp.png", "stdout"],
        capture_output=True, text=True, check=True, timeout=20
    )
    match = re.search(r"AUTH_TOKEN\s*=\s*([A-Za-z0-9_.-]+)", run.stdout)
    assert match, f"Could not read authorization token from image: {run.stdout!r}"
    return match.group(1)


def _add_file(archive, name, data):
    payload = data.encode("utf-8") if isinstance(data, str) else data
    info = tarfile.TarInfo(name)
    info.size = len(payload)
    info.mode = 0o644
    archive.addfile(info, io.BytesIO(payload))


def _add_symlink(archive, name, target):
    info = tarfile.TarInfo(name)
    info.type = tarfile.SYMTYPE
    info.linkname = target
    info.mode = 0o777
    archive.addfile(info)


def _make_archive(path, files=None, symlinks=None):
    mode = "w:gz" if path.endswith(".tar.gz") else "w"
    with tarfile.open(path, mode) as archive:
        for name, data in (files or []):
            _add_file(archive, name, data)
        for name, target in (symlinks or []):
            _add_symlink(archive, name, target)


def test_validator_on_generated_archives():
    validator_path = "/home/user/validator.py"
    token = _image_token()
    valid_meta = json.dumps({"auth_token": token, "title": "manual"})
    valid_gcode = "G28\nG1 X10 Y10\n; END OF GCODE\n"
    prefix = uuid.uuid4().hex

    with tempfile.TemporaryDirectory(prefix="validator-hidden-") as input_dir:
        expected = {}

        def archive(label, suffix, classification, files=None, symlinks=None):
            name = f"{prefix}_{label}{suffix}"
            _make_archive(os.path.join(input_dir, name), files, symlinks)
            expected[name] = classification

        archive("clean_plain", ".tar", "CLEAN", [
            ("meta.json", valid_meta),
            ("README.md", "# Printer manual\n"),
        ])
        archive("clean_gcode", ".tar.gz", "CLEAN", [
            ("meta.json", valid_meta),
            ("parts/start.gcode", valid_gcode),
        ])
        archive("clean_safe_link", ".tar", "CLEAN", [
            ("meta.json", valid_meta),
            ("README.md", "safe target\n"),
        ], [("README-link", "README.md")])
        archive("missing_meta", ".tar", "EVIL", [
            ("manual.gcode", valid_gcode),
        ])
        archive("nested_meta_only", ".tar.gz", "EVIL", [
            ("docs/meta.json", valid_meta),
        ])
        archive("invalid_json", ".tar", "EVIL", [
            ("meta.json", "{not valid json"),
        ])
        archive("wrong_token", ".tar.gz", "EVIL", [
            ("meta.json", json.dumps({"auth_token": token + "_wrong"})),
        ])
        archive("malformed_gcode", ".tar", "EVIL", [
            ("meta.json", valid_meta),
            ("nested/job.gcode", "G28\n; END OF GCODE extra\n"),
        ])
        archive("absolute_symlink", ".tar.gz", "EVIL", [
            ("meta.json", valid_meta),
        ], [("passwd-link", "/etc/passwd")])
        archive("parent_loop", ".tar", "EVIL", [
            ("meta.json", valid_meta),
            ("manual/page.md", "loop test\n"),
        ], [("manual/back", "..")])

        output_path = os.path.join(input_dir, "result.json")
        run = subprocess.run(
            ["python3", validator_path, "--input", input_dir, "--output", output_path],
            capture_output=True, text=True, timeout=30
        )
        assert run.returncode == 0, f"Validator failed on generated corpus. Stderr: {run.stderr}"
        assert os.path.isfile(output_path), f"Validator did not produce output at {output_path}"

        with open(output_path, "r") as f:
            result = json.load(f)

        assert isinstance(result, dict), "Validator output must be a single JSON dictionary"
        assert result == expected, f"Incorrect archive classifications. Expected {expected!r}, got {result!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
