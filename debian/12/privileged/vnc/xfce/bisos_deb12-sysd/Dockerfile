FROM bisos_deb12-fresh:latest

# The confined base image ends with USER bystar. systemd (PID 1) and all the
# build-time apt/systemctl steps below require root, so switch to root and
# stay there — a privileged systemd container runs /sbin/init as root.
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
# Keeps the boot clean and fast.
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

# Install systemd service units for VNC, noVNC, sshd, and /tmp remount.
COPY dockerConf/vncserver.service      /etc/systemd/system/vncserver.service
COPY dockerConf/novnc.service          /etc/systemd/system/novnc.service
COPY dockerConf/sshd-container.service /etc/systemd/system/sshd-container.service
COPY dockerConf/tmp-exec.service       /etc/systemd/system/tmp-exec.service

# Mask polkit --- it fails inside containers (no seat/active session) and would
# leave systemd "degraded"; nothing here uses it (sudo is passwordless).
RUN systemctl mask polkit.service

# Enable the services so systemd starts them at boot.
# tmp-exec remounts /tmp with exec --- Docker's tmpfs applies noexec by default.
RUN systemctl enable vncserver novnc sshd-container dbus tmp-exec

# xstartup for VNC is already baked into the base image under /home/bystar/.vnc/
# Nothing extra needed here.

# systemd is PID 1.
STOPSIGNAL SIGRTMIN+3
ENTRYPOINT ["/sbin/init"]
