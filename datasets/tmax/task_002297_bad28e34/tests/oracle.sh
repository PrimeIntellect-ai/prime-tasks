#!/bin/bash
video="$1"
ffmpeg -i "$video" -vf "fps=1,scale=1:1,format=gray" -f image2pipe -vcodec rawvideo - 2>/dev/null | od -An -v -tu1 | tr -s ' ' '\n' | awk 'NF {val[++n] = $1}
END {
  for(i=1; i<=n; i++) {
    prev = (i==1) ? 0 : val[i-1]
    next_val = (i==n) ? 0 : val[i+1]
    curr = val[i]
    avg = (prev + curr + next_val) / 3.0
    if (avg < 85.0) print "LOW"
    else if (avg <= 170.0) print "MID"
    else print "HIGH"
  }
}'
