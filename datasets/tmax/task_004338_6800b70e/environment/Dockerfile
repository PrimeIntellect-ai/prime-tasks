FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:11aa4c1c75aa
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
