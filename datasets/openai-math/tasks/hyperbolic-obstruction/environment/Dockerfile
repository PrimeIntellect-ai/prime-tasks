# Shared by every openai/math task (agent and separate verifier). See lean_setup.sh.
FROM ubuntu:24.04
ENV ELAN_HOME=/opt/elan \
    PATH=/opt/elan/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    LANG=C.UTF-8
COPY lean_setup.sh fetch_mathlib.sh lakefile.lean lake-manifest.json pack_submission.py /opt/build/
RUN bash /opt/build/lean_setup.sh
# Prime Intellect: Prime VM guests have no Landlock and no iptables `owner` match, so grade.py runs
# Comparator's builds through bubblewrap (landrun_bwrap.py) and blocks the grader with nftables.
COPY landrun_bwrap.py /usr/local/bin/landrun-bwrap
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends bubblewrap nftables >/dev/null \
 && rm -rf /var/lib/apt/lists/* \
 && chmod 0755 /usr/local/bin/landrun-bwrap
WORKDIR /workspace
