#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import shutil
import stat
import subprocess
import uuid

RAW_DIR = "/home/user/raw_configs"
JSON_PATH = "/home/user/config_inventory.json"
LOG_PATH = "/home/user/pipeline.log"


def test_json_output():
    assert os.path.isfile(JSON_PATH), f"Output file {JSON_PATH} is missing."

    with open(JSON_PATH, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{JSON_PATH} is not a valid JSON file."

    assert "clusters" in data, "JSON missing 'clusters' key."
    clusters = data["clusters"]
    assert isinstance(clusters, list), "'clusters' must be a list."
    assert len(clusters) == 3, f"Expected 3 clusters, found {len(clusters)}."

    expected_clusters = [
        {
            "representative": "beta.conf",
            "members": ["alpha.conf", "beta.conf"]
        },
        {
            "representative": "epsilon.cfg",
            "members": ["epsilon.cfg"]
        },
        {
            "representative": "gamma.cfg",
            "members": ["delta.cfg", "gamma.cfg"]
        }
    ]

    representatives = [c.get("representative") for c in clusters]
    assert representatives == sorted(representatives), "Clusters are not sorted alphabetically by representative."

    for c in clusters:
        members = c.get("members", [])
        assert members == sorted(members), f"Members in cluster {c.get('representative')} are not sorted alphabetically."

    assert clusters == expected_clusters, f"Clusters do not match expected output. Got: {clusters}"


def test_log_output():
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} is missing."

    with open(LOG_PATH, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_reads = {
        "[READ] alpha.conf",
        "[READ] beta.conf",
        "[READ] gamma.cfg",
        "[READ] delta.cfg",
        "[READ] epsilon.cfg"
    }

    actual_reads = set(line for line in lines if line.startswith("[READ]"))
    missing_reads = expected_reads - actual_reads
    assert not missing_reads, f"Missing [READ] logs for: {missing_reads}"

    cluster_lines = [line for line in lines if line.startswith("[CLUSTER]")]
    assert len(cluster_lines) >= 1, "Missing [CLUSTER] log line."
    assert cluster_lines[-1] == "[CLUSTER] Found 3 clusters", f"Expected '[CLUSTER] Found 3 clusters' at the end of clustering, got '{cluster_lines[-1]}'."


def decode_config(raw):
    if raw.startswith(b"\xff\xfe") or (len(raw) >= 4 and raw[1::2].count(0) > len(raw[1::2]) // 2):
        return raw.decode("utf-16le").lstrip("\ufeff")
    if raw.startswith(b"\xfe\xff"):
        return raw.decode("utf-16be").lstrip("\ufeff")
    try:
        return raw.decode("utf-8-sig")
    except UnicodeDecodeError:
        return raw.decode("iso-8859-1")


def normalize(raw):
    result = []
    for line in decode_config(raw).splitlines():
        if line.lstrip().startswith("#"):
            continue
        if line == "":
            continue
        result.append(line.strip().lower())
    return "\n".join(result)


def levenshtein(a, b):
    if len(a) < len(b):
        a, b = b, a
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(current[-1] + 1, previous[j] + 1, previous[j - 1] + (ca != cb)))
        previous = current
    return previous[-1]


def derive_expected():
    names = sorted(name for name in os.listdir(RAW_DIR) if os.path.isfile(os.path.join(RAW_DIR, name)))
    raw = {name: open(os.path.join(RAW_DIR, name), "rb").read() for name in names}
    normalized = {name: normalize(content) for name, content in raw.items()}

    parent = {name: name for name in names}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[rb] = ra

    for i, first in enumerate(names):
        for second in names[i + 1:]:
            if levenshtein(normalized[first], normalized[second]) <= 15:
                union(first, second)

    groups = {}
    for name in names:
        groups.setdefault(find(name), []).append(name)

    clusters = []
    for members in groups.values():
        members.sort()
        representative = min(members, key=lambda name: (-len(raw[name]), name))
        clusters.append({"representative": representative, "members": members})
    clusters.sort(key=lambda cluster: cluster["representative"])
    return {"clusters": clusters}


def candidate_commands():
    candidates = []
    excluded = {JSON_PATH, LOG_PATH}
    interpreters = {
        ".py": ["python3"],
        ".sh": ["bash"],
        ".pl": ["perl"],
        ".rb": ["ruby"],
        ".js": ["node"],
        ".php": ["php"]
    }

    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if not d.startswith(".") and d != "raw_configs" and d != "__pycache__"]
        for filename in files:
            path = os.path.join(root, filename)
            if path in excluded or any(part.startswith(".") for part in os.path.relpath(path, "/home/user").split(os.sep)):
                continue
            try:
                if not os.path.isfile(path) or os.path.getsize(path) > 5_000_000:
                    continue
                with open(path, "rb") as f:
                    prefix = f.read(4096)
            except OSError:
                continue

            ext = os.path.splitext(filename)[1].lower()
            command = None
            if ext in interpreters and shutil.which(interpreters[ext][0]):
                command = interpreters[ext] + [path]
            elif prefix.startswith(b"#!") and os.access(path, os.X_OK):
                command = [path]
            elif os.access(path, os.X_OK) and not prefix.startswith(b"{\n"):
                command = [path]
            elif not ext:
                try:
                    source = open(path, "r", encoding="utf-8").read()
                    ast.parse(source)
                    command = ["python3", path]
                except (OSError, UnicodeDecodeError, SyntaxError):
                    pass

            if command:
                priority = 0 if any(word in filename.lower() for word in ("pipeline", "solution", "main", "config")) else 1
                candidates.append((priority, path, command))

    candidates.sort(key=lambda item: (item[0], item[1]))
    return [command for _, _, command in candidates]


