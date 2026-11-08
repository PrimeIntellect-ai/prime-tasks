FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:7c3b4c540e7c
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
