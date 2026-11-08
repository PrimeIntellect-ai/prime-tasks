#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re

import pytest
import requests

BASE_URL = "http://127.0.0.1:8000"
FILE_PATH = "/home/user/processed_data.json"
REFERENCE_WORDS = """The project alpha deployment is complete. System latency decreased by twenty milliseconds. We observed some anomalies in the database cluster. Please investigate the node memory usage."""


def words(text):
    return re.findall(r"[a-z0-9]+(?:'[a-z0-9]+)?", text.lower())


def normalized(text):
    return " ".join(words(text))


def edit_distance(a, b):
    previous = list(range(len(b) + 1))
    for i, left in enumerate(a, 1):
        current = [i]
        for j, right in enumerate(b, 1):
            current.append(min(
                current[-1] + 1,
                previous[j] + 1,
                previous[j - 1] + (left != right),
            ))
        previous = current
    return previous[-1]


def get_json(method, path, **kwargs):
    try:
        response = requests.request(method, BASE_URL + path, timeout=5, **kwargs)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to {BASE_URL + path}: {exc}")
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    try:
        return response.json()
    except ValueError:
        pytest.fail(f"Response from {path} is not valid JSON")


def load_data():
    assert os.path.isfile(FILE_PATH), f"Expected processed data file at {FILE_PATH} does not exist."
    try:
        with open(FILE_PATH, encoding="utf-8") as handle:
            return json.load(handle)
    except json.JSONDecodeError:
        pytest.fail(f"File {FILE_PATH} is not valid JSON.")


def sentence_list(data):
    value = data.get("sentences", data.get("tokenized_sentences"))
    assert isinstance(value, list), "processed_data.json must contain a sentence list"
    assert value and all(isinstance(item, str) and words(item) for item in value)
    return value


def file_ci(data, name):
    value = data.get(name)
    if value is None and isinstance(data.get("stats"), dict):
        value = data["stats"].get(name)
    assert isinstance(value, list) and len(value) == 2, f"{name} must be a list of two numbers"
    assert all(isinstance(x, (int, float)) and not isinstance(x, bool) and math.isfinite(x) for x in value)
    return value


def binomial_quantile(n, p, probability):
    cumulative = 0.0
    for value in range(n + 1):
        cumulative += math.comb(n, value) * (p ** value) * ((1.0 - p) ** (n - value))
        if cumulative + 1e-12 >= probability:
            return value
    return n


def assert_bootstrap_ci(actual, transcript_words, target):
    n = len(transcript_words)
    count = transcript_words.count(target)
    assert n > 0
    lower = binomial_quantile(n, count / n, 0.025)
    upper = binomial_quantile(n, count / n, 0.975)
    # A 1,000-draw empirical percentile occasionally places the upper endpoint
    # between the theoretical quantile and the next count; retain that legitimate
    # Monte Carlo variation while rejecting arbitrary bounds.
    assert abs(actual[0] - lower) <= 0.05, (
        f"{target} lower CI {actual[0]} disagrees with recomputation ({lower})"
    )
    assert upper - 0.05 <= actual[1] <= upper + 1.05, (
        f"{target} upper CI {actual[1]} disagrees with recomputation ({upper})"
    )
    assert actual[0] <= actual[1]


def jaccard(query, sentence):
    q = set(words(query))
    s = set(words(sentence))
    union = q | s
    return len(q & s) / len(union) if union else 0.0


def expected_match(query, sentences):
    scores = [jaccard(query, sentence) for sentence in sentences]
    best = max(scores)
    assert scores.count(best) == 1, f"Verifier query unexpectedly tied: {query}"
    return sentences[scores.index(best)]


def test_server_is_bound_strictly_to_ipv4_loopback():
    listeners = []
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        if not os.path.exists(table):
            continue
        with open(table) as handle:
            next(handle)
            for line in handle:
                fields = line.split()
                address, state = fields[1], fields[3]
                host, port = address.split(":")
                if state == "0A" and int(port, 16) == 8000:
                    listeners.append((table, host))
    assert listeners, "No process is listening on port 8000"
    assert listeners == [("/proc/net/tcp", "0100007F")], (
        f"Port 8000 must listen strictly on 127.0.0.1, found {listeners}"
    )


