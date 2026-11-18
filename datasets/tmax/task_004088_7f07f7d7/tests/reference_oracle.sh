#!/bin/bash
input="$1"
declare -A vars
IFS='|' read -ra cmds <<< "$input"
for cmd_raw in "${cmds[@]}"; do
    cmd=$(echo "$cmd_raw" | sed 's/^[ \t]*//;s/[ \t]*$//')
    if [[ -z "$cmd" ]]; then continue; fi
    read -r op args <<< "$cmd"
    if [[ "$op" == "SET" ]]; then
        read -r var val <<< "$args"
        vars["$var"]="$val"
    elif [[ "$op" == "APPEND" ]]; then
        read -r var val <<< "$args"
        if [[ -z "${vars[$var]+x}" ]]; then
            vars["$var"]="$val"
        else
            vars["$var"]="${vars[$var]},$val"
        fi
    elif [[ "$op" == "SORT" ]]; then
        read -r var <<< "$args"
        if [[ -n "${vars[$var]+x}" ]]; then
            sorted=$(echo "${vars[$var]}" | tr ',' '\n' | sort | paste -sd, -)
            vars["$var"]="$sorted"
        fi
    elif [[ "$op" == "MERGE" ]]; then
        read -r var1 var2 <<< "$args"
        combined="${vars[$var1]},${vars[$var2]}"
        merged=$(echo "$combined" | tr ',' '\n' | sed '/^$/d' | sort -u | paste -sd, -)
        vars["$var1"]="$merged"
    elif [[ "$op" == "URLENCODE" ]]; then
        read -r var <<< "$args"
        if [[ -n "${vars[$var]+x}" ]]; then
            encoded=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe='~.-_'))" "${vars[$var]}")
            vars["$var"]="$encoded"
        fi
    elif [[ "$op" == "JSON" ]]; then
        json="{}"
        for k in $(printf '%s\n' "${!vars[@]}" | sort); do
            if [[ -n "$k" ]]; then
                json=$(echo "$json" | jq -c --arg k "$k" --arg v "${vars[$k]}" '.[$k] = $v')
            fi
        done
        # Pretty print at the end
        echo "$json" | jq .
        exit 0
    fi
done
