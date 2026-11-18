FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:e2e02e0d65de
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
