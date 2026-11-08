#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import stat
import tarfile


def test_curated_artifacts_dir_exists():
    path = "/home/user/curated_artifacts"
    assert os.path.isdir(path), f"Directory does not exist: {path}"


def test_curated_artifacts_files():
    curated_dir = "/home/user/curated_artifacts"
    expected_files = {"alpha.tar.gz", "beta.tar.gz", "delta.tar.gz"}
    for f in expected_files:
        path = os.path.join(curated_dir, f)
        assert os.path.isfile(path), f"Expected curated artifact missing: {path}"
    gamma_path = os.path.join(curated_dir, "gamma.tar.gz")
    assert not os.path.exists(gamma_path), "gamma.tar.gz should have failed validation and not be curated"


def test_alpha_curated_content():
    path = "/home/user/curated_artifacts/alpha.tar.gz"
    assert os.path.isfile(path), f"File missing: {path}"
    with tarfile.open(path, "r:gz") as tar:
        names = tar.getnames()
        assert "metadata.txt" in names, "metadata.txt missing in alpha.tar.gz root"
        assert "payload.bin" in names, "payload.bin missing in alpha.tar.gz root"
        with tar.extractfile("metadata.txt") as f:
            metadata = f.read().decode("utf-8")
            assert "Version: v1.1.0" in metadata, "alpha metadata not correctly updated (Version)"
            assert "Source: https://secure-repo.local/bin" in metadata, "alpha metadata not correctly updated (Source)"
        with tar.extractfile("payload.bin") as f:
            payload = f.read().decode("utf-8")
            assert "binary_data_alpha" in payload, "alpha payload.bin content altered"


def test_beta_curated_content():
    path = "/home/user/curated_artifacts/beta.tar.gz"
    assert os.path.isfile(path), f"File missing: {path}"
    with tarfile.open(path, "r:gz") as tar:
        names = tar.getnames()
        assert "metadata.txt" in names, "metadata.txt missing in beta.tar.gz root"
        assert "payload.bin" in names, "payload.bin missing in beta.tar.gz root"
        with tar.extractfile("metadata.txt") as f:
            metadata = f.read().decode("utf-8")
            assert "Name: beta" in metadata, "beta metadata Name missing"
            assert "STATUS=PUBLISHED" in metadata, "beta metadata not correctly updated (STATUS)"
        with tar.extractfile("payload.bin") as f:
            payload = f.read().decode("utf-8")
            assert "binary_data_beta" in payload, "beta payload.bin content altered"


def test_delta_curated_content():
    path = "/home/user/curated_artifacts/delta.tar.gz"
    assert os.path.isfile(path), f"File missing: {path}"
    with tarfile.open(path, "r:gz") as tar:
        names = tar.getnames()
        assert "metadata.txt" in names, "metadata.txt missing in delta.tar.gz root"
        assert "payload.bin" in names, "payload.bin missing in delta.tar.gz root"
        with tar.extractfile("metadata.txt") as f:
            metadata = f.read().decode("utf-8")
            assert "Name: delta" in metadata, "delta metadata Name missing"
            assert "arch=amd64" in metadata, "delta metadata not correctly updated (arch)"
        with tar.extractfile("payload.bin") as f:
            payload = f.read().decode("utf-8")
            assert "binary_data_delta" in payload, "delta payload.bin content altered"


def test_curation_log():
    log_path = "/home/user/curation_log.txt"
    assert os.path.isfile(log_path), f"Log file missing: {log_path}"
    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    expected_lines = [
        "FAILED: gamma.tar.gz",
        "SUCCESS: alpha.tar.gz",
        "SUCCESS: beta.tar.gz",
        "SUCCESS: delta.tar.gz",
    ]
    assert lines == expected_lines, f"Log file content does not match expected alphabetically sorted output. Got: {lines}"


