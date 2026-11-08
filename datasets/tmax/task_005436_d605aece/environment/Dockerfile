FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:c2c85b97d45e
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
