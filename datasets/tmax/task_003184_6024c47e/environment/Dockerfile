FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:fde0db5aad1f
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