def _read_manifest(path):
    entries = {}
    with open(path, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.rstrip("\n")
            assert line, "checksums.sha256 contains an empty line"
            parts = line.split(maxsplit=1)
            assert len(parts) == 2, f"Malformed checksum line: {line!r}"
            digest, name = parts
            if name.startswith("*"):
                name = name[1:]
            assert len(digest) == 64 and all(c in "0123456789abcdefABCDEF" for c in digest)
            assert name == os.path.basename(name), f"Unexpected path in checksum manifest: {name}"
            assert name not in entries, f"Duplicate checksum entry: {name}"
            entries[name] = digest.lower()
    return entries


def _archive_contents(path):
    with tarfile.open(path, "r:gz") as tar:
        members = tar.getmembers()
        assert sorted(m.name for m in members) == ["metadata.txt", "payload.bin"], (
            f"{path} must contain exactly metadata.txt and payload.bin at archive root"
        )
        assert all(m.isfile() for m in members), f"{path} contains a non-regular member"
        return {
            name: tar.extractfile(name).read()
            for name in ("metadata.txt", "payload.bin")
        }


def test_exact_end_to_end_curation_from_manifest_and_rules():
    incoming = "/home/user/incoming_artifacts"
    curated = "/home/user/curated_artifacts"
    archive_names = sorted(name for name in os.listdir(incoming) if name.endswith(".tar.gz"))
    assert archive_names == ["alpha.tar.gz", "beta.tar.gz", "delta.tar.gz", "gamma.tar.gz"]

    expected_source = {
        "alpha.tar.gz": {
            "metadata.txt": b"Version: v1.0.0\nSource: http://old-repo.local/bin\n",
            "payload.bin": b"binary_data_alpha\n",
        },
        "beta.tar.gz": {
            "metadata.txt": b"Name: beta\nSTATUS=DRAFT\n",
            "payload.bin": b"binary_data_beta\n",
        },
        "gamma.tar.gz": {
            "metadata.txt": b"Name: gamma\nType: Unknown\n",
            "payload.bin": b"binary_data_gamma\n",
        },
        "delta.tar.gz": {
            "metadata.txt": b"Name: delta\narch=x86\n",
            "payload.bin": b"binary_data_delta\n",
        },
    }
    source_contents = {name: _archive_contents(os.path.join(incoming, name)) for name in archive_names}
    assert source_contents == expected_source, "Incoming artifact contents were altered"

    expected_rules = {
        "alpha": [
            {"search": "v1.0.0", "replace": "v1.1.0"},
            {"search": "http://old-repo.local", "replace": "https://secure-repo.local"},
        ],
        "beta": [{"search": "STATUS=DRAFT", "replace": "STATUS=PUBLISHED"}],
        "delta": [{"search": "arch=x86", "replace": "arch=amd64"}],
    }
    with open("/home/user/curation_rules.json", "r", encoding="utf-8") as f:
        rules = json.load(f)
    assert rules == expected_rules, "curation_rules.json was altered"

    manifest = _read_manifest(os.path.join(incoming, "checksums.sha256"))
    assert set(manifest) == set(archive_names), "Checksum manifest must cover exactly all incoming archives"

    validity = {}
    for name in archive_names:
        path = os.path.join(incoming, name)
        with open(path, "rb") as f:
            data = f.read()
        validity[name] = hashlib.sha256(data).hexdigest() == manifest[name]

    assert validity == {
        "alpha.tar.gz": True,
        "beta.tar.gz": True,
        "delta.tar.gz": True,
        "gamma.tar.gz": False,
    }, "Archive validity was not determined from checksums.sha256 as expected"

    with open(os.path.join(incoming, "gamma.tar.gz"), "rb") as f:
        gamma_data = f.read()
    corruption = b"corrupted\n"
    assert gamma_data.endswith(corruption)
    assert hashlib.sha256(gamma_data[:-len(corruption)]).hexdigest() == manifest["gamma.tar.gz"], (
        "The checksum manifest or intentionally corrupted gamma archive was altered"
    )

    expected_curated = sorted(name for name, valid in validity.items() if valid)
    assert sorted(os.listdir(curated)) == expected_curated, (
        "Curated directory contains missing or unrelated files"
    )

    for name in expected_curated:
        output_path = os.path.join(curated, name)
        mode = os.lstat(output_path).st_mode
        assert stat.S_ISREG(mode), f"Curated artifact is not a regular file: {output_path}"

        actual = _archive_contents(output_path)
        base = name[:-len(".tar.gz")]
        expected_metadata = source_contents[name]["metadata.txt"].decode("utf-8")
        for rule in rules.get(base, []):
            expected_metadata = expected_metadata.replace(rule["search"], rule["replace"])

        assert actual["metadata.txt"] == expected_metadata.encode("utf-8"), (
            f"Exact transformed metadata mismatch for {name}"
        )
        assert actual["payload.bin"] == source_contents[name]["payload.bin"], (
            f"payload.bin was not preserved exactly for {name}"
        )
        for rule in rules.get(base, []):
            if rule["search"] != rule["replace"]:
                assert rule["search"].encode("utf-8") not in actual["metadata.txt"], (
                    f"Replaced text remains in {name}"
                )

    expected_log_lines = sorted(
        ("SUCCESS: " if validity[name] else "FAILED: ") + name
        for name in archive_names
    )
    with open("/home/user/curation_log.txt", "rb") as f:
        actual_log = f.read()
    assert actual_log == ("\n".join(expected_log_lines) + "\n").encode("utf-8"), (
        "Log must contain exactly one correctly sorted checksum-derived line per archive"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
