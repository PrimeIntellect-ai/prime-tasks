FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:1a9a43e9c9d9
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
