FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:2848b34c4fce
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
