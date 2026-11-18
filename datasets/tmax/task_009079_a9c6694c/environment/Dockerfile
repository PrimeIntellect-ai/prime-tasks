FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:33ed0e9649c7
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
