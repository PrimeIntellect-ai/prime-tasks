FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:7d11bf1d7c5d
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
