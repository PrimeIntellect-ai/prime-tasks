#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import re
import shutil
import ssl
import subprocess
import urllib.request
from datetime import datetime, timezone

import numpy as np
from scipy.io import wavfile
import pytest

DEPLOY = "/home/user/deploy.sh"
PROJECT = "/home/user/audiocompress"
MEDIA_DIR = "/home/user/srv/media"
OUTPUT = MEDIA_DIR + "/output.mp3"
CERT = "/home/user/certs/cert.pem"
KEY = "/home/user/certs/key.pem"


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, text=True, capture_output=True, **kwargs)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def test_deploy_script_exists():
    """Check that deploy.sh exists and is executable."""
    assert os.path.isfile(DEPLOY), f"Deploy script {DEPLOY} is missing."
    assert os.access(DEPLOY, os.X_OK), f"Deploy script {DEPLOY} is not executable."

    source = open(DEPLOY, encoding="utf-8", errors="replace").read()
    for required in ("openssl", "setfacl", "nginx", "4433", "cert.pem", "key.pem"):
        assert required in source, f"deploy.sh does not configure required component: {required}"
    assert re.search(r"reload|restart", source), "deploy.sh does not reload or restart Nginx."


def test_rust_project_exists():
    """Check that the Rust project and implementation were created."""
    cargo_path = PROJECT + "/Cargo.toml"
    source_path = PROJECT + "/src/main.rs"
    assert os.path.isfile(cargo_path), f"Rust project Cargo.toml missing at {cargo_path}."
    assert os.path.isfile(source_path), f"Rust source missing at {source_path}."

    source = open(source_path, encoding="utf-8", errors="replace").read()
    assert re.search(r"(?:std::process::)?Command", source), "Rust program does not use std::process::Command."
    for required in ("ffmpeg", "/app/input.wav", "/home/user/srv/media/output.mp3", "32k"):
        assert required in source, f"Rust source is missing required ffmpeg setting: {required}"
    assert re.search(r'["\']-ac["\']', source) and re.search(r'["\']1["\']', source), \
        "Rust ffmpeg invocation does not request mono audio."
    assert re.search(r'["\']-b:a["\']', source), "Rust ffmpeg invocation does not set the audio bitrate."


def test_execute_deployment_and_rust_application():
    """Execute the requested artifacts and verify deployment is repeatable."""
    shutil.rmtree("/home/user/certs", ignore_errors=True)
    shutil.rmtree(MEDIA_DIR, ignore_errors=True)

    first = subprocess.run([DEPLOY], text=True, capture_output=True, timeout=120)
    assert first.returncode == 0, f"First deploy.sh run failed:\n{first.stdout}\n{first.stderr}"
    assert os.path.isfile(CERT), "First deploy.sh run did not generate cert.pem."
    assert os.path.isfile(KEY), "First deploy.sh run did not generate key.pem."
    first_cert_hash = sha256(CERT)
    first_key_hash = sha256(KEY)

    second = subprocess.run([DEPLOY], text=True, capture_output=True, timeout=120)
    assert second.returncode == 0, f"Second deploy.sh run failed:\n{second.stdout}\n{second.stderr}"
    assert sha256(CERT) == first_cert_hash, "Second deploy.sh run unnecessarily replaced the certificate."
    assert sha256(KEY) == first_key_hash, "Second deploy.sh run unnecessarily replaced the private key."

    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    built = subprocess.run(
        ["cargo", "run", "--quiet"], cwd=PROJECT, text=True,
        capture_output=True, timeout=180
    )
    assert built.returncode == 0, f"Rust application failed:\n{built.stdout}\n{built.stderr}"
    assert os.path.isfile(OUTPUT), "Running the Rust application did not create output.mp3."
    assert os.path.getsize(OUTPUT) > 0, "Rust application created an empty output.mp3."


