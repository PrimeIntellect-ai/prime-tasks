FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:a449d9e8b64b
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
