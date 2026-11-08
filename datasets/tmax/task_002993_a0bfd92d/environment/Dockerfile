FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:e03973d1f30a
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
