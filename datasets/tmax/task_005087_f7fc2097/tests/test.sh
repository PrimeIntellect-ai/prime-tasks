#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import json
import math
import os
import re
import secrets
import subprocess
import time
import urllib.parse
import urllib.request

import numpy as np

MONGO = ["mongosh", "--quiet", "mongodb://127.0.0.1:27017/retail", "--eval"]
RESULTS = "/home/user/results.ndjson"
SERVICE = "/home/user/analytics_service"


def mongo(script, timeout=300):
    proc = subprocess.run(MONGO + [script], text=True, capture_output=True, timeout=timeout)
    assert proc.returncode == 0, f"mongosh failed: {proc.stderr or proc.stdout}"
    return proc.stdout.strip()


def mongo_json(script, timeout=300):
    output = mongo(script, timeout)
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    assert lines, "mongosh returned no JSON output"
    return json.loads(lines[-1])


def fetch(url):
    start = time.perf_counter()
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=10) as response:
            response.read()
            status = response.status
    except Exception:
        status = 500
    return time.perf_counter() - start, status


def listener_process_on_8080():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].rsplit(":", 1)[-1].upper() == "1F90" and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    for pid in (p for p in os.listdir("/proc") if p.isdigit()):
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    exe = os.path.realpath(f"/proc/{pid}/exe")
                    return int(pid), exe
        except OSError:
            continue
    return None, None


def truncate_results():
    with open(RESULTS, "w"):
        pass


def read_and_validate_results(expected):
    assert os.path.exists(RESULTS), f"Results file {RESULTS} does not exist. Did the service write the output?"
    with open(RESULTS) as f:
        lines = [line.strip() for line in f if line.strip()]
    assert lines, "Results file is empty."

    records = []
    for line in lines:
        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            raise AssertionError(f"Line of {RESULTS} is not valid JSON: {line}")
        assert "category" in data, "Missing 'category' in result JSON."
        assert "total_spent" in data, "Missing 'total_spent' in result JSON."
        assert isinstance(data["category"], str), "category must be a JSON string"
        assert isinstance(data["total_spent"], (int, float)) and not isinstance(data["total_spent"], bool), \
            "total_spent must be a JSON number"
        records.append(data)

    # Preserve the original last-line format assertion explicitly.
    last = records[-1]
    assert "category" in last and "total_spent" in last

    expected_map = {row["category"]: float(row["total_spent"]) for row in expected}
    observed_categories = {row["category"] for row in records}
    assert observed_categories == set(expected_map), \
        f"Export categories do not match MongoDB: expected {set(expected_map)}, got {observed_categories}"
    for row in records:
        want = expected_map[row["category"]]
        got = float(row["total_spent"])
        assert math.isclose(got, want, rel_tol=1e-9, abs_tol=1e-6), \
            f"Wrong total for {row['category']}: expected {want}, got {got}"


def expected_for(customer):
    customer_json = json.dumps(customer)
    return mongo_json(f'''
const d = db.getSiblingDB("retail");
const out = d.orders.aggregate([
  {{$match: {{customer_id: {customer_json}}}}},
  {{$unwind: "$items"}},
  {{$group: {{_id: "$items.category", total_spent: {{$sum: "$items.price"}}}}}},
  {{$project: {{_id: 0, category: "$_id", total_spent: 1}}}},
  {{$sort: {{category: 1}}}}
]).toArray();
print(JSON.stringify(out));
''')