def install_dynamic_fixture(token):
    shutil.rmtree(RAW_DIR, ignore_errors=True)
    os.makedirs(RAW_DIR, exist_ok=True)

    files = {
        f"{token}_alpha.conf": ("# generated comment\nservice=" + token + "\nport=4100\n").encode("utf-8"),
        f"{token}_beta.conf": ("# much longer generated comment\nservice=" + token + "x\nport=4100\n").encode("utf-16le"),
        f"{token}_gamma.cfg": ("# commentaire étendu\ndatabase=café_" + token + "\nmode=active\n").encode("iso-8859-1"),
        f"{token}_delta.cfg": ("database=café_" + token + "\nmode=active\n").encode("utf-8"),
        f"{token}_unrelated.cfg": ("feature=totally_different_" + token[::-1] + "\nlimit=999999\n").encode("utf-8")
    }
    for name, content in files.items():
        with open(os.path.join(RAW_DIR, name), "wb") as f:
            f.write(content)


def dynamic_result_is_valid(expected):
    if not os.path.isfile(JSON_PATH) or not os.path.isfile(LOG_PATH):
        return False
    try:
        with open(JSON_PATH, "r", encoding="utf-8") as f:
            actual = json.load(f)
        if actual != expected:
            return False
        clusters = actual["clusters"]
        if [c["representative"] for c in clusters] != sorted(c["representative"] for c in clusters):
            return False
        if any(c["members"] != sorted(c["members"]) for c in clusters):
            return False
        with open(LOG_PATH, "r", encoding="utf-8") as f:
            lines = [line.strip() for line in f if line.strip()]
    except (OSError, ValueError, KeyError, TypeError):
        return False

    names = set(os.listdir(RAW_DIR))
    reads = {line[7:] for line in lines if line.startswith("[READ] ")}
    if not names.issubset(reads):
        return False
    cluster_lines = [line for line in lines if line.startswith("[CLUSTER]")]
    return bool(cluster_lines) and cluster_lines[-1] == f"[CLUSTER] Found {len(expected['clusters'])} clusters"


def test_pipeline_executes_on_unseen_inputs():
    commands = candidate_commands()
    assert commands, "No runnable pipeline implementation was found under /home/user."

    token = uuid.uuid4().hex[:12]
    errors = []
    for command in commands:
        install_dynamic_fixture(token)
        for path in (JSON_PATH, LOG_PATH):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

        expected = derive_expected()
        try:
            completed = subprocess.run(command, cwd="/home/user", stdout=subprocess.PIPE,
                                       stderr=subprocess.PIPE, text=True, timeout=20)
            if completed.returncode == 0 and dynamic_result_is_valid(expected):
                return
            errors.append(f"{' '.join(command)} exited {completed.returncode}")
        except (OSError, subprocess.TimeoutExpired) as exc:
            errors.append(f"{' '.join(command)}: {exc}")

    assert False, "No submitted pipeline produced correct output for unseen inputs. " + "; ".join(errors[:8])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
