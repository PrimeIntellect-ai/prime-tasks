FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:92a54af6a7b6
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