def test_latency_and_correctness():
    token = secrets.token_hex(8)
    categories = [f"verify_{token}_{i}" for i in range(4)]
    injection_customer = f'inj_{token}_"}}], "$limit": 0, "x": "'

    fixtures = []
    for i in range(40):
        fixtures.append({
            "customer_id": "CUST_999",
            "order_no": f"verify-{token}-{i}",
            "items": [
                {"category": categories[i % 4], "price": (i + 3) * 7},
                {"category": categories[(i + 1) % 4], "price": (i + 5) * 11},
            ],
        })
    fixtures.extend([
        {"customer_id": injection_customer, "order_no": f"inj-{token}-1",
         "items": [{"category": f"injcat_{token}_a", "price": 137}]},
        {"customer_id": injection_customer, "order_no": f"inj-{token}-2",
         "items": [{"category": f"injcat_{token}_b", "price": 251},
                   {"category": f"injcat_{token}_a", "price": 19}]},
    ])

    # Install unpredictable verification records and compensate for the broken
    # image setup by ensuring the promised collection scale exists.
    fixture_json = json.dumps(fixtures)
    prefix = json.dumps(f"filler_{token}_")
    mongo(f'''
const d = db.getSiblingDB("retail");
d.orders.deleteMany({{customer_id: {{$in: ["CUST_999", {json.dumps(injection_customer)}]}}}});
d.orders.insertMany({fixture_json});
let need = Math.max(0, 200000 - d.orders.estimatedDocumentCount());
for (let off = 0; off < need; off += 5000) {{
  const n = Math.min(5000, need - off);
  const batch = [];
  for (let i = 0; i < n; ++i) {{
    const k = off + i;
    batch.push({{
      _id: {prefix} + k,
      customer_id: "LOAD_" + (k % 10000),
      order_no: "load-" + k,
      items: [{{category: "General", price: (k % 97) + 1}},
              {{category: "Household", price: (k % 31) + 1}}]
    }});
  }}
  d.orders.insertMany(batch, {{ordered: false}});
}}
print("ok");
''', timeout=300)

    count = mongo_json('const d=db.getSiblingDB("retail"); print(JSON.stringify(d.orders.estimatedDocumentCount()));')
    assert count >= 200000, f"Expected the promised 200,000 order documents, found {count}"

    pid, exe = listener_process_on_8080()
    assert pid is not None, "No process is listening on port 8080"
    expected_prefix = os.path.join(SERVICE, "target", "release") + os.sep
    assert exe.startswith(expected_prefix) and os.path.basename(exe) == "analytics_service", \
        f"Port 8080 must be served by the release Rust analytics_service binary, not {exe}"
    with open(exe, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The service executable is not a compiled native binary"

    queries_path = os.path.join(SERVICE, "src", "queries.rs")
    assert os.path.isfile(queries_path), "src/queries.rs is missing"
    source = open(queries_path).read()
    assert re.search(r"\bdoc\s*!", source), "queries.rs must construct the query with the BSON doc! macro"

    # Record the actual command sent by the service and verify that its real
    # aggregation filters before unwinding, rather than trusting source shape.
    mongo('const d=db.getSiblingDB("retail"); d.setProfilingLevel(0); d.system.profile.drop(); d.setProfilingLevel(2, {slowms: 0}); print("ok");')
    try:
        truncate_results()
        _, status = fetch("http://127.0.0.1:8080/export?customer_id=CUST_999")
        assert status == 200, "The CUST_999 export request failed"
    finally:
        mongo('const d=db.getSiblingDB("retail"); d.setProfilingLevel(0); print("ok");')

    profile = mongo_json('''
const d=db.getSiblingDB("retail");
const p=d.system.profile.find({"command.aggregate":"orders"}).sort({ts:-1}).limit(1).toArray();
print(JSON.stringify(p.length ? p[0].command.pipeline : null));
''')
    assert isinstance(profile, list) and profile, "The service did not execute a MongoDB aggregation on retail.orders"
    assert "$match" in profile[0], "The aggregation pipeline must filter with $match as its first stage"
    assert "CUST_999" in json.dumps(profile[0]), "The first $match does not use the requested customer_id"
    unwind_positions = [i for i, stage in enumerate(profile) if "$unwind" in stage]
    assert unwind_positions and unwind_positions[0] > 0, "$unwind must occur after the customer $match"

    indexes = mongo_json('const d=db.getSiblingDB("retail"); print(JSON.stringify(d.orders.getIndexes()));')
    useful_index = False
    for index in indexes:
        keys = list(index.get("key", {}).keys())
        if keys and keys[0] == "customer_id":
            useful_index = True
            break
    assert useful_index, "retail.orders needs an index whose leading key is customer_id"

    expected_injection = expected_for(injection_customer)
    assert expected_injection, "Injection test fixture was not inserted"
    truncate_results()
    injection_url = "http://127.0.0.1:8080/export?" + urllib.parse.urlencode({"customer_id": injection_customer})
    _, injection_status = fetch(injection_url)
    assert injection_status == 200, "A customer_id containing query syntax was not handled as a BSON value"
    read_and_validate_results(expected_injection)

    expected = expected_for("CUST_999")
    assert len(expected) == len(categories), "MongoDB verification fixture produced unexpected results"
    truncate_results()

    url = "http://127.0.0.1:8080/export?customer_id=CUST_999"
    times = []
    statuses = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=500) as executor:
        futures = [executor.submit(fetch, url) for _ in range(500)]
        for future in concurrent.futures.as_completed(futures):
            elapsed, status = future.result()
            times.append(elapsed)
            statuses.append(status)

    success_count = sum(1 for status in statuses if status == 200)
    assert success_count == 500, \
        f"Expected 500 successful requests, got {success_count}. Is the service running and handling load?"

    p95 = np.percentile(times, 95)
    read_and_validate_results(expected)
    assert p95 <= 0.250, \
        f"P95 latency is {p95:.4f}s, which is greater than the threshold of 0.250s. The query is not optimized enough."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
