#!/bin/bash
mkdir -p /logs/verifier

PROJECT=/home/user/project
BACKUP=$(mktemp -d)
cp "$PROJECT/app.json" "$BACKUP/app.json"
cp "$PROJECT/registry.csv" "$BACKUP/registry.csv"
cp -a "$PROJECT/downloads" "$BACKUP/downloads"
if [ -f "$PROJECT/lockfile.csv" ]; then
    cp "$PROJECT/lockfile.csv" "$BACKUP/lockfile.csv"
    HAD_LOCKFILE=1
else
    HAD_LOCKFILE=0
fi

cleanup() {
    cp "$BACKUP/app.json" "$PROJECT/app.json"
    cp "$BACKUP/registry.csv" "$PROJECT/registry.csv"
    rm -rf "$PROJECT/downloads"
    cp -a "$BACKUP/downloads" "$PROJECT/downloads"
    if [ "$HAD_LOCKFILE" = 1 ]; then
        cp "$BACKUP/lockfile.csv" "$PROJECT/lockfile.csv"
    else
        rm -f "$PROJECT/lockfile.csv"
    fi
    rm -rf "$BACKUP"
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import hashlib
import pytest

def get_sha256(filepath):
    sha256 = hashlib.sha256()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            sha256.update(chunk)
    return sha256.hexdigest()

def test_lockfile_exists():
    lockfile_path = "/home/user/project/lockfile.csv"
    assert os.path.isfile(lockfile_path), f"Lockfile {lockfile_path} does not exist. The script failed to generate it."

def test_lockfile_contents():
    lockfile_path = "/home/user/project/lockfile.csv"
    assert os.path.isfile(lockfile_path), "Lockfile not found."

    cl_path = "/home/user/project/downloads/core_logger-1.2.0.tar.gz"
    hc_path = "/home/user/project/downloads/http_client-2.1.0.tar.gz"
    nu_path = "/home/user/project/downloads/network_utils-1.1.0.tar.gz"

    assert os.path.isfile(cl_path), f"Tarball {cl_path} is missing."
    assert os.path.isfile(hc_path), f"Tarball {hc_path} is missing."
    assert os.path.isfile(nu_path), f"Tarball {nu_path} is missing."

    sha_cl = get_sha256(cl_path)
    sha_hc = get_sha256(hc_path)
    sha_nu = get_sha256(nu_path)

    expected_lines = [
        f"core_logger,1.2.0,{sha_cl}",
        f"http_client,2.1.0,{sha_hc}",
        f"network_utils,1.1.0,{sha_nu}"
    ]

    with open(lockfile_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), (
        f"Lockfile has {len(actual_lines)} lines, but expected {len(expected_lines)} lines. "
        f"Actual contents: {actual_lines}"
    )

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, (
            f"Line {i+1} of lockfile is incorrect.\n"
            f"Expected: {expected}\n"
            f"Actual:   {actual}"
        )

def test_resolver_script_executable():
    script_path = "/home/user/project/resolver.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."
TEST_EOF

run_tests() {
    # Preserve all original assertions against the submitted final state.
    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1

    # Confirm the artifact is syntactically a Bash script, then actually execute it
    # from a clean lockfile against the original inputs.
    bash -n "$PROJECT/resolver.sh" || return 1
    rm -f "$PROJECT/lockfile.csv"
    (cd "$PROJECT" && timeout 30 ./resolver.sh) || return 1
    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1

    # Install a randomized registry with the same required behaviors: recursive
    # constraints, conflicting constraints, checksum fallback, and backtracking
    # from a version whose dependency cannot be satisfied.
    python3 - << 'PY_SETUP' || return 1
import csv
import hashlib
import io
import json
import os
import random
import secrets
import tarfile

project = "/home/user/project"
downloads = os.path.join(project, "downloads")
for entry in os.listdir(downloads):
    path = os.path.join(downloads, entry)
    if os.path.isfile(path) or os.path.islink(path):
        os.unlink(path)

suffix = secrets.token_hex(5)
alpha = "alpha_" + suffix
beta = "beta_" + suffix
gamma = "gamma_" + suffix
amaj, bmaj, gmaj = [secrets.randbelow(30) + 3 for _ in range(3)]

def version(major, minor):
    return f"{major}.{minor}.0"

def make_tarball(name, ver):
    path = os.path.join(downloads, f"{name}-{ver}.tar.gz")
    payload = secrets.token_bytes(48)
    info = tarfile.TarInfo(name=f"{name}-{ver}.txt")
    info.size = len(payload)
    with tarfile.open(path, "w:gz") as archive:
        archive.addfile(info, io.BytesIO(payload))
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()

rows = []
def add(name, ver, requires="NONE", corrupt=False):
    digest = make_tarball(name, ver)
    rows.append([name, ver, requires, "0" * 64 if corrupt else digest])

# Highest alpha is corrupt, so alpha must fall back to minor 3.
add(alpha, version(amaj, 0))
add(alpha, version(amaj, 3))
add(alpha, version(amaj, 6), corrupt=True)

# Highest beta is corrupt. The selected beta introduces gamma recursively.
add(beta, version(bmaj, 0), f"{gamma}>={version(gmaj, 0)}")
add(beta, version(bmaj, 4), f"{gamma}>={version(gmaj, 2)}")
add(beta, version(bmaj, 7), f"{gamma}>={version(gmaj, 5)}", corrupt=True)

# gamma minor 5 is checksum-valid but requires an unavailable valid alpha >=5,
# so resolution must fall back to gamma minor 2 and merge its alpha constraint.
add(gamma, version(gmaj, 0))
add(gamma, version(gmaj, 2), f"{alpha}>={version(amaj, 2)}")
add(gamma, version(gmaj, 5), f"{alpha}>={version(amaj, 5)}")

random.SystemRandom().shuffle(rows)
with open(os.path.join(project, "registry.csv"), "w", newline="") as f:
    csv.writer(f, lineterminator="\n").writerows(rows)
with open(os.path.join(project, "app.json"), "w") as f:
    json.dump({"dependencies": {
        alpha: ">=" + version(amaj, 0),
        beta: ">=" + version(bmaj, 0),
    }}, f)
PY_SETUP

    rm -f "$PROJECT/lockfile.csv"
    (cd "$PROJECT" && timeout 30 ./resolver.sh) || return 1

    # Independently derive the unique component-wise highest feasible assignment
    # from the altered registry and compare the complete, sorted lockfile.
    python3 - << 'PY_VERIFY' || return 1
import csv
import hashlib
import itertools
import json
import os
import re

project = "/home/user/project"

def vkey(value):
    return tuple(int(part) for part in value.split("."))

def satisfies(actual, minimum):
    return vkey(actual) >= vkey(minimum)

with open(os.path.join(project, "app.json")) as f:
    direct = json.load(f)["dependencies"]

rows_by_name = {}
with open(os.path.join(project, "registry.csv"), newline="") as f:
    for name, version, requires, recorded_sha in csv.reader(f):
        tarball = os.path.join(project, "downloads", f"{name}-{version}.tar.gz")
        if not os.path.isfile(tarball):
            continue
        with open(tarball, "rb") as tf:
            actual_sha = hashlib.sha256(tf.read()).hexdigest()
        if actual_sha == recorded_sha:
            rows_by_name.setdefault(name, []).append(
                {"name": name, "version": version, "requires": requires,
                 "sha": actual_sha}
            )

names = sorted(rows_by_name)
assert names, "Altered registry unexpectedly has no checksum-valid entries"
feasible = []
for choices in itertools.product(*(rows_by_name[name] for name in names)):
    selected = {row["name"]: row for row in choices}
    ok = True
    for name, constraint in direct.items():
        if name not in selected or not constraint.startswith(">=") or not satisfies(selected[name]["version"], constraint[2:]):
            ok = False
            break
    if not ok:
        continue
    for row in choices:
        req = row["requires"]
        if req == "NONE":
            continue
        match = re.fullmatch(r"(.+)>=(.+)", req)
        if not match or match.group(1) not in selected or not satisfies(selected[match.group(1)]["version"], match.group(2)):
            ok = False
            break
    if ok:
        feasible.append(selected)

assert feasible, "Verifier fixture has no feasible resolution"
maximal = []
for candidate in feasible:
    dominated = False
    for other in feasible:
        if all(vkey(other[n]["version"]) >= vkey(candidate[n]["version"]) for n in names) and any(
            vkey(other[n]["version"]) > vkey(candidate[n]["version"]) for n in names
        ):
            dominated = True
            break
    if not dominated:
        maximal.append(candidate)
assert len(maximal) == 1, "Verifier fixture did not produce a unique highest resolution"
selected = maximal[0]
expected = [f"{name},{selected[name]['version']},{selected[name]['sha']}" for name in names]

lockfile = os.path.join(project, "lockfile.csv")
assert os.path.isfile(lockfile), "Resolver did not generate lockfile.csv on altered inputs"
with open(lockfile) as f:
    actual = [line.strip() for line in f if line.strip()]
assert actual == expected, f"Altered-input lockfile mismatch. Expected {expected}, got {actual}"
PY_VERIFY
}

if run_tests; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
