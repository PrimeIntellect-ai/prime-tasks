FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:a42a750e48de
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
