FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:936c1b2a37d8
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
