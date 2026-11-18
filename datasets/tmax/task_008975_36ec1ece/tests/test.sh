#!/bin/bash
set +e
mkdir -p /logs/verifier
status=0

# Independently derive the expected artifacts from the supplied archive before
# executing the submission. The resulting oracle is root-only.
python3 - <<'PY'
import base64
import hashlib
import io
import json
import os
import tarfile
import zipfile

master = "/home/user/project_dump/master.zip"
artifacts = {}

def inspect_file(name, data, depth=0):
    if data.startswith(b"\x7fELF"):
        digest = hashlib.sha256(data).hexdigest()
        artifacts[digest + ".elf"] = data
    elif data.startswith((b"\x37\x7f\x06\x82", b"\x37\x7f\x06\x83")):
        digest = hashlib.sha256(data).hexdigest()
        artifacts[digest + ".wal"] = data

    if depth >= 10:
        raise RuntimeError("Archive nesting is unexpectedly deep")

    lower = name.lower()
    if lower.endswith(".zip"):
        with zipfile.ZipFile(io.BytesIO(data), "r") as archive:
            for info in archive.infolist():
                if not info.is_dir():
                    inspect_file(info.filename, archive.read(info), depth + 1)
    elif lower.endswith(".tar.gz"):
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
            for member in archive.getmembers():
                if member.isfile():
                    extracted = archive.extractfile(member)
                    if extracted is None:
                        raise RuntimeError(f"Could not read tar member {member.name}")
                    inspect_file(member.name, extracted.read(), depth + 1)

with open(master, "rb") as f:
    inspect_file(os.path.basename(master), f.read())

payload = {
    "files": {name: base64.b64encode(data).decode("ascii") for name, data in artifacts.items()}
}
with open("/tmp/verifier_expected.json", "w") as f:
    json.dump(payload, f, sort_keys=True)
os.chmod("/tmp/verifier_expected.json", 0o600)
PY
if [ $? -ne 0 ]; then
    status=1
fi

# Require a real Cargo/Rust submission and regenerate the output by executing it.
if [ ! -f /home/user/archive_organizer/Cargo.toml ] || [ ! -f /home/user/archive_organizer/src/main.rs ]; then
    status=1
else
    rm -f /home/user/extracted_artifacts.tar.gz
    rm -rf /tmp/verifier-cargo-target
    mkdir -p /tmp/verifier-cargo-target
    chown user:user /tmp/verifier-cargo-target
    (
        cd /home/user/archive_organizer &&
        timeout 300s runuser -u user -- env HOME=/home/user CARGO_TARGET_DIR=/tmp/verifier-cargo-target cargo run --release
    )
    if [ $? -ne 0 ]; then
        status=1
    fi
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import json
import os
import tarfile
import pytest

OUTPUT = "/home/user/extracted_artifacts.tar.gz"
EXPECTED = "/tmp/verifier_expected.json"


def test_extracted_artifacts_exists():
    """Test that the final extracted_artifacts.tar.gz archive exists."""
    assert os.path.isfile(OUTPUT), (
        f"File {OUTPUT} does not exist. The output archive was not generated."
    )


def test_extracted_artifacts_contents():
    """Verify names, layout, file contents, hashes, and magic signatures."""
    if not os.path.isfile(OUTPUT):
        pytest.skip("Archive not found, skipping content test.")

    with open(EXPECTED, "r") as f:
        encoded = json.load(f)["files"]
    expected_files = {
        name: base64.b64decode(data) for name, data in encoded.items()
    }
    expected_names = set(expected_files)

    with tarfile.open(OUTPUT, "r:gz") as tar:
        members = tar.getmembers()

        # Preserve the original regular-file and flat-layout assertions.
        for member in members:
            assert member.isfile(), (
                f"Archive contains non-file member: {member.name}. "
                "It should only contain files."
            )

        canonical_names = []
        for member in members:
            name = member.name
            if name.startswith("./"):
                name = name[2:]
            assert "/" not in name, (
                f"File '{member.name}' is not in the root of the archive. "
                "The archive must be flat."
            )
            canonical_names.append(name)

        actual_names = set(member.name.split("/")[-1] for member in members)
        assert len(actual_names) == 3, (
            f"Expected exactly 3 files in the archive, found "
            f"{len(actual_names)}: {actual_names}"
        )
        assert actual_names == expected_names, (
            f"Archive contents mismatch. Expected {expected_names}, "
            f"found {actual_names}"
        )
        assert len(members) == len(expected_names), (
            "Archive contains duplicate or extra members"
        )

        for member, name in zip(members, canonical_names):
            stream = tar.extractfile(member)
            assert stream is not None, f"Could not extract archive member {member.name}"
            data = stream.read()

            assert data == expected_files[name], (
                f"Contents of {name} do not match the artifact from master.zip"
            )

            digest, extension = name.rsplit(".", 1)
            assert hashlib.sha256(data).hexdigest() == digest, (
                f"Filename hash for {name} does not match its contents"
            )
            if extension == "elf":
                assert data.startswith(b"\x7fELF"), (
                    f"ELF artifact {name} has the wrong magic number"
                )
            elif extension == "wal":
                assert data.startswith((b"\x37\x7f\x06\x82", b"\x37\x7f\x06\x83")), (
                    f"WAL artifact {name} has the wrong magic number"
                )
            else:
                pytest.fail(f"Unexpected artifact extension in {name}")
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
if [ $? -ne 0 ]; then
    status=1
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
