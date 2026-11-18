FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:c7ee7e11b074
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
