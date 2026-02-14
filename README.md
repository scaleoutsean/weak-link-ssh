# Weak Link SSH (Ubuntu 16.04)

A small Docker image based on **Ubuntu 16.04** that provides an older OpenSSH client and a convenience wrapper (`ssh-legacy`) pre-configured to allow legacy key-exchange, ciphers and MACs used by old network appliances.

Why: modern Linux distributions have removed or disabled weak SSH algorithms — this image lets you safely run a legacy client in an isolated container for maintenance of end-of-life devices.

## What this image provides

- Ubuntu 16.04 base with `openssh-client` installed
- `/usr/local/bin/ssh-legacy` — wrapper that enables legacy algorithms
- Optional system-wide legacy config at `/etc/ssh/ssh_config.d/legacy.conf` (kept separate; wrapper is opt-in)

Enabled (example) algorithms in the wrapper:
- KexAlgorithms: diffie-hellman-group1-sha1, diffie-hellman-group14-sha1
- HostKeyAlgorithms: ssh-rsa, ssh-dss
- Ciphers: aes128-cbc, 3des-cbc
- MACs: hmac-md5, hmac-sha1

## Quick start — build

```sh
# build locally
docker build -t weak-link-ssh:ubuntu16.04 .
```

## Run examples

1) Use your local SSH keys (recommended):

```sh
docker run --rm -it \
  -v "$HOME/.ssh:/root/.ssh:ro" \
  weak-link-ssh:ubuntu16.04 ssh-legacy user@LEGACY_HOST
```

2) Start an interactive shell and run commands manually:

```sh
docker run --rm -it -v "$HOME/.ssh:/root/.ssh:ro" weak-link-ssh:ubuntu16.04
# then inside container: ssh-legacy user@legacy-host
```

3) Use plain `ssh` with ad-hoc options (if you prefer):

```sh
docker run --rm -it -v "$HOME/.ssh:/root/.ssh:ro" \
  weak-link-ssh:ubuntu16.04 \
  ssh -oKexAlgorithms=+diffie-hellman-group1-sha1 user@legacy-host
```

## Inspect legacy SSH server (report)

The `ssh-report` command queries a server's SSH KEX/host-key/cipher/MAC capabilities without authenticating. Use it to create minimally-weak profiles that are just sufficient to connect.

```sh
# run a quick capability report
docker run --rm -it weak-link-ssh:ubuntu16.04 ssh-report legacy-host.example.com:22
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
  weak-link-ssh:ubuntu16.04 \
  ssh-profile mydevice
```

If `HostFingerprint` is set in the profile (or passed to `ssh-legacy` via `--host-fp`), the client will verify the fingerprint using `ssh-keyscan` before connecting — this prevents naive MITM when you already trust the server's key.

## When to use

- You cannot upgrade or modify the legacy device
- You need a reproducible, isolated environment that still supports old SSH algorithms

## Security warning

This image intentionally enables insecure algorithms. Use it only for short-term maintenance in isolated/trusted networks. Do NOT use it for general-purpose SSH access.

## Troubleshooting

- If the modern client shows "no matching key exchange method" or "no matching cipher" — try `ssh-legacy` from this container.
- Mount your SSH keys with `-v "$HOME/.ssh:/root/.ssh:ro"` so the container can reuse them.

## Shell completion

The repository contains `completions/ssh-profile.bash`. The image installs a completion file at `/etc/bash_completion.d/ssh-profile` so interactive shells inside the container will offer completions for `ssh-profile` and `ssh-legacy`.

To enable completion on your host:

```sh
sudo cp completions/ssh-profile.bash /etc/bash_completion.d/ssh-profile
# restart your shell or `source /etc/bash_completion` to load it
```

## CI / publishing (Makefile + GitHub Actions)

A `Makefile` and GitHub Actions workflow are included to build and publish the image.

- Build locally: `make build`
- Publish to GHCR: `make push-ghcr` (set `GHCR_OWNER` env or edit the `Makefile`)
- Optional: publish to Docker Hub with `make push-dockerhub` (set `DOCKERHUB_USER`)

The workflow `.github/workflows/publish.yml` builds and pushes to `ghcr.io/${{ github.repository_owner }}/weak-link-ssh:ubuntu16.04` on `main` or when you push a tag; it will also push to Docker Hub when `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` are provided as repository secrets.

## Example debug

If you see debug lines mentioning `diffie-hellman-group1-sha1`, `hmac-md5`, or `aes128-cbc`, the legacy wrapper can help negotiate those algorithms when necessary.

## Security

If security is not weak enough, let me know in Issues and we'll consider downgrading it further.

This project intentionally enables deprecated algorithms for device compatibility; treat it as a maintenance tool only.

## License / Notes

- License: Apache 2.0 
- Copyright: github.com/scaleoutsean
