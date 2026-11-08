#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import string
import subprocess
import textwrap

AGENT_SCRIPT = "/home/user/lb_decision.go"
ORACLE_PATH = "/opt/oracle/lb_decision_oracle"
AGENT_BIN = "/tmp/lb_decision_agent"


def generate_random_yaml():
    vms_count = random.randint(0, 10)
    status_choices = ["online", "offline", "maintenance", "booting"]

    yaml_lines = []
    yaml_lines.append("request:")
    yaml_lines.append(f'  path: "/api/{"".join(random.choices(string.ascii_lowercase, k=5))}"')
    yaml_lines.append('  method: "GET"')
    yaml_lines.append("vms:")

    for _ in range(vms_count):
        node_id = f"qemu-node-{random.randint(1, 1000)}"
        status = random.choice(status_choices)
        cpu = round(random.uniform(0.0, 100.0), 2)
        yaml_lines.append(f'  - id: "{node_id}"')
        yaml_lines.append(f'    status: "{status}"')
        yaml_lines.append(f"    cpu: {cpu}")

    if vms_count == 0:
        yaml_lines.append("  []")

    return "\n".join(yaml_lines) + "\n"


def run_checked(cmd, **kwargs):
    proc = subprocess.run(cmd, capture_output=True, text=True, **kwargs)
    assert proc.returncode == 0, (
        f"Command failed: {cmd}\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    )
    return proc


def test_fuzz_equivalence():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} does not exist."
    assert os.path.isfile(ORACLE_PATH), f"Oracle program {ORACLE_PATH} does not exist."

    with open(AGENT_SCRIPT, "rb") as agent_file, open(ORACLE_PATH, "rb") as oracle_file:
        assert agent_file.read() != oracle_file.read(), "Submission is byte-identical to the reference implementation."

    compile_proc = subprocess.run(
        ["go", "build", "-o", AGENT_BIN, AGENT_SCRIPT],
        capture_output=True,
        text=True,
        cwd="/home/user",
    )
    assert compile_proc.returncode == 0, f"Failed to compile {AGENT_SCRIPT}:\n{compile_proc.stderr}"

    random.seed(42)
    inputs = [generate_random_yaml() for _ in range(500)]
    inputs.extend([
        "request: {path: '/api/data', method: GET}\nvms: [{id: qemu-node-9, status: online, cpu: 14.5}, {id: qemu-node-2, status: online, cpu: 14.5}]\n",
        "---\n# keys and list fields may be reordered\nvms:\n  - cpu: 79.99\n    id: 'alpha'\n    status: online\n  - status: online\n    cpu: 80.0\n    id: beta\nrequest:\n  method: GET\n  path: /health\n",
        "defaults: &healthy\n  status: online\n  cpu: 21.25\nrequest:\n  path: /api/data\n  method: GET\nvms:\n  - <<: *healthy\n    id: qemu-node-3\n  - id: qemu-node-1\n    status: offline\n    cpu: 1.0\n",
        "request:\n  path: /none\n  method: POST\nvms: []\n",
    ])

    for i, input_yaml in enumerate(inputs):
        oracle_proc = subprocess.run([ORACLE_PATH], input=input_yaml, capture_output=True, text=True)
        assert oracle_proc.returncode == 0, f"Oracle failed on input:\n{input_yaml}\nStderr:\n{oracle_proc.stderr}"
        oracle_output = oracle_proc.stdout.strip()

        agent_proc = subprocess.run([AGENT_BIN], input=input_yaml, capture_output=True, text=True)
        assert agent_proc.returncode == 0, f"Agent program failed on input:\n{input_yaml}\nStderr:\n{agent_proc.stderr}"
        agent_output = agent_proc.stdout.strip()

        assert agent_output == oracle_output, (
            f"Mismatch on iteration {i}.\nInput YAML:\n{input_yaml}\n"
            f"Expected (Oracle): {oracle_output}\nGot (Agent): {agent_output}"
        )


