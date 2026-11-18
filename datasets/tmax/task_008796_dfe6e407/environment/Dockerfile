FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:b52e2c2e0e64
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
