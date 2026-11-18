FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:061b24e0a17f
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
