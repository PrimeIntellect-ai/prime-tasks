#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import json
import os
import subprocess
import tempfile
import uuid

SCRIPT_PATH = "/home/user/process_translations.py"
CLEAN_CORPUS_DIR = "/app/corpora/clean"
EVIL_CORPUS_DIR = "/app/corpora/evil"
VENDORED_UTILS = "/app/vendored/loc-math-parser-0.1.0/loc_math_parser/utils.py"


def run_script(input_dir, output_dir, env=None):
    return subprocess.run(
        ["python3", SCRIPT_PATH, input_dir, output_dir],
        capture_output=True,
        text=True,
        env=env,
    )


def expected_output(data):
    parsed = datetime.datetime.strptime(data["timestamp"], "%Y-%m-%d %H:%M:%S")
    return {
        "id": data["id"],
        "iso_timestamp": parsed.isoformat(),
        "tokenized": data["math_text"].split(),
    }


def write_inputs(directory, records):
    for index, record in enumerate(records):
        with open(os.path.join(directory, f"input_{index}.json"), "w") as handle:
            json.dump(record, handle)


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."


def test_clean_corpus_preserved_with_id_filenames_and_exact_content():
    with tempfile.TemporaryDirectory() as tmp_out:
        result = run_script(CLEAN_CORPUS_DIR, tmp_out)
        assert result.returncode == 0, f"Script failed on clean corpus. Stderr: {result.stderr}"

        inputs = []
        for filename in os.listdir(CLEAN_CORPUS_DIR):
            if filename.endswith(".json"):
                with open(os.path.join(CLEAN_CORPUS_DIR, filename)) as handle:
                    inputs.append(json.load(handle))

        expected_names = {f"{data['id']}.json" for data in inputs}
        processed_names = {f for f in os.listdir(tmp_out) if f.endswith(".json")}
        assert processed_names == expected_names

        for data in inputs:
            with open(os.path.join(tmp_out, f"{data['id']}.json")) as handle:
                output = json.load(handle)
            assert output == expected_output(data)
            assert "T" in output["iso_timestamp"]
            assert isinstance(output["tokenized"], list)
            assert output["tokenized"]


def test_evil_corpus_rejected():
    with tempfile.TemporaryDirectory() as tmp_out:
        result = run_script(EVIL_CORPUS_DIR, tmp_out)
        assert result.returncode == 0, f"Script failed on evil corpus. Stderr: {result.stderr}"
        processed_files = [f for f in os.listdir(tmp_out) if f.endswith(".json")]
        assert not processed_files, f"Poisoned files produced outputs: {processed_files}"


def test_randomized_mixed_corpus_and_required_parser_calls():
    nonce = uuid.uuid4().hex
    clean = [
        {
            "id": f"safe_{nonce}_a",
            "timestamp": "2024-02-29 23:58:07",
            "math_text": f"Factor z_{nonce}^2 + 7z + 10",
        },
        {
            "id": f"safe_{nonce}_b",
            "timestamp": "1999-12-31 00:01:02",
            "math_text": f"Compare x < y and compute token_{nonce}",
        },
        {
            "id": f"safe_{nonce}_c",
            "timestamp": "2031-06-05 09:08:07",
            "math_text": f"The contact notation user(at)example is safe {nonce}",
        },
    ]
    poisoned = [
        {
            "id": f"mail_{nonce}",
            "timestamp": "2025-01-02 03:04:05",
            "math_text": f"Find x, then email Tutor_{nonce}@Example-domain.com for help",
        },
        {
            "id": f"tag_{nonce}",
            "timestamp": "2025-02-03 04:05:06",
            "math_text": f"Simplify <widget data-key=\"{nonce}\">x+1</widget> now",
        },
    ]

    with tempfile.TemporaryDirectory() as tmp_in, tempfile.TemporaryDirectory() as tmp_out, tempfile.TemporaryDirectory() as spy_root:
        write_inputs(tmp_in, clean + poisoned)
        package_dir = os.path.join(spy_root, "loc_math_parser")
        os.mkdir(package_dir)
        open(os.path.join(package_dir, "__init__.py"), "w").close()
        with open(os.path.join(package_dir, "utils.py"), "w") as handle:
            handle.write(
                "import datetime, os\n"
                "def parse_time(ts):\n"
                "    with open(os.environ['LOC_MATH_SPY_LOG'], 'a') as f: f.write('parse\\t' + ts + '\\n')\n"
                "    return datetime.datetime.strptime(ts, '%Y-%m-%d %H:%M:%S')\n"
            )
        with open(os.path.join(package_dir, "tokenizer.py"), "w") as handle:
            handle.write(
                "import os\n"
                "def tokenize_math(text):\n"
                "    with open(os.environ['LOC_MATH_SPY_LOG'], 'a') as f: f.write('tokenize\\t' + text + '\\n')\n"
                "    return text.split()\n"
            )

        spy_log = os.path.join(spy_root, "calls.log")
        env = os.environ.copy()
        env["PYTHONPATH"] = spy_root + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
        env["LOC_MATH_SPY_LOG"] = spy_log
        result = run_script(tmp_in, tmp_out, env=env)
        assert result.returncode == 0, f"Script failed on generated corpus. Stderr: {result.stderr}"

        expected_names = {f"{item['id']}.json" for item in clean}
        actual_names = {f for f in os.listdir(tmp_out) if f.endswith(".json")}
        assert actual_names == expected_names
        for item in clean:
            with open(os.path.join(tmp_out, f"{item['id']}.json")) as handle:
                assert json.load(handle) == expected_output(item)

        assert os.path.isfile(spy_log), "The required loc_math_parser functions were not called."
        with open(spy_log) as handle:
            calls = handle.read().splitlines()
        for item in clean:
            assert f"parse\t{item['timestamp']}" in calls
            assert f"tokenize\t{item['math_text']}" in calls


def test_vendored_package_fixed_and_installed():
    assert os.path.isfile(VENDORED_UTILS), f"File {VENDORED_UTILS} is missing."
    with open(VENDORED_UTILS) as handle:
        content = handle.read()
    assert "strptime" in content, f"The typo in {VENDORED_UTILS} was not fixed to 'strptime'."
    assert "strp_time" not in content, f"The typo 'strp_time' is still present in {VENDORED_UTILS}."

    code = """
import datetime
from importlib.metadata import version
from loc_math_parser.utils import parse_time
from loc_math_parser.tokenizer import tokenize_math
assert version('loc-math-parser') == '0.1.0'
assert parse_time('2028-02-29 13:14:15') == datetime.datetime(2028, 2, 29, 13, 14, 15)
assert tokenize_math('alpha  x^2 + 1') == ['alpha', 'x^2', '+', '1']
"""
    with tempfile.TemporaryDirectory() as cwd:
        env = os.environ.copy()
        env.pop("PYTHONPATH", None)
        result = subprocess.run(["python3", "-c", code], cwd=cwd, env=env, capture_output=True, text=True)
    assert result.returncode == 0, f"The fixed package is not correctly installed/importable: {result.stderr}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
