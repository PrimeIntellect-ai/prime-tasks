#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import struct
import subprocess
import tempfile
import pytest

REPO = "/home/user/db-exporter"
EXPECTED = "/home/user/expected.bin"
OUTPUT = os.path.join(REPO, "output.bin")
BINARY = os.path.join(REPO, "target/release/db-exporter")


def git(*args):
    return subprocess.run(
        ["git", *args], cwd=REPO, capture_output=True, text=True, check=True
    ).stdout.strip()


def test_bad_commit_hash_identified():
    bad_commit_path = "/home/user/bad_commit.txt"
    assert os.path.isfile(bad_commit_path), f"File {bad_commit_path} does not exist."

    with open(bad_commit_path, "r") as f:
        commit_hash = f.read().strip()

    assert len(commit_hash) == 40, (
        f"Expected a 40-character commit hash, got '{commit_hash}' "
        f"(length {len(commit_hash)})."
    )

    try:
        commit_message = git("log", "--format=%s", "-n", "1", commit_hash)
        assert commit_message == "Commit 137", (
            f"The identified commit is '{commit_message}', expected 'Commit 137'."
        )

        matching = []
        for line in git("log", "--all", "--format=%H%x09%s").splitlines():
            candidate, subject = line.split("\t", 1)
            if subject == "Commit 137":
                matching.append(candidate)
        assert matching == [commit_hash], (
            "bad_commit.txt must contain the hash of the repository's original "
            "Commit 137."
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to retrieve git commit information: {e.stderr}")


def test_repository_remains_at_current_history():
    commits_200 = []
    for line in git("log", "--all", "--format=%H%x09%s").splitlines():
        candidate, subject = line.split("\t", 1)
        if subject == "Commit 200":
            commits_200.append(candidate)
    assert len(commits_200) == 1, "Could not uniquely identify the original Commit 200."
    result = subprocess.run(
        ["git", "merge-base", "--is-ancestor", commits_200[0], "HEAD"], cwd=REPO
    )
    assert result.returncode == 0, (
        "The repository is not at the original current HEAD or a descendant of it."
    )


def canonical_output():
    values = ["Hello, World!", "こんにちは世界", "Rustaceans 🦀"]
    data = bytearray(struct.pack("<I", len(values)))
    for value in values:
        encoded = value.encode("utf-8")
        data.extend(struct.pack("<I", len(encoded)))
        data.extend(encoded)
    return bytes(data)


def test_output_bin_matches_expected_after_release_rebuild_and_execution():
    assert os.path.isfile(EXPECTED), f"File {EXPECTED} does not exist."
    with open(EXPECTED, "rb") as f:
        expected_data = f.read()

    derived_data = canonical_output()
    assert expected_data == derived_data, "The shipped reference does not match the format specification."

    hidden_dir = tempfile.mkdtemp(prefix="db-exporter-oracle-", dir="/root")
    os.chmod(hidden_dir, 0o700)
    hidden_expected = os.path.join(hidden_dir, "expected.bin")
    generated_data = None

    try:
        # Prevent the submitted build or executable from copying the reference file.
        os.replace(EXPECTED, hidden_expected)

        release_dir = os.path.join(REPO, "target", "release")
        if os.path.lexists(release_dir):
            if os.path.isdir(release_dir) and not os.path.islink(release_dir):
                shutil.rmtree(release_dir)
            else:
                os.unlink(release_dir)
        os.makedirs(os.path.join(REPO, "target"), exist_ok=True)
        os.chmod(os.path.join(REPO, "target"), 0o777)

        env = os.environ.copy()
        env["HOME"] = "/home/user"
        build = subprocess.run(
            ["runuser", "-u", "user", "--", "/usr/bin/cargo", "build", "--release"],
            cwd=REPO,
            capture_output=True,
            text=True,
            timeout=180,
            env=env,
        )
        assert build.returncode == 0, (
            "cargo build --release failed:\n" + build.stdout + build.stderr
        )

        assert os.path.isfile(BINARY), "The release build did not create the db-exporter executable."
        assert not os.path.islink(BINARY), "The release executable must not be a symbolic link."
        assert os.access(BINARY, os.X_OK), "The release db-exporter artifact is not executable."
        with open(BINARY, "rb") as f:
            assert f.read(4) == b"\x7fELF", "The release artifact is not an ELF executable."

        if os.path.lexists(OUTPUT):
            if os.path.isdir(OUTPUT) and not os.path.islink(OUTPUT):
                shutil.rmtree(OUTPUT)
            else:
                os.unlink(OUTPUT)

        run = subprocess.run(
            ["runuser", "-u", "user", "--", BINARY, "export"],
            cwd=REPO,
            capture_output=True,
            text=True,
            timeout=30,
            env=env,
        )
        assert run.returncode == 0, (
            "The release exporter failed:\n" + run.stdout + run.stderr
        )
        assert os.path.isfile(OUTPUT), f"File {OUTPUT} was not generated by the export command."
        with open(OUTPUT, "rb") as f:
            generated_data = f.read()
    finally:
        if os.path.exists(hidden_expected):
            os.replace(hidden_expected, EXPECTED)
        shutil.rmtree(hidden_dir, ignore_errors=True)

    assert generated_data == expected_data, f"The generated {OUTPUT} does not match {EXPECTED}."
    assert generated_data == derived_data, "The generated output does not use UTF-8 byte lengths."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
