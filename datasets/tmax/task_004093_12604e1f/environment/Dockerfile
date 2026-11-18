FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:9b9e74e69c2e
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
