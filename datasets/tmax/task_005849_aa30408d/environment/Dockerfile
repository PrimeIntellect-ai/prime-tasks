FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:70d6ff2db7a4
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
