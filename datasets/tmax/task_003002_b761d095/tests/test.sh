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

cat <<'PY_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import signal
import sqlite3
import subprocess
import sys
import time
from pathlib import Path

import requests
from PIL import Image, ImageDraw, ImageFont

URL = "http://127.0.0.1:8080/pattern"
DB = Path("/app/backup.sqlite")
IMAGE = Path("/app/pattern.png")


def get_json(retries=3):
    last = None
    for attempt in range(retries):
        try:
            response = requests.get(URL, timeout=5)
            assert response.status_code == 200, (
                f"Expected status code 200, got {response.status_code}"
            )
            try:
                return response.json()
            except ValueError:
                raise AssertionError(f"Response is not valid JSON: {response.text}")
        except (requests.RequestException, AssertionError) as exc:
            last = exc
            if attempt + 1 < retries:
                time.sleep(1)
    raise AssertionError(f"Failed to obtain a valid response from {URL}: {last}")


def listening_pids():
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

    found = set()
    if not inodes:
        return found
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    found.add(int(proc.name))
        except OSError:
            pass
    return found


def process_command(pid):
    try:
        argv = [x.decode() for x in Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0") if x]
        cwd = os.readlink(f"/proc/{pid}/cwd")
        return (argv, cwd) if argv else None
    except (OSError, UnicodeDecodeError):
        return None


def kill_server():
    for _ in range(20):
        pids = listening_pids()
        if not pids:
            return
        for pid in pids:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        time.sleep(0.1)
    raise AssertionError("Could not stop the submitted server")


def types_from_image(path):
    text = subprocess.check_output(
        ["tesseract", str(path), "stdout"], stderr=subprocess.DEVNULL, text=True
    )
    if ":" in text:
        text = text.split(":", 1)[1]
    result = [part.strip() for part in text.replace("\n", " ").split("->")]
    result = [part for part in result if part]
    assert len(result) >= 2, f"OCR did not yield a path pattern: {text!r}"
    return result


def path_for_types(db_path, types):
    con = sqlite3.connect(db_path)
    try:
        rows = con.execute("SELECT id, type, name FROM nodes").fetchall()
        edges = set(con.execute("SELECT source, target FROM edges").fetchall())
    finally:
        con.close()
    nodes = {row[0]: (row[1], row[2]) for row in rows}
    paths = [([node_id], [name]) for node_id, (typ, name) in nodes.items() if typ == types[0]]
    for typ in types[1:]:
        extended = []
        for ids, names in paths:
            for node_id, (node_type, name) in nodes.items():
                if node_type == typ and (ids[-1], node_id) in edges:
                    extended.append((ids + [node_id], names + [name]))
        paths = extended
    assert len(paths) == 1, f"Fixture should have one matching path, found {len(paths)}"
    return paths[0][1]


def write_hidden_fixture(tag):
    con = sqlite3.connect(DB)
    con.executescript("""
        CREATE TABLE nodes (id INTEGER PRIMARY KEY, type TEXT, name TEXT);
        CREATE TABLE edges (source INTEGER, target INTEGER);
        CREATE INDEX idx_edges_source ON edges(source);
        CREATE INDEX idx_edges_target ON edges(target);
    """)
    names = [f"router_{tag}", f"cache_{tag}", f"worker_{tag}"]
    con.executemany(
        "INSERT INTO nodes VALUES (?, ?, ?)",
        [
            (1, "Router", names[0]), (2, "Cache", names[1]),
            (3, "Worker", names[2]), (4, "Router", f"decoy_{tag}"),
            (5, "Worker", f"wrong_{tag}"),
        ],
    )
    con.executemany("INSERT INTO edges VALUES (?, ?)", [(1, 2), (2, 3), (4, 5)])
    con.commit()
    con.close()

    img = Image.new("RGB", (800, 100), color="white")
    draw = ImageDraw.Draw(img)
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 24)
    draw.text((20, 40), "TARGET: Router -> Cache -> Worker", fill="black", font=font)
    img.save(IMAGE)
    return names


