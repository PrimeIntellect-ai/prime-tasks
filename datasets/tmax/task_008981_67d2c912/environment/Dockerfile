FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:1d19a43f0d98
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
