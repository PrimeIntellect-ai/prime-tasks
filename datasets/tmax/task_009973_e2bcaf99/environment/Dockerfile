FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:b3afe7fbf26f
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
