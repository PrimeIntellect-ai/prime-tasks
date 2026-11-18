FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:8c4a3d5ed14e
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
