FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:f75b06ce3eba
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
