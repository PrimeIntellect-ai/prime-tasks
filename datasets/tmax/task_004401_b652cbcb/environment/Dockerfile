FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:6f2c9e78dbdf
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
