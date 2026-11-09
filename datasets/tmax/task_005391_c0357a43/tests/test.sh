#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import hashlib
import os
import stat


def test_artifact_hasher_script_exists():
    path = "/home/user/build_tools/artifact_hasher.py"
    assert os.path.isfile(path), f"Expected Python script {path} does not exist."


def test_test_hasher_script_exists():
    path = "/home/user/build_tools/test_hasher.py"
    assert os.path.isfile(path), f"Expected pytest suite {path} does not exist."


def test_ci_pipeline_script():
    path = "/home/user/ci_pipeline.sh"
    assert os.path.isfile(path), f"CI pipeline script {path} does not exist."

    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"CI pipeline script {path} is not executable."

    with open(path, 'r') as f:
        content = f.read()

    assert "set -e" in content, f"CI pipeline script {path} does not contain 'set -e'."
    assert "pytest" in content, f"CI pipeline script {path} does not run pytest."
    assert "/home/user/build_tools/artifact_hasher.py" in content, f"CI pipeline script {path} does not run the artifact_hasher.py script."
    assert "--dir" in content and "/home/user/artifacts" in content, f"CI pipeline script {path} does not pass the correct --dir argument."


def test_bundle_manifest_content():
    manifest_path = "/home/user/artifacts/bundle.manifest"
    assert os.path.isfile(manifest_path), f"Manifest file {manifest_path} was not generated."

    canonical_artifacts = {
        "app-v1.0.tar.gz": b"dummy data 1\n",
        "library.jar": b"another artifact here\n",
        "metadata.json": b"meta information\n",
    }
    concatenated = "".join(
        hashlib.sha256(canonical_artifacts[name]).hexdigest()
        for name in sorted(canonical_artifacts)
    )
    expected_hash = hashlib.sha256(concatenated.encode("utf-8")).hexdigest()

    with open(manifest_path, 'r') as f:
        actual_hash = f.read().strip()

    assert actual_hash == expected_hash, f"Bundle manifest hash is incorrect. Expected {expected_hash}, got {actual_hash}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
