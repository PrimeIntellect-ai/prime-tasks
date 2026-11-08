#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import io
import secrets
import tarfile
import zipfile
import subprocess
import tempfile
import requests
import pytest

SERVICE_URL = "http://127.0.0.1:9090/api/v1/process_archive"

def get_expected_hash(content_bytes: bytes) -> str:
    with tempfile.NamedTemporaryFile(delete=False) as f:
        f.write(content_bytes)
        f.flush()
        temp_name = f.name
    try:
        res = subprocess.run(["/app/dedup_hash", temp_name], capture_output=True, text=True, check=True)
        return res.stdout.strip()
    finally:
        os.remove(temp_name)

def test_service_running():
    """Check if the service is listening on the expected port."""
    try:
        requests.get("http://127.0.0.1:9090/")
    except requests.exceptions.ConnectionError:
        pytest.fail("Service is not listening on 127.0.0.1:9090")
    except requests.exceptions.RequestException:
        pass

def test_process_complex_archive():
    """Test the service with a complex archive containing nested zip, encodings, and symlinks."""
    zip_buffer = io.BytesIO()
    with zipfile.ZipFile(zip_buffer, "w") as zf:
        zf.writestr("inner.txt", "こんにちは".encode("shift_jis"))
    zip_data = zip_buffer.getvalue()

    tar_buffer = io.BytesIO()
    with tarfile.open(fileobj=tar_buffer, mode="w") as tf:
        utf16_content = "Storage Admin".encode("utf-16le")
        tinfo1 = tarfile.TarInfo("root_file.txt")
        tinfo1.size = len(utf16_content)
        tf.addfile(tinfo1, io.BytesIO(utf16_content))

        tinfo2 = tarfile.TarInfo("archive.zip")
        tinfo2.size = len(zip_data)
        tf.addfile(tinfo2, io.BytesIO(zip_data))

        tinfo3 = tarfile.TarInfo("bad_link")
        tinfo3.type = tarfile.SYMTYPE
        tinfo3.linkname = "."
        tf.addfile(tinfo3)

    tar_data = tar_buffer.getvalue()

    try:
        response = requests.post(SERVICE_URL, data=tar_data, headers={"Content-Type": "application/x-tar"}, timeout=10)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect or send request to service: {e}")

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}. Body: {response.text}"

    try:
        resp_json = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Body: {response.text}")

    assert "manifest" in resp_json, "Response JSON missing 'manifest' key."
    manifest = resp_json["manifest"]

    expected_root_hash = get_expected_hash("Storage Admin".encode("utf-8"))
    expected_inner_hash = get_expected_hash("こんにちは".encode("utf-8"))

    assert "root_file.txt" in manifest, "Missing 'root_file.txt' in manifest"
    assert manifest["root_file.txt"] == expected_root_hash, f"Hash mismatch for root_file.txt. Expected {expected_root_hash}, got {manifest['root_file.txt']}"

    assert "archive/inner.txt" in manifest, "Missing 'archive/inner.txt' in manifest"
    assert manifest["archive/inner.txt"] == expected_inner_hash, f"Hash mismatch for archive/inner.txt. Expected {expected_inner_hash}, got {manifest['archive/inner.txt']}"

    assert "bad_link" not in manifest, "Symlink 'bad_link' should not be processed or included in manifest."

