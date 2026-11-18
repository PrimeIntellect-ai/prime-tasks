#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
import pytest

HOME = "/home/user"
BINARY = HOME + "/manifest_validator"
SOURCE = HOME + "/manifest_validator.c"
PREFIX = HOME + "/local"
SERVICE = HOME + "/.config/systemd/user/k8s-webhook.service"
PEM = HOME + "/webhook.pem"


def run(cmd, **kwargs):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)


def expected_stdout(word):
    return {word.encode(), (word + "\n").encode()}


def test_libyaml_installed_and_usable():
    lib_path = PREFIX + "/lib"
    include_path = PREFIX + "/include"
    assert os.path.isdir(lib_path), f"libyaml installation directory {lib_path} is missing."
    assert os.path.isdir(include_path), f"libyaml include directory {include_path} is missing."
    assert os.path.isfile(include_path + "/yaml.h"), "Locally installed yaml.h is missing."
    files = os.listdir(lib_path)
    assert any("libyaml" in f for f in files), f"libyaml shared/static library not found in {lib_path}."

    program = r'''#include <yaml.h>
#include <string.h>
int main(void) {
  yaml_parser_t p; yaml_event_t e; int scalars = 0;
  const unsigned char input[] = "probe: value\n";
  if (!yaml_parser_initialize(&p)) return 10;
  yaml_parser_set_input_string(&p, input, strlen((const char *)input));
  do {
    if (!yaml_parser_parse(&p, &e)) { yaml_parser_delete(&p); return 11; }
    if (e.type == YAML_SCALAR_EVENT) scalars++;
    if (e.type == YAML_STREAM_END_EVENT) { yaml_event_delete(&e); break; }
    yaml_event_delete(&e);
  } while (1);
  yaml_parser_delete(&p);
  return scalars == 2 ? 0 : 12;
}
'''
    with tempfile.TemporaryDirectory() as d:
        src = os.path.join(d, "probe.c")
        exe = os.path.join(d, "probe")
        with open(src, "w") as f:
            f.write(program)
        built = run(["gcc", src, "-I" + include_path, "-L" + lib_path,
                     "-Wl,-rpath," + lib_path, "-lyaml", "-o", exe])
        assert built.returncode == 0, "Installed libyaml cannot compile/link a client: " + built.stderr.decode(errors="replace")
        probed = run([exe])
        assert probed.returncode == 0, "Installed libyaml failed a real parser API probe."


def test_validator_binary_exists_and_uses_libyaml():
    assert os.path.isfile(BINARY), f"Validator binary {BINARY} is missing."
    assert os.access(BINARY, os.X_OK), f"Validator binary {BINARY} is not executable."
    assert os.path.isfile(SOURCE), f"Validator source {SOURCE} is missing."
    with open(SOURCE, errors="replace") as f:
        source = f.read()
    assert re.search(r'#\s*include\s*[<\"]yaml\.h[>\"]', source), "Validator source does not include yaml.h."
    assert re.search(r'yaml_(parser|event|token)_', source), "Validator source does not use the libyaml API."

    symbols = run(["nm", "-D", BINARY], text=True)
    all_symbols = symbols.stdout + symbols.stderr
    if not re.search(r'yaml_(parser|event|token)_', all_symbols):
        symbols = run(["nm", BINARY], text=True)
        all_symbols += symbols.stdout + symbols.stderr
    assert re.search(r'yaml_(parser|event|token)_', all_symbols), "Validator binary has no libyaml API symbols."

    linked = run(["ldd", BINARY], text=True)
    if "libyaml" in linked.stdout:
        yaml_lines = [line for line in linked.stdout.splitlines() if "libyaml" in line]
        assert any(PREFIX + "/lib" in line for line in yaml_lines), "Validator is not linked to the locally installed libyaml."


def test_certificate_and_service_configuration():
    assert os.path.isfile(PEM), "Combined TLS PEM is missing."
    cert = run(["openssl", "x509", "-in", PEM, "-noout"])
    key = run(["openssl", "pkey", "-in", PEM, "-noout", "-check"])
    assert cert.returncode == 0, "webhook.pem does not contain a valid certificate."
    assert key.returncode == 0, "webhook.pem does not contain a valid private key."
    cert_pub = run(["openssl", "x509", "-in", PEM, "-pubkey", "-noout"])
    key_pub = run(["openssl", "pkey", "-in", PEM, "-pubout"])
    assert cert_pub.returncode == key_pub.returncode == 0 and cert_pub.stdout == key_pub.stdout, "Certificate and private key do not match."

    assert os.path.isfile(SERVICE), f"Systemd service file {SERVICE} is missing."
    with open(SERVICE, errors="replace") as f:
        unit = f.read()
    assert re.search(r'^\s*ExecStart\s*=.*socat', unit, re.I | re.M), "Service does not start socat."
    assert re.search(r'(OPENSSL|SSL)-LISTEN:8443', unit, re.I), "Service is not configured as a TLS listener on port 8443."
    assert re.search(r'cert\s*=\s*/home/user/webhook\.pem', unit, re.I), "Service does not use webhook.pem."
    assert re.search(r'(^|,)\s*verify\s*=\s*0(?:,|\s|$)', unit, re.I), "Service does not disable client certificate verification."
    assert re.search(r'(^|,)\s*fork(?:,|\s)', unit, re.I), "Service is not configured to fork per connection."
    assert re.search(r'EXEC[^\n]*/home/user/manifest_validator', unit, re.I), "Service does not exec the validator."


