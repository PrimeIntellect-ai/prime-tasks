FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:3f6c53e7e97b
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
