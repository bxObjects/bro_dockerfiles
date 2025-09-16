FROM debian:13.1

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=America/Los_Angeles

# Username and password for the non-root user in the container.
# If these are changed then it is also necessary to change directory
# names in the panel.sh and panel.desktop files.
ARG USERNAME=bystar
ARG PASSWD=insecure

# Install the necessary system software.
# The list of system software was adapted from the cypress/base:16.14.2 Dockerfile.
#  https://github.com/cypress-io/cypress-docker-images/blob/master/base/16.14.2/Dockerfile
RUN apt-get update \
 && apt-get install --no-install-recommends -y \
        libgtk2.0-0 \
        libgtk-3-0 \      
        libnotify-dev \
        libgbm-dev \
        libnss3 \
        libxss1 \
        libasound2 \
        libxtst6 \
        libpci3 \
        libsecret-1-0 \
        gnupg2 \
        at-spi2-core \
        procps \
        xauth \
        xvfb \
        fonts-noto-color-emoji

# Install some base applications.
RUN apt-get install --no-install-recommends -y \
        sudo \
        wget \
        curl \
        man \
        synaptic \
        firefox-esr \
        git \
        gedit \
        emacs \
        meld

# Install the XFCE4 desktop environment.
# Note: Power management does not work inside docker so it is removed.
RUN apt-get install --no-install-recommends -y \
        xfce4 \
        xfce4-goodies \
        xfce4-terminal -y \
 && apt-get autoremove -y \
        xfce4-power-manager

# Install the Tiger VNC server, the noVNC server and dbus-x11 depndency.
# Also rename vnc.html so that the the noVNC server can be accessed
# more directly.
RUN apt-get install -y --no-install-recommends \
        tigervnc-standalone-server \
        tigervnc-common \
        dbus-x11 \
        novnc \
        net-tools \
 && cp /usr/share/novnc/vnc.html /usr/share/novnc/index.html

# Create the non-root user inside the container and give them sudo privlidges.
RUN useradd \
    -m $USERNAME -p "$(openssl passwd -1 $PASSWD)" \
    -s /bin/bash \
    -G sudo

# Allow members of group sudo to execute any command
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

#########  SSH BEGIN

# Install OpenSSH server
RUN apt-get update && apt-get install -y openssh-server

RUN ssh-keygen -A

# Create SSH directory and set permissions
# RUN mkdir /var/run/sshd
# RUN chmod 0755 /var/run/sshd

# Configure SSH to allow root login (for simplicity; consider creating a dedicated user in production)
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

RUN sed -i 's/UsePAM yes/UsePAM no/' /etc/ssh/sshd_config

# NOTYET Set a root password (change this in a real scenario)
RUN echo 'root:password' | chpasswd

########  SSH END

USER $USERNAME
WORKDIR /home/$USERNAME

# Configure the VNC server so that it allows a connection without a login.
RUN touch .Xauthority \
 && mkdir -p .config/tigervnc \
 && /bin/bash -c "echo -e '$PASSWD\n$PASSWD\nn' | vncpasswd; echo;"
COPY --chown=$USERNAME:$USERNAME ./dockerConf/xstartup .config/tigervnc/xstartup
USER root
RUN echo ":1=$USERNAME" >> /etc/tigervnc/vncserver.users \
 && chmod +x .config/tigervnc/xstartup
USER $USERNAME

# Add some scripts for the running container.
RUN mkdir dockerConf \
 && mkdir -p .config/autostart

# entrypoint.sh is run when the container starts.  It sets the ownership and group
# for the FarmData2 repo and the fd2test directories and starts the VNC and noVNC
# servers.
COPY --chown=$USERNAME:$USERNAME ./dockerConf/entrypoint.sh dockerConf/entrypoint.sh
# panel.sh configures the launcheer panel at the bottom of the XFCE4 desktop by adding
# icons for Mousepad, Firefox...
COPY --chown=$USERNAME:$USERNAME ./dockerConf/panel.sh dockerConf/panel.sh
# panel.desktop ensures that the panel.sh script is run when the XFCE4 desktop is started.
COPY --chown=$USERNAME:$USERNAME ./dockerConf/panel.desktop .config/autostart/panel.desktop
# terminalrc has the setting that enables unicode in the terminal
COPY --chown=$USERNAME:$USERNAME ./dockerConf/terminalrc .config/xfce4/terminal/terminalrc

RUN chmod +x dockerConf/entrypoint.sh \
 && chmod +x dockerConf/panel.sh \
 && chmod +x .config/autostart/panel.desktop

# Do some git configuration so that the user doesn't have to.
RUN git config --global credential.helper store \
 && git config --global merge.conflictstyle diff3 \
 && git config --global merge.tool vscode \
 && git config --global mergetool.keepBackup false \
 && git config --global core.editor "emacs" \
 && git config --global pull.ff only \
 && git config --global init.defaultBranch main \
 && git config --global safe.directory '*' \
 && echo "" >> .bashrc \
 && echo "source /usr/share/bash-completion/completions/git" >> .bashrc


# Stuff to reduce image size.
USER root
RUN apt-get clean -y \
 && apt-get autoclean -y \
 && apt-get autoremove -y \
 && rm -rf /var/lib/apt/lists/*

USER $USERNAME

# Run the entrypoint.sh script to ensure that
# the VNC and noVNC servers are running.
ENTRYPOINT dockerConf/entrypoint.sh
