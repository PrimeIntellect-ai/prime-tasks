#!/bin/bash
while IFS= read -r line || [ -n "$line" ]; do
    num_fields=$(echo "$line" | awk -F',' '{print NF}')
    if [ "$num_fields" -ne 4 ]; then
        echo "[INVALID] $line"
        continue
    fi

    service_name=$(echo "$line" | awk -F',' '{print $1}')
    replicas=$(echo "$line" | awk -F',' '{print $2}')
    port=$(echo "$line" | awk -F',' '{print $3}')
    image=$(echo "$line" | awk -F',' '{print $4}')

    if ! [[ "$service_name" =~ ^svc-[a-z0-9]{1,10}$ ]]; then
        echo "[INVALID] $line"
        continue
    fi
    if ! [[ "$replicas" =~ ^[1-9]$ ]]; then
        echo "[INVALID] $line"
        continue
    fi
    if ! [[ "$port" =~ ^80[0-9]{2}$ ]]; then
        echo "[INVALID] $line"
        continue
    fi
    if ! [[ "$image" =~ ^registry\.local/[a-z0-9]{1,20}:v[0-9]$ ]]; then
        echo "[INVALID] $line"
        continue
    fi

    echo "[VALID] ${service_name}:${port}"
done
