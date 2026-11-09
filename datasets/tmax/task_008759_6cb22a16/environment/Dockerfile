FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:d128aa0cd93a
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
