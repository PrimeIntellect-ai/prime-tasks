#!/bin/bash
mkdir -p /logs/verifier
reward=0
finish() {
    printf '%s\n' "$reward" > /logs/verifier/reward.txt
}
trap finish EXIT

SCRIPT=/home/user/curate_artifacts.sh
CORRUPT=/home/user/corrupt.list
REGISTRY=/home/user/registry.csv

# First, remove any precomputed outputs and execute the submitted artifact against
# the original repository fixture.
rm -f "$CORRUPT" "$REGISTRY"
if ! timeout 30s runuser -u user -- bash -n "$SCRIPT"; then
    echo "Submitted script is missing or is not valid Bash." >&2
    exit 0
fi
if ! timeout 30s runuser -u user -- bash "$SCRIPT"; then
    echo "Submitted script failed on the original repository." >&2
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_original_state.py
import os
import re


def test_corrupt_list():
    corrupt_file = "/home/user/corrupt.list"
    assert os.path.exists(corrupt_file), f"File {corrupt_file} does not exist. The script should have generated it."

    with open(corrupt_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_corrupt = {
        "/home/user/repo_raw/group_alpha/sub1/corrupt-app.tar.gz",
        "/home/user/repo_raw/group_beta/broken.tar.gz"
    }

    assert set(lines) == expected_corrupt, f"Contents of {corrupt_file} do not match expected corrupt archives. Found: {lines}"
    assert len(lines) == len(expected_corrupt), f"{corrupt_file} has duplicate or extra lines."


def test_registry_csv():
    registry_file = "/home/user/registry.csv"
    assert os.path.exists(registry_file), f"File {registry_file} does not exist. The script should have generated it."

    with open(registry_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_registry = {
        "/home/user/repo_raw/group_alpha/sub1/app-v1.tar.gz,core-infra,release",
        "/home/user/repo_raw/group_beta/data-sync.tar.gz,data-eng,production",
        "/home/user/repo_raw/group_beta/data-verify.tar.gz,security,staging"
    }

    assert set(lines) == expected_registry, f"Contents of {registry_file} do not match expected registry entries. Found: {lines}"
    assert len(lines) == len(expected_registry), f"{registry_file} has duplicate or extra lines."


def test_script_uses_flock():
    script_file = "/home/user/curate_artifacts.sh"
    assert os.path.exists(script_file), f"Script {script_file} does not exist."

    with open(script_file, "r") as f:
        content = f.read()

    assert "flock" in content, f"Script {script_file} must use 'flock' to ensure thread-safe appending."

    active = "\n".join(line for line in content.splitlines()
                       if not line.lstrip().startswith("#"))
    assert re.search(r"(?:^|[\s;|&(])(?:/[^\s;|&]*/)?flock(?:\s|$)", active), \
        "flock must appear as a command, not only in a comment."

    uses_xargs_parallel = re.search(r"\bxargs\b[^\n]*?(?:-P\s*\d*|--max-procs(?:=|\s))", active)
    backgrounds_jobs = re.search(r"(?:^|[;\s])&\s*(?:$|#)", active, re.MULTILINE)
    waits_for_jobs = re.search(r"(?:^|[\s;])wait(?:\s|;|$)", active)
    assert uses_xargs_parallel or (backgrounds_jobs and waits_for_jobs), \
        "The script must process work concurrently and wait for background jobs."
TEST_EOF

if ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_original_state.py -x --tb=short; then
    exit 0
fi

# Add an unpredictable nested corpus after the agent has finished. Archive names,
# validity, and metadata are generated here, so fixture-specific hardcoding cannot
# satisfy this phase.
if ! python3 << 'PY'
import io
import json
import os
import random
import secrets
import tarfile

root = "/home/user/repo_raw"
token = secrets.token_hex(8)
rng = random.SystemRandom()
directories = [
    os.path.join(root, "generated_" + token, "level1", "level2"),
    os.path.join(root, "generated_" + token, "other"),
]
for directory in directories:
    os.makedirs(directory, exist_ok=True)

expected_corrupt = {
    "/home/user/repo_raw/group_alpha/sub1/corrupt-app.tar.gz",
    "/home/user/repo_raw/group_beta/broken.tar.gz",
}
expected_registry = {
    "/home/user/repo_raw/group_alpha/sub1/app-v1.tar.gz,core-infra,release",
    "/home/user/repo_raw/group_beta/data-sync.tar.gz,data-eng,production",
    "/home/user/repo_raw/group_beta/data-verify.tar.gz,security,staging",
}

records_by_dir = {directory: [] for directory in directories}
validity = [True] * 6 + [False] * 4
rng.shuffle(validity)

for index, is_valid in enumerate(validity):
    directory = directories[index % len(directories)]
    archive_name = secrets.token_hex(7) + ".tar.gz"
    archive_path = os.path.join(directory, archive_name)
    team = "team-" + secrets.token_hex(4)
    stage = "stage-" + secrets.token_hex(4)

    if is_valid:
        payload = ("payload-" + secrets.token_hex(24)).encode()
        with tarfile.open(archive_path, "w:gz") as tf:
            info = tarfile.TarInfo("payload-" + secrets.token_hex(3) + ".bin")
            info.size = len(payload)
            tf.addfile(info, io.BytesIO(payload))
        expected_registry.add(f"{archive_path},{team},{stage}")
    else:
        with open(archive_path, "wb") as f:
            f.write(os.urandom(1500 + rng.randrange(1500)))
        expected_corrupt.add(archive_path)

    records_by_dir[directory].append((archive_name, team, stage))

for directory, records in records_by_dir.items():
    rng.shuffle(records)
    with open(os.path.join(directory, "publish.log"), "w") as log:
        for archive_name, team, stage in records:
            log.write("---\n")
            log.write(f"Archive: {archive_name}\n")
            log.write(f"Team: {team}\n")
            log.write(f"Stage: {stage}\n")
            log.write("Notes: generated verifier record\n")
            log.write("Additional unstructured note line\n")
        log.write("---\n")

with open("/tmp/generated_expectations.json", "w") as f:
    json.dump({
        "corrupt": sorted(expected_corrupt),
        "registry": sorted(expected_registry),
    }, f)
PY
then
    echo "Failed to construct dynamic verification corpus." >&2
    exit 0
fi

chown -R user:user /home/user/repo_raw
rm -f "$CORRUPT" "$REGISTRY"
if ! timeout 45s runuser -u user -- bash "$SCRIPT"; then
    echo "Submitted script failed on the dynamic repository." >&2
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_dynamic_state.py
import json
import os

with open("/tmp/generated_expectations.json") as f:
    EXPECTED = json.load(f)


def nonempty_lines(path):
    assert os.path.isfile(path), f"Required output file {path} was not generated."
    with open(path) as f:
        return [line.strip() for line in f if line.strip()]


def test_dynamic_corrupt_list():
    lines = nonempty_lines("/home/user/corrupt.list")
    expected = set(EXPECTED["corrupt"])
    assert set(lines) == expected, f"Incorrect corrupt archive list: {lines}"
    assert len(lines) == len(expected), "corrupt.list contains duplicate or extra lines"


def test_dynamic_registry():
    lines = nonempty_lines("/home/user/registry.csv")
    expected = set(EXPECTED["registry"])
    assert set(lines) == expected, f"Incorrect registry entries: {lines}"
    assert len(lines) == len(expected), "registry.csv contains duplicate or extra lines"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_dynamic_state.py -x --tb=short; then
    reward=1
fi
exit 0
