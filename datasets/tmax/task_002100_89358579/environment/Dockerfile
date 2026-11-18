FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:ddf2e4d774fe
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
