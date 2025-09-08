FROM debian:bullseye

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=America/New_York

# Username and password for the non-root user in the container.
# If these are changed then it is also necessary to change directory
# names in the panel.bash and panel.desktop files.
ARG USERNAME=student
ARG PASSWD=student

# Install the necessary system software.
# The list of system software was adapted from the cypress/base:16.14.2 Dockerfile.
#  https://github.com/cypress-io/cypress-docker-images/blob/master/base/16.14.2/Dockerfile
RUN apt-get update \
 && apt-get install --no-install-recommends -y \
        libgtk2.0-0 \
        libgtk-3-0 \      
        libnotify-dev \
        libgconf-2-4 \
        libgbm-dev \
        libnss3 \
        libxss1 \
        libasound2 \
        libxtst6 \
        libpci3 \
        libsecret-1-0 \
        software-properties-common \
        gnupg2 \
        atfs \
        at-spi2-core \
        procps \
        xauth \
        xvfb \
        fonts-noto-color-emoji

# Install some base applications.
RUN apt-get install --no-install-recommends -y \
        sudo \
        vim-tiny \
        nano \
        wget \
        curl \
        man \
        synaptic \
        firefox-esr \
        git \
        gedit \
        emacs \
        meld

# Install VSCodium.  Note: Extensions can be installed later so that
# they are installed just for the non-root user.
COPY vscodium.bash .
RUN ./vscodium.bash \
 && rm vscodium.bash

# Add environment variable to /etc/profile so that VSCodium
# launches on Windows with WSL without a warning.
ENV DONT_PROMPT_WSL_INSTALL=1

# Install the XFCE4 desktop environment.
# Note: Power management does not work inside docker so it is removed.
RUN apt-get install -y --no-install-recommends \
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

USER $USERNAME
WORKDIR /home/$USERNAME

# Configure the VNC server so that it allows a connection without a login.
RUN touch .Xauthority \
 && mkdir .vnc \
 && /bin/bash -c "echo -e '$PASSWD\n$PASSWD\nn' | vncpasswd; echo;"
COPY --chown=$USERNAME:$USERNAME ./xstartup .vnc/xstartup
USER root
RUN echo ":1=$USERNAME" >> /etc/tigervnc/vncserver.users \
 && chmod +x .vnc/xstartup
USER $USERNAME

# Add some scripts for the running container.
RUN mkdir .contconf \
 && mkdir -p .config/autostart

# startup.bash is run when the container starts.  It sets the ownership and group
# for the FarmData2 repo and the fd2test directories and starts the VNC and noVNC
# servers.
COPY --chown=$USERNAME:$USERNAME ./startup.bash .contconf/startup.bash
# .bash_aliases defines a few shortcut commands that are useful when doing FarmData2
# development work.
COPY --chown=$USERNAME:$USERNAME ./bash_aliases .bash_aliases
# panel.bash configures the launcheer panel at the bottom of the XFCE4 desktop by adding
# icons for Mousepad, VSCodium and Firefox...
COPY --chown=$USERNAME:$USERNAME ./panel.bash .contconf/panel.bash
# panel.desktop ensures that the panel.bash script is run when the XFCE4 desktop is started.
COPY --chown=$USERNAME:$USERNAME ./panel.desktop .config/autostart/panel.desktop
# terminalrc has the setting that enables unicode in the terminal
COPY --chown=$USERNAME:$USERNAME ./terminalrc .config/xfce4/terminal/terminalrc

RUN chmod +x .contconf/startup.bash \
 && chmod +x .contconf/panel.bash \
 && chmod +x .config/autostart/panel.desktop

# Do some git configuration so that the student doesn't have to.
RUN git config --global credential.helper store \
 && git config --global merge.conflictstyle diff3 \
 && git config --global merge.tool vscode \
 && git config --global mergetool.keepBackup false \
 && git config --global mergetool.vscode.cmd '/usr/bin/codium --no-sandbox --wait --new-window --merge $LOCAL $REMOTE $BASE $MERGED' \
 && git config --global core.editor "nano" \
 && git config --global pull.ff only \
 && git config --global init.defaultBranch main \
 && git config --global safe.directory '*' \
 && echo "" >> .bashrc \
 && echo "source /usr/share/bash-completion/completions/git" >> .bashrc

# Install some useful VSCodium extensions
RUN codium --install-extension streetsidesoftware.code-spell-checker \
  && codium --install-extension bierner.markdown-preview-github-styles

# Stuff to reduce image size.
USER root
RUN apt-get clean -y \
 && apt-get autoclean -y \
 && apt-get autoremove -y \
 && rm -rf /var/lib/apt/lists/*

USER $USERNAME

# Run the startup.bash script to ensure that 
# the VNC and noVNC servers are running.
ENTRYPOINT .contconf/startup.bash
