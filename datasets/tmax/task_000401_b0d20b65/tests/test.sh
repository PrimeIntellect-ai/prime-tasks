#!/bin/bash
set -u
mkdir -p /logs/verifier

# Ensure the submitted artifact, rather than a previously running server, owns port 8000.
python3 - <<'PY'
import os
import signal

inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(table, "r", encoding="utf-8") as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) >= 10 and fields[1].upper().endswith(":1F40") and fields[3] == "0A":
                    inodes.add(fields[9])
    except OSError:
        pass

for pid in os.listdir("/proc"):
    if not pid.isdigit() or int(pid) == os.getpid():
        continue
    fd_dir = f"/proc/{pid}/fd"
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(os.path.join(fd_dir, fd))
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                try:
                    os.kill(int(pid), signal.SIGTERM)
                except (ProcessLookupError, PermissionError):
                    pass
                break
    except OSError:
        pass
PY
sleep 1

python3 /home/user/organizer_api.py >/tmp/organizer_api.log 2>&1 &
API_PID=$!
trap 'kill "$API_PID" 2>/dev/null || true; wait "$API_PID" 2>/dev/null || true' EXIT
sleep 2

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import itertools
import json
import os
import re
import tempfile
from functools import lru_cache

import requests


def get_dependencies(directory):
    files = glob.glob(os.path.join(directory, "*.py"))
    basenames = [os.path.basename(f) for f in files]
    modules_in_dir = [os.path.splitext(b)[0] for b in basenames]

    deps = {}
    for fpath in files:
        bname = os.path.basename(fpath)
        deps[bname] = []
        with open(fpath, "r", encoding="utf-8") as f:
            for line in f:
                match = re.match(r"^\s*import\s+([a-zA-Z0-9_]+)", line)
                if match:
                    imported = match.group(1)
                    if imported in modules_in_dir:
                        deps[bname].append(imported + ".py")
    return deps


def optimum_intra_edges(deps):
    names = sorted(deps)
    index = {name: i for i, name in enumerate(names)}
    edges = [(index[src], index[dst]) for src, dsts in deps.items() for dst in dsts]
    groups_by_vertex = [[] for _ in names]

    for size in (2, 3):
        for group in itertools.combinations(range(len(names)), size):
            group_set = set(group)
            weight = sum(1 for src, dst in edges if src in group_set and dst in group_set)
            if weight:
                bits = sum(1 << i for i in group)
                for i in group:
                    groups_by_vertex[i].append((bits, weight))

    @lru_cache(None)
    def solve(remaining):
        if not remaining:
            return 0
        first_bit = remaining & -remaining
        first = first_bit.bit_length() - 1
        best = solve(remaining ^ first_bit)  # singleton
        for bits, weight in groups_by_vertex[first]:
            if bits & remaining == bits:
                best = max(best, weight + solve(remaining ^ bits))
        return best

    return solve((1 << len(names)) - 1)


def request_and_validate(target_dir, require_threshold=False):
    try:
        resp = requests.post(
            "http://localhost:8000/organize",
            json={"dir": target_dir},
            timeout=10,
        )
    except requests.exceptions.RequestException as e:
        assert False, f"Failed to connect to API on port 8000: {e}"

    assert resp.status_code == 200, (
        f"Expected status code 200, got {resp.status_code}. Response: {resp.text}"
    )

    try:
        data = resp.json()
    except (json.JSONDecodeError, requests.exceptions.JSONDecodeError):
        assert False, f"Response is not valid JSON: {resp.text}"

    assert "score" in data, "Response JSON missing 'score' key."
    assert "modules" in data, "Response JSON missing 'modules' key."
    assert isinstance(data["modules"], dict), "'modules' must be a JSON object."

    modules = data["modules"]
    flattened = []

    # Preserve the max-three-files assertion and validate the response structure.
    for mod_name, files in modules.items():
        assert isinstance(files, list), f"Module '{mod_name}' is not represented by a list."
        assert len(files) <= 3, f"Module '{mod_name}' exceeds 3 files limit: {files}"
        assert all(isinstance(name, str) for name in files), f"Module '{mod_name}' has invalid filenames."
        flattened.extend(files)

    all_target_files = set(
        os.path.basename(f) for f in glob.glob(os.path.join(target_dir, "*.py"))
    )
    all_assigned_files = set(flattened)

    # Preserve the original coverage assertion, then require an actual partition:
    # no omitted, unknown, or multiply assigned files.
    assert all_target_files.issubset(all_assigned_files), (
        "Not all files in the directory were assigned to a module."
    )
    assert all_assigned_files == all_target_files, "Response assigned unknown files."
    assert len(flattened) == len(all_target_files), (
        "Each target file must occur in exactly one module."
    )

    deps = get_dependencies(target_dir)
    total_edges = sum(len(d) for d in deps.values())
    intra_edges = 0
    for files in modules.values():
        files_set = set(files)
        for filename in files:
            if filename in deps:
                for imported in deps[filename]:
                    if imported in files_set:
                        intra_edges += 1

    real_score = 1.0 if total_edges == 0 else intra_edges / total_edges
    agent_score = data["score"]
    assert isinstance(agent_score, (int, float)) and not isinstance(agent_score, bool), (
        "'score' must be numeric."
    )
    assert abs(agent_score - real_score) < 0.01, (
        f"Agent reported score {agent_score}, but recalculated score is {real_score}."
    )

    optimum = optimum_intra_edges(deps)
    optimum_score = 1.0 if total_edges == 0 else optimum / total_edges
    assert intra_edges == optimum, (
        f"Returned partition has score {real_score}, but the maximum is {optimum_score}."
    )

    if require_threshold:
        assert real_score >= 0.80, (
            f"Modularity score {real_score} is below the required threshold of 0.80."
        )


def make_project(file_stems, edges):
    directory = tempfile.mkdtemp(prefix="organizer_verifier_")
    for stem in file_stems:
        with open(os.path.join(directory, stem + ".py"), "w", encoding="utf-8") as f:
            for target in edges.get(stem, []):
                f.write(f"import {target}\n")
            if not edges.get(stem):
                f.write("# no imports\n")
    return directory


def test_required_artifacts_exist():
    assert os.path.isfile("/home/user/organizer_api.py"), "organizer_api.py is missing."
    assert os.path.isfile("/home/user/test_api.py"), "test_api.py is missing."


def test_original_eval_project():
    request_and_validate("/app/eval_project/", require_threshold=True)


def test_generic_nontrivial_project():
    stems = ["amber", "birch", "cedar", "dahlia", "elm", "fir", "ginger", "hazel"]
    edges = {
        "amber": ["birch", "cedar"],
        "birch": ["cedar", "dahlia"],
        "cedar": ["dahlia"],
        "dahlia": ["elm"],
        "elm": ["fir", "ginger"],
        "fir": ["ginger"],
        "ginger": ["hazel"],
    }
    request_and_validate(make_project(stems, edges))


def test_generic_zero_edge_project():
    stems = ["quartz", "raven", "spruce", "tulip", "umber", "violet"]
    request_and_validate(make_project(stems, {}))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