def test_processed_data_and_transcription_tokenization():
    data = load_data()
    transcript = data.get("transcript")
    assert isinstance(transcript, str) and transcript.strip(), "Missing full transcript"

    transcript_words = words(transcript)
    reference_words = words(REFERENCE_WORDS)
    assert edit_distance(transcript_words, reference_words) <= 5, (
        "Transcript does not adequately correspond to status_update.wav"
    )
    for expected in ["alpha", "latency", "anomalies", "database"]:
        assert expected in transcript_words, f"Expected word '{expected}' not found in transcript."

    sentences = sentence_list(data)
    assert len(sentences) >= 4, "The status update should be tokenized into its individual sentences"
    flattened = [token for sentence in sentences for token in words(sentence)]
    assert flattened == transcript_words, "Sentence tokens must cover the transcript in order"

    split_transcript = [part for part in re.split(r"[.!?]+", transcript) if words(part)]
    assert [normalized(x) for x in sentences] == [normalized(x) for x in split_transcript], (
        "Stored sentences do not match sentence tokenization of the transcript"
    )


def test_transcript_and_stats_endpoints_match_file_and_recomputation():
    data = load_data()
    transcript = data["transcript"]
    transcript_words = words(transcript)

    transcript_response = get_json("GET", "/transcript")
    assert "transcript" in transcript_response, "Response JSON missing 'transcript' key."
    assert transcript_response["transcript"] == transcript

    stats_response = get_json("GET", "/stats")
    assert "latency_ci" in stats_response, "Response JSON missing 'latency_ci' key."
    assert "database_ci" in stats_response, "Response JSON missing 'database_ci' key."

    latency_ci = stats_response["latency_ci"]
    database_ci = stats_response["database_ci"]
    assert isinstance(latency_ci, list) and len(latency_ci) == 2, "'latency_ci' must be a list of two numbers."
    assert isinstance(database_ci, list) and len(database_ci) == 2, "'database_ci' must be a list of two numbers."
    for value in latency_ci + database_ci:
        assert isinstance(value, (int, float)) and not isinstance(value, bool), "CI bounds must be numbers"
        assert math.isfinite(value)

    assert latency_ci == file_ci(data, "latency_ci")
    assert database_ci == file_ci(data, "database_ci")
    assert_bootstrap_ci(latency_ci, transcript_words, "latency")
    assert_bootstrap_ci(database_ci, transcript_words, "database")


def test_search_endpoint_uses_jaccard_over_stored_sentences():
    data = load_data()
    sentences = sentence_list(data)

    original = get_json("POST", "/search", json={"query": "how much did latency drop"})
    assert "match" in original, "Response JSON missing 'match' key."
    assert "latency decreased" in original["match"].lower(), (
        f"Expected 'latency decreased' in match, got '{original['match']}'"
    )
    assert normalized(original["match"]) == normalized(expected_match("how much did latency drop", sentences))

    queries = [
        "project deployment complete",
        "system latency milliseconds",
        "observed cluster anomalies",
        "please investigate node memory",
    ]
    for query in queries:
        expected = expected_match(query, sentences)
        result = get_json("POST", "/search", json={"query": query})
        assert set(result) >= {"match"}
        assert isinstance(result["match"], str)
        assert normalized(result["match"]) == normalized(expected), (
            f"Incorrect Jaccard match for query {query!r}: {result['match']!r}"
        )

    # Exact, punctuation-heavy queries must independently retrieve every stored sentence.
    for sentence in sentences:
        query = "!!! " + sentence.upper() + " ???"
        result = get_json("POST", "/search", json={"query": query})
        assert normalized(result.get("match", "")) == normalized(sentence)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
