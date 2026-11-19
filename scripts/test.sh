#!/usr/bin/env bash
# Converge the same desired state with Puppet and with Salt, then prove it from outside:
# idempotency, HTTP behavior, firewall, parity between the two tools, and drift repair.
set -uo pipefail
cd "$(dirname "$0")/.."

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf 'PASS  %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$*"; }
check() { local name=$1; shift; if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi; }

dc() { docker compose "$@"; }
puppet_apply() { dc exec -T node-puppet puppet apply --hiera_config /lab/puppet/hiera.yaml /lab/puppet/site.pp --detailed-exitcodes >/tmp/puppet.out 2>&1; }
salt_apply()   { dc exec -T node-salt /opt/salt/bin/salt-call -c /lab/salt-conf --local state.apply webnode --out=json 2>/dev/null | python3 scripts/salt_changes.py; }
probe() { dc exec -T probe "$@"; }
code()  { probe curl -s -m 3 -o /dev/null -w '%{http_code}' "$@"; }
body()  { probe curl -s -m 3 "$@"; }

dc down -v >/dev/null 2>&1
dc up -d --build >/dev/null 2>&1 || { echo "compose up failed"; exit 1; }
trap 'dc down -v >/dev/null 2>&1' EXIT

echo "== first converge"
puppet_apply; rc=$?;           [ "$rc" = 2 ] && ok "puppet first run made changes (exit 2)" || bad "puppet first run exit $rc"
n=$(salt_apply);               [ "${n:-0}" -gt 0 ] && ok "salt first run changed $n states" || bad "salt first run changed ${n:-?}"

echo "== second converge changes nothing"
puppet_apply; rc=$?;           [ "$rc" = 0 ] && ok "puppet second run: no changes (exit 0)" || bad "puppet second run exit $rc"
n=$(salt_apply);               [ "$n" = 0 ] && ok "salt second run: 0 changes" || bad "salt second run changed ${n:-?}"

echo "== HTTP API from the probe container"
for h in node-puppet node-salt; do
  [ "$(code http://$h:8080/healthz)" = 200 ]            && ok "$h GET /healthz 200"        || bad "$h GET /healthz"
  [ "$(body http://$h:8080/version)" = '{"version":"1.4.2"}' ] && ok "$h GET /version body"  || bad "$h GET /version body"
  [ "$(code http://$h:8080/nope)" = 404 ]               && ok "$h unknown path 404"        || bad "$h unknown path"
  [ "$(code -X POST http://$h:8080/healthz)" = 405 ]    && ok "$h POST 405"                || bad "$h POST"
done

echo "== firewall: admin port is listening on the node but unreachable from the probe"
for h in node-puppet node-salt; do
  probe curl -s -m 3 -o /dev/null http://$h:9090/; rc=$?
  [ "$rc" = 28 ] && ok "$h :9090 dropped (curl timeout)" || bad "$h :9090 reachable or wrong error (rc $rc)"
  dc exec -T $h curl -s -m 3 -o /dev/null http://127.0.0.1:9090/ && ok "$h :9090 answers on loopback" || bad "$h :9090 not listening"
done

echo "== parity between Puppet and Salt"
dc exec -T node-puppet cat /etc/nginx/conf.d/api.conf > /tmp/api.puppet
dc exec -T node-salt   cat /etc/nginx/conf.d/api.conf > /tmp/api.salt
check "rendered nginx config is byte-identical" diff /tmp/api.puppet /tmp/api.salt
dc exec -T node-puppet iptables -S INPUT > /tmp/fw.puppet
dc exec -T node-salt   iptables -S INPUT > /tmp/fw.salt
check "INPUT firewall rules are identical" diff /tmp/fw.puppet /tmp/fw.salt

echo "== drift: edit the config, delete a firewall rule, stop nginx, then converge"
for h in node-puppet node-salt; do
  dc exec -T $h sh -c 'echo "# tampered" >> /etc/nginx/conf.d/api.conf; iptables -D INPUT -s 172.28.0.0/16 -p tcp -m tcp --dport 8080 -j ACCEPT; /etc/init.d/nginx stop' >/dev/null 2>&1
done
[ "$(code http://node-puppet:8080/healthz)" != 200 ] && ok "drift is real: node-puppet no longer serves" || bad "drift did not break node-puppet"
puppet_apply; rc=$?;  [ "$rc" = 2 ] && ok "puppet repaired drift (exit 2)" || bad "puppet drift run exit $rc"
n=$(salt_apply);      [ "${n:-0}" -gt 0 ] && ok "salt repaired drift ($n states)" || bad "salt drift run changed ${n:-?}"
for h in node-puppet node-salt; do
  [ "$(code http://$h:8080/healthz)" = 200 ] && ok "$h serves again after convergence" || bad "$h still broken"
done
check "config identical again after repair" bash -c "diff <(docker compose exec -T node-puppet cat /etc/nginx/conf.d/api.conf) <(docker compose exec -T node-salt cat /etc/nginx/conf.d/api.conf)"
puppet_apply; rc=$?;  [ "$rc" = 0 ] && ok "puppet idempotent after repair" || bad "puppet after repair exit $rc"
n=$(salt_apply);      [ "$n" = 0 ] && ok "salt idempotent after repair" || bad "salt after repair changed ${n:-?}"

echo; echo "passed $PASS, failed $FAIL"
[ "$FAIL" = 0 ]
