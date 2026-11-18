FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:7b9e223e79ed
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
