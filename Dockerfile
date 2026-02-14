FROM docker.io/library/ubuntu@sha256:1f1a2d56de1d604801a9671f301190704c25d604a416f59e03c04f5c6ffee0d6
# Ubuntu 16.04 (docker pull ubuntu:16.04)

LABEL org.opencontainers.image.source="https://github.com/scaleoutsean/weak-link-ssh"

ENV DEBIAN_FRONTEND=noninteractive

# small image with OpenSSH client (legacy-friendly) and common utilities
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       openssh-client \
       ca-certificates \
       netcat-openbsd \
       curl \
       bash-completion \
    && rm -rf /var/lib/apt/lists/*

# ssh-legacy: wrapper that enables legacy KEX / ciphers / MACs when needed
RUN cat > /usr/local/bin/ssh-legacy <<'EOF'
#!/bin/bash
set -euo pipefail

# ssh-legacy: adds legacy algorithms and optionally verifies a provided host-fingerprint
# Usage:
#   ssh-legacy [--host-fp FINGERPRINT] [ssh-options...] user@host [command]

KEX_ADD="+diffie-hellman-group1-sha1,diffie-hellman-group14-sha1"
HOSTKEY_ADD="+ssh-rsa,ssh-dss"
CIPHERS_ADD="+aes128-cbc,3des-cbc"
MACS_ADD="+hmac-md5,hmac-sha1"

HOST_FP=""
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --host-fp)
      shift
      HOST_FP="$1"
      shift
      ;;
    --host-fp=*)
      HOST_FP="${1#--host-fp=}"
      shift
      ;;
    *)
      ARGS+=("$1")
      shift
      ;;
  esac
done

SSH_BASE=(/usr/bin/ssh -oKexAlgorithms=${KEX_ADD} -oHostKeyAlgorithms=${HOSTKEY_ADD} -oCiphers=${CIPHERS_ADD} -oMACs=${MACS_ADD})

# If no host-fingerprint verification requested, exec immediately
if [ -z "${HOST_FP}" ]; then
  exec "${SSH_BASE[@]}" "${ARGS[@]}"
fi

# Find destination (first non-option argument)
DEST=""
for a in "${ARGS[@]}"; do
  case "$a" in
    -*) continue ;;
    *) DEST="$a"; break ;;
  esac
done

if [ -z "$DEST" ]; then
  echo "ssh-legacy: missing destination (required when using --host-fp)" >&2
  exit 2
fi

HOSTPART="${DEST##*@}"
HOSTNAME="${HOSTPART%%:*}"
TMPPORT="${HOSTPART#*:}"
if [ "$TMPPORT" = "$HOSTPART" ]; then
  PORT=22
else
  PORT=$TMPPORT
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
KEYS_FILE="$TMPDIR/keys.pub"
KNOWN_HOSTS_FILE="$TMPDIR/known_hosts"

# gather server host keys
ssh-keyscan -p ${PORT} "${HOSTNAME}" > "$KEYS_FILE" 2>/dev/null || true

matched=0
while IFS= read -r keyline; do
  printf "%s\n" "$keyline" > "$TMPDIR/key.pub"
  fp_sha256=$(ssh-keygen -lf "$TMPDIR/key.pub" -E sha256 2>/dev/null | awk '{print $2}') || fp_sha256=""
  fp_md5=$(ssh-keygen -lf "$TMPDIR/key.pub" 2>/dev/null | awk '{print $2}') || fp_md5=""
  if [ "$fp_sha256" = "$HOST_FP" ] || [ "$fp_md5" = "$HOST_FP" ] || [ "SHA256:$fp_sha256" = "$HOST_FP" ] || [ "MD5:$fp_md5" = "$HOST_FP" ]; then
    printf "%s\n" "$keyline" > "$KNOWN_HOSTS_FILE"
    matched=1
    break
  fi
done < "$KEYS_FILE"

if [ "$matched" -eq 1 ]; then
  exec /usr/bin/ssh -oUserKnownHostsFile="$KNOWN_HOSTS_FILE" -oStrictHostKeyChecking=yes -oKexAlgorithms=${KEX_ADD} -oHostKeyAlgorithms=${HOSTKEY_ADD} -oCiphers=${CIPHERS_ADD} -oMACs=${MACS_ADD} "${ARGS[@]}"
else
  echo "ssh-legacy: host fingerprint did not match any key gathered from server" >&2
  exit 3
fi
EOF
RUN chmod +x /usr/local/bin/ssh-legacy

# ssh-profile: use per-device profile files mounted at /profiles (or ~/.ssh/profiles)
RUN mkdir -p /usr/local/bin /profiles /root/.ssh/profiles \
  && cat > /usr/local/bin/ssh-profile <<'EOF'
#!/bin/bash
set -euo pipefail
if [ $# -lt 1 ]; then
  echo "usage: ssh-profile <profile> [-- <ssh-cmd>...]" >&2
  exit 2
fi
PROFILE="$1"; shift
CONF=""
for d in /profiles /root/.ssh/profiles; do
  if [ -f "$d/$PROFILE" ]; then CONF="$d/$PROFILE"; break; fi
done
if [ -z "$CONF" ]; then
  echo "profile not found: $PROFILE" >&2
  exit 2
fi
# parse simple key=value profile
HOST=""; USER=""; PORT=22; KEX=""; HOSTKEYS=""; CIPHERS=""; MACS=""; HOSTFP=""; EXTRA_OPTS=""
while IFS='=' read -r k v; do
  k=$(echo "$k" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  v=$(echo "$v" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  case "$k" in
    ''|#*) continue ;;
    Host|Hostname) HOST="$v" ;;
    User) USER="$v" ;;
    Port) PORT="$v" ;;
    KexAlgorithms) KEX="$v" ;;
    HostKeyAlgorithms) HOSTKEYS="$v" ;;
    Ciphers) CIPHERS="$v" ;;
    MACs) MACS="$v" ;;
    HostFingerprint) HOSTFP="$v" ;;
    Options) EXTRA_OPTS="$v" ;;
  esac
done < "$CONF"
if [ -z "$HOST" ]; then echo "profile missing Host/Hostname" >&2; exit 2; fi
DST="$HOST"; [ -n "$USER" ] && DST="$USER@$HOST"
OPTS=()
[ -n "$KEX" ] && { [[ $KEX == +* ]] && KEX_ARG="$KEX" || KEX_ARG="+$KEX"; OPTS+=("-oKexAlgorithms=$KEX_ARG"); }
[ -n "$HOSTKEYS" ] && { [[ $HOSTKEYS == +* ]] && HK_ARG="$HOSTKEYS" || HK_ARG="+$HOSTKEYS"; OPTS+=("-oHostKeyAlgorithms=$HK_ARG"); }
[ -n "$CIPHERS" ] && { [[ $CIPHERS == +* ]] && C_ARG="$CIPHERS" || C_ARG="+$CIPHERS"; OPTS+=("-oCiphers=$C_ARG"); }
[ -n "$MACS" ] && { [[ $MACS == +* ]] && M_ARG="$MACS" || M_ARG="+$MACS"; OPTS+=("-oMACs=$M_ARG"); }
[ -n "$EXTRA_OPTS" ] && OPTS+=("$EXTRA_OPTS")

if [ -n "$HOSTFP" ]; then
  /usr/local/bin/ssh-legacy --host-fp "$HOSTFP" -p "$PORT" "${OPTS[@]}" "$DST" "$@"
else
  /usr/local/bin/ssh-legacy -p "$PORT" "${OPTS[@]}" "$DST" "$@"
fi
EOF
RUN chmod +x /usr/local/bin/ssh-profile

# ssh-report: query server algorithms without authenticating
RUN cat > /usr/local/bin/ssh-report <<'EOF'
#!/bin/bash
set -euo pipefail
if [ $# -lt 1 ]; then echo "usage: ssh-report host[:port]" >&2; exit 2; fi
HP="$1"; shift
HOST="${HP%%:*}"; PORT="${HP#*:}"; [ "$PORT" = "$HP" ] && PORT=22
OUT=$(ssh -oBatchMode=yes -oPasswordAuthentication=no -oKbdInteractiveAuthentication=no -oChallengeResponseAuthentication=no -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oConnectTimeout=5 -vvv -p "$PORT" dummy@"$HOST" exit 2>&1 || true)
BLOCK=$(printf "%s\n" "$OUT" | sed -n '/peer server KEXINIT proposal/,$p')
KEX=$(printf "%s\n" "$BLOCK" | sed -n 's/.*KEX algorithms: //p' | head -n1)
HOSTKEYS=$(printf "%s\n" "$BLOCK" | sed -n 's/.*host key algorithms: //p' | head -n1)
CIP_CTO=$(printf "%s\n" "$BLOCK" | sed -n 's/.*ciphers ctos: //p' | head -n1)
CIP_STO=$(printf "%s\n" "$BLOCK" | sed -n 's/.*ciphers stoc: //p' | head -n1)
MAC_CTO=$(printf "%s\n" "$BLOCK" | sed -n 's/.*MACs ctos: //p' | head -n1)
MAC_STO=$(printf "%s\n" "$BLOCK" | sed -n 's/.*MACs stoc: //p' | head -n1)
COMP_CTO=$(printf "%s\n" "$BLOCK" | sed -n 's/.*compression ctos: //p' | head -n1)
COMP_STO=$(printf "%s\n" "$BLOCK" | sed -n 's/.*compression stoc: //p' | head -n1)
cat <<EOH
Host: $HOST:$PORT
KEX algorithms: ${KEX:-(none found)}
Host key algorithms: ${HOSTKEYS:-(none found)}
Ciphers c->s: ${CIP_CTO:-(none found)}
Ciphers s->c: ${CIP_STO:-(none found)}
MACs c->s: ${MAC_CTO:-(none found)}
MACs s->c: ${MAC_STO:-(none found)}
Compression c->s: ${COMP_CTO:-(none found)}
Compression s->c: ${COMP_STO:-(none found)}
EOH
EOF
RUN chmod +x /usr/local/bin/ssh-report

# example profile (drop into a host-mounted /profiles directory)
RUN cat > /profiles/example.conf <<'EOF'
# Example profile: name this file 'mydevice' and mount the directory as /profiles
Host=192.168.1.34
User=admin
Port=22
KexAlgorithms=diffie-hellman-group14-sha1
HostKeyAlgorithms=ssh-rsa
Ciphers=aes128-ctr,aes128-cbc
MACs=hmac-sha1
# optional: expected host key fingerprint to prevent MITM
# HostFingerprint=SHA256:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
EOF
RUN cp /profiles/example.conf /profiles/example

# optional system-wide legacy config (kept separate so user must opt-in via wrapper)
RUN mkdir -p /etc/ssh/ssh_config.d \
  && cat > /etc/ssh/ssh_config.d/legacy.conf <<'EOF'
# System-wide legacy settings (use with care)
# Enables algorithms commonly required by old appliances
KexAlgorithms +diffie-hellman-group1-sha1,diffie-hellman-group14-sha1
HostKeyAlgorithms +ssh-rsa,ssh-dss
Ciphers +aes128-cbc,3des-cbc
MACs +hmac-md5,hmac-sha1
EOF

# install bash-completion helper script (repo contains completions/ssh-profile.bash)
COPY completions/ssh-profile.bash /etc/bash_completion.d/ssh-profile

# default to an interactive shell; image provides `ssh-legacy` helper
CMD ["bash"]
