#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import json
import os
import random
import secrets
import shutil
import string
import subprocess
import tempfile


def test_archive_report_csv_contents():
    report_path = "/home/user/archive_report.csv"
    assert os.path.isfile(report_path), f"The report file {report_path} was not created."

    with open(report_path, "r") as f:
        content = f.read().strip()

    expected_content = (
        "filename,total_size\n"
        "node2.json.gz,2048\n"
        "node3.json.gz,4096\n"
        "node5.json.gz,8192"
    )

    # Compare line by line to ignore trailing newlines and provide better diffs
    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]
    expected_lines = expected_content.splitlines()

    assert actual_lines == expected_lines, "The contents of archive_report.csv do not match the expected output."


def test_log_dumps_directory_contents():
    log_dir = "/home/user/log_dumps"
    assert os.path.isdir(log_dir), f"The directory {log_dir} is missing."

    expected_files = {
        "node1.json.gz",
        "node2.json.gz.processed",
        "node3.json.gz.processed",
        "node4.json.gz",
        "node5.json.gz.processed"
    }

    actual_files = set(os.listdir(log_dir))

    # Check that all expected files exist
    for f in expected_files:
        assert f in actual_files, f"Expected file {f} is missing from {log_dir}."

    # Check that the original files for the processed ones are gone
    unexpected_files = {
        "node2.json.gz",
        "node3.json.gz",
        "node5.json.gz",
        "node1.json.gz.processed",
        "node4.json.gz.processed"
    }

    for f in unexpected_files:
        assert f not in actual_files, f"File {f} should not exist in {log_dir}."


def _find_and_compile_programs():
    sources = []
    for root, dirs, files in os.walk("/home/user"):
        for name in files:
            if name.endswith((".cpp", ".cc", ".cxx")):
                path = os.path.join(root, name)
                if os.path.isfile(path):
                    sources.append(path)

    assert sources, "No C++ source program was found under /home/user."

    build_dir = tempfile.mkdtemp(prefix="archive_verifier_build_")
    plans = [sources]
    if len(sources) > 1:
        plans.extend([[source] for source in sources])

    executables = []
    compile_errors = []
    seen = set()
    for plan in plans:
        key = tuple(sorted(plan))
        if key in seen:
            continue
        seen.add(key)
        exe = os.path.join(build_dir, f"candidate_{len(seen)}")
        result = subprocess.run(
            ["g++", "-std=c++17", "-O2", *plan, "-lz", "-o", exe],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        if result.returncode == 0 and os.path.isfile(exe):
            executables.append(exe)
        else:
            compile_errors.append(result.stderr[-2000:])

    assert executables, "No submitted C++ source could be compiled.\n" + "\n".join(compile_errors)
    return build_dir, executables


def _exercise(executable):
    log_dir = "/home/user/log_dumps"
    report_path = "/home/user/archive_report.csv"

    shutil.rmtree(log_dir, ignore_errors=True)
    os.makedirs(log_dir)
    if os.path.lexists(report_path):
        os.remove(report_path)

    token = secrets.token_hex(6)
    values = [secrets.randbelow(8000000) + 10000 for _ in range(5)]
    records = [
        (f"a_{token}.json.gz", "ACTIVE", values[0]),
        (f"b_{token}.json.gz", "ARCHIVED", values[1]),
        (f"c_{token}.json.gz", "ARCHIVED ", values[2]),
        (f"d_{token}.json.gz", "ARCHIVED", values[3]),
        (f"e_{token}.json.gz", "archived", values[4]),
    ]

    original_objects = {}
    creation_order = list(records)
    random.SystemRandom().shuffle(creation_order)
    for index, (filename, status, total_size) in enumerate(creation_order):
        # Decoy similarly named fields and varied formatting require parsing the
        # specified top-level status and nested metrics.total_size fields.
        obj = {
            "decoy": {"status": "ARCHIVED", "metrics": {"total_size": total_size + 991}},
            "node_id": filename[:-8],
            "metrics": {"sample_count": index + 1, "total_size": total_size},
            "message": 'text containing \\"status\\": \\"ARCHIVED\\"',
            "status": status,
        }
        original_objects[filename] = obj
        payload = json.dumps(obj, indent=(2 if index % 2 else None), sort_keys=(index % 2 == 0)).encode()
        with gzip.open(os.path.join(log_dir, filename), "wb") as stream:
            stream.write(payload)

    result = subprocess.run(
        [executable],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Program exited with {result.returncode}: {result.stderr[-1000:]}"

    archived = sorted((name, size) for name, status, size in records if status == "ARCHIVED")
    expected_lines = ["filename,total_size"] + [f"{name},{size}" for name, size in archived]
    assert os.path.isfile(report_path), "Program did not create archive_report.csv on new inputs."
    with open(report_path, "r") as report:
        actual_lines = [line.strip() for line in report.read().splitlines() if line.strip()]
    assert actual_lines == expected_lines, "Program produced an incorrect report for verifier-generated inputs."

    expected_files = {
        name + (".processed" if status == "ARCHIVED" else "")
        for name, status, _ in records
    }
    actual_files = set(os.listdir(log_dir))
    assert actual_files == expected_files, "Program renamed the wrong files or left uncompressed/temporary files on disk."

    # Every resulting log must still be the original gzip stream, merely renamed
    # where appropriate; this also rejects replacing streams with plain JSON.
    for name, status, _ in records:
        final_name = name + (".processed" if status == "ARCHIVED" else "")
        with gzip.open(os.path.join(log_dir, final_name), "rt") as stream:
            decoded = json.load(stream)
        assert decoded == original_objects[name], f"Compressed contents of {final_name} were altered."


def test_cpp_program_on_unseen_compressed_json():
    # Preserve and re-check the original final-state assertions before replacing
    # the fixture directory with verifier-generated cases.
    test_archive_report_csv_contents()
    test_log_dumps_directory_contents()

    build_dir, executables = _find_and_compile_programs()
    failures = []
    try:
        for executable in executables:
            try:
                _exercise(executable)
                return
            except Exception as exc:
                failures.append(f"{os.path.basename(executable)}: {exc}")
        assert False, "No compiled C++ program handled unseen gzip/JSON inputs correctly. " + " | ".join(failures)
    finally:
        shutil.rmtree(build_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
