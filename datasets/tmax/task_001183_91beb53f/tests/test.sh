#!/bin/bash
set -u
mkdir -p /logs/verifier

ok=1
hidden_test=""

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import re

def test_test_results_log():
    log_path = '/home/user/workspace/test_results.log'
    assert os.path.exists(log_path), "test_results.log does not exist"

    with open(log_path, 'r') as f:
        log_contents = f.read()

    assert 'PASS' in log_contents, "Tests did not pass according to test_results.log"
    assert 'TestMigrationProperty' in log_contents, "TestMigrationProperty missing in test_results.log"
    assert 'TestGenerateManifest' in log_contents, "TestGenerateManifest missing in test_results.log"

def test_artifact_go_contents():
    artifact_path = '/home/user/workspace/artifact.go'
    assert os.path.exists(artifact_path), "artifact.go does not exist"

    with open(artifact_path, 'r') as f:
        content = f.read()

    assert 'type ArtifactV2 struct' in content, "ArtifactV2 struct is missing in artifact.go"
    assert 'type Manifest struct' in content, "Manifest struct is missing in artifact.go"
    assert 'func Migrate(' in content, "Migrate function is missing in artifact.go"
    assert 'func GenerateManifest(' in content, "GenerateManifest function is missing in artifact.go"

def test_artifact_test_go_exists():
    test_path = '/home/user/workspace/artifact_test.go'
    assert os.path.exists(test_path), "artifact_test.go does not exist"

    with open(test_path, 'r') as f:
        content = f.read()

    assert 'func TestMigrationProperty(' in content, "TestMigrationProperty function is missing in artifact_test.go"
    assert 'func TestGenerateManifest(' in content, "TestGenerateManifest function is missing in artifact_test.go"
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || ok=0

# Compile the whole module and actually execute the submitted tests.
if ! (cd /home/user/workspace && go test -count=1 -v ./...) > /tmp/submitted_go_test.log 2>&1; then
    cat /tmp/submitted_go_test.log
    ok=0
else
    cat /tmp/submitted_go_test.log
    grep -Eq '^=== RUN[[:space:]]+TestMigrationProperty($|/)' /tmp/submitted_go_test.log || ok=0
    grep -Eq '^=== RUN[[:space:]]+TestGenerateManifest($|/)' /tmp/submitted_go_test.log || ok=0
fi

# Independently exercise artifact.go without relying on assertions in the submitted tests.
hidden_test=$(mktemp /home/user/workspace/zz_verifier_XXXXXX_test.go) || ok=0
if [ -n "$hidden_test" ] && [ -f "$hidden_test" ]; then
cat > "$hidden_test" <<'GO_EOF'
package artifact

import (
    "bytes"
    "crypto/sha256"
    "encoding/hex"
    "math/rand"
    "reflect"
    "strings"
    "testing"
)

func verifierSHA256(data []byte) string {
    sum := sha256.Sum256(data)
    return hex.EncodeToString(sum[:])
}

func TestVerifierStructFields(t *testing.T) {
    v2 := reflect.TypeOf(ArtifactV2{})
    v2Fields := map[string]reflect.Type{
        "Identifier": reflect.TypeOf(""),
        "Bytes":      reflect.TypeOf(int(0)),
        "Checksum":   reflect.TypeOf(""),
        "Payload":    reflect.TypeOf([]byte(nil)),
        "Version":    reflect.TypeOf(int(0)),
    }
    for name, want := range v2Fields {
        field, found := v2.FieldByName(name)
        if !found {
            t.Fatalf("ArtifactV2 is missing field %s", name)
        }
        if field.Type != want {
            t.Fatalf("ArtifactV2.%s has type %v, want %v", name, field.Type, want)
        }
    }

    manifest := reflect.TypeOf(Manifest{})
    manifestFields := map[string]reflect.Type{
        "Artifacts":    reflect.TypeOf([]ArtifactV2(nil)),
        "ManifestHash": reflect.TypeOf(""),
    }
    for name, want := range manifestFields {
        field, found := manifest.FieldByName(name)
        if !found {
            t.Fatalf("Manifest is missing field %s", name)
        }
        if field.Type != want {
            t.Fatalf("Manifest.%s has type %v, want %v", name, field.Type, want)
        }
    }
}

