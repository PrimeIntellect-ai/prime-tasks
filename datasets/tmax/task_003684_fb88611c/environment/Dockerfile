FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:df02a9474f2c
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
