FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:4c594b4f90de
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