def test_systemd_service_active():
    result = run(["systemctl", "--user", "is-active", "k8s-webhook.service"], text=True)
    assert result.returncode == 0 and result.stdout.strip() == "active", \
        f"k8s-webhook.service is not active. systemctl output: {result.stdout} {result.stderr}"


def generated_cases():
    nonce = secrets.token_hex(12)
    clean = [
        f"apiVersion: v1\nkind: Pod\nmetadata:\n  name: clean-{nonce}\nspec:\n  containers: []\n",
        f"metadata: {{name: clean-{nonce}}}\nspec: {{hostNetwork: false, token: {nonce}}}\n",
        f"note: 'hostNetwork: true'\nrandom_{nonce}: true\n",
        f"literal: |\n  hostNetwork: true\n  random: {nonce}\nspec:\n  safe: true\n",
        f"hostNetworkX: true\nhostnetwork: true\nhostNetwork: True\nnonce: {nonce}\n",
        f"items:\n  - hostNetwork\n  - true\n  - {nonce}\n",
        f"hostNetwork:\n  nested: true\nnonce: {nonce}\n",
        f"? [hostNetwork, {nonce}]\n: true\n",
        f"metadata:\n  annotations:\n    message: hostNetwork: true\nspec:\n  hostNetwork: false\nnonce: {nonce}\n",
    ]
    evil = [
        f"apiVersion: v1\nkind: Pod\nmetadata:\n  name: evil-{nonce}\nspec:\n  hostNetwork: true\n  containers: []\n",
        f"outer_{nonce}:\n  sequence:\n    - safe: false\n    - deeper:\n        hostNetwork: true\n",
        f"{{nonce: {nonce}, spec: {{hostNetwork: true, other: false}}}}\n",
        f"'hostNetwork': 'true'\nnonce: {nonce}\n",
        f"? hostNetwork\n: true\nnonce: {nonce}\n",
        f"---\nsafe: true\n---\nnonce: {nonce}\nnested:\n  hostNetwork: true\n",
        f"list:\n- name: {nonce}\n  hostNetwork : true\n",
    ]
    return clean, evil


def invoke_direct(data):
    return run([BINARY], input=data.encode(), timeout=5)


def invoke_tls(data):
    return run(["socat", "-", "ssl:localhost:8443,verify=0"], input=data.encode(), timeout=7)


def assert_decision(result, decision, code=None):
    assert result.stdout in expected_stdout(decision), \
        f"Expected exactly {decision}, got stdout={result.stdout!r}, stderr={result.stderr!r}, code={result.returncode}"
    if code is not None:
        assert result.returncode == code, f"Expected exit code {code}, got {result.returncode}."


def test_validator_generated_yaml_semantics_directly():
    clean, evil = generated_cases()
    for document in clean:
        assert_decision(invoke_direct(document), "ACCEPT", 0)
    for document in evil:
        assert_decision(invoke_direct(document), "REJECT", 1)


def test_tls_endpoint_executes_validator_on_generated_inputs():
    clean, evil = generated_cases()
    for document in clean[:4]:
        assert_decision(invoke_tls(document), "ACCEPT")
    for document in evil[:4]:
        assert_decision(invoke_tls(document), "REJECT")


def test_webhook_adversarial_corpus():
    evil_dir = "/app/corpora/evil"
    clean_dir = "/app/corpora/clean"
    assert os.path.isdir(evil_dir), f"Evil corpus directory {evil_dir} is missing."
    assert os.path.isdir(clean_dir), f"Clean corpus directory {clean_dir} is missing."
    evil_files = [f for f in os.listdir(evil_dir) if f.endswith((".yaml", ".yml"))]
    clean_files = [f for f in os.listdir(clean_dir) if f.endswith((".yaml", ".yml"))]
    bypassed_evil, modified_clean = [], []
    for filename in evil_files:
        with open(os.path.join(evil_dir, filename), "rb") as f:
            result = run(["socat", "-", "ssl:localhost:8443,verify=0"], input=f.read(), timeout=5)
        if result.stdout.strip() != b"REJECT":
            bypassed_evil.append(filename)
    for filename in clean_files:
        with open(os.path.join(clean_dir, filename), "rb") as f:
            result = run(["socat", "-", "ssl:localhost:8443,verify=0"], input=f.read(), timeout=5)
        if result.stdout.strip() != b"ACCEPT":
            modified_clean.append(filename)
    errors = []
    if bypassed_evil:
        errors.append(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_evil)}")
    if modified_clean:
        errors.append(f"{len(modified_clean)} of {len(clean_files)} clean modified: {', '.join(modified_clean)}")
    assert not errors, " | ".join(errors)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
