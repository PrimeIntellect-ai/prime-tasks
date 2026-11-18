#!/bin/bash
set -e
mkdir -p /logs/verifier

# Interpose a verifier wrapper around the real scorer. It preserves scorer output
# while recording exact argv and concurrent invocations.
rm -f /app/scorer.__verifier_real /tmp/scorer_calls.jsonl /tmp/scorer_state.json /tmp/scorer_state.lock
mv /app/scorer /app/scorer.__verifier_real
cat <<'WRAPPER_EOF' > /app/scorer
#!/usr/bin/env python3
import fcntl
import json
import os
import subprocess
import sys
import time

lock_path = "/tmp/scorer_state.lock"
state_path = "/tmp/scorer_state.json"
log_path = "/tmp/scorer_calls.jsonl"

def update(starting):
    with open(lock_path, "a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            try:
                with open(state_path, "r", encoding="utf-8") as f:
                    state = json.load(f)
            except Exception:
                state = {"active": 0, "max_active": 0}
            if starting:
                state["active"] = state.get("active", 0) + 1
                state["max_active"] = max(state.get("max_active", 0), state["active"])
                with open(log_path, "a", encoding="utf-8") as log:
                    log.write(json.dumps(sys.argv[1:], ensure_ascii=False) + "\n")
            else:
                state["active"] = max(0, state.get("active", 0) - 1)
            with open(state_path, "w", encoding="utf-8") as f:
                json.dump(state, f)
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)

update(True)
try:
    # Long enough that a serial implementation is distinguishable by overlap.
    time.sleep(0.30)
    result = subprocess.run(["/app/scorer.__verifier_real"] + sys.argv[1:])
    raise SystemExit(result.returncode)
finally:
    update(False)
WRAPPER_EOF
chmod 755 /app/scorer
restore_scorer() {
    rm -f /app/scorer
    if [ -e /app/scorer.__verifier_real ]; then
        mv /app/scorer.__verifier_real /app/scorer
    fi
}
trap restore_scorer EXIT

cat <<'TEST_EOF' > /tmp/test_final_state.py
import collections
import json
import os
import re
import secrets
import subprocess
import threading
import time

import pytest
import requests

BASE = "http://127.0.0.1:8080"
REAL_SCORER = "/app/scorer.__verifier_real"


def post(path, **kwargs):
    return requests.post(BASE + path, timeout=20, **kwargs)


def get(path):
    return requests.get(BASE + path, timeout=5)


def flush():
    response = post("/flush")
    assert response.status_code in (200, 201, 202, 204)


def oracle_score(orig, trans):
    result = subprocess.run(
        [REAL_SCORER, orig, trans], capture_output=True, text=True, check=True
    )
    match = re.search(r"Score:\s*([-+0-9.eE]+)", result.stdout)
    assert match, "Could not parse the shipped scorer's output"
    return float(match.group(1))


def read_samples():
    path = "/home/user/low_quality_samples.json"
    assert os.path.exists(path), f"File {path} does not exist"
    with open(path, "r", encoding="utf-8") as f:
        try:
            value = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} does not contain valid JSON")
    assert isinstance(value, list), f"Expected JSON array in {path}"
    return value


def unique_lang(prefix):
    return prefix + secrets.token_hex(5)


def test_01_required_artifacts_and_cpp_binary():
    binary = "/home/user/loc_server"
    assert os.path.exists(binary), "/home/user/loc_server does not exist"
    assert os.access(binary, os.X_OK), "/home/user/loc_server is not executable"
    with open(binary, "rb") as f:
        data = f.read()
    assert data.startswith(b"\x7fELF"), "loc_server must be a compiled ELF executable"
    ldd = subprocess.run(["ldd", binary], capture_output=True, text=True)
    evidence = (ldd.stdout + ldd.stderr).encode("utf-8", "ignore") + data
    assert b"libstdc++" in evidence or b"GLIBCXX" in evidence or b"_ZSt" in evidence, \
        "loc_server does not contain evidence of being a C++ executable"

    script = "/home/user/flush_pipeline.sh"
    assert os.path.exists(script), "/home/user/flush_pipeline.sh does not exist"
    assert os.access(script, os.X_OK), "/home/user/flush_pipeline.sh is not executable"


