#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import io
import json
import os
import secrets
import shutil
import subprocess
import tarfile


def test_script_exists():
    script_path = "/home/user/process_storage.py"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."


def test_cleaned_gcode_files():
    expected_print1 = [
        "G21",
        "G90",
        "G1 X100 Y100 F1500",
        "M104 S200"
    ]
    expected_print2 = [
        "M109 S200",
        "G1 Z0.2 F1200",
        "G1 X110 Y110 E1.5"
    ]

    print1_path = "/home/user/cleaned_gcode/print1.gcode"
    print2_path = "/home/user/cleaned_gcode/print2.gcode"

    assert os.path.isfile(print1_path), f"Cleaned GCode file missing: {print1_path}"
    assert os.path.isfile(print2_path), f"Cleaned GCode file missing: {print2_path}"

    with open(print1_path, 'r') as f:
        content1 = f.read().splitlines()
    assert content1 == expected_print1, f"Content of {print1_path} is incorrect. Expected {expected_print1}, got {content1}"

    with open(print2_path, 'r') as f:
        content2 = f.read().splitlines()
    assert content2 == expected_print2, f"Content of {print2_path} is incorrect. Expected {expected_print2}, got {content2}"


def test_storage_report():
    report_path = "/home/user/storage_report.json"
    assert os.path.isfile(report_path), f"Report file missing: {report_path}"

    with open(report_path, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{report_path} is not a valid JSON file."

    assert "processed_gcode_count" in report, "Missing 'processed_gcode_count' in report."
    assert report["processed_gcode_count"] == 2, f"Incorrect 'processed_gcode_count' in report. Expected 2, got {report['processed_gcode_count']}"

    assert "corrupt_archives" in report, "Missing 'corrupt_archives' in report."
    expected_corrupt = ["/home/user/storage_pool/proj2/broken_backup.tar.gz"]
    assert report["corrupt_archives"] == expected_corrupt, f"Incorrect 'corrupt_archives' in report. Expected {expected_corrupt}, got {report['corrupt_archives']}"


def _clean_gcode(text):
    result = []
    for line in text.splitlines():
        line = line.split(';', 1)[0].rstrip()
        if line.strip():
            result.append(line)
    return result


def test_script_executes_on_fresh_unpredictable_fixture():
    root = "/home/user/storage_pool"
    cleaned = "/home/user/cleaned_gcode"
    report_path = "/home/user/storage_report.json"
    token = secrets.token_hex(8)

    shutil.rmtree(root)
    shutil.rmtree(cleaned)
    if os.path.exists(report_path):
        os.unlink(report_path)

    deep = os.path.join(root, "batch_" + token, "nested")
    archive_dir = os.path.join(root, "archives_" + token)
    os.makedirs(deep)
    os.makedirs(archive_dir)
    os.makedirs(cleaned)

    gcode_inputs = {
        "part_" + token + ".gcode": (
            "; generated fixture\n"
            "G28 ; home all axes\n"
            "  G1 X17 Y29 F" + str(int(token[:4], 16) % 7000 + 1000) + "   ; move\n"
            "\t; comment-only line\n"
            "M104 S" + str(int(token[-4:], 16) % 80 + 180) + "\t\t\n"
        ),
        "finish_" + token + ".gcode": (
            "G90; absolute positioning\n"
            "G1 Z0.35 F900    \n"
            "; ignored\n"
            "M84 ; disable motors\n"
        ),
    }

    gcode_paths = []
    for index, (name, content) in enumerate(gcode_inputs.items()):
        parent = deep if index == 0 else os.path.dirname(deep)
        path = os.path.join(parent, name)
        with open(path, "w") as f:
            f.write(content)
        gcode_paths.append(path)

    valid_path = os.path.join(archive_dir, "valid_" + token + ".tar.gz")
    payload = ("payload-" + token).encode()
    info = tarfile.TarInfo("payload.txt")
    info.size = len(payload)
    with tarfile.open(valid_path, "w:gz") as tf:
        tf.addfile(info, io.BytesIO(payload))

    plain_bad = os.path.join(archive_dir, "a_bad_" + token + ".tar.gz")
    with open(plain_bad, "wb") as f:
        f.write(("not an archive " + token).encode())

    gzip_bad = os.path.join(archive_dir, "z_bad_" + token + ".tar.gz")
    with gzip.open(gzip_bad, "wb") as f:
        f.write(("valid gzip but not tar " + token).encode())

    # A directory link back to the pool exercises loop prevention when links are followed.
    os.symlink(root, os.path.join(deep, "loop_back"))

    subprocess.run(
        ["python3", "/home/user/process_storage.py"],
        cwd="/home/user",
        check=True,
        timeout=8,
    )

    expected_names = set(gcode_inputs)
    actual_names = set(os.listdir(cleaned))
    assert actual_names == expected_names, (
        f"Cleaned output files are incorrect. Expected {expected_names}, got {actual_names}"
    )

    for name, source in gcode_inputs.items():
        output_path = os.path.join(cleaned, name)
        assert os.path.isfile(output_path), f"Cleaned GCode file missing: {output_path}"
        with open(output_path, "r") as f:
            actual = f.read().splitlines()
        expected = _clean_gcode(source)
        assert actual == expected, f"Incorrect transformed content for {name}: expected {expected}, got {actual}"

    assert os.path.isfile(report_path), f"Report file missing after script execution: {report_path}"
    with open(report_path, "r") as f:
        report = json.load(f)

    assert "processed_gcode_count" in report, "Missing 'processed_gcode_count' in report."
    assert report["processed_gcode_count"] == len(gcode_inputs), (
        f"Expected {len(gcode_inputs)} processed GCode files, got {report['processed_gcode_count']}"
    )
    assert "corrupt_archives" in report, "Missing 'corrupt_archives' in report."
    expected_corrupt = sorted([os.path.abspath(plain_bad), os.path.abspath(gzip_bad)])
    assert report["corrupt_archives"] == expected_corrupt, (
        f"Expected corrupt archives {expected_corrupt}, got {report['corrupt_archives']}"
    )
    assert os.path.abspath(valid_path) not in report["corrupt_archives"], "Valid tar archive was reported as corrupt."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
