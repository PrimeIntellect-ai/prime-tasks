#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import subprocess
import time
from pathlib import Path

import pytest

PROJECT = Path('/home/user/project')
GO_DIR = PROJECT / 'go'
ENV = os.environ.copy()
ENV['PATH'] = ':'.join([
    '/home/user/.local/bin',
    '/home/user/go/bin',
    '/home/user/project/bin',
    ENV.get('PATH', ''),
])


def run(cmd, cwd=PROJECT, timeout=180, check=True):
    result = subprocess.run(
        cmd,
        cwd=str(cwd),
        env=ENV,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )
    if check and result.returncode != 0:
        pytest.fail(f"Command failed ({result.returncode}): {' '.join(cmd)}\n{result.stdout}")
    return result


def test_required_local_protobuf_tools_exist():
    for tool in ('protoc', 'protoc-gen-go', 'protoc-gen-go-grpc'):
        path = shutil.which(tool, path=ENV['PATH'])
        assert path, f'{tool} is not available in the expected local tool paths'
        assert os.access(path, os.X_OK), f'{path} is not executable'


def test_proto_source_has_required_declarations():
    proto = PROJECT / 'proto/security.proto'
    assert proto.is_file(), f'Missing {proto}'
    text = proto.read_text()
    text = re.sub(r'//.*?$|/\*.*?\*/', '', text, flags=re.M | re.S)
    assert re.search(r'\bsyntax\s*=\s*[\"\']proto3[\"\']\s*;', text)
    assert re.search(r'\bpackage\s+security\s*;', text)
    assert re.search(r'\boption\s+go_package\s*=\s*[\"\']security/pb[\"\']\s*;', text)
    assert re.search(r'\bservice\s+SecurityAnalyzer\s*\{[^}]*\brpc\s+AnalyzeLogs\s*\(\s*AnalyzeRequest\s*\)\s*returns\s*\(\s*AnalyzeResponse\s*\)', text, re.S)
    assert re.search(r'\bmessage\s+AnalyzeRequest\s*\{[^}]*\brepeated\s+string\s+logs\s*=\s*1\s*;', text, re.S)
    assert re.search(r'\bmessage\s+AnalyzeResponse\s*\{[^}]*\brepeated\s+string\s+malicious_ips\s*=\s*1\s*;', text, re.S)


def test_makefile_targets_execute_real_work():
    makefile = PROJECT / 'Makefile'
    assert makefile.is_file(), f'Missing {makefile}'

    # Dry-run checks retain the explicitly requested recipes rather than aliases/no-ops.
    rules_plan = run(['make', '-B', '-n', 'rules']).stdout
    assert re.search(r'python3\s+python/generate\.py', rules_plan), rules_plan
    proto_plan = run(['make', '-B', '-n', 'proto']).stdout
    assert 'protoc' in proto_plan and 'proto/security.proto' in proto_plan, proto_plan
    test_plan = run(['make', '-B', '-n', 'test']).stdout
    assert re.search(r'go\s+test\s+\.\/\.\.\.', test_plan), test_plan

    generator = PROJECT / 'python/generate.py'
    original_generator = generator.read_bytes()
    marker = '/verifier-rule-7d94b6'
    try:
        # A changed generator proves that the rules prerequisite is actually run by build.
        generator.write_text(
            'import json\n'
            'with open("/home/user/project/rules.json", "w") as f:\n'
            f'    json.dump(["{marker}"], f)\n'
        )
        rules = PROJECT / 'rules.json'
        if rules.exists():
            rules.unlink()
        for generated in (GO_DIR / 'pb').glob('*.go'):
            generated.unlink()
        binary = PROJECT / 'bin/server'
        if binary.exists():
            binary.unlink()

        run(['make', '-B', 'build'], timeout=300)
        assert json.loads(rules.read_text()) == [marker], 'build did not run the rules prerequisite'
        assert list((GO_DIR / 'pb').glob('*.go')), 'build did not regenerate protobuf Go files'
        assert binary.is_file() and os.access(binary, os.X_OK), 'make build did not create an executable server'
    finally:
        generator.write_bytes(original_generator)
        run(['make', '-B', 'rules'])

    # Execute the requested test target, including its proto and rules prerequisites.
    result = run(['make', '-B', 'test'], timeout=300)
    assert re.search(r'(^|\s)(ok|PASS)(\s|$)', result.stdout, re.M), result.stdout


