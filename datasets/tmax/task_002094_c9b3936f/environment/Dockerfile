FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:6b9a355d3e0d
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
