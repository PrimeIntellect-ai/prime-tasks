FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:cb5a5b2775b2
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
