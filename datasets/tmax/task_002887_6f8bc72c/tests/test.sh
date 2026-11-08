#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import math
import operator
import os
import shutil
import subprocess
import tempfile
import uuid

import pytest

FILTER = "/home/user/filter.py"
MAKEFILE = "/home/user/Makefile"
REPORT = "/home/user/final_report.csv"


def reference_math(expression):
    binary_ops = {
        ast.Add: operator.add,
        ast.Sub: operator.sub,
        ast.Mult: operator.mul,
        ast.Div: operator.truediv,
    }
    unary_ops = {ast.UAdd: operator.pos, ast.USub: operator.neg}

    def evaluate(node):
        if isinstance(node, ast.Expression):
            return evaluate(node.body)
        if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)) and not isinstance(node.value, bool):
            return node.value
        if isinstance(node, ast.BinOp) and type(node.op) in binary_ops:
            return binary_ops[type(node.op)](evaluate(node.left), evaluate(node.right))
        if isinstance(node, ast.UnaryOp) and type(node.op) in unary_ops:
            return unary_ops[type(node.op)](evaluate(node.operand))
        raise ValueError("unsafe or unsupported expression")

    value = evaluate(ast.parse(expression, mode="eval"))
    if not isinstance(value, (int, float)) or isinstance(value, bool) or not math.isfinite(value):
        raise ValueError("non-finite result")
    return value


def run_filter(directory):
    result = subprocess.run(
        ["python3", FILTER, directory], capture_output=True, text=True, timeout=15
    )
    assert result.returncode == 0, f"filter.py failed: {result.stderr}"
    try:
        output = json.loads(result.stdout)
    except json.JSONDecodeError:
        pytest.fail("filter.py did not output a single valid JSON value")
    assert isinstance(output, list), "filter.py output must be a JSON array"
    assert all(isinstance(item, dict) for item in output), "Every output item must be an object"
    return output


def assert_exact_clean_output(output, expected):
    assert len(output) == len(expected), "Filter added, duplicated, or dropped clean records"
    ids = [item.get("id") for item in output]
    assert len(ids) == len(set(ids)), "Filter output contains duplicate IDs"
    assert set(ids) == set(expected), "Filter did not preserve exactly the clean IDs"

    by_id = {item["id"]: item for item in output}
    for record_id, source in expected.items():
        item = by_id[record_id]
        assert set(item) == set(source) | {"metric_value"}, "Required fields were changed or unexpected fields were added"
        assert item["id"] == source["id"]
        assert item["metric_formula"] == source["metric_formula"]
        value = item["metric_value"]
        assert isinstance(value, (int, float)) and not isinstance(value, bool), "metric_value must be numeric"
        assert math.isfinite(value)
        assert math.isclose(value, reference_math(source["metric_formula"]), rel_tol=1e-12, abs_tol=1e-12)


def test_filter_clean_corpus():
    clean_dir = "/app/corpora/clean"
    expected_ids = set()
    expected = {}
    for fname in os.listdir(clean_dir):
        if fname.endswith(".json"):
            with open(os.path.join(clean_dir, fname)) as f:
                try:
                    data = json.load(f)
                    expected_ids.add(data.get("id"))
                    expected[data["id"]] = data
                except json.JSONDecodeError:
                    pass

    output_data = run_filter(clean_dir)
    output_ids = {item.get("id") for item in output_data if isinstance(item, dict)}
    missing = expected_ids - output_ids
    if missing:
        pytest.fail(f"{len(missing)} of {len(expected_ids)} clean modified/rejected. Missing IDs: {missing}")

    assert_exact_clean_output(output_data, expected)


def test_filter_evil_corpus():
    evil_dir = "/app/corpora/evil"
    expected_ids = set()
    for fname in os.listdir(evil_dir):
        if fname.endswith(".json"):
            with open(os.path.join(evil_dir, fname)) as f:
                try:
                    data = json.load(f)
                    expected_ids.add(data.get("id"))
                except json.JSONDecodeError:
                    pass

    output_data = run_filter(evil_dir)
    output_ids = {item.get("id") for item in output_data if isinstance(item, dict)}
    bypassed = expected_ids.intersection(output_ids)
    if bypassed:
        pytest.fail(f"{len(bypassed)} of {len(expected_ids)} evil bypassed. Bypassed IDs: {bypassed}")

    assert output_data == [], "The evil-only corpus must produce an empty array"


