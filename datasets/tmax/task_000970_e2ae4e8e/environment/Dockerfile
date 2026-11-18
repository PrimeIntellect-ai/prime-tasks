FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:2d7e925c8d5f
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
