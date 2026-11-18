FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:1ec6c32d7c2d
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
