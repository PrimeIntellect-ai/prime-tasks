#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
from difflib import SequenceMatcher

import faiss
import numpy as np
import requests
import soundfile as sf
import torch
from sentence_transformers import SentenceTransformer
from transformers import AutoModelForSpeechSeq2Seq, AutoProcessor

INDEX_PATH = "/home/user/faiss_index.bin"
CHUNKS_PATH = "/home/user/chunks.json"
AUDIO_PATH = "/app/data/support_call.wav"
URL = "http://127.0.0.1:8080/search"
GOOD_HEADERS = {"Authorization": "Bearer etl-secure-token-2024"}


def normalized_words(text):
    return " ".join(re.findall(r"[a-z0-9]+", text.lower()))


def load_chunks():
    assert os.path.isfile(INDEX_PATH), f"FAISS index file missing at {INDEX_PATH}"
    assert os.path.getsize(INDEX_PATH) > 0, f"FAISS index file at {INDEX_PATH} is empty"
    assert os.path.isfile(CHUNKS_PATH), f"Chunks file missing at {CHUNKS_PATH}"

    with open(CHUNKS_PATH, "r", encoding="utf-8") as f:
        try:
            chunks = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {CHUNKS_PATH} is not valid JSON"

    assert isinstance(chunks, list), f"Chunks file {CHUNKS_PATH} must contain a JSON array"
    assert len(chunks) > 0, "Chunks array is empty"
    assert all(isinstance(c, str) for c in chunks), "All items in chunks array must be strings"
    assert all(c == c.strip() and c for c in chunks), "Chunks must be nonempty and stripped"
    return chunks


def transcribe_reference():
    audio, rate = sf.read(AUDIO_PATH, dtype="float32")
    assert rate == 16000, f"Unexpected audio sample rate: {rate}"
    if audio.ndim > 1:
        audio = audio.mean(axis=1)

    model_name = "openai/whisper-tiny"
    processor = AutoProcessor.from_pretrained(model_name)
    model = AutoModelForSpeechSeq2Seq.from_pretrained(model_name)
    model.eval()
    inputs = processor(audio, sampling_rate=rate, return_tensors="pt", return_attention_mask=True)
    kwargs = {}
    if "attention_mask" in inputs:
        kwargs["attention_mask"] = inputs.attention_mask
    with torch.inference_mode():
        ids = model.generate(inputs.input_features, **kwargs)
    return processor.batch_decode(ids, skip_special_tokens=True)[0].strip()


def test_transcription_and_sentence_chunks():
    chunks = load_chunks()

    # Joining the submitted chunks and applying the required regex must reproduce
    # exactly the submitted boundaries.
    submitted_transcript = " ".join(chunks)
    resplit = [c.strip() for c in re.split(r"(?<=[.?])\s+", submitted_transcript) if c.strip()]
    assert resplit == chunks, "Chunks do not follow the required sentence-boundary regex"

    reference_transcript = transcribe_reference()
    reference_chunks = [
        c.strip() for c in re.split(r"(?<=[.?])\s+", reference_transcript) if c.strip()
    ]

    submitted_norm = normalized_words(submitted_transcript)
    reference_norm = normalized_words(reference_transcript)
    similarity = SequenceMatcher(None, submitted_norm, reference_norm).ratio()
    assert similarity >= 0.88, (
        "Submitted chunks do not represent the Whisper transcription of support_call.wav; "
        f"similarity was {similarity:.3f}"
    )
    assert len(chunks) == len(reference_chunks), (
        f"Expected {len(reference_chunks)} sentence chunks from Whisper output, got {len(chunks)}"
    )
    for i, (actual, expected) in enumerate(zip(chunks, reference_chunks)):
        ratio = SequenceMatcher(None, normalized_words(actual), normalized_words(expected)).ratio()
        assert ratio >= 0.78, f"Chunk {i} does not match the corresponding transcribed sentence"


