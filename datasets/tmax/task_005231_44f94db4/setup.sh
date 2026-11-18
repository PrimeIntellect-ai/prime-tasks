#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 python3-pip \
        ffmpeg tesseract-ocr jq gawk fonts-liberation

    pip3 install pytest

    mkdir -p /app /opt/oracle

    # Create the oracle script
    cat << 'EOF' > /opt/oracle/graph_builder_oracle.sh
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
EOF
    chmod +x /opt/oracle/graph_builder_oracle.sh

    # Generate the dataset video
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=5 \
        -vf "drawtext=fontfile=/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf:text='Alpha\,Beta':fontcolor=white:fontsize=36:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,0.5,1.0)',\
             drawtext=fontfile=/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf:text='Alpha\,Gamma':fontcolor=white:fontsize=36:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,1.5,2.0)',\
             drawtext=fontfile=/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf:text='Beta\,Delta':fontcolor=white:fontsize=36:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,2.5,3.0)',\
             drawtext=fontfile=/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf:text='Gamma\,Delta':fontcolor=white:fontsize=36:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,3.5,4.0)',\
             drawtext=fontfile=/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf:text='Delta\,Alpha':fontcolor=white:fontsize=36:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,4.5,5.0)'" \
        -c:v libx264 -pix_fmt yuv420p /app/dataset.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
