#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import sqlite3
import time
from collections import deque

import pytest
import requests

URL = "http://127.0.0.1:8080/citation-path"
DB = "/app/citations.db"


def get_response():
    response = None
    for i in range(5):
        try:
            response = requests.get(URL, timeout=2)
            break
        except requests.exceptions.RequestException:
            if i == 4:
                pytest.fail(
                    f"Failed to connect to {URL} after 5 attempts. Ensure the web service is running on 127.0.0.1:8080."
                )
            time.sleep(1)

    assert response.status_code == 200, f"Expected HTTP status 200, got {response.status_code}"
    content_type = response.headers.get("Content-Type", "")
    assert "application/json" in content_type, f"Expected Content-Type application/json, got {content_type}"
    try:
        return response.json()
    except ValueError:
        pytest.fail("Response body is not valid JSON.")


def listener_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    result = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    result.append(int(name))
                    break
        except OSError:
            pass
    return result


def running_service_text():
    pids = listener_pids(8080)
    assert pids, "No process is listening on port 8080"

    texts = []
    python_service = False
    for pid in pids:
        proc = f"/proc/{pid}"
        try:
            exe = os.path.basename(os.readlink(f"{proc}/exe")).lower()
            raw = open(f"{proc}/cmdline", "rb").read()
            args = [x.decode(errors="replace") for x in raw.split(b"\0") if x]
            cwd = os.readlink(f"{proc}/cwd")
        except OSError:
            continue

        joined = " ".join(args)
        if "python" in exe or any(x in joined.lower() for x in ("flask", "gunicorn", "uvicorn")):
            python_service = True

        if "-c" in args:
            idx = args.index("-c")
            if idx + 1 < len(args):
                texts.append(args[idx + 1])

        candidates = set()
        for arg in args:
            value = arg.split(":", 1)[0]
            if value.endswith((".py", ".sql")):
                candidates.add(value if os.path.isabs(value) else os.path.join(cwd, value))
            elif ":" in arg and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_.]*", value):
                candidates.add(os.path.join(cwd, value.replace(".", "/") + ".py"))

        try:
            env = open(f"{proc}/environ", "rb").read().split(b"\0")
            for item in env:
                if item.startswith(b"FLASK_APP="):
                    value = item.split(b"=", 1)[1].decode(errors="replace").split(":", 1)[0]
                    if not value.endswith(".py"):
                        value = value.replace(".", "/") + ".py"
                    candidates.add(value if os.path.isabs(value) else os.path.join(cwd, value))
        except OSError:
            pass

        source_dirs = set()
        for path in list(candidates):
            if os.path.isfile(path):
                source_dirs.add(os.path.dirname(path))
                try:
                    texts.append(open(path, errors="replace").read())
                except OSError:
                    pass
        for directory in source_dirs:
            try:
                for name in os.listdir(directory):
                    if name.endswith(".sql"):
                        try:
                            texts.append(open(os.path.join(directory, name), errors="replace").read())
                        except OSError:
                            pass
            except OSError:
                pass

    assert python_service, "The process serving port 8080 is not a Python HTTP service"
    assert texts, "Could not find readable source code for the running Python service"
    return "\n".join(texts)


def shortest_path_from_db(conn, source, target):
    edges = {}
    for a, b in conn.execute("SELECT source_id, target_id FROM citations"):
        edges.setdefault(a, []).append(b)

    queue = deque([(source, [source])])
    seen = {source}
    while queue:
        node, path = queue.popleft()
        if node == target:
            return path
        for nxt in edges.get(node, []):
            if nxt not in seen:
                seen.add(nxt)
                queue.append((nxt, path + [nxt]))
    return None


def test_citation_path_endpoint_and_implementation():
    # Preserve all original endpoint assertions.
    data = get_response()
    assert data.get("source_id") == 105, f"Expected source_id 105, got {data.get('source_id')}"
    assert data.get("target_id") == 402, f"Expected target_id 402, got {data.get('target_id')}"
    assert data.get("path_length") == 3, f"Expected path_length 3, got {data.get('path_length')}"

    expected_path = [
        {"step": 1, "id": 105, "title": "Graph Theory Basics"},
        {"step": 2, "id": 210, "title": "Advanced Network Analysis"},
        {"step": 3, "id": 315, "title": "Citation Dynamics"},
        {"step": 4, "id": 402, "title": "Predictive Modeling in Academia"},
    ]
    assert data.get("path") == expected_path, f"Expected path {expected_path}, got {data.get('path')}"

    # The running implementation must contain the requested recursive SQLite query.
    service_text = running_service_text()
    assert re.search(r"\bWITH\s+RECURSIVE\b", service_text, re.IGNORECASE), "The running service does not contain a WITH RECURSIVE query"
    assert "citations.db" in service_text, "The running service does not reference citations.db"
    assert re.search(r"\bcitations\b", service_text, re.IGNORECASE), "The recursive query does not reference citations"
    assert re.search(r"\bpapers\b", service_text, re.IGNORECASE), "The implementation does not query paper titles"

    # Replace the graph and titles with an unpredictable valid instance. The
    # endpoint must query SQLite rather than return the original constant JSON.
    conn = sqlite3.connect(DB)
    original_papers = list(conn.execute("SELECT id, title FROM papers"))
    original_citations = list(conn.execute("SELECT source_id, target_id FROM citations"))
    try:
        mids = secrets.SystemRandom().sample([210, 315, 999, 888], 2)
        nodes = [105] + mids + [402]
        token = secrets.token_hex(8)

        conn.execute("DELETE FROM citations")
        conn.executemany(
            "INSERT INTO citations(source_id, target_id) VALUES (?, ?)",
            list(zip(nodes, nodes[1:])),
        )
        for paper_id, _ in original_papers:
            conn.execute(
                "UPDATE papers SET title = ? WHERE id = ?",
                (f"dynamic-{token}-{paper_id}", paper_id),
            )
        conn.commit()

        derived_nodes = shortest_path_from_db(conn, 105, 402)
        assert derived_nodes is not None
        titles = dict(conn.execute("SELECT id, title FROM papers"))
        derived_path = [
            {"step": i + 1, "id": paper_id, "title": titles[paper_id]}
            for i, paper_id in enumerate(derived_nodes)
        ]

        changed = get_response()
        assert changed.get("source_id") == 105
        assert changed.get("target_id") == 402
        assert changed.get("path_length") == len(derived_nodes) - 1
        assert changed.get("path") == derived_path, (
            "Endpoint did not return the shortest path and titles derived from the modified SQLite database"
        )
    finally:
        conn.execute("DELETE FROM citations")
        conn.execute("DELETE FROM papers")
        conn.executemany("INSERT INTO papers(id, title) VALUES (?, ?)", original_papers)
        conn.executemany(
            "INSERT INTO citations(source_id, target_id) VALUES (?, ?)",
            original_citations,
        )
        conn.commit()
        conn.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
