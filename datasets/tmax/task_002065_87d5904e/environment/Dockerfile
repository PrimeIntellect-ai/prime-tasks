FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:f74f6afc8d4d
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
