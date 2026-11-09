#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import os
import re
import subprocess
import tempfile
import time
import uuid

import pytest
import redis
import requests

DETECTOR = "/home/user/detector.py"
DBS = ("financial_network", "postgres")


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, text=True, **kwargs)


def psql(sql, db="postgres"):
    return run(["sudo", "-u", "postgres", "psql", "-v", "ON_ERROR_STOP=1", "-d", db, "-c", sql], capture_output=True)


def detector_env():
    env = os.environ.copy()
    env.update({
        "PGHOST": "127.0.0.1",
        "PGPORT": "5432",
        "PGDATABASE": "financial_network",
        "PGUSER": "detector",
        "PGPASSWORD": "detector",
        "DB_HOST": "127.0.0.1",
        "DB_PORT": "5432",
        "DB_NAME": "financial_network",
        "DB_USER": "detector",
        "DB_PASSWORD": "detector",
        "DATABASE_URL": "postgresql://detector:detector@127.0.0.1:5432/financial_network",
        "REDIS_HOST": "127.0.0.1",
        "REDIS_PORT": "6379",
        "REDIS_URL": "redis://127.0.0.1:6379/0",
        "API_BASE_URL": "http://127.0.0.1:5000",
    })
    return env


def invoke(input_path, output_path):
    return subprocess.run(
        ["python3", DETECTOR, input_path, output_path],
        env=detector_env(), capture_output=True, text=True, timeout=30
    )


def setup_database(ids):
    run(["service", "postgresql", "start"], capture_output=True)
    run(["service", "redis-server", "start"], capture_output=True)

    psql("ALTER ROLE postgres PASSWORD 'postgres';")
    roles = psql("SELECT rolname FROM pg_roles;").stdout
    if "detector" not in roles.split():
        psql("CREATE ROLE detector LOGIN PASSWORD 'detector';")
    else:
        psql("ALTER ROLE detector LOGIN PASSWORD 'detector';")

    databases = psql("SELECT datname FROM pg_database;").stdout
    if "financial_network" not in databases.split():
        psql("CREATE DATABASE financial_network OWNER detector;")

    ddl = """
    CREATE TABLE IF NOT EXISTS transactions (
      tx_id text PRIMARY KEY,
      sender text NOT NULL,
      receiver text NOT NULL,
      amount numeric NOT NULL,
      transaction_time timestamp NOT NULL DEFAULT now(),
      transaction_date timestamp NOT NULL DEFAULT now(),
      created_at timestamp NOT NULL DEFAULT now()
    );
    CREATE TABLE IF NOT EXISTS historical_transactions (
      tx_id text PRIMARY KEY,
      sender text NOT NULL,
      receiver text NOT NULL,
      amount numeric NOT NULL,
      transaction_time timestamp NOT NULL DEFAULT now(),
      transaction_date timestamp NOT NULL DEFAULT now(),
      created_at timestamp NOT NULL DEFAULT now()
    );
    CREATE TABLE IF NOT EXISTS transaction_history (
      tx_id text PRIMARY KEY,
      sender text NOT NULL,
      receiver text NOT NULL,
      amount numeric NOT NULL,
      transaction_time timestamp NOT NULL DEFAULT now(),
      transaction_date timestamp NOT NULL DEFAULT now(),
      created_at timestamp NOT NULL DEFAULT now()
    );
    TRUNCATE transactions, historical_transactions, transaction_history;
    GRANT USAGE ON SCHEMA public TO detector;
    GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO detector;
    """

    rows = [
        ("cycle-current", ids["cycle"], ids["cycle_receiver"], 25, 0),
        ("cycle-edge-1", ids["cycle_receiver"], ids["cycle_mid"], 20, 1),
        ("cycle-edge-2", ids["cycle_mid"], ids["cycle"], 20, 2),
    ]
    for day in range(7):
        rows.append((f"volume-history-{day}", ids["volume"], f"merchant_{day}_{ids['suffix']}", 20000, day))
    # Disconnected decoy edges make an uncorrelated recursive term produce false paths.
    for n in range(20):
        rows.append((f"decoy-{n}", f"decoy_from_{n}_{ids['suffix']}", f"decoy_to_{n}_{ids['suffix']}", 5, n % 7))

    values = []
    for tx_id, sender, receiver, amount, days in rows:
        esc = lambda s: s.replace("'", "''")
        values.append("('%s','%s','%s',%s,now()-interval '%s days',now()-interval '%s days',now()-interval '%s days')" % (
            esc(tx_id), esc(sender), esc(receiver), amount, days, days, days
        ))
    insert_values = ",".join(values)

    for db in DBS:
        psql(ddl, db)
        for table in ("transactions", "historical_transactions", "transaction_history"):
            psql(
                f"INSERT INTO {table} (tx_id,sender,receiver,amount,transaction_time,transaction_date,created_at) VALUES {insert_values};",
                db,
            )

    psql("ALTER SYSTEM SET log_statement = 'all';")
    psql("SELECT pg_reload_conf();")
    time.sleep(0.5)
    for path in glob.glob("/var/log/postgresql/postgresql-*.log"):
        open(path, "w").close()


