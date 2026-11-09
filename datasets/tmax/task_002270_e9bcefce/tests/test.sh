#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import subprocess
import urllib.parse
import urllib.request
import uuid
import zipfile


def read_result():
    result_path = "/home/user/result.json"
    assert os.path.exists(result_path), f"Expected output file not found at {result_path}"
    with open(result_path, encoding="utf-8") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as e:
            raise AssertionError(f"Failed to parse JSON in {result_path}: {e}") from e


def post_form(url, fields, accept=None):
    headers = {"Content-Type": "application/x-www-form-urlencoded"}
    if accept:
        headers["Accept"] = accept
    req = urllib.request.Request(
        url,
        data=urllib.parse.urlencode(fields).encode(),
        headers=headers,
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=15) as response:
        assert 200 <= response.status < 300, f"HTTP request to {url} failed: {response.status}"
        return response.read()


def test_complete_pipeline():
    # Preserve all assertions made by the original verifier.
    data = read_result()
    assert "source" in data, "JSON missing required key 'source'"
    assert data["source"] == "user1", f"Expected source to be 'user1', got '{data['source']}'"
    assert "transitive_connections" in data, "JSON missing required key 'transitive_connections'"
    expected_connections = ["user2", "user3", "user4", "user7"]
    actual_connections = data["transitive_connections"]
    assert isinstance(actual_connections, list), "'transitive_connections' must be a list"
    assert sorted(actual_connections) == expected_connections, \
        f"Expected transitive_connections to contain {expected_connections}, got {sorted(actual_connections)}"
    assert actual_connections == expected_connections, \
        f"Expected transitive_connections to be sorted alphabetically: {expected_connections}, got {actual_connections}"

    # Confirm the requested Fuseki distribution and live in-memory /ds service exist.
    fuseki_dir = "/home/user/fuseki"
    assert os.path.isdir(fuseki_dir), "Fuseki was not extracted to /home/user/fuseki"
    jar_paths = []
    for root, _, files in os.walk(fuseki_dir):
        for name in files:
            if name.endswith(".jar") and "fuseki" in name.lower():
                jar_paths.append(os.path.join(root, name))
    assert jar_paths, "No Apache Jena Fuseki server JAR found under /home/user/fuseki"
    version_found = False
    for jar in jar_paths:
        try:
            with zipfile.ZipFile(jar) as zf:
                manifest = zf.read("META-INF/MANIFEST.MF").decode("utf-8", "replace")
                if "4.8.0" in manifest:
                    version_found = True
                    break
        except (KeyError, zipfile.BadZipFile):
            pass
    assert version_found, "Installed Fuseki artifacts are not version 4.8.0"

    live_fuseki = False
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            cmdline = open(f"/proc/{pid}/cmdline", "rb").read().replace(b"\0", b" ").decode("utf-8", "replace")
        except OSError:
            continue
        if "fuseki" in cmdline.lower() and ("/ds" in cmdline or "--mem" in cmdline):
            live_fuseki = True
            break
    assert live_fuseki, "No running Fuseki process configured for the in-memory /ds dataset was found"
    with urllib.request.urlopen("http://localhost:3030/$/ping", timeout=10) as response:
        assert 200 <= response.status < 300, "Fuseki is not responding on port 3030"

    etl_path = "/home/user/etl.go"
    query_path = "/home/user/query.go"
    assert os.path.isfile(etl_path), "Required Go ETL program /home/user/etl.go is missing"
    go_files = [etl_path]
    if os.path.exists(query_path):
        assert os.path.isfile(query_path), "/home/user/query.go is not a regular file"
        go_files.append(query_path)

    for path in go_files:
        formatted = subprocess.run(
            ["gofmt", "-d", path], capture_output=True, text=True, timeout=15
        )
        assert formatted.returncode == 0 and not formatted.stdout, f"Go source is not gofmt-formatted: {path}"

    sources = "\n".join(open(path, encoding="utf-8").read() for path in go_files)
    etl_source = open(etl_path, encoding="utf-8").read()
    assert "/ds/update" in etl_source and re.search(r"INSERT\s+DATA", etl_source, re.I), \
        "etl.go must perform a SPARQL INSERT DATA against /ds/update"
    assert "/ds/query" in sources and re.search(r"SELECT\b", sources, re.I), \
        "The Go pipeline must execute a SPARQL SELECT against /ds/query"
    assert "knows" in sources and "+" in sources, \
        "The query source does not contain a transitive knows property path"

    # Replace the fixture with an unpredictable graph, clear Fuseki, and execute
    # the submitted programs. This prevents a precomputed result.json from passing.
    network_path = "/home/user/network.csv"
    with open(network_path, "rb") as f:
        original_csv = f.read()

    token = uuid.uuid4().hex[:10]
    a, b, c, d, e, branch = [f"n_{token}_{x}" for x in ("a", "b", "c", "d", "e", "branch")]
    outsider = f"n_{token}_outsider"
    liked = f"n_{token}_liked"
    rows = [
        ("user1", "knows", a),
        (a, "knows", b),
        (b, "knows", c),
        (c, "knows", d),
        (d, "knows", e),
        (b, "knows", branch),
        (e, "knows", a),
        (outsider, "knows", "user1"),
        ("user1", "likes", liked),
    ]
    try:
        with open(network_path, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(("subject", "predicate", "object"))
            writer.writerows(rows)

        post_form("http://localhost:3030/ds/update", {"update": "CLEAR ALL"})

        env = os.environ.copy()
        env["HOME"] = "/home/user"
        etl_run = subprocess.run(
            ["go", "run", etl_path], cwd="/home/user", env=env,
            capture_output=True, text=True, timeout=120
        )
        assert etl_run.returncode == 0, f"etl.go failed:\n{etl_run.stdout}\n{etl_run.stderr}"

        if os.path.exists(query_path):
            query_run = subprocess.run(
                ["go", "run", query_path], cwd="/home/user", env=env,
                capture_output=True, text=True, timeout=120
            )
            assert query_run.returncode == 0, f"query.go failed:\n{query_run.stdout}\n{query_run.stderr}"

        # Independently query Fuseki to verify that every CSV row was mapped to
        # the required example.org URI triple and actually loaded into /ds.
        raw = post_form(
            "http://localhost:3030/ds/query",
            {"query": "SELECT ?s ?p ?o WHERE { ?s ?p ?o }"},
            "application/sparql-results+json",
        )
        bindings = json.loads(raw)["results"]["bindings"]
        actual_triples = {
            (item["s"]["value"], item["p"]["value"], item["o"]["value"])
            for item in bindings
        }
        expected_triples = {
            tuple(f"http://example.org/{part}" for part in row) for row in rows
        }
        assert actual_triples == expected_triples, \
            f"Fuseki dataset does not contain exactly the RDF triples from network.csv: {actual_triples}"

        dynamic_result = read_result()
        expected_dynamic = sorted([a, b, c, d, e, branch])
        assert dynamic_result == {
            "source": "user1",
            "transitive_connections": expected_dynamic,
        }, f"Pipeline produced the wrong projection for the dynamic graph: {dynamic_result}"
    finally:
        with open(network_path, "wb") as f:
            f.write(original_csv)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
