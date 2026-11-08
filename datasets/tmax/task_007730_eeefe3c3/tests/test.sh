#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import posixpath
import tarfile

EXTRACTED = "/home/user/extracted_data"
MERGED = "/home/user/merged_large_data.txt"
SPLIT_DIR = "/home/user/split_data"
ARCHIVE = "/home/user/final_backup.tar.gz"
CHUNK_NAMES = ["chunk_aa.txt", "chunk_ab.txt", "chunk_ac.txt", "chunk_ad.txt"]


def numbered_lines(prefix, count, padding_count, csv=False):
    result = []
    for i in range(1, count + 1):
        if csv:
            line = f"{prefix}{i:05d}," + ",".join(["padding"] * padding_count) + "\n"
        else:
            line = f"{prefix}{i:05d} " + " ".join(["padding"] * padding_count) + "\n"
        result.append(line.encode("ascii"))
    return result


EXPECTED_EXTRACTED = {
    "dir1/file_A.txt": b"".join(numbered_lines("Data line ", 800, 13)),
    "dir2/file_B.txt": b"".join(numbered_lines("Small line ", 100, 13)),
    "dir2/file_C.txt": b"".join(numbered_lines("Record ", 1200, 14)),
    "file_D.csv": b"".join(numbered_lines("CSV,", 1000, 15, csv=True)),
}

# The qualifying files, sorted by their full absolute paths, are file_A then file_C.
EXPECTED_MERGED_LINES = (
    numbered_lines("Data line ", 800, 13)
    + numbered_lines("Record ", 1200, 14)
)
EXPECTED_MERGED = b"".join(EXPECTED_MERGED_LINES)
EXPECTED_CHUNKS = {
    name: b"".join(EXPECTED_MERGED_LINES[i * 500:(i + 1) * 500])
    for i, name in enumerate(CHUNK_NAMES)
}


def test_extracted_data_dir():
    assert os.path.isdir(EXTRACTED), f"Directory {EXTRACTED} does not exist."
    for relative_path, expected in EXPECTED_EXTRACTED.items():
        path = os.path.join(EXTRACTED, *relative_path.split("/"))
        assert os.path.isfile(path), f"Extracted file {path} is missing."
        with open(path, "rb") as f:
            assert f.read() == expected, f"Extracted file {path} does not match the supplied dataset."


def test_merged_large_data_file():
    assert os.path.isfile(MERGED), f"File {MERGED} does not exist."
    with open(MERGED, "rb") as f:
        actual = f.read()
    assert len(actual.splitlines()) == 2000, f"Expected 2000 lines in {MERGED}, but found {len(actual.splitlines())}."
    assert actual == EXPECTED_MERGED, (
        "Merged data does not contain exactly the qualifying .txt files in "
        "alphabetical full-path order."
    )


def test_split_data_chunks():
    assert os.path.isdir(SPLIT_DIR), f"Directory {SPLIT_DIR} does not exist."
    files_in_dir = os.listdir(SPLIT_DIR)
    for name in CHUNK_NAMES:
        assert name in files_in_dir, f"Expected file {name} is missing in {SPLIT_DIR}."
        path = os.path.join(SPLIT_DIR, name)
        assert os.path.isfile(path), f"{path} is not a regular file."
        with open(path, "rb") as f:
            actual = f.read()
        assert len(actual.splitlines()) == 500, f"Expected 500 lines in {name}, but found {len(actual.splitlines())}."
        assert actual == EXPECTED_CHUNKS[name], f"Contents of {name} do not match the corresponding merged-data segment."

    txt_files = [f for f in files_in_dir if f.endswith(".txt")]
    assert len(txt_files) == 4, f"Expected exactly 4 .txt chunk files, but found {len(txt_files)}."


def normalized_tar_name(name):
    normalized = posixpath.normpath(name.lstrip("/"))
    assert normalized != ".." and not normalized.startswith("../"), "Archive contains an unsafe path."
    return normalized


def test_final_backup_archive():
    assert os.path.isfile(ARCHIVE), f"Archive {ARCHIVE} does not exist."
    assert tarfile.is_tarfile(ARCHIVE), f"File {ARCHIVE} is not a valid tar archive."

    with tarfile.open(ARCHIVE, "r:gz") as tar:
        members = tar.getmembers()
        normalized = [(member, normalized_tar_name(member.name)) for member in members]
        assert any("split_data" in path.split("/") for _, path in normalized), (
            "The split_data directory is missing from the final backup archive."
        )

        candidate_roots = set()
        for _, path in normalized:
            parts = path.split("/")
            for i, part in enumerate(parts):
                if part == "split_data":
                    candidate_roots.add("/".join(parts[:i + 1]))

        valid_root = None
        for root in candidate_roots:
            expected_paths = {f"{root}/{name}" for name in CHUNK_NAMES}
            regular_paths = {path for member, path in normalized if member.isfile()}
            all_under_root = all(path == root or path.startswith(root + "/") for _, path in normalized)
            if regular_paths == expected_paths and all_under_root:
                valid_root = root
                break

        assert valid_root is not None, (
            "Archive must contain the split_data directory with exactly the four expected chunk files."
        )

        by_path = {path: member for member, path in normalized if member.isfile()}
        for name in CHUNK_NAMES:
            path = f"{valid_root}/{name}"
            assert path in by_path, f"Chunk {name} is missing from the final backup archive."
            extracted = tar.extractfile(by_path[path])
            assert extracted is not None, f"Could not read archived chunk {name}."
            assert extracted.read() == EXPECTED_CHUNKS[name], (
                f"Archived chunk {name} does not match /home/user/split_data/{name}."
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
