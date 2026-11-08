FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:af4c1c6e6145
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
