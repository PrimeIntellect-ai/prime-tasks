#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import http.server
import os
import random
import re
import socket
import subprocess
import threading
import time
import urllib.parse
import urllib.request


def test_url_tool_compiled_and_tests_pass():
    tool_path = '/home/user/url_tool'
    source_path = '/home/user/url_tool.cpp'
    assert os.path.exists(tool_path), f"Compiled binary {tool_path} does not exist."
    assert os.access(tool_path, os.X_OK), f"{tool_path} is not executable."
    with open(tool_path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"{tool_path} is not a compiled ELF executable."

    result = subprocess.run([tool_path, '--test'], capture_output=True, text=True, timeout=20)
    assert result.returncode == 0, f"url_tool --test failed with exit code {result.returncode}. Stderr: {result.stderr}"
    assert "PASS" in result.stdout, f"url_tool --test did not print 'PASS'. Output: {result.stdout}"

    # Exercise the submitted executable on verifier-generated encoded data.
    rng = random.SystemRandom()
    raw_values = [
        b'/admin/config?a=b', b'/vulnerable path', b'a/b?x=y&z=1',
        b'plus+sign and spaces', b'%percent', b'/lower/hex/slash'
    ]
    alphabet = b'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 /?&=+%._~-'
    for _ in range(250):
        raw_values.append(bytes(rng.choice(alphabet) for _ in range(rng.randint(5, 80))))

    encoded = []
    for raw in raw_values:
        value = urllib.parse.quote_from_bytes(raw, safe='-_.~')
        # Randomly use lower-case hex and the form convention '+' for spaces.
        value = re.sub(r'%[0-9A-F]{2}', lambda m: m.group(0).lower() if rng.randrange(2) else m.group(0), value)
        if rng.randrange(2):
            value = value.replace('%20', '+').replace('%20'.lower(), '+')
        encoded.append(value.encode('ascii'))

    decoded = subprocess.run(
        [tool_path], input=b'\n'.join(encoded) + b'\n', capture_output=True, timeout=20
    )
    assert decoded.returncode == 0, f"url_tool decoding failed: {decoded.stderr!r}"
    assert decoded.stdout.splitlines() == raw_values, "url_tool produced incorrect URL-decoding results"

    # Instrument the submitted source to verify that --test really performs exactly
    # 1000 encode/decode trials on alphanumeric strings of lengths 5 through 20.
    source = open(source_path, 'r').read()
    match = re.search(r'\bvoid\s+run_property_tests\s*\(\s*\)\s*\{', source)
    assert match, "run_property_tests() is missing from url_tool.cpp"
    open_brace = source.find('{', match.start())

    def matching_brace(text, start):
        depth = 0
        i = start
        quote = None
        line_comment = False
        block_comment = False
        while i < len(text):
            c = text[i]
            n = text[i + 1] if i + 1 < len(text) else ''
            if line_comment:
                if c == '\n': line_comment = False
            elif block_comment:
                if c == '*' and n == '/': block_comment = False; i += 1
            elif quote:
                if c == '\\': i += 1
                elif c == quote: quote = None
            elif c == '/' and n == '/': line_comment = True; i += 1
            elif c == '/' and n == '*': block_comment = True; i += 1
            elif c in ('\"', "'"): quote = c
            elif c == '{': depth += 1
            elif c == '}':
                depth -= 1
                if depth == 0: return i
            i += 1
        raise AssertionError("run_property_tests() has unbalanced braces")

    close_brace = matching_brace(source, open_brace)
    body = source[open_brace + 1:close_brace]
    body, encode_replacements = re.subn(r'\bencode_url\s*\(', 'verifier_encode_url(', body)
    body, decode_replacements = re.subn(r'\bdecode_url\s*\(', 'verifier_decode_url(', body)
    assert encode_replacements and decode_replacements, "property tests must call encode_url and decode_url"

    instrumentation = r'''
static int verifier_encodes = 0;
static int verifier_decodes = 0;
static std::vector<std::string> verifier_encoded_values;
static std::vector<std::string> verifier_original_values;
static bool verifier_fault_mode() { return std::getenv("VERIFIER_INJECT_MISMATCH") != nullptr; }
static std::string verifier_encode_url(const std::string& value) {
    if (value.size() < 5 || value.size() > 20) ::_Exit(91);
    for (unsigned char c : value) {
        if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'))) ::_Exit(92);
    }
    ++verifier_encodes;
    verifier_original_values.push_back(value);
    std::string encoded = encode_url(value);
    verifier_encoded_values.push_back(encoded);
    return encoded;
}
static std::string verifier_decode_url(const std::string& value) {
    if (verifier_decodes >= (int)verifier_encoded_values.size()) ::_Exit(93);
    if (value != verifier_encoded_values[verifier_decodes]) ::_Exit(94);
    ++verifier_decodes;
    std::string result = decode_url(value);
    if (verifier_fault_mode() && verifier_decodes == 500) result += "!";
    return result;
}
static void verifier_finish() {
    if (verifier_fault_mode()) return;
    if (verifier_encodes != 1000 || verifier_decodes != 1000) ::_Exit(95);
    int distinct = 0;
    for (size_t i = 0; i < verifier_original_values.size(); ++i) {
        bool first = true;
        for (size_t j = 0; j < i; ++j) if (verifier_original_values[i] == verifier_original_values[j]) { first = false; break; }
        if (first) ++distinct;
    }
    if (distinct < 100) ::_Exit(96);
}
struct verifier_registration {
    verifier_registration() { std::atexit(verifier_finish); }
} verifier_registration_instance;
'''
    instrumented = source[:match.start()] + instrumentation + source[match.start():open_brace + 1] + body + source[close_brace:]
    instrumented_path = '/tmp/instrumented_url_tool.cpp'
    instrumented_bin = '/tmp/instrumented_url_tool'
    open(instrumented_path, 'w').write(instrumented)
    build = subprocess.run(['g++', '-O2', '-std=c++17', instrumented_path, '-o', instrumented_bin], capture_output=True, text=True)
    assert build.returncode == 0, f"Instrumented url_tool.cpp did not compile: {build.stderr}"

    normal = subprocess.run([instrumented_bin, '--test'], capture_output=True, text=True, timeout=20)
    assert normal.returncode == 0 and 'PASS' in normal.stdout, (
        f"run_property_tests did not complete 1000 valid property trials: {normal.stdout} {normal.stderr}"
    )
    fault_env = os.environ.copy()
    fault_env['VERIFIER_INJECT_MISMATCH'] = '1'
    faulted = subprocess.run([instrumented_bin, '--test'], env=fault_env, capture_output=True, text=True, timeout=20)
    assert faulted.returncode != 0, "run_property_tests did not fail when a decode mismatch was injected"
    assert (faulted.stdout + faulted.stderr).strip(), "run_property_tests did not print an error for a mismatch"


def test_matches_txt_contents():
    matches_path = '/home/user/matches.txt'
    assert os.path.exists(matches_path), f"{matches_path} does not exist."

    with open(matches_path, 'r') as f:
        matches = [line.strip() for line in f.readlines() if line.strip()]

    expected = [
        "/admin/config?a=b",
        "/etc/passwd",
        "/vulnerable path"
    ]
    assert sorted(matches) == sorted(expected), f"Contents of {matches_path} do not match expected known bad paths. Found: {matches}"

    # Independently derive the intersection from the actual log and bad-signature file.
    request_paths = []
    request_re = re.compile(r'"[^" ]+\s+(\S+)\s+HTTP/[0-9.]+"')
    with open('/home/user/access.log', 'r') as f:
        for line in f:
            m = request_re.search(line)
            if m:
                request_paths.append(urllib.parse.unquote_plus(m.group(1)))
    with open('/home/user/known_bad.txt', 'r') as f:
        known_bad = {line.rstrip('\n') for line in f if line.rstrip('\n')}
    derived = sorted(set(request_paths) & known_bad)
    assert matches == sorted(set(matches)), "matches.txt must be sorted and contain no duplicates"
    assert matches == derived, f"matches.txt is not the derived log/signature intersection: expected {derived}, found {matches}"


def test_nginx_proxy_conf():
    conf_path = '/home/user/proxy.conf'
    assert os.path.exists(conf_path), f"{conf_path} does not exist."

    with open(conf_path, 'r') as f:
        content = f.read()

    assert "daemon off;" in content, f"{conf_path} is missing 'daemon off;' directive."
    assert "listen 127.0.0.1:8080;" in content or "listen 8080;" in content and "127.0.0.1" in content, f"{conf_path} does not seem to listen on 127.0.0.1:8080."
    assert "proxy_pass http://127.0.0.1:9000;" in content or "proxy_pass http://127.0.0.1:9000" in content, f"{conf_path} is missing the proxy_pass directive to http://127.0.0.1:9000."
    assert "access_log /home/user/access.log;" in content, f"{conf_path} is missing 'access_log /home/user/access.log;' directive."
    assert "pid /home/user/nginx.pid;" in content, f"{conf_path} is missing 'pid /home/user/nginx.pid;' directive."
    assert "user " not in content, f"{conf_path} should not contain a 'user' directive."

    syntax = subprocess.run(['nginx', '-t', '-c', conf_path], capture_output=True, text=True)
    assert syntax.returncode == 0, f"nginx rejected proxy.conf: {syntax.stdout}\n{syntax.stderr}"

    class Backend(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            body = ('backend:' + self.path).encode()
            self.send_response(200)
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        def log_message(self, *args):
            pass

    backend = http.server.ThreadingHTTPServer(('127.0.0.1', 9000), Backend)
    thread = threading.Thread(target=backend.serve_forever, daemon=True)
    thread.start()
    nginx = subprocess.Popen(['nginx', '-c', conf_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        response = None
        last_error = None
        for _ in range(40):
            if nginx.poll() is not None:
                out, err = nginx.communicate()
                raise AssertionError(f"nginx exited before serving requests: {out}\n{err}")
            try:
                with urllib.request.urlopen('http://127.0.0.1:8080/verifier-proxy-check?q=1', timeout=1) as r:
                    response = r.read()
                break
            except Exception as exc:
                last_error = exc
                time.sleep(0.1)
        assert response == b'backend:/verifier-proxy-check?q=1', f"reverse proxy did not reach the configured backend: {last_error}"
    finally:
        backend.shutdown()
        backend.server_close()
        if nginx.poll() is None:
            nginx.terminate()
            try:
                nginx.wait(timeout=5)
            except subprocess.TimeoutExpired:
                nginx.kill()
                nginx.wait(timeout=5)


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