def test_02_crontab_entry_exists_and_runs_every_minute():
    result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to list crontab"
    assert "/home/user/flush_pipeline.sh" in result.stdout, \
        "Crontab does not contain /home/user/flush_pipeline.sh"
    matching = []
    for raw in result.stdout.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split()
        if len(fields) >= 6 and "/home/user/flush_pipeline.sh" in line:
            matching.append(fields)
    assert any(fields[:5] == ["*", "*", "*", "*", "*"] for fields in matching), \
        "flush_pipeline.sh must be scheduled every minute"


def test_03_http_service_original_fixed_cases():
    try:
        get("/stats")
    except requests.exceptions.ConnectionError:
        pytest.fail("HTTP server is not running on 127.0.0.1:8080")

    flush()
    payload1 = [
        {"lang": "de", "orig": "Welcome", "trans": "Willkommen"},
        {"lang": "de", "orig": "Cat", "trans": "Katze"},
    ]
    response = post("/translations", json=payload1)
    assert response.status_code in (200, 201, 202, 204), \
        f"POST /translations failed: {response.status_code}"
    response = get("/stats")
    assert response.status_code == 200, f"GET /stats failed: {response.status_code}"
    stats = response.json()
    assert "de" in stats, "Language 'de' not found in stats"
    assert abs(stats["de"] - 0.75) < 0.01, \
        f"Expected 'de' average to be ~0.75, got {stats['de']}"

    payload2 = [
        {"lang": "es", "orig": "Very long string here", "trans": "Short"}
    ]
    response = post("/translations", json=payload2)
    assert response.status_code in (200, 201, 202, 204), \
        f"POST /translations failed: {response.status_code}"
    response = get("/stats")
    assert response.status_code == 200
    stats = response.json()
    assert "es" in stats, "Language 'es' not found in stats"
    assert abs(stats["es"] - 0.10) < 0.01, \
        f"Expected 'es' average to be ~0.10, got {stats['es']}"

    samples = read_samples()
    es_samples = [s for s in samples if s.get("lang") == "es"]
    assert len(es_samples) >= 1, "Expected at least one 'es' sample"
    assert es_samples[-1].get("orig") == "Very long string here", \
        "Sample original text does not match"


def test_04_dynamic_oracle_unicode_and_rolling_last_five():
    flush()
    lang = unique_lang("roll_")
    pairs = [
        ("éclair", "猫"),
        ("Здравствуйте", "привет"),
        ("🙂🙂 alpha", "β"),
        ("mañana", "morgen"),
        ("東京 station", "東京駅"),
        ("مرحبا بالعالم", "أهلا"),
        ("naïve café résumé", "文"),
    ]
    expected = []
    for orig, trans in pairs:
        score = oracle_score(orig, trans)
        expected.append(score)
        response = post("/translations", json=[{"lang": lang, "orig": orig, "trans": trans}])
        assert response.status_code in (200, 201, 202, 204)
    stats = get("/stats").json()
    assert lang in stats
    wanted = sum(expected[-5:]) / 5.0
    assert abs(float(stats[lang]) - wanted) < 0.011, \
        f"Rolling average must use exactly the latest five scores: expected {wanted}, got {stats[lang]}"


def test_05_each_parallel_item_invokes_scorer_with_exact_unicode_argv():
    flush()
    with open("/tmp/scorer_state.lock", "a+") as lock:
        import fcntl
        fcntl.flock(lock, fcntl.LOCK_EX)
        with open("/tmp/scorer_state.json", "w", encoding="utf-8") as f:
            json.dump({"active": 0, "max_active": 0}, f)
        open("/tmp/scorer_calls.jsonl", "w", encoding="utf-8").close()
        fcntl.flock(lock, fcntl.LOCK_UN)

    token = secrets.token_hex(6)
    payload = []
    for i, (orig, trans) in enumerate([
        ("猫🙂", "árbol"), ("γειά", "κόσμε"), ("हैलो", "दुनिया"),
        ("한국어", "번역"), ("العربية", "نص"), ("français", "élève"),
        ("Україна", "мова"), ("日本語", "テキスト"),
    ]):
        payload.append({"lang": f"par_{token}_{i}", "orig": orig + token, "trans": trans})
    response = post("/translations", json=payload)
    assert response.status_code in (200, 201, 202, 204)

    with open("/tmp/scorer_calls.jsonl", "r", encoding="utf-8") as f:
        calls = [json.loads(line) for line in f if line.strip()]
    expected_calls = collections.Counter((p["orig"], p["trans"]) for p in payload)
    actual_calls = collections.Counter(tuple(call) for call in calls)
    assert actual_calls == expected_calls, \
        "The service must invoke /app/scorer once per entry with exact original and translated Unicode argv"
    with open("/tmp/scorer_state.json", "r", encoding="utf-8") as f:
        state = json.load(f)
    assert state.get("max_active", 0) >= 2, \
        "Scorer invocations did not overlap; the batch was not processed in parallel"

    stats = get("/stats").json()
    for item in payload:
        expected = oracle_score(item["orig"], item["trans"])
        assert abs(float(stats[item["lang"]]) - expected) < 0.011


