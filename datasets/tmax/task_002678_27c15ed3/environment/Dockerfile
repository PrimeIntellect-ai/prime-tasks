FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:0e2b1e4d8ef3
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
