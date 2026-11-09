FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:16acc9a5f1e6
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
