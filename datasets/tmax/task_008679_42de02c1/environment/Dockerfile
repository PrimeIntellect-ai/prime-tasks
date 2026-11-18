FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:8b58fbe1e6ca
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