def test_filter_random_mixed_adversarial_corpus():
    marker = f"/tmp/filter_marker_{uuid.uuid4().hex}"
    safe_records = [
        {"id": "safe-a", "metric_formula": "(4 + 5) * 2"},
        {"id": "safe-b", "metric_formula": "100 / 4"},
        {"id": "safe-c", "metric_formula": "-5 + 12.5"},
        {"id": "safe-d", "metric_formula": "8 * (7 - (3 + 1))"},
    ]
    evil_formulas = [
        f"__import__('os').system('touch {marker}')",
        "open('/etc/passwd').read()",
        "eval('1 + 1')",
        "(1).__class__.__mro__",
        "[x for x in [1, 2, 3]]",
        "abs(-3)",
        "1 if 1 else 0",
        "1 / 0",
    ]

    with tempfile.TemporaryDirectory(prefix="logs_", dir="/tmp") as corpus:
        for index, record in enumerate(safe_records):
            with open(os.path.join(corpus, f"entry_{index}.json"), "w") as f:
                json.dump(record, f)
        evil_ids = set()
        for index, formula in enumerate(evil_formulas):
            record_id = f"attack-{index}"
            evil_ids.add(record_id)
            with open(os.path.join(corpus, f"payload_{index}.json"), "w") as f:
                json.dump({"id": record_id, "metric_formula": formula}, f)
        with open(os.path.join(corpus, "broken.json"), "w") as f:
            f.write('{"id": "broken",')
        with open(os.path.join(corpus, "not_object.json"), "w") as f:
            json.dump(["not", "an", "object"], f)

        output = run_filter(corpus)

    assert not os.path.exists(marker), "A malicious expression executed code"
    assert evil_ids.isdisjoint({item.get("id") for item in output}), "Malicious records were retained"
    assert_exact_clean_output(output, {record["id"]: record for record in safe_records})


def extract_multiplier(video_path):
    result = subprocess.run(
        [
            "ffmpeg", "-v", "error", "-i", video_path,
            "-vf", "fps=1,scale=1:1,format=gray", "-f", "rawvideo", "-"
        ],
        capture_output=True,
        timeout=30,
    )
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    pixels = list(result.stdout)
    assert len(pixels) == 12, f"Expected 12 video frames, got {len(pixels)}"
    bits = "".join("1" if pixel > 128 else "0" for pixel in pixels)
    return int(bits, 2)


