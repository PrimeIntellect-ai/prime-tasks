FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:fe1746f46c9d
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
