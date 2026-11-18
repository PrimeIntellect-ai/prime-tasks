FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:8d08e2439a0c
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
