FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:565aa8961f47
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
