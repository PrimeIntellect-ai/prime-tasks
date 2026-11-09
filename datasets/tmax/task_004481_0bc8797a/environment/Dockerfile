FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:e3f72fc4ebd3
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
