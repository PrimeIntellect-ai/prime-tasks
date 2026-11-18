FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:4f4651638ce6
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
