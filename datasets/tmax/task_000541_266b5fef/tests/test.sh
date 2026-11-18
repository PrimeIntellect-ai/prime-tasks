#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import glob
import hashlib
import json
import os
import random
import shutil
import sqlite3
import stat
import subprocess
import tempfile

SCRIPT = "/home/user/audit_filter.py"
DB = "/home/user/system_graph.db"
ORACLE = "/app/path_verifier"


def file_hash(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def oracle_answer(src, dst):
    result = subprocess.run([ORACLE, str(src), str(dst)], stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL)
    assert result.returncode in (0, 1), f"Oracle failed for {src}->{dst}"
    return "ACCEPT" if result.returncode == 0 else "REJECT"


def run_filter(request_path, expected_db_hash):
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "python3", SCRIPT, request_path],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert file_hash(DB) == expected_db_hash, "audit_filter.py modified the graph database"
    return result.stdout.strip(), result.stderr.strip()


def install_graph(nodes, edges):
    conn = sqlite3.connect(DB)
    try:
        cur = conn.cursor()
        cur.execute("DELETE FROM edges")
        cur.execute("DELETE FROM nodes")
        cur.executemany(
            "INSERT INTO nodes (id, name, is_restricted) VALUES (?, ?, ?)", nodes
        )
        cur.executemany(
            "INSERT INTO edges (source_id, target_id) VALUES (?, ?)", edges
        )
        conn.commit()
    finally:
        conn.close()


def restore_database(backup, mode):
    try:
        os.unlink(DB)
    except FileNotFoundError:
        pass
    shutil.copyfile(backup, DB)
    os.chmod(DB, mode)


def main():
    assert os.path.isfile(SCRIPT), f"The required script {SCRIPT} does not exist."
    assert os.path.isfile(ORACLE), f"The legacy oracle {ORACLE} does not exist."

    clean_files = sorted(glob.glob("/home/user/corpora/clean/*.json"))
    evil_files = sorted(glob.glob("/home/user/corpora/evil/*.json"))
    assert clean_files, "No clean corpus files found in /home/user/corpora/clean/."
    assert evil_files, "No evil corpus files found in /home/user/corpora/evil/."

    corpus_cases = []
    for path in clean_files + evil_files:
        with open(path, "r", encoding="utf-8") as f:
            request = json.load(f)
        expected = oracle_answer(int(request["source"]), int(request["destination"]))
        corpus_cases.append((path, expected))

    # Retain the valid clean-corpus assertion while deriving all classifications
    # from the actual legacy engine. In particular, req3 is ACCEPT according to it.
    for path, expected in corpus_cases[:len(clean_files)]:
        assert expected == "ACCEPT", f"Clean corpus case {path} disagrees with the oracle"

    original_mode = stat.S_IMODE(os.stat(DB).st_mode)
    backup = "/root/system_graph.verifier-backup.db"
    shutil.copyfile(DB, backup)

    rng = random.SystemRandom()
    ids = rng.sample(range(10000, 900000), 20)
    restricted = set(rng.sample(ids, 5))
    nodes = [(node_id, f"hidden_{i}_{rng.randrange(1 << 30)}",
              1 if node_id in restricted else 0)
             for i, node_id in enumerate(ids)]

    edges_set = set()
    for u in ids:
        for v in ids:
            if u != v and rng.random() < 0.11:
                edges_set.add((u, v))
    # Guarantee useful reachable and over-depth cases without making the rest fixed.
    for i in range(6):
        edges_set.add((ids[i], ids[i + 1]))
    edges = sorted(edges_set)

    temp_dir = tempfile.mkdtemp(prefix="audit-hidden-", dir="/tmp")
    os.chmod(temp_dir, 0o755)
    hidden_cases = []
    hidden_oracle = f"/root/.path_verifier_hidden_{os.getpid()}_{rng.randrange(1 << 30)}"

    try:
        install_graph(nodes, edges)

        pairs = {(node_id, node_id) for node_id in rng.sample(ids, 5)}
        pairs.update((ids[i], ids[i + 1]) for i in range(6))
        while len(pairs) < 80:
            pairs.add((rng.choice(ids), rng.choice(ids)))

        for index, (src, dst) in enumerate(pairs):
            path = os.path.join(temp_dir, f"case_{index}_{rng.randrange(1 << 30)}.json")
            with open(path, "w", encoding="utf-8") as f:
                json.dump({
                    "request_id": f"hidden-{rng.randrange(1 << 60)}",
                    "source": src,
                    "destination": dst,
                    "timestamp": "2026-01-01T00:00:00Z"
                }, f)
            os.chmod(path, 0o644)
            hidden_cases.append((path, oracle_answer(src, dst)))

        assert {expected for _, expected in hidden_cases} == {"ACCEPT", "REJECT"}, \
            "Generated tests did not contain both oracle outcomes"

        # The candidate must replace, rather than call, the legacy engine while tested.
        os.rename(ORACLE, hidden_oracle)
        os.chmod(hidden_oracle, 0o700)

        restore_database(backup, original_mode)
        corpus_db_hash = file_hash(DB)
        failures = []
        for path, expected in corpus_cases:
            output, stderr = run_filter(path, corpus_db_hash)
            if output != expected:
                failures.append((os.path.basename(path), expected, output, stderr))
        assert not failures, "Corpus mismatches: " + repr(failures[:5])

        install_graph(nodes, edges)
        hidden_db_hash = file_hash(DB)
        failures = []
        for path, expected in hidden_cases:
            output, stderr = run_filter(path, hidden_db_hash)
            if output != expected:
                failures.append((os.path.basename(path), expected, output, stderr))
        assert not failures, "Hidden oracle-derived mismatches: " + repr(failures[:5])
    finally:
        restore_database(backup, original_mode)
        try:
            os.unlink(backup)
        except FileNotFoundError:
            pass
        if os.path.exists(hidden_oracle):
            os.chmod(hidden_oracle, 0o755)
            os.rename(hidden_oracle, ORACLE)
        shutil.rmtree(temp_dir, ignore_errors=True)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
