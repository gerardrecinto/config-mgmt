FROM debian:12-slim
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends puppet-agent iptables curl ca-certificates python3-venv python3-pip procps iproute2 \
 && apt-get install -y -qq --no-install-recommends gcc python3-dev \
 && python3 -m venv /opt/salt \
 && /opt/salt/bin/pip install -q salt==3008.5 \
 && apt-get purge -y -qq gcc python3-dev && apt-get autoremove -y -qq \
 && rm -rf /root/.cache
# Containers have no init system. Salt's sysvinit service module calls runlevel, so supply a stub.
RUN printf '#!/bin/sh\necho "N 5"\n' > /sbin/runlevel && chmod +x /sbin/runlevel
# nginx-light is deliberately not installed here: the tools must install it.
CMD ["sleep", "infinity"]
