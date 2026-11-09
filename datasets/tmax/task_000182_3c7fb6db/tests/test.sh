#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY' > /tmp/test_final_state.py
import collections
import datetime
import os
import subprocess
import sys
import time

import psycopg2
from neo4j import GraphDatabase

ETL_PATH = "/home/user/etl.py"
CYPHER_QUERY_PATH = "/home/user/target_query.cypher"


def test_full_pipeline():
    assert os.path.isfile(ETL_PATH), f"ETL script is missing at {ETL_PATH}"
    assert os.path.isfile(CYPHER_QUERY_PATH), f"Target query file is missing at {CYPHER_QUERY_PATH}"

    with open(ETL_PATH, "r", encoding="utf-8") as f:
        etl_source = f.read()
    compile(etl_source, ETL_PATH, "exec")
    compact_source = "".join(etl_source.upper().split())
    assert "OVER(" in compact_source, "ETL must use an SQL window function."
    assert any(fn in compact_source for fn in ("LEAD(", "LAG(", "ROW_NUMBER(")), \
        "ETL must use a sequencing SQL window function such as LEAD, LAG, or ROW_NUMBER."
    assert "PSYCOPG2" in etl_source.upper(), "ETL must connect to PostgreSQL."
    assert "NEO4J" in etl_source.upper(), "ETL must connect to Memgraph using the Neo4j driver."
    assert "CREATE INDEX" in etl_source.upper() or "CREATE CONSTRAINT" in etl_source.upper(), \
        "ETL must create a Memgraph index or constraint."

    with open(CYPHER_QUERY_PATH, "r", encoding="utf-8") as f:
        query = f.read().strip()
    assert query, "The Cypher query file is empty."
    upper_query = query.upper()
    assert "NEXT" in upper_query, "The target query must analyze NEXT relationships."
    assert "COUNT" in upper_query, "The target query must calculate path frequency."

    pg = psycopg2.connect(host="localhost", port=5432, user="postgres", password="postgres", dbname="analytics")
    pg.autocommit = True
    with pg.cursor() as cur:
        # Add a hidden dominant path so an answer hardcoded from the agent-visible
        # random data cannot pass. The full expected answer is still derived below.
        cur.execute("SELECT setval(pg_get_serial_sequence('raw_events','event_id'), GREATEST(COALESCE(MAX(event_id), 1), 1), true) FROM raw_events")
        cur.execute("""
            WITH base AS (SELECT COALESCE(MAX(user_id), 0) AS max_user FROM raw_events),
                 users AS (SELECT max_user + g AS user_id, g FROM base, generate_series(1, 450) AS g)
            INSERT INTO raw_events(user_id, event_timestamp, event_type)
            SELECT user_id,
                   timestamp '2024-01-01 00:00:00' + g * interval '1 day' + s.n * interval '10 minutes',
                   s.event_type
            FROM users
            CROSS JOIN (VALUES (0, 'logout'), (1, 'login'), (2, 'checkout')) AS s(n, event_type)
        """)
        cur.execute("SELECT event_id, user_id, event_timestamp, event_type FROM raw_events ORDER BY event_id")
        source_rows = cur.fetchall()

    assert source_rows, "PostgreSQL raw_events is empty."
    assert len({r[0] for r in source_rows}) == len(source_rows), "raw_events event_id values must be unique."

    by_user = collections.defaultdict(list)
    event_types = {}
    for event_id, user_id, timestamp, event_type in source_rows:
        assert timestamp is not None and event_type is not None
        by_user[user_id].append((timestamp, event_id, event_type))
        event_types[event_id] = event_type

    expected_edges = []
    for events in by_user.values():
        events.sort(key=lambda row: (row[0], row[1]))
        for left, right in zip(events, events[1:]):
            delta = right[0] - left[0]
            if datetime.timedelta(0) <= delta <= datetime.timedelta(minutes=60):
                expected_edges.append((left[1], right[1]))
    expected_edges.sort()

    successors = {a: b for a, b in expected_edges}
    frequencies = collections.Counter()
    for a, b in expected_edges:
        c = successors.get(b)
        if c is not None:
            frequencies[(event_types[a], event_types[b], event_types[c])] += 1
    assert frequencies, "The relational input contains no three-event paths."
    max_frequency = max(frequencies.values())
    expected_winners = {path for path, count in frequencies.items() if count == max_frequency}

    driver = GraphDatabase.driver("bolt://localhost:7687")
    driver.verify_connectivity()

    # Remove prior graph contents so the verifier tests what this execution of
    # etl.py materializes, rather than accepting graph state prepared by hand.
    with driver.session() as session:
        session.run("MATCH (n) DETACH DELETE n").consume()
        try:
            indexes = list(session.run("SHOW INDEX INFO"))
            for record in indexes:
                data = record.data()
                label = data.get("label")
                prop = data.get("property")
                if not label:
                    continue
                safe_label = str(label).replace("`", "``")
                if prop:
                    safe_prop = str(prop).replace("`", "``")
                    statement = f"DROP INDEX ON :`{safe_label}`(`{safe_prop}`)"
                else:
                    statement = f"DROP INDEX ON :`{safe_label}`"
                try:
                    session.run(statement).consume()
                except Exception:
                    pass
        except Exception:
            pass

    completed = subprocess.run(
        [sys.executable, ETL_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=300,
    )
    assert completed.returncode == 0, f"etl.py failed:\n{completed.stdout}"

    # The ETL must not change the relational source used to derive the oracle.
    with pg.cursor() as cur:
        cur.execute("SELECT event_id, user_id, event_timestamp, event_type FROM raw_events ORDER BY event_id")
        assert cur.fetchall() == source_rows, "etl.py modified raw_events."
    pg.close()

    with driver.session() as session:
        graph_rows = [
            (r["event_id"], r["user_id"], r["event_type"])
            for r in session.run("MATCH (e:Event) RETURN e.event_id AS event_id, e.user_id AS user_id, e.event_type AS event_type")
        ]
        expected_nodes = sorted((event_id, user_id, event_type) for event_id, user_id, _, event_type in source_rows)
        assert sorted(graph_rows) == expected_nodes, "Event nodes do not exactly represent raw_events."

        total_nodes = session.run("MATCH (n) RETURN count(n) AS n").single()["n"]
        assert total_nodes == len(source_rows), "Graph contains unexpected non-Event or duplicate nodes."

        graph_edges = sorted(
            (r["a"], r["b"])
            for r in session.run("MATCH (a:Event)-[:NEXT]->(b:Event) RETURN a.event_id AS a, b.event_id AS b")
        )
        assert graph_edges == expected_edges, "NEXT relationships do not match immediate same-user events within 60 minutes."
        total_relationships = session.run("MATCH ()-[r]->() RETURN count(r) AS n").single()["n"]
        assert total_relationships == len(expected_edges), "Graph contains unexpected relationships."

        strategy_records = []
        try:
            strategy_records.extend(r.data() for r in session.run("SHOW INDEX INFO"))
        except Exception:
            pass
        try:
            strategy_records.extend(r.data() for r in session.run("SHOW CONSTRAINT INFO"))
        except Exception:
            pass
        strategy_text = " ".join(str(v).lower() for r in strategy_records for v in r.values())
        assert "event" in strategy_text, "No index or constraint was created for Event nodes."

        records = list(session.run(query))
        assert len(records) == 1, f"Query must return exactly one row, returned {len(records)}."
        record = records[0]
        keys = record.keys()
        assert "step1" in keys, "Result must contain 'step1' column."
        assert "step2" in keys, "Result must contain 'step2' column."
        assert "step3" in keys, "Result must contain 'step3' column."
        assert "frequency" in keys, "Result must contain 'frequency' column."
        returned_path = (record["step1"], record["step2"], record["step3"])
        assert returned_path in expected_winners, f"Query returned {returned_path}, not an actual most-frequent path."
        assert record["frequency"] == max_frequency, \
            f"Expected frequency {max_frequency}, got {record['frequency']}."

    # Preserve the original 50-iteration, strict 15 ms performance assertion.
    with driver.session() as session:
        session.run(query).consume()
    start = time.time()
    for _ in range(50):
        with driver.session() as session:
            result = session.run(query)
            _ = result.single()
    duration = (time.time() - start) / 50.0
    driver.close()
    assert duration < 0.015, \
        f"Query execution time was {duration:.4f}s per run, which exceeds the 0.015s threshold. Indexes might be missing or the query is not optimized."
PY

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
