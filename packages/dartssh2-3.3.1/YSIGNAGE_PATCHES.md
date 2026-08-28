# YSignage local changes

Upstream: `dartssh2` 3.3.1 (`https://github.com/vicajilau/dartssh2`)

The package is kept as a local path dependency so the Windows application does not depend on an
external SSH executable. The following OpenSSH `PROTOCOL` 2.4 features were added:

- `streamlocal-forward@openssh.com` and cancellation global requests
- `forwarded-streamlocal@openssh.com` channel decoding and acceptance
- `SSHClient.forwardRemoteUnix` and `SSHRemoteUnixForward`

The original `LICENSE` is retained in this directory.
