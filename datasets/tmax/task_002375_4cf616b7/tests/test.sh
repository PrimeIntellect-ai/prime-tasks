#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import time
import uuid
from pathlib import Path

import pytest
import requests

BASE = "http://127.0.0.1:8080"
EXPECTED_EXPORT = [
    {"source": "FactorC", "relation": "activates", "target": "KinaseA"},
    {"source": "KinaseA", "relation": "activates", "target": "ProteaseB"},
    {"source": "KinaseA", "relation": "phosphorylates", "target": "ReceptorD"},
    {"source": "ProteaseB", "relation": "inhibits", "target": "FactorC"},
    {"source": "ReceptorD", "relation": "inhibits", "target": "ProteaseB"},
]


def get(path, params=None):
    url = BASE + path
    try:
        response = requests.get(url, params=params, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {url}: {e}")
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
    assert response.raw.version == 11, "Response was not HTTP/1.1"
    content_type = response.headers.get("Content-Type", "").lower()
    assert content_type.split(";", 1)[0].strip() == "application/json", \
        f"Expected Content-Type application/json, got {content_type!r}"
    try:
        return response.json()
    except ValueError:
        pytest.fail(f"Response from {response.url} is not valid JSON: {response.text}")


def test_ready_file_exists():
    ready_file = "/app/ready.txt"
    assert os.path.isfile(ready_file), f"File {ready_file} does not exist. Did you signal readiness?"
    with open(ready_file, "r") as f:
        content = f.read().strip()
    assert "READY" in content, f"File {ready_file} does not contain 'READY'. Content: {content}"


def test_interactions_kinasea():
    data = get("/interactions", {"protein": "KinaseA"})
    expected = [
        {"relation": "activates", "target": "ProteaseB"},
        {"relation": "phosphorylates", "target": "ReceptorD"},
    ]
    assert data == expected, f"Expected {expected}, got {data}"


def test_interactions_factorc():
    data = get("/interactions", {"protein": "FactorC"})
    expected = [{"relation": "activates", "target": "KinaseA"}]
    assert data == expected, f"Expected {expected}, got {data}"


def test_interactions_empty():
    data = get("/interactions", {"protein": "UnknownProteinX"})
    assert data == [], f"Expected empty array [], got {data}"


def test_export():
    data = get("/export")
    assert data == EXPECTED_EXPORT, f"Expected {EXPECTED_EXPORT}, got {data}"


def test_interactions_for_every_graph_protein():
    """Exercise every source and target, deriving each answer from the verified graph."""
    expected_by_source = {}
    proteins = set()
    for edge in EXPECTED_EXPORT:
        proteins.add(edge["source"])
        proteins.add(edge["target"])
        expected_by_source.setdefault(edge["source"], []).append({
            "relation": edge["relation"],
            "target": edge["target"],
        })

    for protein in sorted(proteins):
        expected = sorted(expected_by_source.get(protein, []), key=lambda x: x["target"])
        actual = get("/interactions", {"protein": protein})
        assert actual == expected, f"For {protein}, expected {expected}, got {actual}"

    unpredictable = "NoSuchProtein_" + uuid.uuid4().hex
    assert get("/interactions", {"protein": unpredictable}) == []


def listening_pids_for_8080():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[1].upper().endswith(":1F90") and fields[3] == "0A":
                inodes.add(fields[9])

    pids = set()
    for proc in Path("/proc").glob("[0-9]*"):
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    pids.add(int(proc.name))
                    break
        except OSError:
            continue
    return pids


def proc_cmdline(pid):
    try:
        raw = Path(f"/proc/{pid}/cmdline").read_bytes()
        return raw.replace(b"\0", b" ").decode("utf-8", "replace").strip()
    except OSError:
        return ""


def proc_parent(pid):
    try:
        for line in Path(f"/proc/{pid}/status").read_text().splitlines():
            if line.startswith("PPid:"):
                return int(line.split()[1])
    except OSError:
        pass
    return 0


def test_server_query_path_is_bash_based():
    """Ensure the live port is backed by Bash rather than a Python/Node query server."""
    pids = listening_pids_for_8080()
    assert pids, "Could not identify a process listening on 127.0.0.1:8080"

    contexts = []
    direct_commands = []
    for pid in pids:
        direct_commands.append(proc_cmdline(pid))
        seen = set()
        while pid > 1 and pid not in seen:
            seen.add(pid)
            cmd = proc_cmdline(pid)
            if cmd:
                contexts.append(cmd)
            pid = proc_parent(pid)

    direct_text = "\n".join(direct_commands)
    assert not re.search(r"(^|[ /])(?:python(?:[0-9.]*)?|node(?:js)?)(?:[ /]|$)", direct_text, re.I), \
        f"The process bound to port 8080 is a forbidden Python/Node server: {direct_text}"

    context_text = "\n".join(contexts)
    referenced_files = set()
    for match in re.finditer(r"/[A-Za-z0-9_.+/-]+", context_text):
        candidate = match.group(0).rstrip(".,:;)")
        if os.path.isfile(candidate):
            referenced_files.add(candidate)

    script_texts = []
    bash_script_found = False
    for filename in referenced_files:
        try:
            content = Path(filename).read_text(errors="replace")
        except OSError:
            continue
        first = content.splitlines()[0] if content.splitlines() else ""
        if re.match(r"^#!.*(?:/|\benv\s+)bash(?:\s|$)", first):
            bash_script_found = True
            script_texts.append(content)

    bash_in_command = bool(re.search(r"(^|[ /])bash(?:[ /]|$)", context_text))
    assert bash_in_command or bash_script_found, \
        f"No Bash query handler was associated with the live server. Process context: {context_text}"

    combined_logic = context_text + "\n" + "\n".join(script_texts)
    noncomment_logic = "\n".join(
        line for line in combined_logic.splitlines() if not line.lstrip().startswith("#")
    )
    assert not re.search(r"\b(?:python(?:[0-9.]*)?|node(?:js)?)\b", noncomment_logic, re.I), \
        "The live Bash server path delegates its query logic to Python or Node.js"
    assert re.search(r"\b(?:awk|gawk|grep|jq|sort)\b", noncomment_logic), \
        "The live Bash server path does not contain the required Unix text-processing query logic"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