def test_06_samples_are_strict_latest_unique_and_atomically_replaced():
    low_lang = unique_lang("low_")
    boundary_lang = unique_lang("boundary_")
    first = {"lang": low_lang, "orig": "x" * 30, "trans": "短"}
    second = {"lang": low_lang, "orig": "LATEST_" + "y" * 35, "trans": "z"}
    assert oracle_score(first["orig"], first["trans"]) < 0.5
    assert oracle_score(second["orig"], second["trans"]) < 0.5

    response = post("/translations", json=[first])
    assert response.status_code in (200, 201, 202, 204)
    read_samples()

    # Keep the old inode open while updating; atomic replacement must publish a new inode.
    path = "/home/user/low_quality_samples.json"
    with open(path, "rb") as old_file:
        old_inode = os.fstat(old_file.fileno()).st_ino
        response = post("/translations", json=[second])
        assert response.status_code in (200, 201, 202, 204)
        new_inode = os.stat(path).st_ino
        assert new_inode != old_inode, \
            "low_quality_samples.json was modified in place rather than atomically replaced"
        json.load(old_file if False else open(path, "r", encoding="utf-8"))

    # Difference of exactly five bytes gives exactly 0.50 and must not be sampled.
    boundary = {"lang": boundary_lang, "orig": "abcdefghij", "trans": "abcde"}
    assert abs(oracle_score(boundary["orig"], boundary["trans"]) - 0.5) < 1e-9
    response = post("/translations", json=[boundary])
    assert response.status_code in (200, 201, 202, 204)

    samples = read_samples()
    langs = [s.get("lang") for s in samples]
    counts = collections.Counter(langs)
    assert all(count == 1 for count in counts.values()), \
        "There must be exactly one, not multiple, low-quality sample per language"
    chosen = [s for s in samples if s.get("lang") == low_lang]
    assert len(chosen) == 1
    assert chosen[0].get("orig") == second["orig"] and chosen[0].get("trans") == second["trans"], \
        "The retained sample must be the most recent low-quality item for its language"
    assert boundary_lang not in langs, "A score equal to 0.5 must not be sampled"


def test_07_flush_script_really_posts_flush_and_endpoint_clears_stats():
    lang = unique_lang("flush_")
    response = post("/translations", json=[{"lang": lang, "orig": "abc", "trans": "abcd"}])
    assert response.status_code in (200, 201, 202, 204)
    assert lang in get("/stats").json()

    run = subprocess.run(
        ["/home/user/flush_pipeline.sh"], capture_output=True, text=True, timeout=10
    )
    assert run.returncode == 0, "flush_pipeline.sh failed to make its flush request"
    stats = get("/stats").json()
    assert len(stats) == 0 or all(float(v) == 0.0 for v in stats.values()), \
        "Stats were not cleared by flush_pipeline.sh"

    # Preserve the original direct endpoint assertion as well.
    response = post("/flush")
    assert response.status_code in (200, 201, 202, 204), \
        f"POST /flush failed: {response.status_code}"
    response = get("/stats")
    assert response.status_code == 200, f"GET /stats failed: {response.status_code}"
    stats = response.json()
    assert len(stats) == 0 or all(float(v) == 0.0 for v in stats.values()), \
        "Stats were not cleared after /flush"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
