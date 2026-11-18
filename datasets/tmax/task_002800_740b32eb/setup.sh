#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gawk coreutils binutils g++
pip3 install pytest

mkdir -p /home/user/

# 1. Create the buggy C++ source code
cat << 'EOF' > /home/user/session_manager.cpp
#include <iostream>
#include <string>
#include <map>

struct Session {
    std::string id;
    std::string payload;
    Session(std::string i) : id(i), payload("SESSION_PAYLOAD_" + i) {}
};

std::map<std::string, Session*> active_sessions;

void create_session(std::string session_id) {
    active_sessions[session_id] = new Session(session_id);
}

void handle_disconnect(std::string session_id, bool graceful) {
    if (active_sessions.find(session_id) != active_sessions.end()) {
        Session* s = active_sessions[session_id];
        active_sessions.erase(session_id);

        if (graceful) {
            delete s; // properly cleaned up
        } else {
            // BUG: Memory leak on forceful disconnect
            // delete s; is missing here
        }
    }
}
EOF

# 2. Create the simulated memory dump
dd if=/dev/urandom of=/home/user/memory.dump bs=1M count=1 2>/dev/null
for i in {1000..1050}; do
    echo -n "SESSION_PAYLOAD_$i" >> /home/user/memory.dump
    echo -ne '\0' >> /home/user/memory.dump
done

# Inject the leaked session multiple times
for i in {1..300}; do
    echo -n "SESSION_PAYLOAD_83920" >> /home/user/memory.dump
    echo -ne '\0' >> /home/user/memory.dump
done

# 3. Create the log file
cat << 'EOF' > /home/user/service.log
[INFO] Service started.
[TRACE] Allocation for Session 1001
[TRACE] Disconnect Session 1001 (Graceful)
[TRACE] Allocation for Session 1002
[TRACE] Disconnect Session 1002 (Graceful)
[TRACE] Allocation for Session 83920
[WARN] Network timeout detected on socket 44.
[ERROR] Traceback: Connection dropped abruptly.
[TRACE] Disconnect Session 83920 (Forceful)
[TRACE] Allocation for Session 1003
[TRACE] Disconnect Session 1003 (Graceful)
[FATAL] Out of Memory.
EOF

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/
chmod -R 777 /home/user