def create_video(path, bits):
    assert len(bits) == 12
    with tempfile.TemporaryDirectory(prefix="frames_", dir="/tmp") as frames:
        for index, bit in enumerate(bits):
            value = 255 if bit == "1" else 0
            with open(os.path.join(frames, f"img_{index:02d}.ppm"), "w") as out:
                out.write("P3\n10 10\n255\n")
                out.write((f"{value} {value} {value}\n") * 100)
        result = subprocess.run(
            [
                "ffmpeg", "-v", "error", "-y", "-framerate", "1",
                "-i", os.path.join(frames, "img_%02d.ppm"), "-c:v", "libx264",
                "-r", "1", "-pix_fmt", "yuv420p", path
            ],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, result.stderr


def assert_report(expected_records, users, multiplier):
    assert os.path.isfile(REPORT), f"Final report not found at {REPORT}"
    with open(REPORT, newline="") as f:
        rows = list(csv.reader(f))
    assert rows and rows[0] == ["id", "user_name", "department", "final_metric"], "Incorrect CSV header"
    body = rows[1:]
    expected_ids = sorted(expected_records)
    assert [row[0] for row in body] == expected_ids, "Report IDs are missing, duplicated, or not alphanumerically sorted"
    assert len(body) == len(expected_ids)
    assert all(len(row) == 4 for row in body)
    assert len({row[0] for row in body}) == len(body), "Report is not deduplicated"

    for row in body:
        record_id, user_name, department, final_metric = row
        assert (user_name, department) == users[record_id], "User data was not joined correctly"
        expected_value = reference_math(expected_records[record_id]) * multiplier
        try:
            actual_value = float(final_metric)
        except ValueError:
            pytest.fail(f"final_metric for {record_id} is not numeric")
        assert math.isfinite(actual_value)
        assert math.isclose(actual_value, expected_value, rel_tol=1e-12, abs_tol=1e-12), "Incorrect formula evaluation or multiplier"


def run_make(target=None):
    command = ["make", "-B", "-C", "/home/user"]
    if target is not None:
        command.append(target)
    result = subprocess.run(command, capture_output=True, text=True, timeout=90)
    assert result.returncode == 0, f"make failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"


def test_makefile_executes_video_filter_and_merge_pipeline():
    assert os.path.isfile(MAKEFILE), "A Makefile must exist at /home/user/Makefile"
    assert os.path.isfile(FILTER), "filter.py must exist at /home/user/filter.py"

    video = "/app/transmission.mp4"
    users_csv = "/app/user_data.csv"
    raw_logs = "/app/raw_logs"
    backup_root = tempfile.mkdtemp(prefix="pipeline_backup_", dir="/tmp")
    backup_video = os.path.join(backup_root, "transmission.mp4")
    backup_users = os.path.join(backup_root, "user_data.csv")
    backup_logs = os.path.join(backup_root, "raw_logs")
    shutil.copy2(video, backup_video)
    shutil.copy2(users_csv, backup_users)
    shutil.copytree(raw_logs, backup_logs)

    custom_records = {"10": "(7 - 2) * 3", "2": "100 / 4"}
    custom_users = {"10": ("Alice", "Research"), "2": ("Bob", "Operations")}

    try:
        create_video(video, "000000001011")
        shutil.rmtree(raw_logs)
        os.mkdir(raw_logs)
        with open(os.path.join(raw_logs, "one.json"), "w") as f:
            json.dump({"id": "10", "metric_formula": custom_records["10"]}, f)
        with open(os.path.join(raw_logs, "duplicate.json"), "w") as f:
            json.dump({"id": "10", "metric_formula": custom_records["10"]}, f)
        with open(os.path.join(raw_logs, "two.json"), "w") as f:
            json.dump({"id": "2", "metric_formula": custom_records["2"]}, f)
        with open(os.path.join(raw_logs, "evil.json"), "w") as f:
            json.dump({"id": "999", "metric_formula": "__import__('os')"}, f)
        with open(users_csv, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["id", "user_name", "department"])
            writer.writerow(["2", "Bob", "Operations"])
            writer.writerow(["10", "Alice", "Research"])
            writer.writerow(["999", "Mallory", "Security"])

        if os.path.exists(REPORT):
            os.remove(REPORT)
        run_make()
        multiplier = extract_multiplier(video)
        assert multiplier == 11
        assert_report(custom_records, custom_users, multiplier)
    finally:
        shutil.copy2(backup_video, video)
        shutil.copy2(backup_users, users_csv)
        if os.path.exists(raw_logs):
            shutil.rmtree(raw_logs)
        shutil.copytree(backup_logs, raw_logs)
        shutil.rmtree(backup_root)

    if os.path.exists(REPORT):
        os.remove(REPORT)
    run_make("all")

    original_records = {str(i): f"{i} + {i}" for i in range(1, 5)}
    original_users = {str(i): (f"User{i}", f"Dept{i % 3}") for i in range(1, 5)}
    assert_report(original_records, original_users, extract_multiplier(video))


def test_final_report_exists_and_format():
    report_path = "/home/user/final_report.csv"
    assert os.path.isfile(report_path), f"Final report not found at {report_path}"

    with open(report_path, "r") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["id", "user_name", "department", "final_metric"], "Incorrect CSV header in final report."
        rows = list(reader)
        assert len(rows) > 0, "Final report CSV is empty."
        ids = [row[0] for row in rows]
        assert ids == sorted(ids), "Final report CSV is not sorted alphanumerically by id."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
