#!/bin/bash
set -u -o pipefail
mkdir -p /logs/verifier

if (
  set -e

  # Preserve the original final-output assertion.
  python3 - <<'PY'
import os

def levenshtein_distance(s1, s2):
    if len(s1) < len(s2):
        return levenshtein_distance(s2, s1)
    previous = range(len(s2) + 1)
    for i, c1 in enumerate(s1):
        current = [i + 1]
        for j, c2 in enumerate(s2):
            current.append(min(previous[j + 1] + 1,
                               current[j] + 1,
                               previous[j] + (c1 != c2)))
        previous = current
    return previous[-1]

path = '/home/user/extracted.txt'
assert os.path.exists(path), f'Expected extracted text file not found at {path}'
with open(path, encoding='utf-8') as f:
    extracted = f.read().strip()
truth = '''INVOICE #9981
Date: 2023-10-01
Total: $1,234.56
Thank you for your business!'''
distance = levenshtein_distance(truth.strip(), extracted)
assert distance <= 10, f'Levenshtein distance is {distance}, which exceeds the threshold of 10. Extracted text was:\n{extracted}'
PY

  export PATH=/usr/local/go/bin:/home/user/go/bin:$PATH
  cd /home/user/workspace

  test -f go.mod
  test -f proto/ocr.proto
  test -f server/server.go
  test -f client/client.go
  find . -type f -name '*_grpc.pb.go' -print -quit | grep -q .
  find . -type f -name '*.pb.go' ! -name '*_grpc.pb.go' -print -quit | grep -q .

  protoc -I proto --include_imports --descriptor_set_out=/tmp/ocr_descriptor.pb proto/ocr.proto
  go build ./...
  go build -o /tmp/ocr_server_verify ./server
  go build -o /tmp/ocr_client_verify ./client

  cat > /tmp/grpc_probe.go <<'GO'
package main

import (
    "context"
    "hash/crc32"
    "os"
    "time"

    "google.golang.org/grpc"
    "google.golang.org/grpc/codes"
    "google.golang.org/grpc/credentials/insecure"
    "google.golang.org/grpc/status"
    "google.golang.org/protobuf/proto"
    "google.golang.org/protobuf/reflect/protodesc"
    "google.golang.org/protobuf/reflect/protoreflect"
    "google.golang.org/protobuf/types/descriptorpb"
    "google.golang.org/protobuf/types/dynamicpb"
)

func main() {
    raw, err := os.ReadFile("/tmp/ocr_descriptor.pb")
    if err != nil { panic(err) }
    set := new(descriptorpb.FileDescriptorSet)
    if err := proto.Unmarshal(raw, set); err != nil { panic(err) }
    files, err := protodesc.NewFiles(set)
    if err != nil { panic(err) }

    var service protoreflect.ServiceDescriptor
    files.RangeFiles(func(fd protoreflect.FileDescriptor) bool {
        services := fd.Services()
        for i := 0; i < services.Len(); i++ {
            if services.Get(i).Name() == "OcrService" {
                service = services.Get(i)
                return false
            }
        }
        return true
    })
    if service == nil { panic("OcrService not found") }
    method := service.Methods().ByName("ExtractText")
    if method == nil { panic("ExtractText not found") }

    input := method.Input()
    output := method.Output()
    crcField := input.Fields().ByName("crc32")
    textField := output.Fields().ByName("text")
    if crcField == nil || crcField.Kind() != protoreflect.Uint32Kind {
        panic("request crc32 uint32 field not found")
    }
    if textField == nil || textField.Kind() != protoreflect.StringKind {
        panic("response text string field not found")
    }
    var imageField protoreflect.FieldDescriptor
    for i := 0; i < input.Fields().Len(); i++ {
        f := input.Fields().Get(i)
        if f.Kind() == protoreflect.BytesKind {
            if imageField != nil { panic("request has multiple bytes fields") }
            imageField = f
        }
    }
    if imageField == nil { panic("request image bytes field not found") }

    image, err := os.ReadFile("/app/invoice.png")
    if err != nil { panic(err) }
    sum := crc32.ChecksumIEEE(image)
    conn, err := grpc.NewClient("localhost:50051", grpc.WithTransportCredentials(insecure.NewCredentials()))
    if err != nil { panic(err) }
    defer conn.Close()
    rpc := "/" + string(service.FullName()) + "/" + string(method.Name())

    bad := dynamicpb.NewMessage(input)
    bad.Set(imageField, protoreflect.ValueOfBytes(image))
    bad.Set(crcField, protoreflect.ValueOfUint32(uint32(sum ^ 0xffffffff)))
    badResponse := dynamicpb.NewMessage(output)
    badCtx, badCancel := context.WithTimeout(context.Background(), 10*time.Second)
    err = conn.Invoke(badCtx, rpc, bad, badResponse)
    badCancel()
    if status.Code(err) != codes.InvalidArgument {
        panic("incorrect CRC was not rejected with InvalidArgument")
    }

    good := dynamicpb.NewMessage(input)
    good.Set(imageField, protoreflect.ValueOfBytes(image))
    good.Set(crcField, protoreflect.ValueOfUint32(sum))
    goodResponse := dynamicpb.NewMessage(output)
    goodCtx, goodCancel := context.WithTimeout(context.Background(), 30*time.Second)
    err = conn.Invoke(goodCtx, rpc, good, goodResponse)
    goodCancel()
    if err != nil { panic(err) }
    if err := os.WriteFile("/tmp/server_response.txt", []byte(goodResponse.Get(textField).String()), 0644); err != nil {
        panic(err)
    }
}
GO

  cp /app/invoice.png /tmp/original_invoice.png
  SERVER_PID=''
  cleanup() {
    if [ -n "$SERVER_PID" ]; then kill "$SERVER_PID" 2>/dev/null || true; fi
    cp /tmp/original_invoice.png /app/invoice.png 2>/dev/null || true
  }
  trap cleanup EXIT

  fuser -k 50051/tcp >/dev/null 2>&1 || true
  token="VERIFY-$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
  convert -background white -fill black -font Liberation-Mono -pointsize 28 \
    label:"OCR DYNAMIC TEST\n${token}\nAmount: \$739.42" /app/invoice.png
  tesseract /app/invoice.png stdout > /tmp/direct_tesseract.txt 2>/tmp/direct_tesseract.log

  # A real gRPC client must not produce the result while no server is available.
  rm -f /home/user/extracted.txt
  set +e
  timeout 8 /tmp/ocr_client_verify >/tmp/client_without_server.log 2>&1
  no_server_rc=$?
  set -e
  test "$no_server_rc" -ne 0
  test ! -e /home/user/extracted.txt

  /tmp/ocr_server_verify >/tmp/ocr_server.log 2>&1 &
  SERVER_PID=$!
  ready=0
  for _ in $(seq 1 50); do
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
      cat /tmp/ocr_server.log >&2
      exit 1
    fi
    if python3 - <<'PY'
import socket
s = socket.socket()
s.settimeout(.2)
try:
    s.connect(('localhost', 50051))
finally:
    s.close()
PY
    then
      ready=1
      break
    fi
    sleep .2
  done
  test "$ready" -eq 1

  go run /tmp/grpc_probe.go

  python3 - <<'PY'
def distance(a, b):
    if len(a) < len(b):
        return distance(b, a)
    row = list(range(len(b) + 1))
    for i, x in enumerate(a):
        new = [i + 1]
        for j, y in enumerate(b):
            new.append(min(row[j + 1] + 1, new[j] + 1, row[j] + (x != y)))
        row = new
    return row[-1]
with open('/tmp/direct_tesseract.txt', encoding='utf-8') as f:
    expected = f.read().strip()
with open('/tmp/server_response.txt', encoding='utf-8') as f:
    actual = f.read().strip()
assert expected, 'direct Tesseract produced no text'
assert distance(expected, actual) <= 10, (expected, actual)
PY

  rm -f /home/user/extracted.txt
  timeout 30 /tmp/ocr_client_verify >/tmp/client_with_server.log 2>&1
  test -f /home/user/extracted.txt
  cmp -s /tmp/server_response.txt /home/user/extracted.txt
); then
  echo "1" > /logs/verifier/reward.txt
else
  echo "0" > /logs/verifier/reward.txt
fi
