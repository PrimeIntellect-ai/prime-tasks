#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import string
import subprocess
import tempfile
import urllib.parse

BINARY = '/home/user/waf_filter'
SOURCE = '/home/user/waf.go'


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def test_waf_filter_binary_exists():
    assert os.path.isfile(BINARY), f"Compiled binary {BINARY} is missing."
    assert os.access(BINARY, os.X_OK), f"Binary {BINARY} is not executable."

    result = run(['go', 'version', '-m', BINARY])
    assert result.returncode == 0, f"{BINARY} is not a compiled Go binary: {result.stderr}"
    build_info = result.stdout + result.stderr
    assert 'github.com/testorg/gowaf' in build_info, \
        f"{BINARY} does not include the required gowaf module."


def test_gowaf_fixes():
    parser_path = '/app/gowaf/parser.go'
    with open(parser_path, 'r') as f:
        parser_content = f.read()
    assert '"strings"' in parser_content, f"{parser_path} is still missing the 'strings' import."

    makefile_path = '/app/gowaf/Makefile'
    with open(makefile_path, 'r') as f:
        makefile_content = f.read()
    assert 'go build' in makefile_content, f"{makefile_path} still has the typo or is missing 'go build'."
    assert 'go biuld' not in makefile_content, f"{makefile_path} still contains the 'go biuld' typo."

    dry_run = run(['make', '-B', '-n', 'build'], cwd='/app/gowaf')
    assert dry_run.returncode == 0, f"gowaf Makefile build target is invalid: {dry_run.stderr}"
    assert re.search(r'(^|[;&|]\s*)go\s+build(?:\s|$)', dry_run.stdout, re.MULTILINE), \
        "gowaf Makefile build target does not run go build."

    make_result = run(['make', '-B', 'build'], cwd='/app/gowaf')
    assert make_result.returncode == 0, \
        f"gowaf Makefile cannot build the package:\n{make_result.stdout}\n{make_result.stderr}"

    direct_build = run(['go', 'build', './...'], cwd='/app/gowaf')
    assert direct_build.returncode == 0, \
        f"gowaf package does not compile:\n{direct_build.stdout}\n{direct_build.stderr}"


def test_source_exists_builds_and_calls_normalize_payload():
    assert os.path.isfile(SOURCE), f"Required Go source {SOURCE} is missing."

    analyzer = r'''
package main
import (
    "go/ast"
    "go/parser"
    "go/token"
    "os"
    "strconv"
)
func main() {
    f, err := parser.ParseFile(token.NewFileSet(), os.Args[1], nil, 0)
    if err != nil { os.Exit(2) }
    aliases := map[string]bool{}
    dot := false
    imported := false
    for _, imp := range f.Imports {
        p, err := strconv.Unquote(imp.Path.Value)
        if err != nil || p != "github.com/testorg/gowaf" { continue }
        imported = true
        if imp.Name == nil { aliases["gowaf"] = true
        } else if imp.Name.Name == "." { dot = true
        } else if imp.Name.Name != "_" { aliases[imp.Name.Name] = true }
    }
    called := false
    ast.Inspect(f, func(n ast.Node) bool {
        call, ok := n.(*ast.CallExpr)
        if !ok { return true }
        if dot {
            if id, ok := call.Fun.(*ast.Ident); ok && id.Name == "NormalizePayload" { called = true }
        }
        if sel, ok := call.Fun.(*ast.SelectorExpr); ok && sel.Sel.Name == "NormalizePayload" {
            if id, ok := sel.X.(*ast.Ident); ok && aliases[id.Name] { called = true }
        }
        return true
    })
    if !imported || !called { os.Exit(1) }
}
'''
    with open('/tmp/check_waf_ast.go', 'w') as f:
        f.write(analyzer)
    checked = run(['go', 'run', '/tmp/check_waf_ast.go', SOURCE])
    assert checked.returncode == 0, \
        f"{SOURCE} must import github.com/testorg/gowaf and call its NormalizePayload function."

    rebuilt = '/tmp/rebuilt_waf_filter'
    built = run(['go', 'build', '-gcflags=all=-l', '-o', rebuilt, SOURCE], cwd='/home/user')
    assert built.returncode == 0, \
        f"{SOURCE} cannot be compiled:\n{built.stdout}\n{built.stderr}"

    symbols = run(['go', 'tool', 'nm', rebuilt])
    assert symbols.returncode == 0, f"Unable to inspect rebuilt Go binary: {symbols.stderr}"
    assert re.search(r'github\.com/testorg/gowaf\.NormalizePayload(?:\s|$)', symbols.stdout), \
        "The binary rebuilt from waf.go does not link gowaf.NormalizePayload."


