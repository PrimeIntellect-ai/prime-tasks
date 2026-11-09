#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/extractor.c
#include <stdio.h>
int main() {
    // Base64 for: {"timestamp": "2024-01-01T10:00:00Z", "user": "admin", "event_data": "User viewed <script>alert('XSS')</script>"}
    printf("eyJ0aW1lc3RhbXAiOiAiMjAyNC0wMS0wMVQxMDowMDowMFoiLCAidXNlciI6ICJhZG1pbiIsICJldmVudF9kYXRhIjogIlVzZXIgdmlld2VkIDxzY3JpcHQ+YWxlcnQoJ1hTUycpPC9zY3JpcHQ+In0=\n");
    // Base64 for: {"timestamp": "2024-01-01T10:05:00Z", "user": "hr_manager", "event_data": "Updated record for SSN 123-45-6789 and 987-65-4321."}
    printf("eyJ0aW1lc3RhbXAiOiAiMjAyNC0wMS0wMVQxMDowNTowMFoiLCAidXNlciI6ICJocl9tYW5hZ2VyIiwgImV2ZW50X2RhdGEiOiAiVXBkYXRlZCByZWNvcmQgZm9yIFNTTiAxMjMtNDUtNjc4OSBhbmQgOTg3LTY1LTQzMjEuIn0=\n");
    return 0;
}
EOF
    gcc -O2 /tmp/extractor.c -o /app/log_extractor
    strip /app/log_extractor
    rm /tmp/extractor.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
