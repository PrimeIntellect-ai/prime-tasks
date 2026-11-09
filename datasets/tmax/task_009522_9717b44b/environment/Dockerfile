FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:8b7b8e79d74f
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
