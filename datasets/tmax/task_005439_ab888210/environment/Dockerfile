FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:b9c6a70bf6ec
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
