#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import secrets
import shutil
import subprocess
import tarfile
import zipfile


def run_extractor(script_path, archive_path, output_dir):
    result = subprocess.run(
        ["python3", script_path, archive_path, output_dir],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Agent script failed with error: {result.stderr}"


def make_zip(entries, compression=zipfile.ZIP_DEFLATED):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=compression) as zf:
        for name, contents in entries:
            zf.writestr(name, contents)
    return buffer.getvalue()


def test_safe_extractor_metric():
    script_path = "/home/user/safe_extractor.py"
    assert os.path.exists(script_path), f"Agent script not found at {script_path}"
    assert os.path.isfile(script_path), f"Agent script is not a regular file: {script_path}"

    hidden_archive = "/tmp/hidden_eval_backup.tar.gz"
    eval_out_dir = "/tmp/eval_restored_data"

    zip_data = make_zip([
        ("safe.txt", b"safe"),
        ("../../../tmp/eval_restored_data_evil/evil.txt", b"evil1"),
        ("/absolute/path/evil2.txt", b"evil2"),
    ])

    with tarfile.open(hidden_archive, "w:gz") as tf:
        tarinfo = tarfile.TarInfo("nested.zip")
        tarinfo.size = len(zip_data)
        tf.addfile(tarinfo, io.BytesIO(zip_data))

    shutil.rmtree(eval_out_dir, ignore_errors=True)
    shutil.rmtree("/tmp/eval_restored_data_evil", ignore_errors=True)
    shutil.rmtree("/absolute/path", ignore_errors=True)
    os.makedirs(eval_out_dir)

    run_extractor(script_path, hidden_archive, eval_out_dir)

    correct_actions = 0
    total_files = 3

    safe_path = os.path.join(eval_out_dir, "safe.txt")
    if os.path.exists(safe_path):
        correct_actions += 1
    if not os.path.exists("/tmp/eval_restored_data_evil/evil.txt"):
        correct_actions += 1
    if not os.path.exists("/absolute/path/evil2.txt"):
        correct_actions += 1

    accuracy = correct_actions / total_files

    if os.path.exists("/tmp/eval_restored_data_evil/evil.txt"):
        os.remove("/tmp/eval_restored_data_evil/evil.txt")
    if os.path.exists("/absolute/path/evil2.txt"):
        os.remove("/absolute/path/evil2.txt")

    assert accuracy >= 1.0, f"Extraction Security Accuracy: {accuracy} < 1.0 threshold. Script did not correctly handle all files."
    assert open(safe_path, "rb").read() == b"safe", "Extracted safe.txt has incorrect contents"


def test_generalized_nested_archives():
    script_path = "/home/user/safe_extractor.py"
    token = secrets.token_hex(12)
    work_dir = f"/tmp/safe_extractor_test_{token}"
    archive_path = os.path.join(work_dir, "backup.tar.gz")
    output_dir = os.path.join(work_dir, "output")
    relative_escape_dir = f"/tmp/zip_slip_relative_{token}"
    absolute_escape_dir = f"/tmp/zip_slip_absolute_{token}"
    relative_escape_file = os.path.join(relative_escape_dir, "escaped.bin")
    absolute_escape_file = os.path.join(absolute_escape_dir, "escaped.bin")

    shutil.rmtree(work_dir, ignore_errors=True)
    shutil.rmtree(relative_escape_dir, ignore_errors=True)
    shutil.rmtree(absolute_escape_dir, ignore_errors=True)
    os.makedirs(output_dir)

    relative_escape_name = os.path.relpath(relative_escape_file, output_dir)
    assert relative_escape_name.startswith("..")

    expected = {
        "documents/report.txt": secrets.token_bytes(97),
        "empty.dat": b"",
        "deep/one/two/data.bin": secrets.token_bytes(4097),
        "unicode/caf\u00e9.txt": secrets.token_bytes(31),
    }

    zip_archives = {
        "archives/first.zip": make_zip([
            ("documents/report.txt", expected["documents/report.txt"]),
            ("empty.dat", expected["empty.dat"]),
            (relative_escape_name, b"relative traversal payload"),
        ]),
        "archives/history/second.zip": make_zip([
            ("deep/one/two/data.bin", expected["deep/one/two/data.bin"]),
            (absolute_escape_file, b"absolute traversal payload"),
        ]),
        "third.zip": make_zip([
            ("unicode/caf\u00e9.txt", expected["unicode/caf\u00e9.txt"]),
        ], compression=zipfile.ZIP_STORED),
    }

    with tarfile.open(archive_path, "w:gz") as tf:
        for member_name, data in zip_archives.items():
            info = tarfile.TarInfo(member_name)
            info.size = len(data)
            tf.addfile(info, io.BytesIO(data))

    try:
        run_extractor(script_path, archive_path, output_dir)

        for relative_path, expected_contents in expected.items():
            extracted_path = os.path.join(output_dir, *relative_path.split("/"))
            assert os.path.isfile(extracted_path), f"Missing extracted file: {relative_path}"
            with open(extracted_path, "rb") as handle:
                assert handle.read() == expected_contents, f"Incorrect contents for {relative_path}"

        assert not os.path.lexists(relative_escape_file), "Relative Zip Slip payload escaped the output directory"
        assert not os.path.lexists(absolute_escape_file), "Absolute Zip Slip payload escaped the output directory"
    finally:
        shutil.rmtree(work_dir, ignore_errors=True)
        shutil.rmtree(relative_escape_dir, ignore_errors=True)
        shutil.rmtree(absolute_escape_dir, ignore_errors=True)


def test_restored_data_directory():
    target_dir = "/home/user/restored_data"
    assert os.path.isdir(target_dir), f"Target directory {target_dir} was not created. Did you run the script against the sample backup?"

    files = os.listdir(target_dir)
    assert len(files) > 0, f"Target directory {target_dir} is empty."

    sample_file = os.path.join(target_dir, "safe_sample.txt")
    assert os.path.isfile(sample_file), "The expected sample backup file was not restored"
    with open(sample_file, "rb") as handle:
        assert handle.read() == b"safe", "The restored sample file has incorrect contents"
    assert not os.path.exists("/tmp/evil_sample.txt"), "The sample archive's Zip Slip payload was extracted"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
