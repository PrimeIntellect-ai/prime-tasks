#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess


def test_sampled_events_file():
    file_path = '/home/user/sampled_events.jsonl'

    assert os.path.exists(file_path), f"The file {file_path} is missing."
    assert os.path.isfile(file_path), f"The path {file_path} is not a file."

    line_count = 0
    actions_count = {"view": 0, "click": 0, "purchase": 0}

    with open(file_path, 'r') as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    record = json.loads(line)
                except json.JSONDecodeError:
                    assert False, f"Invalid JSON on line {line_count + 1} in {file_path}."

                assert "user_id" in record, "Missing user_id in sampled record."
                assert "item_id" in record, "Missing item_id in sampled record."
                assert "action" in record, "Missing action in sampled record."
                assert "timestamp" in record, "Missing timestamp in sampled record."

                action = record["action"]
                assert action in actions_count, f"Invalid normalized action '{action}' found."
                actions_count[action] += 1
                line_count += 1

    assert line_count == 280, f"Expected exactly 280 lines in {file_path}, but found {line_count}."
    assert actions_count["view"] == 100, f"Expected 100 views, found {actions_count['view']}."
    assert actions_count["click"] == 100, f"Expected 100 clicks, found {actions_count['click']}."
    assert actions_count["purchase"] == 80, f"Expected 80 purchases, found {actions_count['purchase']}."


def test_pipeline_run_log():
    file_path = '/home/user/pipeline_run.json'

    assert os.path.exists(file_path), f"The file {file_path} is missing."
    assert os.path.isfile(file_path), f"The path {file_path} is not a file."

    with open(file_path, 'r') as f:
        try:
            log_data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"The file {file_path} is not valid JSON."

    expected_data = {
        "records_read": 580,
        "dropped_missing_fields": 20,
        "dropped_unknown_action": 15,
        "duplicates_removed": 15,
        "final_counts": {
            "view": 100,
            "click": 100,
            "purchase": 80
        }
    }

    assert log_data == expected_data, f"Pipeline log data does not match expected output. Got: {log_data}"


def normalize_action(value):
    value = str(value).lower()
    if "view" in value:
        return "view"
    if "click" in value:
        return "click"
    if "purchase" in value or "buy" in value:
        return "purchase"
    return None


def derive_expected(records):
    required = ("user_id", "item_id", "action", "timestamp")
    cleaned = []
    seen = set()
    missing = unknown = duplicates = 0

    for source in records:
        if any(key not in source for key in required):
            missing += 1
            continue
        action = normalize_action(source["action"])
        if action is None:
            unknown += 1
            continue
        key = (source["user_id"], source["item_id"], action, source["timestamp"])
        if key in seen:
            duplicates += 1
            continue
        seen.add(key)
        cleaned.append({
            "user_id": source["user_id"],
            "item_id": source["item_id"],
            "action": action,
            "timestamp": source["timestamp"],
        })

    selected = {}
    for action in ("view", "click", "purchase"):
        category = [record for record in cleaned if record["action"] == action]
        category.sort(key=lambda record: (record["timestamp"], record["user_id"]))
        selected[action] = category[:100]

    log = {
        "records_read": len(records),
        "dropped_missing_fields": missing,
        "dropped_unknown_action": unknown,
        "duplicates_removed": duplicates,
        "final_counts": {action: len(selected[action]) for action in ("view", "click", "purchase")},
    }
    return selected, log