def test_faiss_index_matches_embeddings():
    chunks = load_chunks()
    try:
        index = faiss.read_index(INDEX_PATH)
    except Exception as exc:
        assert False, f"Could not load FAISS index: {exc}"

    assert isinstance(index, faiss.IndexFlatL2), "FAISS index must be IndexFlatL2"
    assert index.metric_type == faiss.METRIC_L2, "FAISS index must use L2 distance"
    assert index.ntotal == len(chunks), "FAISS vector count must equal the chunks count"

    embedder = SentenceTransformer("sentence-transformers/all-MiniLM-L6-v2")
    expected = np.asarray(embedder.encode(chunks), dtype=np.float32)
    assert expected.ndim == 2
    assert index.d == expected.shape[1], "FAISS dimension does not match all-MiniLM-L6-v2"

    stored = np.empty((index.ntotal, index.d), dtype=np.float32)
    index.reconstruct_n(0, index.ntotal, stored)
    assert np.allclose(stored, expected, rtol=1e-4, atol=1e-5), (
        "FAISS vectors do not match the ordered all-MiniLM-L6-v2 chunk embeddings"
    )


def post_search(query, headers=GOOD_HEADERS):
    try:
        return requests.post(URL, json={"query": query}, headers=headers, timeout=10)
    except requests.RequestException as exc:
        assert False, f"Failed to connect to API on 127.0.0.1:8080: {exc}"


def test_api_unauthorized():
    response = post_search("test", {"Authorization": "Bearer wrong-token"})
    assert response.status_code == 401, (
        f"Expected 401 Unauthorized for wrong token, got {response.status_code}"
    )

    invalid_headers = [
        {},
        {"Authorization": "etl-secure-token-2024"},
        {"Authorization": "bearer etl-secure-token-2024"},
        {"Authorization": "Bearer etl-secure-token-2024 "},
        {"Authorization": "Bearer  etl-secure-token-2024"},
    ]
    for headers in invalid_headers:
        response = post_search("test", headers)
        assert response.status_code == 401, f"Invalid Authorization header was accepted: {headers}"


def expected_match(query, index, chunks, embedder):
    vector = np.asarray(embedder.encode([query]), dtype=np.float32)
    _, positions = index.search(vector, 1)
    return chunks[int(positions[0, 0])]


def assert_authorized_result(query, expected):
    response = post_search(query)
    assert response.status_code == 200, f"Expected 200 OK for valid token, got {response.status_code}"
    try:
        data = response.json()
    except (ValueError, json.JSONDecodeError):
        assert False, "Response is not valid JSON"
    assert isinstance(data, dict), "Response JSON must be an object"
    assert set(data.keys()) == {"best_match"}, "Response must contain exactly the best_match key"
    assert isinstance(data["best_match"], str), "best_match must be a string"
    assert data["best_match"] == expected, (
        f"API returned the wrong nearest chunk for query {query!r}: {data['best_match']!r}"
    )
    return data


def test_api_authorized_and_retrieval():
    chunks = load_chunks()
    index = faiss.read_index(INDEX_PATH)
    embedder = SentenceTransformer("sentence-transformers/all-MiniLM-L6-v2")

    # Preserve the original semantic retrieval assertion while also deriving the
    # exact expected result from the verified index.
    original_query = "restarting the router device"
    expected = expected_match(original_query, index, chunks, embedder)
    data = assert_authorized_result(original_query, expected)
    best_match = data["best_match"].lower()
    expected_keywords = ["unplugging", "power", "cable", "plugging"]
    matched_keywords = [kw for kw in expected_keywords if kw in best_match]
    assert len(matched_keywords) >= 2, (
        f"Retrieved chunk does not seem to match the expected answer. Got: {data['best_match']}"
    )

    # Runtime-generated queries prevent a fixed authorized response from passing.
    vocabulary = normalized_words(" ".join(chunks)).split()
    rng = random.SystemRandom()
    dynamic_queries = [
        " ".join(rng.choice(vocabulary) for _ in range(7)) + " " + secrets.token_hex(6)
        for _ in range(4)
    ]
    dynamic_queries.extend([
        "technician checking the outside fiber line " + secrets.token_hex(5),
        "red blinking connection light " + secrets.token_hex(5),
    ])
    for query in dynamic_queries:
        assert_authorized_result(query, expected_match(query, index, chunks, embedder))


if __name__ == "__main__":
    raise SystemExit(1)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