def test_go_module_and_yaml_usage():
    go_mod = "/home/user/go.mod"
    assert os.path.isfile(go_mod), "A local /home/user/go.mod is required."

    gomod_proc = run_checked(["go", "env", "GOMOD"], cwd="/home/user")
    assert os.path.realpath(gomod_proc.stdout.strip()) == go_mod, "The program is not using /home/user/go.mod."

    edit_proc = run_checked(["go", "mod", "edit", "-json"], cwd="/home/user")
    mod_data = json.loads(edit_proc.stdout)
    assert any(r.get("Path") == "gopkg.in/yaml.v3" for r in mod_data.get("Require", [])), (
        "go.mod must require gopkg.in/yaml.v3."
    )

    replacements = [r for r in mod_data.get("Replace", []) if r.get("Old", {}).get("Path") == "gopkg.in/yaml.v3"]
    assert replacements, "go.mod must replace gopkg.in/yaml.v3 with the local vendored package."
    replacement_path = replacements[0].get("New", {}).get("Path", "")
    if not os.path.isabs(replacement_path):
        replacement_path = os.path.join("/home/user", replacement_path)
    assert os.path.realpath(replacement_path) == "/app/vendor/yaml.v3", (
        "gopkg.in/yaml.v3 must be replaced with /app/vendor/yaml.v3."
    )

    module_proc = run_checked(
        ["go", "list", "-m", "-f", "{{.Dir}}", "gopkg.in/yaml.v3"], cwd="/home/user"
    )
    assert os.path.realpath(module_proc.stdout.strip()) == "/app/vendor/yaml.v3", (
        "gopkg.in/yaml.v3 does not resolve to /app/vendor/yaml.v3."
    )

    ast_checker = r'''
package main
import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
    "strconv"
)
func main() {
    if len(os.Args) != 2 { os.Exit(2) }
    f, err := parser.ParseFile(token.NewFileSet(), os.Args[1], nil, 0)
    if err != nil { panic(err) }
    alias := ""
    dot := false
    for _, imp := range f.Imports {
        p, _ := strconv.Unquote(imp.Path.Value)
        if p == "gopkg.in/yaml.v3" {
            if imp.Name == nil { alias = "yaml" } else if imp.Name.Name == "." { dot = true } else if imp.Name.Name != "_" { alias = imp.Name.Name }
        }
    }
    if alias == "" && !dot { fmt.Println("missing usable yaml.v3 import"); os.Exit(1) }
    used := false
    ast.Inspect(f, func(n ast.Node) bool {
        call, ok := n.(*ast.CallExpr)
        if !ok { return true }
        if sel, ok := call.Fun.(*ast.SelectorExpr); ok {
            if id, ok := sel.X.(*ast.Ident); ok && id.Name == alias { used = true }
        }
        if dot {
            if id, ok := call.Fun.(*ast.Ident); ok && (id.Name == "Unmarshal" || id.Name == "NewDecoder") { used = true }
        }
        return true
    })
    if !used { fmt.Println("yaml.v3 is imported but not used to parse input"); os.Exit(1) }
}
'''
    with open("/tmp/check_yaml_usage.go", "w") as f:
        f.write(ast_checker)
    run_checked(["go", "build", "-o", "/tmp/check_yaml_usage", "/tmp/check_yaml_usage.go"], cwd="/home/user")
    usage_proc = subprocess.run(["/tmp/check_yaml_usage", AGENT_SCRIPT], capture_output=True, text=True)
    assert usage_proc.returncode == 0, usage_proc.stdout + usage_proc.stderr


def test_yaml_fixed():
    with open('/app/vendor/yaml.v3/yaml.go', 'r') as f:
        content = f.read()
    assert 'panic("TODO: implement")' not in content, "The panic perturbation in yaml.go is still present."

    probe = r'''
package main
import (
    "fmt"
    "gopkg.in/yaml.v3"
)
type VM struct {
    ID string `yaml:"id"`
    Status string `yaml:"status"`
    CPU float64 `yaml:"cpu"`
}
type Payload struct {
    Request struct {
        Path string `yaml:"path"`
        Method string `yaml:"method"`
    } `yaml:"request"`
    VMs []VM `yaml:"vms"`
}
func main() {
    input := []byte("defaults: &base\n  status: online\n  cpu: 12.5\nrequest: {path: '/api/data', method: GET}\nvms:\n  - <<: *base\n    id: qemu-node-2\n  - id: qemu-node-1\n    status: offline\n    cpu: 7\n")
    var p Payload
    if err := yaml.Unmarshal(input, &p); err != nil { panic(err) }
    if p.Request.Path != "/api/data" || p.Request.Method != "GET" || len(p.VMs) != 2 || p.VMs[0].ID != "qemu-node-2" || p.VMs[0].Status != "online" || p.VMs[0].CPU != 12.5 || p.VMs[1].ID != "qemu-node-1" {
        panic(fmt.Sprintf("unexpected decoded value: %#v", p))
    }
}
'''
    with open("/tmp/yaml_unmarshal_probe.go", "w") as f:
        f.write(probe)
    run_checked(["go", "build", "-o", "/tmp/yaml_unmarshal_probe", "/tmp/yaml_unmarshal_probe.go"], cwd="/home/user")
    run_checked(["/tmp/yaml_unmarshal_probe"])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
