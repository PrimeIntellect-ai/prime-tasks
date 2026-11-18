FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:5a6e3dd39ab8
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
