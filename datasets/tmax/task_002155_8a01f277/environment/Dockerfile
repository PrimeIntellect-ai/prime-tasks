FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:8f87d946a28a
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