def validate_probe_output(expected, expected_log):
    sampled_path = '/home/user/sampled_events.jsonl'
    log_path = '/home/user/pipeline_run.json'
    assert os.path.isfile(sampled_path), "Script did not create sampled_events.jsonl."
    assert os.path.isfile(log_path), "Script did not create pipeline_run.json."

    actual = {"view": [], "click": [], "purchase": []}
    with open(sampled_path, 'r') as handle:
        for line_number, line in enumerate(handle, 1):
            if not line.strip():
                continue
            record = json.loads(line)
            assert all(key in record for key in ("user_id", "item_id", "action", "timestamp")), \
                f"Probe output line {line_number} is missing a required field."
            assert record["action"] in actual, f"Probe output has invalid action {record['action']!r}."
            actual[record["action"]].append((
                record["user_id"], record["item_id"], record["action"], record["timestamp"]
            ))

    for action in actual:
        expected_rows = [
            (record["user_id"], record["item_id"], record["action"], record["timestamp"])
            for record in expected[action]
        ]
        assert actual[action] == expected_rows, \
            f"Probe output for {action} was not the required sorted, deduplicated sample."

    with open(log_path, 'r') as handle:
        actual_log = json.load(handle)
    assert actual_log == expected_log, f"Probe pipeline log is incorrect: {actual_log}"


def test_python_pipeline_executes_on_derived_probe():
    raw_path = '/home/user/raw_events.jsonl'
    sampled_path = '/home/user/sampled_events.jsonl'
    log_path = '/home/user/pipeline_run.json'

    candidates = []
    for directory, _, files in os.walk('/home/user'):
        for name in files:
            path = os.path.join(directory, name)
            if name.endswith('.py') and os.path.isfile(path):
                candidates.append(path)
    assert candidates, "No Python pipeline script was written under /home/user."

    variants = {
        "view": ["VIEW", "viewed", "Preview"],
        "click": ["CLICK", "Clicked", "doubleCLICK"],
        "purchase": ["Purchase", "buy", "BUYING"],
    }
    sizes = {"view": 107, "click": 104, "purchase": 83}
    probe = []
    bases = {action: [] for action in sizes}
    nonce = os.urandom(5).hex()

    for action, size in sizes.items():
        for i in range(size):
            record = {
                "user_id": f"{nonce}_{action}_u{i:03d}",
                "item_id": f"{nonce}_item_{action}_{i:03d}",
                "action": variants[action][i % len(variants[action])],
                "timestamp": 1700000000 + ((i * 37) % 131),
            }
            bases[action].append(record)
            probe.append(record)

    # These become duplicates only after action normalization.
    for action in ("view", "click", "purchase"):
        for index in (2, 7):
            duplicate = dict(bases[action][index])
            duplicate["action"] = variants[action][(index + 1) % len(variants[action])]
            probe.append(duplicate)

    for i in range(7):
        probe.append({
            "user_id": f"{nonce}_missing_{i}",
            "action": "SCROLL" if i % 2 else "view",
            "timestamp": 1800000000 + i,
        })
    for i in range(9):
        probe.append({
            "user_id": f"{nonce}_unknown_{i}",
            "item_id": f"unknown_item_{i}",
            "action": "SCROLL",
            "timestamp": 1810000000 + i,
        })

    random.SystemRandom().shuffle(probe)
    expected, expected_log = derive_expected(probe)

    backups = {}
    for path in (raw_path, sampled_path, log_path):
        backups[path] = open(path, 'rb').read() if os.path.exists(path) else None

    errors = []
    try:
        for candidate in sorted(candidates):
            with open(raw_path, 'w') as handle:
                for record in probe:
                    handle.write(json.dumps(record) + '\n')
            for path in (sampled_path, log_path):
                try:
                    os.remove(path)
                except FileNotFoundError:
                    pass

            try:
                result = subprocess.run(
                    ['python3', candidate], cwd=os.path.dirname(candidate) or '/home/user',
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
                )
                assert result.returncode == 0, f"exit code {result.returncode}: {result.stderr[-500:]}"
                validate_probe_output(expected, expected_log)
                return
            except Exception as exc:
                errors.append(f"{candidate}: {exc}")

        assert False, "No submitted Python script correctly processed the probe input. " + " | ".join(errors)
    finally:
        for path, content in backups.items():
            if content is None:
                try:
                    os.remove(path)
                except FileNotFoundError:
                    pass
            else:
                with open(path, 'wb') as handle:
                    handle.write(content)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
