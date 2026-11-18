FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:18b9a7584243
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
