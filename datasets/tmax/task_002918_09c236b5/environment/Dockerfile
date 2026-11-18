FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:5c686a0d2b7d
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
