FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:75a2a57a4794
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
