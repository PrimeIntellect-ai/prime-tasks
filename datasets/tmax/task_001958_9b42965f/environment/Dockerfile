FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:c6288f5e0ffc
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