def test_generated_descriptor_and_analyzer_behavior():
    token = 'vfy_4e21'
    malicious_paths = [f'/{token}/zeta', f'/{token}/alpha', f'/{token}/exact']
    rules_path = PROJECT / 'rules.json'
    original_rules = rules_path.read_bytes() if rules_path.exists() else None
    hidden_test = GO_DIR / 'verifier_hidden_test.go'

    hidden_test.write_text(r'''package main

import (
    "context"
    "reflect"
    "testing"
    "security/pb"
    "google.golang.org/protobuf/reflect/protoreflect"
)

func TestVerifierProtoDescriptorAndBehavior(t *testing.T) {
    fd := pb.File_proto_security_proto
    if string(fd.Package()) != "security" { t.Fatalf("package = %q", fd.Package()) }
    req := fd.Messages().ByName("AnalyzeRequest")
    resp := fd.Messages().ByName("AnalyzeResponse")
    if req == nil || resp == nil { t.Fatal("required messages missing") }
    logs := req.Fields().ByName("logs")
    ips := resp.Fields().ByName("malicious_ips")
    if logs == nil || logs.Number() != 1 || logs.Kind() != protoreflect.StringKind || logs.Cardinality() != protoreflect.Repeated {
        t.Fatal("AnalyzeRequest.logs has the wrong descriptor")
    }
    if ips == nil || ips.Number() != 1 || ips.Kind() != protoreflect.StringKind || ips.Cardinality() != protoreflect.Repeated {
        t.Fatal("AnalyzeResponse.malicious_ips has the wrong descriptor")
    }
    svc := fd.Services().ByName("SecurityAnalyzer")
    if svc == nil { t.Fatal("SecurityAnalyzer service missing") }
    method := svc.Methods().ByName("AnalyzeLogs")
    if method == nil || method.Input().FullName() != req.FullName() || method.Output().FullName() != resp.FullName() {
        t.Fatal("AnalyzeLogs has the wrong input or output type")
    }

    s := &Server{}
    got, err := s.AnalyzeLogs(context.Background(), &pb.AnalyzeRequest{Logs: []string{
        "203.0.113.9 GET /vfy_4e21/zeta",
        "198.51.100.20 POST /vfy_4e21/alpha",
        "203.0.113.9 PUT /vfy_4e21/exact",
        "192.0.2.4 GET /vfy_4e21/exact/extra",
        "198.51.100.3 GET /ordinary",
        "198.51.100.20 GET /vfy_4e21/zeta",
    }})
    if err != nil { t.Fatalf("AnalyzeLogs: %v", err) }
    want := []string{"198.51.100.20", "203.0.113.9"}
    if !reflect.DeepEqual(got.MaliciousIps, want) {
        t.Fatalf("malicious_ips = %v, want %v", got.MaliciousIps, want)
    }
}
''')

    try:
        rules_path.write_text(json.dumps(malicious_paths))
        run(['go', 'test', './...', '-run', '^TestVerifierProtoDescriptorAndBehavior$', '-count=1'], cwd=GO_DIR, timeout=300)
    finally:
        hidden_test.unlink(missing_ok=True)
        if original_rules is None:
            rules_path.unlink(missing_ok=True)
        else:
            rules_path.write_bytes(original_rules)


def test_server_go_exists_and_uses_concurrency():
    server_go_path = GO_DIR / 'server.go'
    assert server_go_path.is_file(), f'Go source file at {server_go_path} does not exist.'
    content = server_go_path.read_text()

    # Preserve the original assertions.
    has_go = 'go ' in content or 'go\t' in content or 'go\n' in content
    has_chan = 'chan ' in content or 'chan\t' in content or 'chan<-' in content or '<-chan' in content
    assert has_go, f"The file {server_go_path} does not appear to use goroutines ('go' keyword missing)."
    assert has_chan, f"The file {server_go_path} does not appear to use channels ('chan' keyword missing)."

    # Parse the Go AST so comments and string literals cannot satisfy concurrency checks.
    checker = Path('/tmp/check_concurrency.go')
    checker.write_text(r'''package main
import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
)
func main() {
    path := os.Args[len(os.Args)-1]
    f, err := parser.ParseFile(token.NewFileSet(), path, nil, 0)
    if err != nil { panic(err) }
    hasGo, hasChan := false, false
    ast.Inspect(f, func(n ast.Node) bool {
        switch n.(type) {
        case *ast.GoStmt:
            hasGo = true
        case *ast.ChanType:
            hasChan = true
        }
        return true
    })
    if !hasGo || !hasChan {
        fmt.Fprintf(os.Stderr, "real goroutine=%v channel=%v\n", hasGo, hasChan)
        os.Exit(1)
    }
}
''')
    run(['go', 'run', str(checker), '--', str(server_go_path)], timeout=120)


def test_bin_server_exists_executable_and_is_runnable_go_binary():
    bin_path = PROJECT / 'bin/server'
    assert bin_path.is_file(), f"Expected binary at {bin_path} does not exist. Did 'make build' run successfully?"
    assert os.access(bin_path, os.X_OK), f'The file at {bin_path} is not executable.'
    run(['go', 'version', '-m', str(bin_path)])

    proc = subprocess.Popen(
        [str(bin_path)], cwd=str(PROJECT), env=ENV,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )
    try:
        time.sleep(0.75)
        assert proc.poll() is None, f'server binary exited immediately with status {proc.returncode}'
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=3)


def test_report_txt_contains_pass():
    report_path = Path('/home/user/test_report.txt')
    assert report_path.is_file(), f'Test report at {report_path} does not exist. Did you pipe make test output to it?'
    content = report_path.read_text()
    assert 'PASS' in content, f"The test report {report_path} does not contain 'PASS'. The Go tests might have failed."


def test_rules_json_exists():
    rules_json_path = PROJECT / 'rules.json'
    assert rules_json_path.is_file(), f'rules.json at {rules_json_path} does not exist. Did make rules run successfully?'
    rules = json.loads(rules_json_path.read_text())
    assert isinstance(rules, list) and all(isinstance(item, str) for item in rules)
PYTEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
