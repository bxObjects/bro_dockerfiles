# bisos_deb12-rootless-sysd
#
# Same systemd-as-PID-1 image as the privileged variant, but INTENDED TO RUN
# UNDER ROOTLESS PODMAN. The image build is identical to bisos_deb12-sysd;
# the difference is entirely at run time:
#   - NO --privileged
#   - NO host /sys/fs/cgroup bind mount
#   - NO cgroupns/cgroup: host
# Podman's native systemd integration (--systemd=always) sets up the cgroup
# subtree delegation and tmpfs mounts systemd needs, all inside the user
# namespace. Container root == the engineer's mapped unprivileged host UID.
#
# See run.bash / the Quadlet unit for the run-time configuration.

FROM bisos/deb12-fresh-vnc-xfce:1.21

# The confined base image ends with USER bystar. systemd (PID 1) and the
# build-time apt/systemctl steps below require root. Under rootless Podman
# this "root" is namespaced to the launching user, not host root.
USER root

ENV DEBIAN_FRONTEND=noninteractive

# Install systemd and D-Bus.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        systemd \
        systemd-sysv \
        dbus \
        dbus-user-session \
 && apt-get clean -y \
 && rm -rf /var/lib/apt/lists/*

# Remove systemd units that make no sense inside a container.
RUN find /lib/systemd/system/sysinit.target.wants/ -type l \
        ! -name 'systemd-tmpfiles-setup.service' -delete \
 && rm -f /lib/systemd/system/multi-user.target.wants/* \
          /etc/systemd/system/*.wants/* \
          /lib/systemd/system/local-fs.target.wants/* \
          /lib/systemd/system/sockets.target.wants/*udev* \
          /lib/systemd/system/sockets.target.wants/*initctl* \
          /lib/systemd/system/basic.target.wants/* \
          /lib/systemd/system/anaconda.target.wants/* \
          /lib/systemd/system/plymouth* \
          /lib/systemd/system/rescue.service \
          /lib/systemd/system/rescue.target 2>/dev/null || true

# Install systemd service units for VNC, noVNC and sshd.
COPY dockerConf/vncserver.service      /etc/systemd/system/vncserver.service
COPY dockerConf/novnc.service          /etc/systemd/system/novnc.service
COPY dockerConf/sshd-container.service /etc/systemd/system/sshd-container.service

# Mask polkit --- it fails inside containers (no seat/active session) and would
# leave systemd "degraded"; nothing here uses it (sudo is passwordless).
RUN systemctl mask polkit.service

# Enable the services so systemd starts them at boot.
RUN systemctl enable vncserver novnc sshd-container dbus

# systemd is PID 1.
STOPSIGNAL SIGRTMIN+3
ENTRYPOINT ["/sbin/init"]
