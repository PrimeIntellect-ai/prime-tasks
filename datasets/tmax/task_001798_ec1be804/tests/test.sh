#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import gzip
import io
import json
import os
import pathlib
import subprocess
import tarfile
import uuid
import zipfile

GO_PATH = "/home/user/process_dataset.go"
DATASET_PATH = pathlib.Path("/home/user/dataset.tar.gz")
OUTPUT_PATH = pathlib.Path("/home/user/valid_records.jsonl")


def run_program():
    OUTPUT_PATH.unlink(missing_ok=True)
    result = subprocess.run(
        ["timeout", "30s", "go", "run", GO_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, (
        f"The Go program failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_go_script_exists():
    go_path = GO_PATH
    assert os.path.exists(go_path), f"The Go program {go_path} is missing."
    assert os.path.isfile(go_path), f"{go_path} should be a file."


def test_valid_records_jsonl():
    # Remove any precomputed answer and require the submitted Go program to
    # regenerate it from the supplied archive.
    run_program()

    output_jsonl = str(OUTPUT_PATH)
    assert os.path.exists(output_jsonl), f"The output file {output_jsonl} is missing."
    assert os.path.isfile(output_jsonl), f"{output_jsonl} should be a file."

    expected_records = [
        {"id": "A1", "status": "valid", "value": 10.5},
        {"id": "A3", "status": "valid", "value": 42.1},
        {"id": "B2", "status": "valid", "value": 99.9},
        {"id": "C1", "status": "valid", "value": 3.14},
        {"id": "C2", "status": "valid", "value": 2.71}
    ]

    actual_records = []
    with open(output_jsonl, 'r', encoding='utf-8') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
                actual_records.append(record)
            except json.JSONDecodeError:
                assert False, f"Line {line_num} in {output_jsonl} is not valid JSON: {line}"

    assert len(actual_records) == len(expected_records), f"Expected {len(expected_records)} valid records, but found {len(actual_records)}."

    # Compare independent of order
    def sort_key(record):
        return record.get("id", "")

    expected_sorted = sorted(expected_records, key=sort_key)
    actual_sorted = sorted(actual_records, key=sort_key)

    assert actual_sorted == expected_sorted, f"The records in {output_jsonl} do not match the expected valid records."

    # Also require the original bytes of every selected JSON line to be
    # preserved rather than accepting parsed-and-reserialized JSON.
    expected_lines = [
        b'{"id": "A1", "status": "valid", "value": 10.5}\n',
        b'{"id": "A3", "status": "valid", "value": 42.1}\n',
        b'{"id": "B2", "status": "valid", "value": 99.9}\n',
        b'{"id": "C1", "status": "valid", "value": 3.14}\n',
        b'{"id": "C2", "status": "valid", "value": 2.71}\n',
    ]
    actual_lines = OUTPUT_PATH.read_bytes().splitlines(keepends=True)
    assert collections.Counter(actual_lines) == collections.Counter(expected_lines), (
        "The selected JSON lines were not preserved exactly as they appeared uncompressed."
    )


def make_zip(entries):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("empty_directory/", b"")
        for name, data in entries.items():
            zf.writestr(name, data)
        zf.writestr("ignored.json", b'{"status":"valid","source":"not gz"}\n')
    return buf.getvalue()


def test_program_processes_fresh_nested_archive_and_preserves_formatting():
    nonce = uuid.uuid4().hex
    streams = {
        "deep/sensor_one.txt.gz": [
            f'{{ "id" : "{nonce}-A" , "status" : "valid" , "value" : 7 }}\n'.encode(),
            f'{{"id":"{nonce}-B","status":"invalid","value":8}}\n'.encode(),
            f'\t{{"status":"valid","id":"{nonce}-C","text":"spaced value"}}   \n'.encode(),
        ],
        "sensor_two.txt.gz": [
            f'{{"id":"{nonce}-D","status":true,"value":9}}\n'.encode(),
            f'{{"id":"{nonce}-E", "value":10, "status":"valid"}}\n'.encode(),
            f'{{"id":"{nonce}-F","status":"validly"}}\n'.encode(),
        ],
    }

    expected_lines = []
    for lines in streams.values():
        for raw_line in lines:
            obj = json.loads(raw_line)
            if obj.get("status") == "valid" and isinstance(obj.get("status"), str):
                expected_lines.append(raw_line)

    zip_one = make_zip({
        "deep/sensor_one.txt.gz": gzip.compress(b"".join(streams["deep/sensor_one.txt.gz"])),
        "deep/not_selected.csv.gz": gzip.compress(b'{"status":"valid"}\n'),
    })
    zip_two = make_zip({
        "sensor_two.txt.gz": gzip.compress(b"".join(streams["sensor_two.txt.gz"])),
    })

    original_dataset = DATASET_PATH.read_bytes()
    try:
        with tarfile.open(DATASET_PATH, "w:gz") as tf:
            directory = tarfile.TarInfo("irrelevant_directory")
            directory.type = tarfile.DIRTYPE
            directory.mode = 0o755
            tf.addfile(directory)

            loop = tarfile.TarInfo("loop_dir")
            loop.type = tarfile.SYMTYPE
            loop.linkname = "."
            tf.addfile(loop)

            for name, payload in [
                ("nested/experiment_dynamic.zip", zip_one),
                ("experiment_extra.zip", zip_two),
            ]:
                info = tarfile.TarInfo(name)
                info.size = len(payload)
                info.mode = 0o644
                tf.addfile(info, io.BytesIO(payload))

            ignored = b"not a zip"
            info = tarfile.TarInfo("notes.txt")
            info.size = len(ignored)
            tf.addfile(info, io.BytesIO(ignored))

        run_program()
        assert OUTPUT_PATH.exists(), "The Go program did not create valid_records.jsonl."
        actual_lines = OUTPUT_PATH.read_bytes().splitlines(keepends=True)
        assert collections.Counter(actual_lines) == collections.Counter(expected_lines), (
            "The Go program did not correctly process a fresh nested archive or did not "
            "preserve the selected source lines exactly."
        )
    finally:
        DATASET_PATH.write_bytes(original_dataset)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