def test_certs_exist():
    """Check that valid requested TLS certificates were generated."""
    assert os.path.isfile(CERT), f"Certificate missing at {CERT}."
    assert os.path.isfile(KEY), f"Private key missing at {KEY}."

    cert_info = run(["openssl", "x509", "-in", CERT, "-noout", "-subject", "-issuer", "-dates"]).stdout
    subject = next(line for line in cert_info.splitlines() if line.startswith("subject="))[8:].strip()
    issuer = next(line for line in cert_info.splitlines() if line.startswith("issuer="))[7:].strip()
    assert subject == issuer, "Certificate is not self-signed."

    dates = dict(line.split("=", 1) for line in cert_info.splitlines() if "=" in line and line.split("=", 1)[0] in ("notBefore", "notAfter"))
    fmt = "%b %d %H:%M:%S %Y %Z"
    start = datetime.strptime(dates["notBefore"], fmt).replace(tzinfo=timezone.utc)
    end = datetime.strptime(dates["notAfter"], fmt).replace(tzinfo=timezone.utc)
    assert 364 <= (end - start).total_seconds() / 86400 <= 366, "Certificate is not valid for 365 days."

    pub_details = subprocess.run(
        f"openssl x509 -in {CERT} -pubkey -noout | openssl pkey -pubin -text -noout",
        shell=True, check=True, text=True, capture_output=True
    ).stdout
    assert "2048 bit" in pub_details, "Certificate does not contain a 2048-bit RSA key."
    assert "RSA Public-Key" in pub_details or "Modulus:" in pub_details, "Certificate key is not RSA."

    cert_pub = run(["openssl", "x509", "-in", CERT, "-pubkey", "-noout"]).stdout
    key_pub = run(["openssl", "pkey", "-in", KEY, "-pubout"]).stdout
    assert cert_pub.strip() == key_pub.strip(), "Private key does not match cert.pem."
    run(["openssl", "verify", "-CAfile", CERT, CERT])


def test_acls_applied():
    """Check that ACLs were applied to the media directory and generated files."""
    assert os.path.isdir(MEDIA_DIR), f"Media directory {MEDIA_DIR} is missing."

    result = subprocess.run(["getfacl", "-c", MEDIA_DIR], capture_output=True, text=True)
    assert "user:www-data:r-x" in result.stdout, "www-data does not have r-x ACL on the media directory."

    for root, dirs, files in os.walk(MEDIA_DIR):
        for directory in dirs:
            acl = run(["getfacl", "-c", os.path.join(root, directory)]).stdout
            assert "user:www-data:r-x" in acl, f"www-data lacks r-x ACL on directory {directory}."
        for filename in files:
            acl = run(["getfacl", "-c", os.path.join(root, filename)]).stdout
            assert "user:www-data:r--" in acl, f"www-data lacks read ACL on file {filename}."


def test_nginx_running():
    """Check that Nginx alone serves HTTPS on 4433 with the requested configuration."""
    result = subprocess.run(["ss", "-tlnp"], capture_output=True, text=True)
    assert ":4433" in result.stdout, "Nginx is not listening on port 4433."
    lines_4433 = [line for line in result.stdout.splitlines() if re.search(r":4433\s", line)]
    assert lines_4433 and any("nginx" in line for line in lines_4433), "Port 4433 is not owned by Nginx."
    assert not any(re.search(r"(?:^|:|\])80\s", line) for line in result.stdout.splitlines()), \
        "HTTP is still enabled on port 80."

    config_result = subprocess.run(["nginx", "-T"], text=True, capture_output=True)
    assert config_result.returncode == 0, f"Nginx configuration is invalid:\n{config_result.stderr}"
    config = config_result.stdout + config_result.stderr
    assert len(re.findall(r"(?m)^\s*listen\s+[^;]*\b4433\b[^;]*;", config)) == 1, \
        "Nginx must contain exactly one active listen directive for port 4433."
    assert not re.search(r"(?m)^\s*listen\s+[^;]*\b80\b[^;]*;", config), "Active Nginx HTTP listener found."
    for required in (MEDIA_DIR, CERT, KEY):
        assert required in config, f"Active Nginx configuration does not reference {required}."
    assert re.search(r"(?m)^\s*listen\s+[^;]*\b4433\b[^;]*\bssl\b", config), \
        "Nginx port 4433 listener is not configured for SSL."

    served_pem = ssl.get_server_certificate(("127.0.0.1", 4433))
    with open(CERT, encoding="ascii") as f:
        local_pem = f.read()
    assert ssl.PEM_cert_to_DER_cert(served_pem) == ssl.PEM_cert_to_DER_cert(local_pem), \
        "Nginx is not serving the generated cert.pem."


