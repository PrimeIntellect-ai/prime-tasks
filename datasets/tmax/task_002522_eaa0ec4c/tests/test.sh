#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import random
import re
import secrets
import shutil
import subprocess
import tempfile
import urllib.parse

import pytest

SCRIPT_PATH = "/home/user/evaluate_requests.py"
CLEAN_CORPUS = "/app/hidden_corpus/clean/urls.txt"
EVIL_CORPUS = "/app/hidden_corpus/evil/urls.txt"
PACKAGE_ROOT = "/app/legacy_router"


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} is missing."


def test_legacy_router_installed():
    try:
        result = subprocess.run(
            ["python3", "-c", "import legacy_router"],
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, f"Failed to import legacy_router in Python 3: {result.stderr}"
    except Exception as e:
        pytest.fail(f"Error checking legacy_router installation: {e}")


def test_vendored_package_was_repaired_and_extension_builds():
    makefile = os.path.join(PACKAGE_ROOT, "Makefile")
    assert os.path.isfile(makefile), "Vendored Makefile is missing."
    with open(makefile, encoding="utf-8") as f:
        active_makefile = "\n".join(line for line in f if not line.lstrip().startswith("#"))
    assert re.search(r"\bpython3-config\b", active_makefile), "Makefile does not use python3-config."
    assert not re.search(r"\bpython-config\b", active_makefile), "Makefile still uses the Python 2 python-config tool."

    build = subprocess.run(
        ["make", "-B"], cwd=PACKAGE_ROOT, capture_output=True, text=True, timeout=60
    )
    assert build.returncode == 0, f"Vendored extension failed to build:\n{build.stdout}\n{build.stderr}"

    env = os.environ.copy()
    env["PYTHONPATH"] = PACKAGE_ROOT
    probe = subprocess.run(
        [
            "python3",
            "-c",
            "import json, legacy_router, legacy_router.ext; "
            "print(json.dumps(legacy_router.parse_url('https://probe.invalid/x?a=one&b=two')))"
        ],
        cwd="/tmp",
        env=env,
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert probe.returncode == 0, f"Repaired vendored package cannot be imported: {probe.stderr}"
    assert json.loads(probe.stdout.strip()) == {"a": "one", "b": "two"}

    installed_probe = subprocess.run(
        [
            "python3",
            "-c",
            "import legacy_router, legacy_router.ext; "
            "assert legacy_router.parse_url('https://installed.invalid/?x=7')['x'] == '7'"
        ],
        cwd="/tmp",
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert installed_probe.returncode == 0, f"Installed package or extension is unusable: {installed_probe.stderr}"


def run_script(corpus_path):
    result = subprocess.run(
        ["python3", SCRIPT_PATH, corpus_path],
        capture_output=True,
        text=True,
        timeout=30,
    )
    return result.stdout.strip().split("\n")


def test_clean_corpus_accepted():
    assert os.path.isfile(CLEAN_CORPUS), f"Clean corpus {CLEAN_CORPUS} is missing."
    with open(CLEAN_CORPUS, "r") as f:
        urls = [line.strip() for line in f if line.strip()]
    num_urls = len(urls)

    outputs = run_script(CLEAN_CORPUS)
    outputs = [o.strip() for o in outputs if o.strip()]

    assert len(outputs) == num_urls, f"Expected {num_urls} outputs, got {len(outputs)}."

    rejected = [i for i, out in enumerate(outputs) if out != "ACCEPT"]
    if rejected:
        offending_urls = [urls[i] for i in rejected]
        pytest.fail(f"{len(rejected)} of {num_urls} clean URLs were rejected/modified. Offending URLs: {offending_urls}")


def test_evil_corpus_rejected():
    assert os.path.isfile(EVIL_CORPUS), f"Evil corpus {EVIL_CORPUS} is missing."
    with open(EVIL_CORPUS, "r") as f:
        urls = [line.strip() for line in f if line.strip()]
    num_urls = len(urls)

    outputs = run_script(EVIL_CORPUS)
    outputs = [o.strip() for o in outputs if o.strip()]

    assert len(outputs) == num_urls, f"Expected {num_urls} outputs, got {len(outputs)}."

    accepted = [i for i, out in enumerate(outputs) if out != "REJECT"]
    if accepted:
        offending_urls = [urls[i] for i in accepted]
        pytest.fail(f"{len(accepted)} of {num_urls} evil URLs bypassed the filter. Offending URLs: {offending_urls}")


def oracle(url):
    try:
        parsed = urllib.parse.urlparse(url)
        params = dict(urllib.parse.parse_qsl(parsed.query))
        encoded = params["bytecode"]
        raw = base64.b64decode(encoded, validate=True)
        plaintext = raw.decode("utf-8")
        if not plaintext:
            return "REJECT"
        for instruction in plaintext.split("|"):
            if " " not in instruction:
                return "REJECT"
            command, argument = instruction.split(" ", 1)
            if not command or not argument:
                return "REJECT"
            if command == "EXEC":
                return "REJECT"
            if command in ("READ", "WRITE"):
                if ".." in argument:
                    return "REJECT"
                if argument.startswith("/") and not argument.startswith("/data/public/"):
                    return "REJECT"
        return "ACCEPT"
    except Exception:
        return "REJECT"


def encoded_url(host, path, plaintext):
    encoded = base64.b64encode(plaintext.encode("utf-8")).decode("ascii")
    return f"https://{host}/{path}?" + urllib.parse.urlencode({"bytecode": encoded})


def test_randomized_requests_and_required_router_use():
    nonce = secrets.token_hex(12)
    host = f"gateway-{nonce}.invalid"
    urls = []

    for i in range(8):
        token = secrets.token_hex(8)
        safe_payloads = [
            f"READ /data/public/{token}.dat",
            f"WRITE relative_{token}.txt",
            f"READ folder/{token}/item",
            f"PING {token}",
            f"READ /data/public/{token}|WRITE saved_{token}",
        ]
        urls.append(encoded_url(host, f"safe/{i}/{nonce}", random.choice(safe_payloads)))

    for i in range(14):
        token = secrets.token_hex(8)
        evil_payloads = [
            f"EXEC command_{token}",
            f"READ /etc/{token}",
            f"WRITE /var/tmp/{token}",
            f"READ relative/../{token}",
            f"WRITE /data/public/../private/{token}",
            f"READ /data/publicity/{token}",
            "READ /data/public",
            f"PING {token}|EXEC second_{token}",
        ]
        urls.append(encoded_url(host, f"evil/{i}/{nonce}", random.choice(evil_payloads)))

    urls.extend([
        f"https://{host}/missing/{nonce}?other=value",
        f"https://{host}/bad64/{nonce}?bytecode=" + urllib.parse.quote("%%%not-base64%%%"),
        f"https://{host}/empty/{nonce}?bytecode=",
        f"https://{host}/badutf/{nonce}?" + urllib.parse.urlencode({"bytecode": base64.b64encode(b"\xff\xfe").decode("ascii")}),
        encoded_url(host, f"malformed/{nonce}", "READ"),
        encoded_url(host, f"emptyinstruction/{nonce}", "READ local|"),
    ])
    random.SystemRandom().shuffle(urls)
    expected = [oracle(url) for url in urls]
    assert "ACCEPT" in expected and "REJECT" in expected

    with tempfile.TemporaryDirectory(prefix="firewall-check-") as td:
        corpus = os.path.join(td, secrets.token_hex(10) + ".txt")
        with open(corpus, "w", encoding="utf-8") as f:
            f.write("\n".join(urls) + "\n")

        # Run an exact copy from a randomized directory so fixed path branches cannot
        # identify the corpus, and provide an instrumented legacy_router implementation.
        copied_script = os.path.join(td, secrets.token_hex(10) + ".py")
        shutil.copy2(SCRIPT_PATH, copied_script)
        shim_root = os.path.join(td, "shim")
        package_dir = os.path.join(shim_root, "legacy_router")
        os.makedirs(package_dir)
        call_log = os.path.join(td, "router-calls.jsonl")
        with open(os.path.join(package_dir, "__init__.py"), "w", encoding="utf-8") as f:
            f.write(
                "import json, os, urllib.parse\n"
                "def parse_url(url):\n"
                "    with open(os.environ['ROUTER_CALL_LOG'], 'a', encoding='utf-8') as log:\n"
                "        log.write(json.dumps(url) + '\\n')\n"
                "    parsed = urllib.parse.urlparse(url)\n"
                "    return dict(urllib.parse.parse_qsl(parsed.query))\n"
            )

        env = os.environ.copy()
        env["PYTHONPATH"] = shim_root
        env["ROUTER_CALL_LOG"] = call_log
        result = subprocess.run(
            ["python3", copied_script, corpus],
            cwd=td,
            env=env,
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"Firewall script failed: {result.stderr}"
        outputs = result.stdout.splitlines()
        assert outputs == expected, f"Incorrect randomized results. Expected {expected}, got {outputs}."
        assert os.path.isfile(call_log), "The script did not call legacy_router.parse_url."
        with open(call_log, encoding="utf-8") as f:
            calls = [json.loads(line) for line in f if line.strip()]
        for url in urls:
            assert url in calls, f"legacy_router.parse_url was not used for input {url!r}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
