FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:66a5a6f8b135
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
