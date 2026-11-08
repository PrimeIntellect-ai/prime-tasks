#!/bin/bash
mkdir -p /logs/verifier

GO_FILES=()
if [[ -f /home/user/process_dataset.go ]]; then
    GO_FILES=(/home/user/process_dataset.go)
else
    mapfile -t GO_FILES < <(find /home/user -maxdepth 2 -type f -name '*.go' -not -path '*/dataset_incoming/*' -not -path '*/dataset_processed/*' | sort)
fi

run_program() {
    [[ ${#GO_FILES[@]} -gt 0 ]] || return 1
    go run "${GO_FILES[@]}"
}

cleanup() {
    if [[ -n "${BACKUP_DIR:-}" && -d "$BACKUP_DIR" ]]; then
        if [[ -f "$BACKUP_DIR/robotics_data.tar.gz" ]]; then
            cp "$BACKUP_DIR/robotics_data.tar.gz" /home/user/dataset_incoming/robotics_data.tar.gz
        fi
        if [[ -d "$BACKUP_DIR/processed" ]]; then
            rm -rf /home/user/dataset_processed
            cp -a "$BACKUP_DIR/processed" /home/user/dataset_processed
        fi
        rm -rf "$BACKUP_DIR"
    fi
}
trap cleanup EXIT

verify_all() {
    [[ ${#GO_FILES[@]} -gt 0 ]] || return 1

    rm -rf /home/user/dataset_processed
    mkdir -p /home/user/dataset_processed
    run_program || return 1

    cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import gzip
import os
import tarfile

PROCESSED = "/home/user/dataset_processed"
ARCHIVE = "/home/user/dataset_incoming/robotics_data.tar.gz"


def expected_from_archive():
    expected = {}
    with tarfile.open(ARCHIVE, "r:gz") as archive:
        for member in archive.getmembers():
            if not member.isfile() or not member.name.endswith(".gcode.gz"):
                continue
            compressed = archive.extractfile(member).read()
            try:
                content = gzip.decompress(compressed)
            except (OSError, EOFError):
                continue

            maximum = None
            for raw_line in content.decode("utf-8").splitlines():
                line = raw_line.split(";", 1)[0].strip()
                fields = line.split()
                if not fields or fields[0].upper() != "G1":
                    continue
                for field in fields[1:]:
                    if field.upper().startswith("E") and len(field) > 1:
                        try:
                            value = float(field[1:])
                        except ValueError:
                            continue
                        maximum = value if maximum is None else max(maximum, value)
            assert maximum is not None, f"Fixture file has no G1 E value: {member.name}"
            basename = os.path.basename(member.name)[:-len(".gcode.gz")]
            expected[f"{basename}_E{int(maximum)}.gcode"] = content
    return expected


def test_processed_files_exist():
    assert os.path.isdir(PROCESSED), f"Target directory missing: {PROCESSED}"

    partA_expected = os.path.join(PROCESSED, "partA_E7.gcode")
    partB_expected = os.path.join(PROCESSED, "partB_E150.gcode")

    assert os.path.isfile(partA_expected), f"Expected file not found: {partA_expected}"
    assert os.path.isfile(partB_expected), f"Expected file not found: {partB_expected}"

    partC_files = glob.glob(os.path.join(PROCESSED, "*partC*"))
    assert len(partC_files) == 0, f"Corrupted partC should have been skipped, but found: {partC_files}"


def test_processed_files_content():
    partA_expected = os.path.join(PROCESSED, "partA_E7.gcode")
    partB_expected = os.path.join(PROCESSED, "partB_E150.gcode")

    with open(partA_expected, "r") as f:
        contentA = f.read()
    assert "E7.8" in contentA, f"File {partA_expected} missing expected content 'E7.8'"
    assert "G28" in contentA, f"File {partA_expected} missing expected content 'G28'"

    with open(partB_expected, "r") as f:
        contentB = f.read()
    assert "E150.9" in contentB, f"File {partB_expected} missing expected content 'E150.9'"
    assert "G28" in contentB, f"File {partB_expected} missing expected content 'G28'"


def test_no_extra_files():
    files = os.listdir(PROCESSED)
    expected_files = {"partA_E7.gcode", "partB_E150.gcode"}
    actual_files = set(files)
    extra_files = actual_files - expected_files
    assert not extra_files, f"Found unexpected files in {PROCESSED}: {extra_files}"


def test_complete_decompressed_contents_match_archive():
    expected = expected_from_archive()
    actual = set(os.listdir(PROCESSED))
    assert actual == set(expected), f"Output set differs from valid archive members: {actual} != {set(expected)}"
    for filename, expected_content in expected.items():
        path = os.path.join(PROCESSED, filename)
        assert os.path.isfile(path), f"Output is not a regular file: {path}"
        with open(path, "rb") as output:
            assert output.read() == expected_content, f"Decompressed content mismatch in {filename}"
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1

    BACKUP_DIR=$(mktemp -d)
    cp /home/user/dataset_incoming/robotics_data.tar.gz "$BACKUP_DIR/robotics_data.tar.gz" || return 1
    cp -a /home/user/dataset_processed "$BACKUP_DIR/processed" || return 1

    python3 << 'PY_EOF' || return 1
import gzip
import io
import json
import secrets
import tarfile

archive_path = "/home/user/dataset_incoming/robotics_data.tar.gz"
manifest_path = "/tmp/dynamic_manifest.json"
token = secrets.token_hex(6)
base1 = 20 + secrets.randbelow(500)
base2 = 600 + secrets.randbelow(500)

files = {
    f"trajectory_{token}.gcode.gz": (
        "G28\n"
        f"G1 X1 Y2 E{base1}.25\n"
        f"G0 X4 Y5 E{base2 + 9000}.9\n"
        f"G1 X8 Y9 E{base1 + 17}.875\n"
    ).encode(),
    f"sample_{token}.gcode.gz": (
        "G28\n"
        "G1 X0 Y0 E0.0\n"
        f"G1 X3 Y4 E{base2}.99\n"
        f"G1 X7 Y8 E{base2 + 41}.125\n"
    ).encode(),
}

corrupt_name = f"damaged_{token}.gcode.gz"
corrupt = bytearray(gzip.compress(b"G28\nG1 X1 Y1 E99999.0\n"))
corrupt[-1] ^= 0xFF

with tarfile.open(archive_path, "w:gz") as archive:
    for name, content in files.items():
        payload = gzip.compress(content)
        info = tarfile.TarInfo(name)
        info.size = len(payload)
        archive.addfile(info, io.BytesIO(payload))
    info = tarfile.TarInfo(corrupt_name)
    info.size = len(corrupt)
    archive.addfile(info, io.BytesIO(corrupt))

expected = {
    f"trajectory_{token}_E{base1 + 17}.gcode": files[f"trajectory_{token}.gcode.gz"].decode(),
    f"sample_{token}_E{base2 + 41}.gcode": files[f"sample_{token}.gcode.gz"].decode(),
}
with open(manifest_path, "w") as manifest:
    json.dump({"expected": expected, "corrupt_token": f"damaged_{token}"}, manifest)
PY_EOF

    rm -rf /home/user/dataset_processed
    mkdir -p /home/user/dataset_processed
    run_program || return 1

    python3 << 'PY_EOF' || return 1
import json
import os

processed = "/home/user/dataset_processed"
with open("/tmp/dynamic_manifest.json") as manifest_file:
    manifest = json.load(manifest_file)

expected = manifest["expected"]
assert os.path.isdir(processed), "Target directory was not created"
actual = set(os.listdir(processed))
assert actual == set(expected), f"Dynamic output set mismatch: {actual} != {set(expected)}"
assert not any(manifest["corrupt_token"] in name for name in actual), "Corrupted gzip member was output"
for filename, content in expected.items():
    path = os.path.join(processed, filename)
    assert os.path.isfile(path), f"Expected regular output file missing: {path}"
    with open(path, "rb") as output:
        assert output.read() == content.encode(), f"Dynamic decompressed content mismatch: {filename}"
PY_EOF
}

if verify_all; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
