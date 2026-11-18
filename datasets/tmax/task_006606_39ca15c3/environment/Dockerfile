FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:178b092d8b9b
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
