#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import difflib
import glob
import json
import os
import random
import shutil
import subprocess
import sys

import pytest


def test_results_json_exists():
    results_path = "/home/user/results.json"
    assert os.path.exists(results_path), f"Expected output file not found at {results_path}"
    assert os.path.isfile(results_path), f"{results_path} is not a file"


def test_semantic_similarity_threshold():
    results_path = "/home/user/results.json"
    assert os.path.exists(results_path), "Cannot evaluate metric: results.json is missing."

    with open(results_path, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {results_path} is not a valid JSON file.")

    expected = {
        "What is the status of the humidity sensors?": "The humidity sensors in sector A are showing anomalous readings",
        "How well is the visual anomaly detection model performing?": "It is now achieving 94 percent accuracy on the validation set",
        "What supplies need to be ordered?": "I need to order more nutrient solution for the hydroponics bay tomorrow"
    }

    scores = []
    for query, expected_ans in expected.items():
        expected_clean = expected_ans.lower().strip('. !?')

        user_ans = results.get(query, "")
        user_clean = str(user_ans).lower().strip('. !?')

        ratio = difflib.SequenceMatcher(None, expected_clean, user_clean).ratio()
        scores.append(ratio)

    avg_score = sum(scores) / len(scores) if scores else 0.0
    threshold = 0.80

    assert avg_score >= threshold, (
        f"Average string similarity ratio {avg_score:.4f} is below the required threshold of {threshold}. "
        f"Individual scores: {scores}"
    )


def find_pipeline_command():
    pipeline_dir = "/home/user/pipeline"
    assert os.path.isdir(pipeline_dir), f"Pipeline directory not found: {pipeline_dir}"

    for makefile in ("Makefile", "makefile"):
        if os.path.isfile(os.path.join(pipeline_dir, makefile)):
            return ["make", "-f", makefile]

    preferred_shell = ("run.sh", "main.sh", "pipeline.sh", "execute.sh")
    for name in preferred_shell:
        path = os.path.join(pipeline_dir, name)
        if os.path.isfile(path):
            return ["bash", path]

    shell_scripts = sorted(glob.glob(os.path.join(pipeline_dir, "*.sh")))
    if shell_scripts:
        return ["bash", shell_scripts[0]]

    for name in ("main.py", "pipeline.py", "run.py"):
        path = os.path.join(pipeline_dir, name)
        if os.path.isfile(path):
            return [sys.executable, path]

    pytest.fail(
        "No reproducible pipeline entry point found. Expected a Makefile, shell runner, "
        "or main.py/pipeline.py/run.py in /home/user/pipeline/."
    )


def test_pipeline_runs_on_unseen_audio_and_queries():
    command = find_pipeline_command()
    audio_path = "/app/research_log.wav"
    queries_path = "/app/search_queries.txt"
    results_path = "/home/user/results.json"

    with open(audio_path, "rb") as f:
        original_audio = f.read()
    with open(queries_path, "rb") as f:
        original_queries = f.read()

    rng = random.SystemRandom()
    sector = rng.choice(["north", "south", "east", "west"])
    condition = rng.choice(["unstable", "normal", "erratic", "steady"])
    performance = rng.choice(["excellent", "strong", "poor", "improved"])
    supply = rng.choice(["copper tubing", "rubber gloves", "glass bottles", "filter paper"])
    location = rng.choice(["irrigation bench", "field station", "sample room", "testing bay"])

    sentences = [
        f"The humidity sensor in the {sector} sector reports {condition} readings",
        f"The image model showed {performance} performance during validation",
        f"We must order {supply} for the {location}"
    ]
    queries = [
        "What is the status of the humidity sensor?",
        "How is the image model performing?",
        "What item must be ordered?"
    ]
    expected = dict(zip(queries, sentences))

    try:
        spoken_text = ". ".join(sentences) + "."
        subprocess.run(
            ["espeak-ng", "-w", audio_path, spoken_text],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        with open(queries_path, "w", encoding="utf-8") as f:
            f.write("\n".join(queries) + "\n")

        if os.path.lexists(results_path):
            if os.path.isdir(results_path) and not os.path.islink(results_path):
                shutil.rmtree(results_path)
            else:
                os.unlink(results_path)

        completed = subprocess.run(
            command,
            cwd="/home/user/pipeline",
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=600,
        )
        assert completed.returncode == 0, (
            f"Pipeline command {command!r} failed with exit code {completed.returncode}.\n"
            f"Output:\n{completed.stdout[-6000:]}"
        )
        assert os.path.isfile(results_path), "Pipeline did not recreate /home/user/results.json"

        try:
            with open(results_path, "r", encoding="utf-8") as f:
                results = json.load(f)
        except (OSError, json.JSONDecodeError) as exc:
            pytest.fail(f"Pipeline produced an invalid results.json: {exc}")

        assert isinstance(results, dict), "Pipeline output must be a JSON dictionary"
        assert set(results.keys()) == set(queries), (
            "Pipeline output keys must exactly match the unseen queries from search_queries.txt"
        )

        scores = []
        for query, expected_answer in expected.items():
            actual = str(results[query]).lower().strip(". !?")
            target = expected_answer.lower().strip(". !?")
            scores.append(difflib.SequenceMatcher(None, target, actual).ratio())

        average = sum(scores) / len(scores)
        assert min(scores) >= 0.45 and average >= 0.65, (
            "Pipeline did not transcribe and retrieve the unseen audio sentences accurately. "
            f"Average similarity: {average:.4f}; individual scores: {scores}"
        )
    finally:
        with open(audio_path, "wb") as f:
            f.write(original_audio)
        with open(queries_path, "wb") as f:
            f.write(original_queries)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
