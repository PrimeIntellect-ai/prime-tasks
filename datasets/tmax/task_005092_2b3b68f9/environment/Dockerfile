FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:3a24d7968d9a
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
