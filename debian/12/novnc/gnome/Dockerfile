FROM debian:stable-slim

ENV DISPLAY=:1 \
    VNC_PORT=5901 \
    NO_VNC_PORT=6901 \
    VNC_COL_DEPTH=32 \
    VNC_RESOLUTION=1920x1080

# ENV VNC_PASSWORD=your_vnc_password_here  ### Is this needed at all

# No interactive frontend during docker build
ENV DEBIAN_FRONTEND=noninteractive

# Install necessary packages
RUN apt-get update && apt-get install -y \
    task-gnome-desktop \
    tightvncserver \
    novnc \
    xterm \
    sudo \
    && apt-get clean && rm -rf /var/lib/apt/lists/*


ENV TERM=xterm

# disable shared memory X11 affecting Chromium
ENV QT_X11_NO_MITSHM=1 \
    _X11_NO_MITSHM=1 \
    _MITSHM=0

# give every user read write access to the "/root" folder where the binary is cached
RUN ls -la /root
RUN chmod 777 /root && mkdir /src


# NOTYET
# Create a user for VNC access (optional, but recommended)
# RUN useradd -m -s /bin/bash vncuser && echo "vncuser:$VNC_PASSWORD" | chpasswd
# RUN mkdir -p ~/.vnc && \
#     echo "$VNC_PASSWORD" | vncpasswd -f > ~/.vnc/passwd && \
#     chmod 600 ~/.vnc/passwd


RUN groupadd -g 61000 dockeruser; \
    useradd -g 61000 -l -m -s /bin/bash -u 61000 dockeruser

RUN chown -R dockeruser:dockeruser /home/dockeruser;\
    chmod -R 777 /home/dockeruser ;\
    adduser dockeruser sudo;\
    echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

USER dockeruser
# versions of local tools
RUN echo  "debian version:  $(cat /etc/debian_version) \n" \
          "user:            $(whoami) \n"

COPY scripts/entrypoint.sh /src

#Expose port 5901 to view display using VNC Viewer
EXPOSE 5901 6901
ENTRYPOINT ["/src/entrypoint.sh"]

# Insecure option is needed to accept connections from the docker host.

# CMD rm /tmp/.X1-lock 2> /dev/null && \
#     /usr/share/novnc/utils/launch.sh --vnc localhost:$VNC_PORT --listen $NO_VNC_PORT  && \
#   tightvncserver  $DISPLAY -depth $VNC_COL_DEPTH -geometry $VNC_RESOLUTION -SecurityTypes None -localhost no --I-KNOW-THIS-IS-INSECURE

# # Expose VNC and noVNC ports
# EXPOSE 5901
# EXPOSE 6080

# # Start VNC server and noVNC
# CMD tightvncserver -geometry $RESOLUTION :1 && \
#     /usr/share/novnc/utils/launch.sh --vnc localhost:5901 --listen 6080
