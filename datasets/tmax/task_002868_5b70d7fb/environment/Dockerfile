FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:b9a49f75a23e
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
