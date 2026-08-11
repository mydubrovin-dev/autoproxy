# autoproxy

One-shot bootstrap for a fresh CentOS/Rocky/RHEL VPS that turns it into a
proxy box. Download and run a single script — everything else is handled
for you, except one interactive step for the MTProto/SNI setup (see below).

## What it sets up

1. **Squid** forward proxy with login/password authentication. Only
   authenticated clients are allowed through to the internet.
2. **[MTProto FIX by MEKO](https://github.com/Mekotofeuka/MTPROTO_FIX_By_MEKO)**,
   running in a Docker container (`--network host --cap-add NET_ADMIN`,
   required because the fix manipulates the host's iptables rules).
3. **fail2ban**, watching sshd and banning brute-force offenders.

## Usage

On a fresh CentOS/Rocky/RHEL machine, as root:

```bash
curl -fsSL https://raw.githubusercontent.com/mydubrovin-dev/autoproxy/main/install.sh | sudo bash
```

Optional overrides (env vars, set before the pipe):

| Variable                 | Default      | Description                     |
|---------------------------|--------------|----------------------------------|
| `AUTOPROXY_SQUID_USER`     | `proxyuser`  | Squid login username            |
| `AUTOPROXY_SQUID_PASS`     | random       | Squid login password            |
| `AUTOPROXY_SQUID_PORT`     | `3128`       | Squid listen port               |

Squid credentials are always written to `/root/autoproxy/squid-credentials.txt`
(root-only, mode 600) regardless of whether they were auto-generated or supplied.

## MTProto / SNI setup (one manual step)

The upstream MEKO installer is an interactive menu with no flags for
unattended use, so `install.sh` only prepares the container — you finish
the proxy setup yourself, once:

```bash
docker exec -it autoproxy-mtproto bash /tmp/meko-install.sh
```

In the menu: install a proxy (Telemt / MTG / MTProto.zig) → apply
**MTProto FIX** ([1]) → check SNI ([7]) and use this domain:

```
www.ite-ng.ru
```

Re-open the menu any time with:

```bash
docker exec -it autoproxy-mtproto mekopr
```

## Project layout

```
install.sh              bootstrap entrypoint (what you curl)
lib/
  common.sh              logging, root/OS checks, shared helpers
  squid.sh                Squid install + auth config
  fail2ban.sh              fail2ban install + sshd jail
  docker.sh                 Docker Engine install
  mtproto.sh                 builds/runs the MTProto-fix container
docker/mtproto/
  Dockerfile                 image for the MTProto-fix container
  entrypoint.sh                fetches the MEKO installer, prints instructions
```

## Notes

- Targets CentOS/Rocky/RHEL (`dnf`/`yum`). Not tested on Debian/Ubuntu hosts.
- Review `install.sh` before piping it into `bash` on a box you care about —
  standard advice for any `curl | bash` installer, including this one.
- Re-running `install.sh` is safe for Squid/fail2ban/Docker; the MTProto
  container is recreated from scratch each time (any in-container MEKO
  config is lost — reconfigure via `mekopr` afterwards).