def test_audio_psnr():
    """Fetch the output MP3 and verify its format, compression settings, size, duration and PSNR."""
    url = "https://127.0.0.1:4433/output.mp3"
    downloaded = "/tmp/eval_output.mp3"

    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    try:
        with urllib.request.urlopen(url, context=ctx) as response, open(downloaded, "wb") as f:
            assert response.status == 200
            f.write(response.read())
    except Exception as e:
        pytest.fail(f"Failed to fetch {url}: {e}")

    assert os.path.isfile(downloaded), "Downloaded MP3 file is missing."
    assert sha256(downloaded) == sha256(OUTPUT), "TLS endpoint did not serve the generated output.mp3."
    assert os.path.getsize(downloaded) < os.path.getsize("/app/input.wav"), \
        "Compressed output is not smaller than the input WAV."

    probe = json.loads(run([
        "ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", downloaded
    ]).stdout)
    audio_streams = [s for s in probe["streams"] if s.get("codec_type") == "audio"]
    assert probe["format"].get("format_name") == "mp3", "Downloaded file is not an MP3 container."
    assert len(audio_streams) == 1, "Output must contain exactly one audio stream."
    stream = audio_streams[0]
    assert stream.get("codec_name") == "mp3", "Output audio codec is not MP3."
    assert int(stream.get("channels", 0)) == 1, "Output audio is not mono."
    assert int(stream.get("bit_rate", 0)) == 32000, "Output MP3 audio bitrate is not 32k."

    packets = json.loads(run([
        "ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries", "packet=size",
        "-of", "json", downloaded
    ]).stdout).get("packets", [])
    packet_sizes = [int(p["size"]) for p in packets if p.get("size")]
    assert len(packet_sizes) > 100, "Output audio is unexpectedly short."
    assert max(packet_sizes) - min(packet_sizes) <= 2, "MP3 frames are not constant-bitrate encoded."

    input_duration = float(json.loads(run([
        "ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "json", "/app/input.wav"
    ]).stdout)["format"]["duration"])
    output_duration = float(probe["format"]["duration"])
    assert abs(output_duration - input_duration) <= 0.25, \
        f"Output duration {output_duration}s does not match input duration {input_duration}s."

    subprocess.run(["ffmpeg", "-y", "-i", downloaded, "-ar", "44100", "-ac", "1", "/tmp/eval_output.wav"],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["ffmpeg", "-y", "-i", "/app/input.wav", "-ac", "1", "/tmp/eval_input_mono.wav"],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    sr1, ref_audio = wavfile.read("/tmp/eval_input_mono.wav")
    sr2, test_audio = wavfile.read("/tmp/eval_output.wav")
    assert sr1 == sr2
    assert abs(len(ref_audio) - len(test_audio)) <= int(sr1 * 0.25), "Decoded output is truncated."

    min_len = min(len(ref_audio), len(test_audio))
    ref_audio = ref_audio[:min_len].astype(np.float32)
    test_audio = test_audio[:min_len].astype(np.float32)

    mse = np.mean((ref_audio - test_audio) ** 2)
    if mse == 0:
        psnr = 100.0
    else:
        max_pixel = 32767.0
        psnr = 20 * np.log10(max_pixel / np.sqrt(mse))

    assert psnr >= 20.0, f"Audio quality too low, PSNR is {psnr} dB (Threshold: 20.0 dB)"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
