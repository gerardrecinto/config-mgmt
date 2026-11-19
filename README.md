# config-mgmt-lab

The same Linux web node built twice, once with Puppet and once with Salt, from one desired-state file. A third container checks both from the outside: idempotency, HTTP API behavior, a default-deny firewall, parity between the tools, and drift repair. 26 checks, all run in Docker.

[Pages](https://gerardrecinto.github.io/config-mgmt-lab/) | [Recorded test output](docs/TEST_OUTPUT.txt)

## Run it

```bash
./scripts/test.sh
```

Needs Docker with Compose. The first run builds one image (about a minute, mostly Salt), converges both nodes, runs the checks, and removes the containers. It exits non-zero if any check fails.

## What gets configured

Both tools read `desired-state.yaml` (API port, admin port, version string, allowed source range and ports) and produce:

- `nginx-light` and `iptables` installed by the tool (the image does not include nginx).
- `/etc/nginx/conf.d/api.conf` rendered from a template: `GET /healthz` and `GET /version` return JSON, unknown paths 404, non-GET methods 405. A second listener on the admin port.
- nginx running, reloaded when the config changes.
- Firewall: accept established and loopback, accept the lab subnet to the API port, then default DROP on INPUT.

Puppet lives in `puppet/` (manifest, EPP template, Hiera data lookup). Salt lives in `salt/` and `salt-conf/` (one state file, Jinja template). Both run masterless inside the node container.

## Checks

| Group | What is proven |
|---|---|
| Idempotency | First run changes things. Second run changes nothing (Puppet exit 0, Salt 0 changed states). |
| HTTP API | From the probe container: 200 on `/healthz`, exact `/version` body, 404 on unknown path, 405 on POST, on both nodes. |
| Linux networking | The admin port answers on loopback but the probe times out (curl exit 28) because the INPUT policy is DROP and only the API port is allowed. |
| Parity | The rendered nginx config is byte-identical across the two tools. `iptables -S INPUT` is identical. |
| Drift | Append to the config, delete the firewall allow rule, stop nginx. The node stops serving. One converge repairs all three and a second converge changes nothing. |

## Puppet or Salt

| | Puppet | Salt |
|---|---|---|
| Model in this lab | Compiled catalog with a dependency graph. Order comes from `require` and `before`. | Ordered states with `require` and `watch`. |
| Firewall | No built-in rule resource used here. I wrote idempotent `exec` resources guarded by `iptables -C`. | `iptables.append` and `iptables.set_policy` are built in and idempotent. |
| Service in a container | The default provider refuses without an init system. I used the `base` provider with explicit commands. | Needs a `runlevel` binary. The Dockerfile supplies a stub. |
| Reads shared data | Hiera (`lookup`). | `import_yaml`. |
| Change report | Exit code 2 when something changed. | JSON result per state, counted by `scripts/salt_changes.py`. |

What I would choose: for a fleet that must prove state continuously and reject a bad catalog before it applies, Puppet's compile step and `--noop` earn their cost. For fast ad hoc commands across many hosts and event-driven reactions, Salt's remote execution is the draw. The lab runs both masterless, so it does not exercise the part where they differ most (Puppet Server and PuppetDB, Salt master and minions). Flip the choice by whichever of those two things the team actually needs.

## Limits

- Containers, not VMs. No systemd, no kernel settings (`sysctl` is read-only here), no reboot behavior.
- Masterless only. No Puppet Server, PuppetDB, Salt master, minion keys or reactor.
- One package, one service, one firewall chain. This shows convergence and verification, not a module library.
- Run on Docker Desktop (arm64) and in CI (amd64). Package versions come from Debian 12 and Salt 3008.5.

MIT license.