def parse_output(result, expected_names):
    assert result.returncode == 0, \
        f"waf_filter failed with status {result.returncode}: {result.stderr}"
    observed = {}
    lines = result.stdout.splitlines()
    for line in lines:
        assert ': ' in line, f"Malformed output line: {line!r}"
        name, classification = line.split(': ', 1)
        assert name not in observed, f"Duplicate output for {name!r}."
        assert classification in ('EVIL', 'CLEAN'), f"Invalid classification in line: {line!r}"
        observed[name] = classification
    assert set(observed) == set(expected_names), \
        f"Output filenames differ: expected {set(expected_names)!r}, got {set(observed)!r}"
    return observed


def legacy_expected(payload):
    norm = urllib.parse.unquote(payload).lower().replace('\x00', '')
    evil = (
        '<script>' in norm or 'javascript:' in norm or
        'union select' in norm or 'drop table' in norm or
        '../' in norm or '/etc/passwd' in norm
    )
    return 'EVIL' if evil else 'CLEAN'


def test_generated_hidden_cases_on_submitted_and_rebuilt_binaries():
    nonce = secrets.token_hex(10)
    payloads = [
        f"prefix-{nonce}-%3CsCrIpT%3Ealert(1)%3C/script%3E",
        f"x{nonce}JaVa%53cRiPt%3Aconfirm(1)",
        f"id={nonce}%00UNION%20SeLeCt%20name%20FROM%20accounts",
        f"before{nonce}DrOp%00%20TaBlE%20audit",
        f"root={nonce}..%2F..%2Fprivate",
        f"file={nonce}%2FeTc%2FpAsSwD",
        f"ordinary text {nonce}",
        f"%3Cscript data-x={nonce}%3E",
        f"javascript%3D{nonce}",
        f"union%20all%20select%20{nonce}",
        f"drop%20tables%20{nonce}",
        f"..%5C..%5C{nonce}",
        f"%252e%252e%252f{nonce}",
        f"search={nonce}%20apple%20pie",
    ]

    with tempfile.TemporaryDirectory(prefix='waf-hidden-' + nonce + '-') as directory:
        expected = {}
        alphabet = string.ascii_letters + string.digits
        for index, payload in enumerate(payloads):
            name = ''.join(secrets.choice(alphabet) for _ in range(18)) + f'-{index}.dat'
            with open(os.path.join(directory, name), 'wb') as f:
                f.write(payload.encode('utf-8'))
            expected[name] = legacy_expected(payload)

        for binary in (BINARY, '/tmp/rebuilt_waf_filter'):
            result = run([binary, directory])
            observed = parse_output(result, expected)
            assert observed == expected, \
                f"{binary} classifications differ from the legacy filter: expected {expected!r}, got {observed!r}"


def test_adversarial_corpus_results():
    evil_dir = '/home/user/corpus/evil/'
    clean_dir = '/home/user/corpus/clean/'

    evil_result = run([BINARY, evil_dir])
    assert evil_result.returncode == 0, "waf_filter failed to run on evil corpus."
    evil_output = evil_result.stdout.strip().split('\n')
    evil_dict = {}
    for line in evil_output:
        if ': ' in line:
            fname, res = line.split(': ', 1)
            evil_dict[fname.strip()] = res.strip()

    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    evil_bypassed = []
    for f in evil_files:
        if evil_dict.get(f) != 'EVIL':
            evil_bypassed.append(f)

    clean_result = run([BINARY, clean_dir])
    assert clean_result.returncode == 0, "waf_filter failed to run on clean corpus."
    clean_output = clean_result.stdout.strip().split('\n')
    clean_dict = {}
    for line in clean_output:
        if ': ' in line:
            fname, res = line.split(': ', 1)
            clean_dict[fname.strip()] = res.strip()

    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    clean_modified = []
    for f in clean_files:
        if clean_dict.get(f) != 'CLEAN':
            clean_modified.append(f)

    error_msg = []
    if evil_bypassed:
        error_msg.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msg.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    assert not error_msg, " | ".join(error_msg)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
