#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import shutil
import subprocess
import tempfile
import hashlib
import urllib.request
import urllib.error
import urllib.parse
import uuid
import pytest
import redis


def decode_allowed(data, encodings):
    for encoding in encodings:
        try:
            return data.decode(encoding)
        except (UnicodeDecodeError, LookupError):
            pass
    raise UnicodeDecodeError("all", data, 0, len(data), "no allowed encoding succeeded")


def test_sanitizer_adversarial_corpus():
    sanitizer_path = "/home/user/sanitizer.py"
    assert os.path.isfile(sanitizer_path), f"Sanitizer script not found at {sanitizer_path}"

    with open("/app/config/sanitizer_config.json", "r", encoding="utf-8") as cf:
        config = json.load(cf)
    allowed_encodings = config["allowed_encodings"]
    target_encoding = config["target_encoding"]

    clean_corpus = "/app/test_corpus/clean"
    evil_corpus = "/app/test_corpus/evil"

    with tempfile.TemporaryDirectory() as temp_in, tempfile.TemporaryDirectory() as temp_out:
        clean_files = set(os.listdir(clean_corpus)) if os.path.exists(clean_corpus) else set()
        evil_files = set(os.listdir(evil_corpus)) if os.path.exists(evil_corpus) else set()
        expected_clean = {}

        for f in clean_files:
            source = os.path.join(clean_corpus, f)
            shutil.copy(source, os.path.join(temp_in, f))
            with open(source, "rb") as inp:
                expected_clean[f] = decode_allowed(inp.read(), allowed_encodings).encode(target_encoding)
        for f in evil_files:
            shutil.copy(os.path.join(evil_corpus, f), os.path.join(temp_in, f))

        token = uuid.uuid4().hex
        dynamic_clean = {
            f"utf8_{token}.txt": (f"Random clean UTF-8 document {token}\nCafé and snowman: ☃\n").encode("utf-8"),
            f"cp1252_{token}.txt": b"Legacy caf\xe9 \x96 clean document\r\n",
        }
        dynamic_evil = {
            f"null_{token}.txt": f"prefix-{token}".encode() + b"\x00suffix",
            f"script_{token}.txt": f"safe-{token}<ScRiPt>alert(1)</sCrIpT>".encode(),
            f"undecodable_{token}.txt": b"\x81",
        }

        for name, data in dynamic_clean.items():
            with open(os.path.join(temp_in, name), "wb") as f:
                f.write(data)
            clean_files.add(name)
            expected_clean[name] = decode_allowed(data, allowed_encodings).encode(target_encoding)
        for name, data in dynamic_evil.items():
            with open(os.path.join(temp_in, name), "wb") as f:
                f.write(data)
            evil_files.add(name)

        try:
            result = subprocess.run(
                ["python3", sanitizer_path, "--input", temp_in, "--output", temp_out],
                capture_output=True, text=True, timeout=10
            )
        except subprocess.TimeoutExpired:
            pytest.fail("Sanitizer script timed out after 10 seconds.")

        assert result.returncode == 0, (
            f"Sanitizer script failed with return code {result.returncode}.\nStderr: {result.stderr}"
        )

        output_files = set(os.listdir(temp_out))
        output_files.discard("manifest.json")

        bypassed_evil = evil_files.intersection(output_files)
        missing_clean = clean_files - output_files
        unexpected_files = output_files - clean_files
        modified_clean = set()

        for f in clean_files.intersection(output_files):
            out_path = os.path.join(temp_out, f)
            try:
                with open(out_path, "r", encoding=target_encoding) as out_f:
                    out_f.read()
            except (UnicodeDecodeError, LookupError):
                modified_clean.add(f)
                continue
            with open(out_path, "rb") as out_f:
                if out_f.read() != expected_clean[f]:
                    modified_clean.add(f)

        error_msgs = []
        if bypassed_evil:
            error_msgs.append(
                f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {', '.join(sorted(bypassed_evil))}"
            )
        if missing_clean or modified_clean:
            bad = missing_clean.union(modified_clean)
            error_msgs.append(
                f"{len(bad)} of {len(clean_files)} clean modified or missing: {', '.join(sorted(bad))}"
            )
        if unexpected_files:
            error_msgs.append(f"Unexpected output files: {', '.join(sorted(unexpected_files))}")
        if error_msgs:
            pytest.fail(" | ".join(error_msgs))

        manifest_path = os.path.join(temp_out, "manifest.json")
        assert os.path.isfile(manifest_path), "manifest.json was not generated in the output directory."

        with open(manifest_path, "r", encoding="utf-8") as mf:
            try:
                manifest_data = json.load(mf)
            except json.JSONDecodeError:
                pytest.fail("manifest.json is not valid JSON.")

        assert isinstance(manifest_data, dict), "manifest.json must contain a JSON object."
        assert set(manifest_data.keys()) == {"files"}, "manifest.json must have exactly the 'files' key."
        assert isinstance(manifest_data["files"], list), "manifest.json 'files' must be an array."
        for item in manifest_data["files"]:
            assert isinstance(item, dict), "Each manifest entry must be an object."
            assert set(item.keys()) == {"filename", "sha256"}, "Manifest entries must contain exactly filename and sha256."
            assert isinstance(item["filename"], str) and isinstance(item["sha256"], str)

        manifest_names = [item["filename"] for item in manifest_data["files"]]
        assert len(manifest_names) == len(set(manifest_names)), "manifest.json contains duplicate filenames."
        assert set(manifest_names) == clean_files, "Manifest must list every and only clean output file."
        manifest_files = {item["filename"]: item["sha256"] for item in manifest_data["files"]}

        for f in clean_files:
            assert f in manifest_files, f"Clean file {f} missing from manifest.json."
            out_path = os.path.join(temp_out, f)
            with open(out_path, "rb") as out_f:
                expected_hash = hashlib.sha256(out_f.read()).hexdigest()
            assert manifest_files[f] == expected_hash, (
                f"Hash mismatch in manifest for {f}. Expected {expected_hash}, got {manifest_files[f]}"
            )


