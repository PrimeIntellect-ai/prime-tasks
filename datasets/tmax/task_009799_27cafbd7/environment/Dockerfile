FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:4a2450b03c98
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
