#!/usr/bin/bash
set -euo pipefail

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
  echo "=== $* ==="
}

log "Starting system cleanup"

# Ensure all system users/groups from sysusers.d are committed to /etc/passwd and /etc/group.
# RPM scriptlets create users at install time, but ostree 3-way merges can fail to propagate
# new system users to existing deployments. Running this explicitly guarantees the users are
# in the image so bootc/ostree has a correct base to merge against.
systemd-sysusers

# Clean package manager cache
dnf5 clean all

# Clean temporary files
rm -rf /tmp/* || true

# Cleanup the entirety of `/var`.
# None of these get in the end-user system and bootc lints get super mad if anything is in there
rm -rf /var
mkdir -p /var/tmp
chmod -R 1777 /var/tmp

# Commit and lint container
bootc container lint || true

log "Cleanup completed"
