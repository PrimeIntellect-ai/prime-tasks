FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:c99d3a17814f
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
