FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:3dc1cc6c7f3a
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
