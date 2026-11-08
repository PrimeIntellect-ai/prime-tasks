FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:e84a4a2c6d04
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