def start_api(risk_id, count_file):
    subprocess.run(["pkill", "-f", "/app/app.py"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    api_source = r'''
import os
from flask import Flask, jsonify
app = Flask(__name__)
risk_id = os.environ["TEST_RISK_ID"]
count_file = os.environ["TEST_COUNT_FILE"]
@app.route("/score/<account_id>")
def score(account_id):
    with open(count_file, "a") as f:
        f.write(account_id + "\\n")
    return jsonify({"score": 0.95 if account_id in (risk_id, "evil_user") else 0.1})
app.run(host="127.0.0.1", port=5000, threaded=False)
'''
    with open("/tmp/verifier_api.py", "w") as f:
        f.write(api_source)
    open(count_file, "w").close()
    env = os.environ.copy()
    env["TEST_RISK_ID"] = risk_id
    env["TEST_COUNT_FILE"] = count_file
    proc = subprocess.Popen(
        ["python3", "/tmp/verifier_api.py"], env=env,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    for _ in range(50):
        try:
            requests.get("http://127.0.0.1:5000/score/__probe__", timeout=0.2)
            open(count_file, "w").close()
            return proc
        except requests.RequestException:
            time.sleep(0.1)
    proc.terminate()
    raise RuntimeError("verification API did not start")


def read_calls(path):
    with open(path) as f:
        return [line.strip() for line in f if line.strip()]


def test_detector_adversarial_corpus_and_services():
    assert os.path.isfile(DETECTOR), f"Detector script not found at {DETECTOR}"

    suffix = uuid.uuid4().hex
    ids = {
        "suffix": suffix,
        "clean": f"normal_{suffix}",
        "clean_receiver": f"shop_{suffix}",
        "cycle": f"circle_sender_{suffix}",
        "cycle_receiver": f"circle_receiver_{suffix}",
        "cycle_mid": f"circle_mid_{suffix}",
        "volume": f"volume_sender_{suffix}",
        "risk": f"risk_sender_{suffix}",
    }
    count_file = "/tmp/verifier_api_calls.txt"
    api = None
    try:
        setup_database(ids)
        redis_client = redis.Redis(host="127.0.0.1", port=6379, db=0)
        redis_client.flushall()
        api = start_api(ids["risk"], count_file)

        # Preserve the original fixed-corpus assertions.
        clean_dir = "/home/user/corpora/clean"
        evil_dir = "/home/user/corpora/evil"
        clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.csv')]
        evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.csv')]
        clean_modified = []
        evil_bypassed = []

        with tempfile.TemporaryDirectory() as tmpdir:
            for c_file in clean_files:
                out_file = os.path.join(tmpdir, os.path.basename(c_file))
                result = invoke(c_file, out_file)
                if result.returncode != 0:
                    clean_modified.append(f"{os.path.basename(c_file)} (script crashed)")
                    continue
                if not os.path.exists(out_file):
                    clean_modified.append(f"{os.path.basename(c_file)} (no output file)")
                    continue
                with open(c_file, 'r') as f1, open(out_file, 'r') as f2:
                    if f1.readlines() != f2.readlines():
                        clean_modified.append(os.path.basename(c_file))

            for e_file in evil_files:
                out_file = os.path.join(tmpdir, os.path.basename(e_file))
                result = invoke(e_file, out_file)
                if result.returncode != 0:
                    evil_bypassed.append(f"{os.path.basename(e_file)} (script crashed)")
                    continue
                if not os.path.exists(out_file):
                    continue
                with open(out_file, 'r') as f:
                    out_lines = f.readlines()
                    if len(out_lines) > 1:
                        evil_bypassed.append(os.path.basename(e_file))
                    elif len(out_lines) == 1:
                        with open(e_file, 'r') as in_f:
                            if out_lines[0] != in_f.readline():
                                evil_bypassed.append(os.path.basename(e_file))

            errors = []
            if evil_bypassed:
                errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
            if clean_modified:
                errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
            assert not errors, " | ".join(errors)

            # Unseen accounts exercise each independent suspicious condition.
            generated_in = os.path.join(tmpdir, "generated.csv")
            generated_out = os.path.join(tmpdir, "generated_out.csv")
            rows = [
                {"tx_id": f"clean-{suffix}", "sender": ids["clean"], "receiver": ids["clean_receiver"], "amount": "50"},
                {"tx_id": f"cycle-{suffix}", "sender": ids["cycle"], "receiver": ids["cycle_receiver"], "amount": "25"},
                {"tx_id": f"volume-{suffix}", "sender": ids["volume"], "receiver": f"volume_dest_{suffix}", "amount": "10"},
                {"tx_id": f"risk-{suffix}", "sender": ids["risk"], "receiver": f"risk_dest_{suffix}", "amount": "10"},
            ]
            with open(generated_in, "w", newline="") as f:
                writer = csv.DictWriter(f, fieldnames=["tx_id", "sender", "receiver", "amount"])
                writer.writeheader()
                writer.writerows(rows)

            first = invoke(generated_in, generated_out)
            assert first.returncode == 0, first.stderr
            assert os.path.isfile(generated_out), "detector did not create generated output"
            with open(generated_out, newline="") as f:
                output_rows = list(csv.DictReader(f))
            assert [r["tx_id"] for r in output_rows] == [f"clean-{suffix}"], \
                "unseen clean/circular/high-volume/high-risk transactions were classified incorrectly"

            first_calls = read_calls(count_file)
            assert ids["risk"] in first_calls, "high-risk sender was not scored through the Flask API"
            assert redis_client.dbsize() > 0, "no Flask risk score was cached in Redis"

            second_out = os.path.join(tmpdir, "generated_out_second.csv")
            second = invoke(generated_in, second_out)
            assert second.returncode == 0, second.stderr
            second_calls = read_calls(count_file)
            assert second_calls.count(ids["risk"]) == first_calls.count(ids["risk"]), \
                "the risk API was called again instead of using Redis across detector invocations"

        time.sleep(0.5)
        sql_log = ""
        for path in glob.glob("/var/log/postgresql/postgresql-*.log"):
            with open(path, errors="replace") as f:
                sql_log += f.read().lower()
        assert re.search(r"with\s+recursive", sql_log), "no recursive CTE was executed in PostgreSQL"
        assert re.search(r"with\s+recursive[\s\S]{0,8000}\bjoin\b[\s\S]{0,1000}\bon\b", sql_log), \
            "recursive traversal did not execute an explicitly correlated JOIN ... ON"
        assert "cross join" not in sql_log, "recursive graph SQL executed a CROSS JOIN"
        assert re.search(r"\bover\s*\(", sql_log), "no SQL window function was executed for moving-volume analysis"
    finally:
        if api is not None:
            api.terminate()
            try:
                api.wait(timeout=3)
            except subprocess.TimeoutExpired:
                api.kill()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
