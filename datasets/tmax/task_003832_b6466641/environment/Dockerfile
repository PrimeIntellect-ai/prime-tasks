FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:30b3b7afc7e4
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
