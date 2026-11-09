FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:f658db3b0f9f
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
