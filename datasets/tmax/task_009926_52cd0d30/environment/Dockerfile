FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:0f32e2e12a1f
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
