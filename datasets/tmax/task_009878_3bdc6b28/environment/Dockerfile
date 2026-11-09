FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:ac0a6f4e8d3a
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
