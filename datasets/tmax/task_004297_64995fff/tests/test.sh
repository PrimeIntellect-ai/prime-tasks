#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import json
import requests

def test_metrics_endpoint():
    """Verify that the background HTTP server is running and returns the expected metrics."""
    url = "http://127.0.0.1:9090/metrics"
    try:
        resp = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        raise AssertionError(f"Failed to connect to the server at {url}. Is it running? Error: {e}")

    assert resp.status_code == 200, f"Expected HTTP 200 OK, got {resp.status_code}"

    try:
        data = resp.json()
    except json.JSONDecodeError:
        raise AssertionError(f"Expected JSON response, got: {resp.text}")

    assert "transcription" in data, "Response JSON is missing the 'transcription' key."

    # Clean up the transcription string to handle varying whisper output formats
    transcription = data["transcription"].upper().replace(" ", "").replace(",", "").replace(".", "")
    assert transcription == "MACKLEY", f"Expected transcription to be 'MACKLEY', got '{data['transcription']}'"

    assert "wasserstein_distance" in data, "Response JSON is missing the 'wasserstein_distance' key."
    assert isinstance(data["wasserstein_distance"], float), f"Expected 'wasserstein_distance' to be a float, got {type(data['wasserstein_distance'])}"

    # Calculate expected Wasserstein distance manually to verify the value
    std_aa = "ACDEFGHIKLMNPQRSTVWY"
    seq1 = "MACKLEY"
    seq2 = "MACKLEYMACKLEYMACKLEYAAACCC"

    def get_prob_dist(seq):
        counts = {aa: 0 for aa in std_aa}
        for aa in seq:
            if aa in counts:
                counts[aa] += 1
        total = sum(counts.values())
        return [counts[aa] / total for aa in std_aa]

    p1 = get_prob_dist(seq1)
    p2 = get_prob_dist(seq2)

    # 1D Wasserstein distance is the L1 distance between the CDFs
    cdf1 = 0.0
    cdf2 = 0.0
    expected_distance = 0.0
    for prob1, prob2 in zip(p1, p2):
        cdf1 += prob1
        cdf2 += prob2
        expected_distance += abs(cdf1 - cdf2)

    actual_distance = data["wasserstein_distance"]
    assert abs(actual_distance - expected_distance) < 1e-4, f"Expected wasserstein_distance to be approx {expected_distance:.4f}, got {actual_distance}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
