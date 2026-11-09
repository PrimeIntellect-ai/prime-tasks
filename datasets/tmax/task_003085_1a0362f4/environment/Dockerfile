FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:96a19e40a2b4
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
