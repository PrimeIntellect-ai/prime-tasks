#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /app/vendored/jsonparse-1.2/include
    mkdir -p /app/vendored/jsonparse-1.2/src

    cat << 'EOF' > /app/vendored/jsonparse-1.2/include/jsonparse.h
#ifndef JSONPARSE_H
#define JSONPARSE_H

#include <string>
#include <map>

namespace jsonparse {
    class JsonValue {
    public:
        std::string string_val;
        JsonValue() {}
        JsonValue(std::string s) : string_val(s) {}
    };

    class JsonObject {
    public:
        std::map<std::string, JsonValue> fields;
        bool valid;
        JsonObject() : valid(false) {}
    };

    JsonObject parse(const std::string& json);
}

#endif
EOF

    cat << 'EOF' > /app/vendored/jsonparse-1.2/src/parser.cpp
#include "jsonparse.h"
#include <iostream>

namespace jsonparse {
    JsonObject parse(const std::string& json) {
        JsonObject obj;
        obj.valid = true;

        // Simulate Unicode escape parsing bug
        for(size_t i = 0; i < json.size(); ++i) {
            if(json[i] == '\\' && i + 1 < json.size() && json[i+1] == 'u') {
                // BUG: should be j < 4
                for(int j = 0; j < 3; ++j) {
                    if (i + 2 + j >= json.size()) { 
                        obj.valid = false; 
                        break; 
                    }
                }
            }
        }

        auto extract_val = [&](const std::string& key) {
            size_t pos = json.find("\"" + key + "\"");
            if(pos == std::string::npos) return std::string("");
            pos = json.find(":", pos);
            if(pos == std::string::npos) return std::string("");

            size_t start_quote = json.find("\"", pos);
            size_t start_num = json.find_first_of("-0123456789", pos);

            if(start_quote != std::string::npos && (start_num == std::string::npos || start_quote < start_num)) {
                size_t end_quote = json.find("\"", start_quote + 1);
                if(end_quote != std::string::npos) {
                    return json.substr(start_quote + 1, end_quote - start_quote - 1);
                }
            } else if (start_num != std::string::npos) {
                size_t end_num = json.find_first_not_of("-0123456789", start_num);
                if(end_num != std::string::npos) {
                    return json.substr(start_num, end_num - start_num);
                } else {
                    return json.substr(start_num);
                }
            }
            return std::string("");
        };

        std::string ts = extract_val("timestamp");
        std::string sip = extract_val("source_ip");
        std::string et = extract_val("event_type");
        std::string bt = extract_val("bytes_transferred");

        if(ts != "") obj.fields["timestamp"] = JsonValue(ts);
        if(sip != "") obj.fields["source_ip"] = JsonValue(sip);
        if(et != "") obj.fields["event_type"] = JsonValue(et);
        if(bt != "") obj.fields["bytes_transferred"] = JsonValue(bt);

        if(ts == "" || sip == "" || et == "" || bt == "") {
            obj.valid = false;
        }

        return obj;
    }
}
EOF

    mkdir -p /home/user/logs/clean
    mkdir -p /home/user/logs/evil

    cat << 'EOF' > /home/user/logs/clean/clean_logs.jsonl
{"timestamp": "2023-10-01T10:00:00Z", "source_ip": "192.168.1.10", "event_type": "login\\u2028", "bytes_transferred": 1042}
{"timestamp": "2023-10-01T10:01:00Z", "source_ip": "10.0.0.5", "event_type": "upload", "bytes_transferred": "2048"}
{"timestamp": "2023-10-01T10:02:00Z", "source_ip": "172.16.0.2", "event_type": "download\\u00A9", "bytes_transferred": 500}
{"timestamp": "2023-10-01T10:03:00Z", "source_ip": "8.8.8.8", "event_type": "ping", "bytes_transferred": 64}
{"timestamp": "2023-10-01T10:04:00Z", "source_ip": "127.0.0.1", "event_type": "healthcheck", "bytes_transferred": "0"}
EOF

    cat << 'EOF' > /home/user/logs/evil/evil_logs.jsonl
{"timestamp": "2023-10-01T10:00:00Z", "source_ip": "256.168.1.10", "event_type": "login", "bytes_transferred": 1042}
{"timestamp": "2023-10-01T10:01:00Z", "source_ip": "10.0.0.5", "event_type": "upload", "bytes_transferred": -50}
{"timestamp": "2023-10-01T10:02:00Z", "source_ip": "172.16.0.2", "event_type": "download"}
{"timestamp": "2023-10-01T10:03:00Z", "source_ip": "8.8.8.256", "event_type": "ping", "bytes_transferred": 64}
{"timestamp": "2023-10-01T10:04:00Z", "source_ip": "127.0.0.1", "event_type": "healthcheck", "bytes_transferred": "-10"}
{"source_ip": "192.168.1.10", "event_type": "login", "bytes_transferred": 1042}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
