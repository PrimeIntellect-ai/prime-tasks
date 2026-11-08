FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:0b6d84f1b2db
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
