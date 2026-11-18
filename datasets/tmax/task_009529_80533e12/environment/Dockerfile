FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:5052f3a8f32b
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