def file_hash(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def script_candidates(process_commands):
    candidates = []
    seen = set()

    for command in process_commands:
        if command and tuple(command[0]) not in seen:
            seen.add(tuple(command[0]))
            candidates.append((100, command[0], command[1]))

    roots = [Path("/app"), Path("/home/user"), Path("/root"), Path("/tmp")]
    for root in roots:
        if not root.exists():
            continue
        try:
            files = root.rglob("*")
            for path in files:
                try:
                    if not path.is_file() or path.stat().st_size > 1_000_000:
                        continue
                    if str(path) == "/tmp/test_final_state.py" or path in (DB, IMAGE):
                        continue
                    raw = path.read_bytes()
                    text = raw.decode("utf-8", errors="ignore")
                except OSError:
                    continue
                low = text.lower()
                score = sum(token in low for token in (
                    "8080", "backup.sqlite", "pattern.png", "reindex", "tesseract", "/pattern"
                ))
                if score < 2:
                    continue
                if path.suffix == ".py" or text.startswith("#!/usr/bin/env python") or text.startswith("#!/usr/bin/python"):
                    argv = [sys.executable, str(path)]
                elif path.suffix in (".sh", ".bash") or text.startswith("#!/bin/bash") or text.startswith("#!/usr/bin/env bash"):
                    argv = ["/bin/bash", str(path)]
                elif os.access(path, os.X_OK):
                    argv = [str(path)]
                else:
                    continue
                key = tuple(argv)
                if key not in seen:
                    seen.add(key)
                    candidates.append((score * 20, argv, str(path.parent)))
        except OSError:
            pass

    candidates.sort(key=lambda item: item[0], reverse=True)
    return candidates[:20]


def exercise_candidate(argv, cwd, tag):
    kill_server()
    for suffix in ("", "-wal", "-shm", "-journal"):
        try:
            Path(str(DB) + suffix).unlink()
        except FileNotFoundError:
            pass
    expected = write_hidden_fixture(tag)
    ocr_types = types_from_image(IMAGE)
    assert ocr_types == ["Router", "Cache", "Worker"], f"Unexpected hidden OCR result: {ocr_types}"
    expected = path_for_types(DB, ocr_types)
    before = file_hash(DB)

    proc = None
    try:
        proc = subprocess.Popen(
            argv,
            cwd=cwd if os.path.isdir(cwd) else "/app",
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        deadline = time.time() + 10
        data = None
        while time.time() < deadline:
            try:
                response = requests.get(URL, timeout=1)
                if response.status_code == 200:
                    data = response.json()
                    break
            except (requests.RequestException, ValueError):
                pass
            time.sleep(0.25)
        if data != {"path": expected}:
            return False
        time.sleep(0.3)
        # A real REINDEX or index rebuild on this fresh fixture changes the database file.
        if file_hash(DB) == before:
            return False
        con = sqlite3.connect(DB)
        try:
            if con.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
                return False
        finally:
            con.close()
        return True
    except (OSError, subprocess.SubprocessError):
        return False
    finally:
        kill_server()
        if proc is not None and proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


# Preserve the original endpoint assertion.
original_data = get_json()
expected_data = {"path": ["web01", "lb01", "db01"]}
assert original_data == expected_data, f"Expected JSON {expected_data}, but got {original_data}"

# Independently derive the original answer from OCR and the supplied database.
original_types = types_from_image(IMAGE)
derived = {"path": path_for_types(DB, original_types)}
assert original_data == derived, f"Endpoint does not match OCR/database-derived path {derived}"

con = sqlite3.connect(DB)
try:
    assert con.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
    indexes = {row[0] for row in con.execute(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='edges'"
    )}
    assert "idx_edges_source" in indexes and "idx_edges_target" in indexes
finally:
    con.close()

# Save how the submitted server was launched before replacing the public fixtures.
commands = [process_command(pid) for pid in listening_pids()]
candidates = script_candidates(commands)
assert candidates, "Could not locate the script used to start the submitted server"

passed = False
for number, (_, argv, cwd) in enumerate(candidates):
    if exercise_candidate(argv, cwd, f"{os.getpid()}_{number}"):
        passed = True
        break
assert passed, (
    "No submitted server script performed OCR/database discovery and index repair "
    "when exercised on a verifier-generated fixture"
)
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
