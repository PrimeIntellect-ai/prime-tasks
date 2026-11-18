FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:ce7087a7c2ec
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
