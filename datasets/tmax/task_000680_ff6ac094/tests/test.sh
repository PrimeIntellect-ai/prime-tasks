#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re

import numpy as np
import pytest
import requests
from sentence_transformers import SentenceTransformer
from transformers import pipeline


def normalize_transcription(text):
    return " ".join(re.findall(r"\w+", text.casefold(), flags=re.UNICODE))


def test_predict_intent_endpoint():
    """Test the endpoint against results independently derived from the required models."""
    url = "http://127.0.0.1:5000/predict_intent"
    wav_path = "/app/support_call.wav"
    intents_path = "/app/intents.json"

    assert os.path.isfile(wav_path), f"Test file {wav_path} is missing."
    assert os.path.isfile(intents_path), f"Intent file {intents_path} is missing."

    with open(wav_path, "rb") as f:
        audio_data = f.read()

    try:
        response = requests.post(
            url,
            data=audio_data,
            headers={"Content-Type": "audio/wav"},
            timeout=30,
        )
    except requests.exceptions.ConnectionError:
        pytest.fail(f"Failed to connect to the service at {url}. Is the server running?")
    except requests.exceptions.Timeout:
        pytest.fail(f"Request to {url} timed out.")

    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. "
        f"Response: {response.text}"
    )

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response body: {response.text}")

    assert "transcription" in data, "Response JSON missing 'transcription' key."
    assert "intent" in data, "Response JSON missing 'intent' key."
    assert set(data.keys()) == {"transcription", "intent"}, (
        f"Response JSON must contain exactly 'transcription' and 'intent'; got {sorted(data.keys())}."
    )
    assert isinstance(data["transcription"], str), "'transcription' must be a string."
    assert isinstance(data["intent"], str), "'intent' must be a string."

    asr = pipeline(
        "automatic-speech-recognition",
        model="openai/whisper-tiny",
        device=-1,
    )
    expected_transcription = asr(wav_path)["text"]

    assert normalize_transcription(data["transcription"]) == normalize_transcription(expected_transcription), (
        "Transcription does not match openai/whisper-tiny. "
        f"Expected {expected_transcription!r}, got {data['transcription']!r}."
    )

    with open(intents_path, "r", encoding="utf-8") as f:
        intents = json.load(f)

    embedder = SentenceTransformer("sentence-transformers/all-MiniLM-L6-v2")
    descriptions = [item["description"] for item in intents]
    description_embeddings = embedder.encode(descriptions, convert_to_numpy=True)
    transcription_embedding = embedder.encode([expected_transcription], convert_to_numpy=True)[0]

    description_norms = np.linalg.norm(description_embeddings, axis=1)
    transcription_norm = np.linalg.norm(transcription_embedding)
    similarities = (description_embeddings @ transcription_embedding) / (
        description_norms * transcription_norm
    )
    expected_intent = intents[int(np.argmax(similarities))]["intent_name"]

    actual_intent = data["intent"]
    assert actual_intent == expected_intent, (
        f"Expected intent '{expected_intent}', got '{actual_intent}'."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
