#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import shlex
import stat
import string
import subprocess
import tempfile
from urllib.parse import urlparse, parse_qs

PAYLOAD = "http://evil.com/exploit"
XOR_KEY = 0x42


def expected_signature(value):
    return "".join(f"{ord(c) ^ XOR_KEY:02x}" for c in value)


def test_client2_key_permissions():
    key_path = "/home/user/certs/client2.key"
    assert os.path.isfile(key_path), f"File {key_path} is missing."

    mode = os.stat(key_path).st_mode
    perms = stat.S_IMODE(mode)

    assert perms in (0o400, 0o600), f"Permissions for {key_path} are {oct(perms)}, expected 0o400 or 0o600."


def test_exploit_sh_exists_and_executable():
    script_path = "/home/user/exploit.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."


def test_exploit_sh_content():
    script_path = "/home/user/exploit.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist."

    with open(script_path, "r") as f:
        content = f.read()

    expected_sig = expected_signature(PAYLOAD)

    # Preserve the original content assertions.
    assert "curl " in content, "The script must contain a curl command."
    assert "--cacert /home/user/certs/ca.crt" in content, "Missing or incorrect --cacert argument."
    assert "--cert /home/user/certs/client2.crt" in content, "Missing or incorrect --cert argument."
    assert "--key /home/user/certs/client2.key" in content, "Missing or incorrect --key argument."

    url_start = content.find("https://localhost:8443/login")
    assert url_start != -1, "The target URL https://localhost:8443/login is missing in the curl command."

    url_substring = content[url_start:]
    end_idx = -1
    for i, char in enumerate(url_substring):
        if char in ('"', "'", " ", "\n"):
            end_idx = i
            break

    full_url = url_substring[:end_idx] if end_idx != -1 else url_substring
    parsed_url = urlparse(full_url)
    query_params = parse_qs(parsed_url.query)

    assert "redirect" in query_params, "The 'redirect' query parameter is missing."
    assert query_params["redirect"][0] == PAYLOAD, f"Expected redirect parameter to be {PAYLOAD}."
    assert "sig" in query_params, "The 'sig' query parameter is missing."
    assert query_params["sig"][0] == expected_sig, f"Expected sig parameter to be {expected_sig}."

    # Comments and unrelated strings do not count as curl commands. Require one
    # literal curl command token in the shell source.
    lexer = shlex.shlex(content, posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    lexer.commenters = "#"
    tokens = list(lexer)
    assert tokens.count("curl") == 1, "exploit.sh must contain exactly one literal curl command."


def test_forge_c_compiles_and_handles_arbitrary_inputs():
    source = "/home/user/forge.c"
    assert os.path.isfile(source), f"{source} does not exist."

    with tempfile.TemporaryDirectory() as td:
        binary = os.path.join(td, "forge")
        compiled = subprocess.run(
            ["gcc", "-std=c11", "-Wall", "-Wextra", "-O2", source, "-o", binary],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert compiled.returncode == 0, f"forge.c did not compile:\n{compiled.stderr}"

        rng = random.SystemRandom()
        alphabet = string.ascii_letters + string.digits + "/:?&=._-"
        cases = [
            PAYLOAD,
            "/admin",
            "space value",
            "A?b=c&d=e",
            "".join(rng.choice(alphabet) for _ in range(37)),
            "".join(rng.choice(alphabet) for _ in range(73)),
        ]
        for value in cases:
            result = subprocess.run(
                [binary, value],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=5,
            )
            assert result.returncode == 0, f"forge failed for input {value!r}: {result.stderr}"
            assert result.stdout.strip() == expected_signature(value), (
                f"forge produced an incorrect signature for {value!r}"
            )


def _has_pair(args, option, value):
    return any(args[i] == option and i + 1 < len(args) and args[i + 1] == value
               for i in range(len(args)))


def test_exploit_executes_one_functional_curl_command():
    script = "/home/user/exploit.sh"
    with tempfile.TemporaryDirectory() as td:
        curl_log = os.path.join(td, "curl.jsonl")
        fake_curl = os.path.join(td, "curl")
        with open(fake_curl, "w") as f:
            f.write("#!/usr/bin/python3\n")
            f.write("import json, os, sys\n")
            f.write("with open(os.environ['CURL_LOG'], 'a') as out:\n")
            f.write("    out.write(json.dumps(sys.argv[1:]) + '\\n')\n")
        os.chmod(fake_curl, 0o755)

        env = os.environ.copy()
        env["PATH"] = td + os.pathsep + env.get("PATH", "")
        env["CURL_LOG"] = curl_log
        run = subprocess.run(
            ["/bin/bash", script],
            cwd="/home/user",
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert run.returncode == 0, f"exploit.sh failed when executed:\n{run.stderr}"
        assert os.path.isfile(curl_log), "exploit.sh did not execute the curl command."

        with open(curl_log) as f:
            calls = [json.loads(line) for line in f if line.strip()]
        assert len(calls) == 1, f"Expected exactly one curl execution, observed {len(calls)}."
        args = calls[0]

        assert _has_pair(args, "--cacert", "/home/user/certs/ca.crt"), "Executed curl lacks the required --cacert argument."
        assert _has_pair(args, "--cert", "/home/user/certs/client2.crt"), "Executed curl lacks the valid client certificate."
        assert _has_pair(args, "--key", "/home/user/certs/client2.key"), "Executed curl lacks the valid client's private key."

        urls = [arg for arg in args if arg.startswith("https://localhost:8443/login")]
        assert len(urls) == 1, "Executed curl must receive exactly one staging login URL."
        parsed = urlparse(urls[0])
        assert parsed.scheme == "https" and parsed.hostname == "localhost" and parsed.port == 8443
        assert parsed.path == "/login", "Executed curl targets the wrong endpoint."
        query = parse_qs(parsed.query)
        assert query.get("redirect") == [PAYLOAD], "Executed curl has the wrong redirect parameter."
        assert query.get("sig") == [expected_signature(PAYLOAD)], "Executed curl has the wrong forged signature."

        forbidden = ("--data", "-d", "--form", "-F", "--upload-file", "-T", "--head", "-I", "--next")
        assert not any(arg == flag or arg.startswith(flag + "=") for arg in args for flag in forbidden), (
            "The curl invocation must perform a single GET request."
        )
        for i, arg in enumerate(args):
            if arg in ("-X", "--request"):
                assert i + 1 < len(args) and args[i + 1].upper() == "GET", "curl request method is not GET."
            elif arg.startswith("--request="):
                assert arg.split("=", 1)[1].upper() == "GET", "curl request method is not GET."
            elif arg.startswith("-X") and arg != "-X":
                assert arg[2:].upper() == "GET", "curl request method is not GET."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
