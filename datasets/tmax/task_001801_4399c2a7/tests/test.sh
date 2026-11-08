#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import stat

INITIAL_FILES = {
    "/home/user/grpc_project/math_basic.proto": b'''syntax = "proto3";
package math.basic;

service MathService {
  rpc Add (AddRequest) returns (AddResponse);
}
''',
    "/home/user/grpc_project/hamming_encoder.proto": b'''syntax = "proto3";
package telecom.ecc.v1;

service ErrorCorrection {
  rpc EncodeHamming (DataRequest) returns (DataResponse);
}
''',
    "/home/user/grpc_project/file_verifier.proto": b'''syntax = "proto3";
package storage.verification;

service FileVerifier {
  rpc CalculateChecksum (FileRequest) returns (HashResponse);
}
''',
    "/home/user/grpc_project/random_stuff.proto": b'''syntax = "proto3";
package random.stuff;

// Just a random comment mentioning hamming, wait no, lowercase doesn't match!
service RandomService {
  rpc DoNothing (Empty) returns (Empty);
}
''',
}

PACKAGE_RE = re.compile(rb"(?m)^\s*package\s+([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*;")


def is_match(data):
    return b"Hamming" in data or b"Checksum" in data


def destination(source, data):
    match = PACKAGE_RE.search(data)
    assert match is not None, f"Fixture has no protobuf package: {source}"
    package_path = match.group(1).decode("ascii").replace(".", "/")
    return f"/home/user/organized_protos/{package_path}/{os.path.basename(source)}"


MATCHED = {
    source: (destination(source, data), data)
    for source, data in INITIAL_FILES.items()
    if is_match(data)
}
UNMATCHED = {
    source: data for source, data in INITIAL_FILES.items() if not is_match(data)
}


def assert_regular_file(path):
    assert os.path.isfile(path), f"Expected file {path} was not found."
    assert stat.S_ISREG(os.lstat(path).st_mode), f"{path} must be a regular file, not a symlink."


def proto_files_under(root):
    found = set()
    if not os.path.isdir(root):
        return found
    for directory, _, files in os.walk(root):
        for name in files:
            if name.endswith(".proto"):
                found.add(os.path.join(directory, name))
    return found


def test_files_moved_correctly_and_unchanged():
    for source, (target, expected_bytes) in MATCHED.items():
        assert_regular_file(target)
        with open(target, "rb") as handle:
            assert handle.read() == expected_bytes, f"Contents of moved file {target} were changed."
        assert not os.path.lexists(source), f"Matching file {source} was copied rather than moved."


def test_files_not_moved_or_modified():
    for path, expected_bytes in UNMATCHED.items():
        assert_regular_file(path)
        with open(path, "rb") as handle:
            assert handle.read() == expected_bytes, f"Non-matching file {path} was modified."


def test_complete_proto_file_sets():
    expected_remaining = set(UNMATCHED)
    expected_organized = {target for target, _ in MATCHED.values()}
    assert proto_files_under("/home/user/grpc_project") == expected_remaining, \
        "The original project does not contain exactly the non-matching .proto files."
    assert proto_files_under("/home/user/organized_protos") == expected_organized, \
        "The organized tree does not contain exactly the matching .proto files at package-derived paths."


def test_manifest_correctness():
    manifest_path = "/home/user/manifest.txt"
    assert_regular_file(manifest_path)

    expected_entries = []
    for _, (target, expected_bytes) in MATCHED.items():
        checksum = hashlib.sha256(expected_bytes).hexdigest()
        expected_entries.append((target, f"{checksum}  {target}"))
    expected_lines = [line for _, line in sorted(expected_entries, key=lambda item: item[0])]

    with open(manifest_path, "r", encoding="utf-8") as handle:
        actual_lines = handle.read().splitlines()

    assert actual_lines == expected_lines, \
        f"Manifest must contain exactly the checksums of unchanged moved files, sorted by path.\nExpected: {expected_lines}\nActual:   {actual_lines}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
