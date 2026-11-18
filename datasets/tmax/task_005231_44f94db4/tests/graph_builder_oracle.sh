#!/bin/bash
FILE=$1
if [ ! -f "$FILE" ] || [ ! -s "$FILE" ]; then
  echo '{"nodes":[]}' | jq .
  exit 0
fi

cat "$FILE" | tr -d '\r' | awk -F',' 'NF==2 {print $1, $2}' | sort | uniq | \
awk '
{
    targets[$1] = targets[$1] ? targets[$1] "\n" $2 : $2
}
END {
    print "{\"nodes\": ["
    n = asorti(targets, sorted_nodes)
    for (i=1; i<=n; i++) {
        node = sorted_nodes[i]
        split(targets[node], t, "\n")
        m = asort(t, sorted_t)

        printf "  {\"id\": \"%s\", \"out_degree\": %d, \"targets\": [", node, m
        for (j=1; j<=m; j++) {
            printf "\"%s\"%s", sorted_t[j], (j==m ? "" : ", ")
        }
        printf "]}%s\n", (i==n ? "" : ",")
    }
    print "]}"
}' | jq .