func TestVerifierMigrationBehavior(t *testing.T) {
    cases := []ArtifactV1{
        {ID: "", Size: 123, Hash: "legacy", Data: nil},
        {ID: "empty", Size: -1, Hash: "not-an-md5", Data: []byte{}},
        {ID: "unicode-世界", Size: 999, Hash: "ignored", Data: []byte{0, 1, 2, 127, 128, 255}},
        {ID: "binary\\x00id", Data: []byte("payload with spaces and newlines\n")},
    }

    rng := rand.New(rand.NewSource(739391))
    for i := 0; i < 200; i++ {
        payload := make([]byte, rng.Intn(1024))
        if _, err := rng.Read(payload); err != nil {
            t.Fatal(err)
        }
        idBytes := make([]byte, rng.Intn(80))
        if _, err := rng.Read(idBytes); err != nil {
            t.Fatal(err)
        }
        cases = append(cases, ArtifactV1{
            ID:   string(idBytes),
            Size: rng.Int(),
            Hash: "untrusted legacy hash",
            Data: payload,
        })
    }

    for i, input := range cases {
        got := Migrate(input)
        if got.Identifier != input.ID {
            t.Fatalf("case %d: Identifier = %q, want %q", i, got.Identifier, input.ID)
        }
        if !bytes.Equal(got.Payload, input.Data) {
            t.Fatalf("case %d: Payload does not equal input Data", i)
        }
        if got.Bytes != len(input.Data) {
            t.Fatalf("case %d: Bytes = %d, want %d", i, got.Bytes, len(input.Data))
        }
        if got.Version != 2 {
            t.Fatalf("case %d: Version = %d, want 2", i, got.Version)
        }
        wantChecksum := verifierSHA256(input.Data)
        if got.Checksum != wantChecksum {
            t.Fatalf("case %d: Checksum = %q, want %q", i, got.Checksum, wantChecksum)
        }
    }
}

func TestVerifierManifestBehavior(t *testing.T) {
    cases := [][]ArtifactV2{
        nil,
        {},
        {{Identifier: "a", Checksum: "abc", Payload: []byte("ignored")}},
        {
            {Identifier: "first", Checksum: "00ff", Version: 2},
            {Identifier: "second", Checksum: "not-even-hex", Version: 17},
            {Identifier: "third", Checksum: "", Bytes: 999},
        },
        {
            Migrate(ArtifactV1{ID: "one", Data: []byte("alpha")}),
            Migrate(ArtifactV1{ID: "two", Data: []byte{0, 255, 4, 9}}),
        },
    }

    for i, artifacts := range cases {
        before := append([]ArtifactV2(nil), artifacts...)
        got := GenerateManifest(artifacts)
        if !reflect.DeepEqual(got.Artifacts, artifacts) {
            t.Fatalf("case %d: manifest Artifacts = %#v, want %#v", i, got.Artifacts, artifacts)
        }
        checksums := make([]string, len(artifacts))
        for j := range artifacts {
            checksums[j] = artifacts[j].Checksum
        }
        wantHash := verifierSHA256([]byte(strings.Join(checksums, "")))
        if got.ManifestHash != wantHash {
            t.Fatalf("case %d: ManifestHash = %q, want %q", i, got.ManifestHash, wantHash)
        }
        if !reflect.DeepEqual(artifacts, before) {
            t.Fatalf("case %d: GenerateManifest modified its input", i)
        }
    }
}
GO_EOF

    hidden_base=$(basename "$hidden_test")
    if ! (cd /home/user/workspace && go test -count=1 -v artifact.go "$hidden_base") > /tmp/independent_go_test.log 2>&1; then
        cat /tmp/independent_go_test.log
        ok=0
    else
        cat /tmp/independent_go_test.log
    fi
else
    ok=0
fi

[ -n "$hidden_test" ] && rm -f "$hidden_test"

if [ "$ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
