FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:4e01fe4f31a0
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
