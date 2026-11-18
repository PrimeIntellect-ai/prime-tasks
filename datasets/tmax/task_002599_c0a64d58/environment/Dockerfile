FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:5acab9a46a9e
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