def fetch(url, timeout=5):
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.status, response.read()


def test_multi_service_stack():
    assert os.path.isfile("/home/user/nginx.conf"), "Nginx configuration file is missing."
    assert os.path.isfile("/home/user/processed_docs/manifest.json"), "Processed manifest is missing."

    try:
        status, manifest_bytes = fetch("http://127.0.0.1:8080/manifest.json")
        assert status == 200, f"Expected status 200 for manifest.json, got {status}"
        manifest_data = json.loads(manifest_bytes.decode("utf-8"))
    except Exception as e:
        pytest.fail(f"Failed to fetch or parse /manifest.json from Nginx: {e}")

    assert "files" in manifest_data, "manifest.json fetched from Nginx missing 'files' key."
    assert isinstance(manifest_data["files"], list), "Manifest files value is not an array."
    assert manifest_data["files"], "The processed manifest must not be empty."

    disk_manifest = open("/home/user/processed_docs/manifest.json", "rb").read()
    assert manifest_bytes == disk_manifest, "Nginx manifest response does not match the processed manifest file."

    entries = {item.get("filename"): item.get("sha256") for item in manifest_data["files"]}
    assert "sample.txt" in entries, "Processed raw sample.txt is missing from the manifest."
    expected_sample = b"Sample clean file\n"
    assert entries["sample.txt"] == hashlib.sha256(expected_sample).hexdigest(), "sample.txt manifest hash is incorrect."
    assert "evil.txt" not in entries, "The null-containing raw evil.txt was included in the manifest."

    sample_file = manifest_data["files"][0]["filename"]
    try:
        status, doc_content = fetch(
            "http://127.0.0.1:8080/docs/" + urllib.parse.quote(sample_file, safe="")
        )
        assert status == 200, f"Expected status 200 for /docs/{sample_file}, got {status}"
        expected_hash = manifest_data["files"][0]["sha256"]
        actual_hash = hashlib.sha256(doc_content).hexdigest()
        assert actual_hash == expected_hash, f"Content hash mismatch for {sample_file} via Nginx proxy."
    except Exception as e:
        pytest.fail(f"Failed to fetch /docs/{sample_file} from Nginx proxy: {e}")

    # Exercise Redis, the Flask backend, and the Nginx proxy with an unpredictable
    # cache-only document which does not exist on disk.
    key = "verifier_" + uuid.uuid4().hex + ".txt"
    payload = ("dynamic redis/flask/nginx payload " + uuid.uuid4().hex).encode("utf-8")
    try:
        client = redis.Redis(host="127.0.0.1", port=6379, db=0, socket_timeout=3)
        assert client.ping(), "Redis did not answer PING."
        client.set(key, payload)

        quoted = urllib.parse.quote(key, safe="")
        direct_status, direct_body = fetch(f"http://127.0.0.1:5000/docs/{quoted}")
        assert direct_status == 200 and direct_body == payload, "Flask did not retrieve the dynamic value from Redis."

        proxy_status, proxy_body = fetch(f"http://127.0.0.1:8080/docs/{quoted}")
        assert proxy_status == 200 and proxy_body == payload, "Nginx did not proxy the dynamic Flask response."
    except Exception as e:
        pytest.fail(f"Redis/Flask/Nginx integration failed: {e}")
    finally:
        try:
            client.delete(key)
        except Exception:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
