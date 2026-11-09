FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:7b4e7b1b9c0f
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
