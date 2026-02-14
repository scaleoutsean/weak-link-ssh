profiles — per-device configuration

Place simple key=value profile files in a directory on the Docker host and mount that directory as `/profiles` into the container. Each profile describes the host, username, port and any algorithm overrides needed to connect.

Format

```
Host=192.168.1.34
User=admin
Port=22
KexAlgorithms=diffie-hellman-group14-sha1
HostKeyAlgorithms=ssh-rsa
Ciphers=aes128-ctr,aes128-cbc
MACs=hmac-sha1
# optional: expected server host key fingerprint to avoid naive MITM
# HostFingerprint=SHA256:...
# Options= (extra ssh -o options)
```

Create a profile from `ssh-report`

1. Run `ssh-report` against the device: `ssh-report device:22`.
2. Copy only the minimal algorithms required (prefer `-ctr` ciphers and `sha256` MACs if available).
3. Save the file as `/profiles/<name>` and mount it when running the container.

Host fingerprint (recommended when possible)

To extract a SHA256 fingerprint you can run:

```sh
ssh-keyscan -p 22 example-host | ssh-keygen -lf - -E sha256 | awk '{print $2}'
```

Add the result as `HostFingerprint=SHA256:...` in the profile to prevent naive MITM.

Shell completion

The repository includes a bash completion script at `completions/ssh-profile.bash`. You can install it locally:

```sh
# system-wide (root)
sudo cp completions/ssh-profile.bash /etc/bash_completion.d/ssh-profile
# or per-user
mkdir -p ~/.bash_completion.d && cp completions/ssh-profile.bash ~/.bash_completion.d/ssh-profile && source ~/.bashrc
```

When the completion file is present in the container (image ships it), interactive shells inside the container will also provide completion for `ssh-profile` and `ssh-legacy`.
