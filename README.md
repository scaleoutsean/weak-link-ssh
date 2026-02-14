# Weak Link SSH

A small Docker image based on **Ubuntu 16.04** that provides an older OpenSSH client and a convenience wrapper (`ssh-legacy`) pre-configured to allow legacy key-exchange, ciphers and MACs used by old network appliances.

Feature highlights:

- Security as weak as required to connect
- Very convenient
- SSH to servers on your own terms

Why: modern OS have removed or disabled weak SSH algorithms. This image lets you safely run a legacy client in an isolated container for maintenance of end-of-life devices.

## What this image provides

- Ubuntu 16.04 base with `openssh-client` installed
- `/usr/local/bin/ssh-legacy` - CLI wrapper that enables legacy algorithms
- Optional system-wide legacy config at `/etc/ssh/ssh_config.d/legacy.conf` (kept separate; wrapper is opt-in)

Enabled (example) algorithms in the wrapper:
- KexAlgorithms: diffie-hellman-group1-sha1, diffie-hellman-group14-sha1
- HostKeyAlgorithms: ssh-rsa, ssh-dss
- Ciphers: aes128-cbc, 3des-cbc
- MACs: hmac-md5, hmac-sha1

## Quick start - build or pull

```sh
# pull container image
docker pull docker.io/scaleoutsean/weak-link-ssh:latest
# or build locally
docker build -t weak-link-ssh:latest .
```

## Run examples

These assume self-built container image. If you've downloaded from registry, tag the container or modify image name when using these examples.


1) Generate a legacy-compatible SSH key (inside the container):

Modern systems often cannot create keys weak enough for legacy servers (e.g., DSA or 1024-bit RSA). Use the container's legacy ssh-keygen to generate a compatible key:

```sh
docker run --rm -it -v "$PWD:/mnt" weak-link-ssh:latest bash
# Inside the container, generate a weak key (e.g., DSA or 1024-bit RSA):
ssh-keygen -t dsa -f /mnt/legacy_id_dsa
# or for weak RSA:
ssh-keygen -t rsa -b 1024 -f /mnt/legacy_id_rsa
exit
```

This will create legacy_id_dsa (or legacy_id_rsa) and its .pub file in your current directory on the host. Add the public key to your legacy server's authorized_keys as usual.

2) Use your legacy SSH key (with correct permissions):

**Note:** Mounting your $HOME/.ssh directly can cause errors like `Bad owner or permissions on /root/.ssh/config` because SSH is strict about file permissions and ownership. To avoid this, copy your SSH config and keys to a temporary directory and set the correct permissions before mounting:

```sh
mkdir -p ~/.ssh_weak_link
cp legacy_id_dsa* ~/.ssh_weak_link/   # or legacy_id_rsa*
# Optionally copy config or known_hosts if needed
chmod 700 ~/.ssh_weak_link
chmod 600 ~/.ssh_weak_link/*
docker run --rm -it \
  -v "$HOME/.ssh_weak_link:/root/.ssh:ro" \
  weak-link-ssh:latest ssh-legacy user@LEGACY_HOST
```

3) Start an interactive shell and run commands manually:

```sh
docker run --rm -it -v "$HOME/.ssh:/root/.ssh:ro" weak-link-ssh:latest
# then inside container: ssh-legacy user@legacy-host
```

4) Use plain `ssh` with ad-hoc options (if you prefer):

```sh
docker run --rm -it -v "$HOME/.ssh:/root/.ssh:ro" \
  weak-link-ssh:latest \
  ssh -oKexAlgorithms=+diffie-hellman-group1-sha1 user@legacy-host
```

## Inspect legacy SSH server (report)

The `ssh-report` command queries a server's SSH KEX/host-key/cipher/MAC capabilities without authenticating. Use it to create minimally-weak profiles that are just sufficient to connect.

```sh
# run a quick capability report
docker run --rm -it weak-link-ssh:latest ssh-report legacy-host.example.com:22
```

Sample output lists server KEX algorithms, host-key types, ciphers and MACs so you can pick only the required weak items.

## Connection profiles (mount from host)

Create per-device profiles on the Docker host and mount them into `/profiles` inside the container. With a profile you can drop the `user@` destination — the profile contains host, username and algorithm overrides.

Profile format (simple key=value):

```raw
Host=192.168.1.34
User=admin
Port=22
KexAlgorithms=diffie-hellman-group14-sha1
HostKeyAlgorithms=ssh-rsa
Ciphers=aes128-ctr,aes128-cbc
MACs=hmac-sha1
# optional: expected host key fingerprint to avoid naive MITM
# HostFingerprint=SHA256:...
```

Save as `mydevice` in a directory and mount that directory when running the container:

```sh
# mount a local 'profiles' directory and your SSH keys
docker run --rm -it \
  -v "$PWD/profiles:/profiles:ro" \
  -v "$HOME/.ssh:/root/.ssh:ro" \
  weak-link-ssh:latest \
  ssh-profile mydevice
```

If `HostFingerprint` is set in the profile (or passed to `ssh-legacy` via `--host-fp`), the client will verify the fingerprint using `ssh-keyscan` before connecting — this prevents naive MITM when you already trust the server's key.

## Troubleshooting

- **SSH config permissions error:**
  - If you see `Bad owner or permissions on /root/.ssh/config`, it means the SSH config or key files are not owned by root or have overly permissive permissions. This often happens when mounting your $HOME/.ssh directly. Use the workaround above to copy files to a temp directory and set permissions.
- If the modern client shows "no matching key exchange method" or "no matching cipher" — try `ssh-legacy` from this container.
- Mount your SSH keys with the correct permissions as shown above so the container can reuse them.

## Shell completion

The repository contains `completions/ssh-profile.bash`. The image installs a completion file at `/etc/bash_completion.d/ssh-profile` so interactive shells inside the container will offer completions for `ssh-profile` and `ssh-legacy`.

To enable completion on your host:

```sh
sudo cp completions/ssh-profile.bash /etc/bash_completion.d/ssh-profile
# restart your shell or `source /etc/bash_completion` to load it
```

## Example debug

If you see debug lines mentioning `diffie-hellman-group1-sha1`, `hmac-md5`, or `aes128-cbc`, the legacy wrapper can help negotiate those algorithms when necessary.

## Security

This image intentionally enables insecure algorithms. Use it only for short-term maintenance in isolated/trusted networks. Do NOT use it for general-purpose SSH access. Use cases:

- You cannot upgrade or modify the legacy device
- You need a reproducible, isolated environment that still supports old SSH algorithms

If the security is not weak enough, let me know in Issues and we'll consider downgrading it further.

## License / Notes

- License: Apache 2.0 
- Copyright: github.com/scaleoutsean
