#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import re
import stat
import subprocess
import uuid


def mongosh(eval_js):
    result = subprocess.run(
        ["mongosh", "iot", "--quiet", "--eval", eval_js],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"mongosh failed: {result.stderr}"
    return result.stdout.strip()


def parse_json_file(path):
    assert os.path.isfile(path), f"Required file {path} was not created."
    with open(path, encoding="utf-8") as f:
        content = f.read().strip()
    assert content, f"Required file {path} is empty."
    try:
        return json.loads(content), content
    except json.JSONDecodeError as exc:
        raise AssertionError(f"{path} is not valid JSON: {exc}")


def numeric(value):
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, dict) and len(value) == 1:
        key, inner = next(iter(value.items()))
        if key in ("$numberDouble", "$numberInt", "$numberLong", "$numberDecimal"):
            try:
                return float(inner)
            except (TypeError, ValueError):
                return None
    return None


def walk(value):
    yield value
    if isinstance(value, dict):
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def pipelines_in(value):
    found = []
    for node in walk(value):
        if isinstance(node, dict) and isinstance(node.get("pipeline"), list):
            found.append(node["pipeline"])
    return found


def test_complete_pipeline():
    executable = "/home/user/analyze"
    source_path = "/home/user/analyze.cpp"
    assert os.path.isfile(executable), f"Executable {executable} not found."
    assert os.access(executable, os.X_OK), f"{executable} is not executable."
    assert os.path.isfile(source_path), f"C++ source {source_path} not found."

    with open(source_path, encoding="utf-8", errors="replace") as f:
        source = f.read()
    assert "mongoimport" in source, "The C++ program does not construct a mongoimport command."
    assert "mongosh" in source, "The C++ program does not construct a mongosh command."
    assert re.search(r"\b(?:system|popen)\s*\(", source), \
        "The C++ program does not invoke its shell commands with system() or popen()."

    token = uuid.uuid4().hex[:8]
    rng = random.SystemRandom()
    base = rng.randrange(2000, 8000)
    locations = [f"Harbor_{token}", f"Ridge_{token}", f"Vale_{token}"]
    sensors = [f"X{i}_{token}" for i in range(1, 5)]
    a, b, c, d, e, f = [rng.randrange(120, 380) / 10.0 for _ in range(6)]

    rows = [
        [sensors[0], locations[0], a, base + 1, "OK"],
        [sensors[0], locations[0], b, base + 11, "OK"],
        [sensors[1], locations[0], c, base + 4, "OK"],
        [sensors[1], locations[0], 999.7, base + 15, "ERROR"],
        [sensors[2], locations[1], d, base + 6, "OK"],
        [sensors[2], locations[1], 888.6, base + 18, "CORRUPTED"],
        [sensors[3], locations[2], e, base + 3, "OK"],
        [sensors[3], locations[2], f, base + 14, "OK"],
    ]
    expected = {
        locations[0]: (b + c) / 2.0,
        locations[1]: d,
        locations[2]: f,
    }

    with open("/home/user/sensor_dump.csv", "w", newline="", encoding="utf-8") as out:
        writer = csv.writer(out, lineterminator="\n")
        writer.writerow(["sensor_id", "location", "temp", "timestamp", "status"])
        writer.writerows(rows)

    for artifact in ("/home/user/final_report.json", "/home/user/query_plan.json"):
        try:
            os.remove(artifact)
        except FileNotFoundError:
            pass

    # Start from an empty collection and profile the commands issued by analyze.
    mongosh('db.setProfilingLevel(0); db.readings.drop(); db.system.profile.drop(); db.setProfilingLevel(2);')

    wrapper_dir = "/tmp/verifier-command-wrappers"
    os.makedirs(wrapper_dir, exist_ok=True)
    command_log = "/tmp/analyze-command.log"
    open(command_log, "w").close()
    for command in ("mongoimport", "mongosh"):
        real = subprocess.run(["bash", "-lc", f"command -v {command}"], capture_output=True, text=True, check=True).stdout.strip()
        wrapper = os.path.join(wrapper_dir, command)
        with open(wrapper, "w", encoding="utf-8") as fobj:
            fobj.write(f'#!/bin/sh\necho "{command} $*" >> {command_log}\nexec {real} "$@"\n')
        os.chmod(wrapper, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR)

    env = os.environ.copy()
    env["PATH"] = wrapper_dir + os.pathsep + env.get("PATH", "")
    try:
        result = subprocess.run(
            [executable], capture_output=True, text=True, timeout=90, env=env
        )
    except subprocess.TimeoutExpired:
        raise AssertionError(f"Execution of {executable} timed out.")
    assert result.returncode == 0, \
        f"Execution failed with code {result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"

    with open(command_log, encoding="utf-8") as fobj:
        command_calls = fobj.read()

    # Confirm the current randomized CSV was actually imported into MongoDB.
    docs_text = mongosh('JSON.stringify(db.readings.find({}, {_id:0}).toArray())')
    try:
        docs = json.loads(docs_text)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"Could not parse imported readings: {exc}; output={docs_text!r}")
    assert len(docs) == len(rows), "iot.readings does not contain exactly the randomized CSV rows."

    actual_rows = set()
    for doc in docs:
        assert all(k in doc for k in ("sensor_id", "location", "temp", "timestamp", "status")), \
            f"Imported document has the wrong schema: {doc!r}"
        temp = numeric(doc["temp"])
        timestamp = numeric(doc["timestamp"])
        assert temp is not None and timestamp is not None, \
            "Temperature and timestamp must be imported as numeric values."
        actual_rows.add((str(doc["sensor_id"]), str(doc["location"]), temp, timestamp, str(doc["status"])))
    expected_rows = {(str(s), str(loc), float(temp), float(ts), str(status)) for s, loc, temp, ts, status in rows}
    assert actual_rows == expected_rows, "MongoDB contents do not match the randomized CSV input."

    report, report_content = parse_json_file("/home/user/final_report.json")
    assert isinstance(report, list), "final_report.json must be a JSON array of aggregation results."
    assert len(report) == len(expected), "The final report has missing or unexpected location rows."

    seen = set()
    for item in report:
        assert isinstance(item, dict), "Every final report entry must be a JSON object."
        matching_locations = [loc for loc in expected if loc in item.values()]
        assert len(matching_locations) == 1, \
            f"Could not associate report entry with exactly one location: {item!r}"
        location = matching_locations[0]
        assert location not in seen, f"Duplicate result for location {location}."
        seen.add(location)

        averages = []
        for key, value in item.items():
            lowered = str(key).lower()
            if "avg" in lowered or "average" in lowered or "temp" in lowered:
                number = numeric(value)
                if number is not None:
                    averages.append(number)
        assert averages, f"No numeric average-temperature field was found for {location}."
        assert any(math.isclose(value, expected[location], rel_tol=1e-9, abs_tol=1e-9) for value in averages), \
            f"Incorrect average associated with {location}: expected {expected[location]}, got {averages}."
    assert seen == set(expected), "The final report does not contain exactly the expected locations."

    plan, plan_content = parse_json_file("/home/user/query_plan.json")
    assert isinstance(plan, (dict, list)), "query_plan.json must contain a JSON explain result."
    assert any(isinstance(node, dict) and "executionStats" in node for node in walk(plan)), \
        "query_plan.json does not contain explain(\"executionStats\") output."
    assert any(keyword in plan_content for keyword in ("explainVersion", "executionStats", "queryPlanner")), \
        "query_plan.json does not appear to contain MongoDB explain output."

    profile_text = mongosh('JSON.stringify(db.system.profile.find({ns:"iot.readings"}).toArray())')
    try:
        profile = json.loads(profile_text)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"Could not parse MongoDB profiler output: {exc}")

    profile_dump = json.dumps(profile)
    assert "mongoimport" in command_calls or "mongoimport" in profile_dump.lower(), \
        "No evidence that the program invoked mongoimport."
    assert "mongosh" in command_calls, "No evidence that the program invoked mongosh."
    assert any(
        isinstance(node, dict) and (node.get("op") == "insert" or node.get("insert") == "readings")
        for node in walk(profile)
    ), "MongoDB profiler did not observe the CSV import into iot.readings."

    executed_pipelines = pipelines_in(profile)
    valid_pipeline = False
    for pipeline in executed_pipelines:
        stage_names = [next(iter(stage)) for stage in pipeline if isinstance(stage, dict) and len(stage) == 1]
        text = json.dumps(pipeline)
        if ("$match" in stage_names and "$sort" in stage_names and stage_names.count("$group") >= 2
                and all(field in text for field in ("status", "timestamp", "sensor_id", "location", "temp"))):
            valid_pipeline = True
            break
    assert valid_pipeline, \
        "MongoDB profiler did not observe the required match, sort, latest-per-sensor, and location aggregation pipeline."

    indexes_text = mongosh('JSON.stringify(db.readings.getIndexes())')
    try:
        indexes = json.loads(indexes_text)
    except json.JSONDecodeError:
        raise AssertionError("Failed to parse the index list from MongoDB.")

    # Preserve the original custom-index assertion and require one index that
    # jointly supports the status filter and sensor/timestamp ordering.
    assert any(
        any(field in idx.get("key", {}) for field in ("status", "timestamp", "sensor_id"))
        for idx in indexes
    ), "No appropriate custom index was found in iot.readings."
    assert any(
        all(field in idx.get("key", {}) for field in ("status", "sensor_id", "timestamp"))
        for idx in indexes
    ), "No compound index targets both status filtering and sensor/timestamp sorting."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
