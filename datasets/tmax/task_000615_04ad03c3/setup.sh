#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Node.js 18
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs

    # Create project structure
    mkdir -p /app/api-gateway-core/src
    cd /app/api-gateway-core

    # Create package.json
    cat << 'EOF' > package.json
{
  "name": "api-gateway-core",
  "version": "1.2.0",
  "scripts": {
    "build": "node-gyp rebuild",
    "benchmark": "node benchmark.js"
  },
  "dependencies": {
    "node-addon-api": "^5.0.0"
  }
}
EOF

    # Create binding.gyp with typo
    cat << 'EOF' > binding.gyp
{
  "targets": [
    {
      "target_name": "validator",
      "sources": [ "src/validatr.cpp" ],
      "include_dirs": [
        "<!@(node -p \"require('node-addon-api').include\")"
      ],
      "dependencies": [
        "<!(node -p \"require('node-addon-api').gyp\")"
      ],
      "cflags!": [ "-fno-exceptions" ],
      "cflags_cc!": [ "-fno-exceptions" ],
      "defines": [ "NAPI_DISABLE_CPP_EXCEPTIONS" ]
    }
  ]
}
EOF

    # Create src/validator.cpp with O(N^2) logic
    cat << 'EOF' > src/validator.cpp
#include <napi.h>
#include <string>

bool IsBase64Char(char c) {
    return (isalnum(c) || c == '+' || c == '/');
}

Napi::Boolean ValidatePayload(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsString()) {
        Napi::TypeError::New(env, "String expected").ThrowAsJavaScriptException();
        return Napi::Boolean::New(env, false);
    }

    std::string payload = info[0].As<Napi::String>().Utf8Value();
    bool valid = true;

    // O(N^2) implementation
    for (size_t i = 0; i < payload.length(); i++) {
        char c = payload[i];
        if (c == '=') continue;

        bool found = false;
        // Inefficient search
        for (size_t j = 0; j <= i; j++) {
            if (IsBase64Char(payload[j])) {
                found = true;
            }
        }
        if (!found || !IsBase64Char(c)) {
            valid = false;
            break;
        }
    }

    return Napi::Boolean::New(env, valid);
}

Napi::Object Init(Napi::Env env, Napi::Object exports) {
    exports.Set(Napi::String::New(env, "validatePayload"), Napi::Function::New(env, ValidatePayload));
    return exports;
}

NODE_API_MODULE(validator, Init)
EOF

    # Create server.js
    cat << 'EOF' > server.js
const addon = require('./build/Release/validator.node');
console.log("Server started, addon loaded.");
EOF

    # Create benchmark.js
    cat << 'EOF' > benchmark.js
const addon = require('./build/Release/validator.node');
const payload = "A".repeat(100000); // 100KB valid Base64 string

const start = process.hrtime.bigint();
for(let i=0; i<1000; i++) {
    const res = addon.validatePayload(payload);
    if (!res) throw new Error("Validation incorrectly failed");
}
const end = process.hrtime.bigint();
const elapsedSec = Number(end - start) / 1e9;
console.log(`Elapsed: ${elapsedSec}s`);
EOF

    # Install dependencies without running build scripts (since build is currently broken)
    npm install --ignore-scripts
    npm install -g node-gyp

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
