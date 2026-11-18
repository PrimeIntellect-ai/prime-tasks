FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:b076f0db0a0c
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
