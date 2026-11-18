FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:36b30417ea6d
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
