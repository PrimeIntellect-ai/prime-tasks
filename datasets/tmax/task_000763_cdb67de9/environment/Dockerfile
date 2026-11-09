FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:5d26b1c0e90b
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