def test_process_deep_nesting():
    """Test deep nesting of tar archives."""
    inner_tar_buf = io.BytesIO()
    with tarfile.open(fileobj=inner_tar_buf, mode="w") as tf:
        content = b"Deeply nested data"
        tinfo = tarfile.TarInfo("deep.bin")
        tinfo.size = len(content)
        tf.addfile(tinfo, io.BytesIO(content))
    inner_tar_data = inner_tar_buf.getvalue()

    middle_tar_buf = io.BytesIO()
    with tarfile.open(fileobj=middle_tar_buf, mode="w") as tf:
        tinfo = tarfile.TarInfo("inner.tar")
        tinfo.size = len(inner_tar_data)
        tf.addfile(tinfo, io.BytesIO(inner_tar_data))
    middle_tar_data = middle_tar_buf.getvalue()

    outer_tar_buf = io.BytesIO()
    with tarfile.open(fileobj=outer_tar_buf, mode="w") as tf:
        tinfo = tarfile.TarInfo("middle.tar")
        tinfo.size = len(middle_tar_data)
        tf.addfile(tinfo, io.BytesIO(middle_tar_data))
    outer_tar_data = outer_tar_buf.getvalue()

    try:
        response = requests.post(SERVICE_URL, data=outer_tar_data, timeout=10)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect or send request to service: {e}")

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}. Body: {response.text}"
    resp_json = response.json()
    manifest = resp_json.get("manifest", {})

    expected_hash = get_expected_hash(b"Deeply nested data")
    expected_path = "middle/inner/deep.bin"

    assert expected_path in manifest, f"Missing '{expected_path}' in manifest"
    assert manifest[expected_path] == expected_hash, "Hash mismatch for deeply nested file."

def test_novel_dynamic_archives_have_exact_manifests():
    """Exercise fresh names and contents so a fixed manifest cannot pass."""
    for iteration in range(2):
        token = secrets.token_hex(8)
        root_name = f"root_{token}.bin"
        zip_name = f"bundle_{token}.zip"
        zip_dir = zip_name[:-4]
        zip_leaf_name = f"leaf_{token}.dat"
        nested_tar_name = f"layer_{token}.tar"
        nested_tar_dir = nested_tar_name[:-4]
        deep_name = f"deep_{token}.bin"
        link_name = f"loop_{token}"

        root_content = b"root:" + token.encode() + secrets.token_bytes(31 + iteration)
        zip_leaf_content = b"zip:" + token.encode() + secrets.token_bytes(43 + iteration)
        deep_content = b"deep:" + token.encode() + secrets.token_bytes(59 + iteration)

        inner_tar_buffer = io.BytesIO()
        with tarfile.open(fileobj=inner_tar_buffer, mode="w") as tf:
            info = tarfile.TarInfo(deep_name)
            info.size = len(deep_content)
            tf.addfile(info, io.BytesIO(deep_content))
        inner_tar_data = inner_tar_buffer.getvalue()

        zip_buffer = io.BytesIO()
        with zipfile.ZipFile(zip_buffer, "w") as zf:
            zf.writestr(zip_leaf_name, zip_leaf_content)
            zf.writestr(nested_tar_name, inner_tar_data)
        zip_data = zip_buffer.getvalue()

        outer_buffer = io.BytesIO()
        with tarfile.open(fileobj=outer_buffer, mode="w") as tf:
            root_info = tarfile.TarInfo(root_name)
            root_info.size = len(root_content)
            tf.addfile(root_info, io.BytesIO(root_content))

            zip_info = tarfile.TarInfo(zip_name)
            zip_info.size = len(zip_data)
            tf.addfile(zip_info, io.BytesIO(zip_data))

            link_info = tarfile.TarInfo(link_name)
            link_info.type = tarfile.SYMTYPE
            link_info.linkname = "."
            tf.addfile(link_info)

        expected = {
            root_name: get_expected_hash(root_content),
            f"{zip_dir}/{zip_leaf_name}": get_expected_hash(zip_leaf_content),
            f"{zip_dir}/{nested_tar_dir}/{deep_name}": get_expected_hash(deep_content),
        }

        try:
            response = requests.post(
                SERVICE_URL,
                data=outer_buffer.getvalue(),
                headers={"Content-Type": "application/x-tar"},
                timeout=10,
            )
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed to process novel archive: {e}")

        assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}. Body: {response.text}"
        try:
            body = response.json()
        except ValueError:
            pytest.fail(f"Response is not valid JSON. Body: {response.text}")
        assert isinstance(body.get("manifest"), dict), "Response JSON must contain a manifest dictionary"
        assert body["manifest"] == expected, f"Manifest did not exactly match novel archive contents: {body['manifest']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
