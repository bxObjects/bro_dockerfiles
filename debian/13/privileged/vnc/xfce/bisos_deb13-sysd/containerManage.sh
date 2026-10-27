#!/bin/bash
#
# containerManage.sh --- Manage this leaf's container, with docker compose or podman.
#
# STANDALONE PATH. This script needs nothing but docker and compose (or podman,
# for the rootless-sysd leaves) --- no BISOS, no pip install. It is the
# run-side companion of ./imageBuild.sh and a permanent peer of the leaf's
# dockerProc.spcs / podmanProc.spcs (containerProc_instance* commands); the two
# must be kept at parity. See ./README.org.
#
# This file is IDENTICAL in every leaf of bro_dockerfiles. The leaf's profile
# (debian/<release>/<profile>/vnc/xfce/<leafName>/) selects the engine:
#
#   confined, privileged  -> docker compose. The host's cgroup version selects
#                            the compose file, and only that one is used:
#                              cgroup v2 (cgroup2fs) -> docker-compose.yml
#                              cgroup v1 (tmpfs)     -> docker-compose.cgv1.yml
#                            A confined leaf has no cgv1 file: its one
#                            docker-compose.yml is used on either version.
#                            The container name, image, host ports and subnet
#                            are read from that compose file.
#   rootless-sysd         -> rootless podman, cgroup v2 only. The container
#                            name and the published ports are read from the
#                            leaf's Podman Quadlet file (*.container); the image
#                            is the locally built <leafName>:latest.
#
# Either way the leaf's file stays the single source of truth for them.
#
# A leaf named <primary>-<N> (a numeric suffix) is a secondary instance: it runs
# the image of ../<primary> under its own container name, ports and subnet, and
# has no image of its own.
#
# Usage:
#   ./containerManage.sh [-n] <verb>
#   ./containerManage.sh [-n] vncPassword set|clear
#
#   -n         Dry run: run the (read-only) checks, then print the commands
#              that would be executed instead of executing them.
#
# Verbs:
#   create     Create the container (not started). Refuses if the container
#              already exists, if any of its host ports is in use, if the
#              compose network's subnet (cgroup v1) overlaps a docker network
#              or host route, or if the image has not been built.
#   start      Start the created container.
#   stop       Stop the container (it, and its writable layer, are kept).
#   restart    Stop then start the container.
#   delete     Stop and remove the container (and its compose network). The
#              container's writable layer is lost; the image is kept.
#   status     Show cgroup version, engine, container state, VNC auth and ports.
#   vncPassword set|clear
#              VNC has no password by default (convenient for local use).
#              "set" asks for one and puts it in the container; VNC viewers and
#              noVNC then ask for it. "clear" goes back to no password. Either
#              restarts a running container. The password is lost on delete.
#              Only its first 8 characters count, and VNC traffic is not
#              encrypted: across a network, use an SSH tunnel.

# All paths below are relative to this leaf, wherever the script is run from.
SELF=$(readlink -f "$0")
cd "$(dirname "$SELF")" || exit 1

COMPOSE_FILE_CGV2="docker-compose.yml"
COMPOSE_FILE_CGV1="docker-compose.cgv1.yml"

# The instance's VNC password, as written by "vncpasswd -f"; missing or empty means no
# password. Read by /usr/local/bin/vncStart.sh in the image at each VNC start.
VNC_PASSWD_PATH="/home/bystar/.config/bisosVncPasswd"

usage() {
  sed -n '/^# Usage:/,/^$/s/^# \{0,1\}//p' "$SELF" >&2
  exit 2
}

DRY_RUN=0
while getopts 'nh' opt; do
  case $opt in
    n) DRY_RUN=1 ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))
VERB="$1"
SUBVERB=""
case "$VERB" in
  create|start|stop|restart|delete|status)
    [ $# -eq 1 ] || usage ;;
  vncPassword)
    [ $# -eq 2 ] || usage
    SUBVERB="$2"
    case "$SUBVERB" in
      set|clear) ;;
      *) echo "ERROR: vncPassword takes set or clear, not: $SUBVERB" >&2; usage ;;
    esac
    ;;
  "") usage ;;
  *) echo "ERROR: unknown verb: $VERB" >&2; usage ;;
esac

# --- Refuse to run inside a container ---------------------------------------
# Same heuristics as ./imageBuild.sh and bisos.dockerProc
# (containerProc_csu._detectInContainer).
inContainerReason() {
  if [ -e /.dockerenv ]; then echo "/.dockerenv exists (docker)"; return 0; fi
  if [ -e /run/.containerenv ]; then echo "/run/.containerenv exists (podman)"; return 0; fi
  local marker
  for marker in docker containerd libpod kubepods lxc; do
    if grep -q "$marker" /proc/1/cgroup 2>/dev/null; then
      echo "/proc/1/cgroup contains '$marker'"; return 0
    fi
  done
  return 1
}
if reason=$(inContainerReason); then
  echo "ERROR: this is running inside a container ($reason)." >&2
  echo "       Manage containers from the host (the Container Platform), not from a container." >&2
  exit 1
fi

# --- Facts from the leaf path -----------------------------------------------
# .../debian/<release>/<profile>/vnc/xfce/<leafName>
LEAF_NAME=$(basename "$PWD")
PROFILE=$(basename "$(readlink -f ../../..)")
case "$PROFILE" in
  confined|privileged) ENGINE="docker" ;;
  rootless-sysd)       ENGINE="podman" ;;
  *)
    echo "ERROR: unexpected leaf path $PWD" >&2
    echo "       (profile segment is '$PROFILE'; expected confined, privileged or rootless-sysd)." >&2
    exit 1
    ;;
esac

# A leaf named <primary>-<N> (e.g. bisos_deb13-sysd-2) is another instance of
# the image of ../<primary>, which is where that image is built.
PRIMARY_LEAF=""
if [[ $LEAF_NAME =~ ^(.+)-([0-9]+)$ ]]; then
  PRIMARY_LEAF="${BASH_REMATCH[1]}"
fi

# --- cgroup version ---------------------------------------------------------
cgroupFsType=$(stat -fc %T /sys/fs/cgroup 2>/dev/null)
case "$cgroupFsType" in
  cgroup2fs) CGROUP_VER="v2" ;;
  tmpfs)     CGROUP_VER="v1" ;;
  *)
    echo "ERROR: cannot tell the host's cgroup version (/sys/fs/cgroup is '${cgroupFsType:-?}')." >&2
    exit 1
    ;;
esac

# --- The engine -------------------------------------------------------------
if ! command -v "$ENGINE" >/dev/null 2>&1; then
  echo "ERROR: $ENGINE is not installed on this host (this is a $PROFILE leaf)." >&2
  exit 1
fi
if ! $ENGINE info >/dev/null 2>&1; then
  if [ "$ENGINE" == "docker" ]; then
    echo "ERROR: cannot talk to the docker daemon. Is it running? Are you in the" >&2
    echo "       docker group (or do you need sudo)?" >&2
  else
    echo "ERROR: 'podman info' fails for this user; rootless podman is not usable here." >&2
  fi
  exit 1
fi

SUBNET=""
NETWORK_NAME=""

if [ "$ENGINE" == "docker" ]; then
  # --- cgroup version selects the compose file ------------------------------
  if [ "$CGROUP_VER" == "v2" ]; then
    COMPOSE_FILE="$COMPOSE_FILE_CGV2"
  elif [ -f "$COMPOSE_FILE_CGV1" ]; then
    COMPOSE_FILE="$COMPOSE_FILE_CGV1"
  elif [ "$PROFILE" == "confined" ]; then
    # No systemd in a confined container, so nothing cgroup-specific to say.
    COMPOSE_FILE="$COMPOSE_FILE_CGV2"
  else
    echo "ERROR: host is cgroup v1 but $COMPOSE_FILE_CGV1 is missing from this leaf." >&2
    exit 1
  fi
  if [ ! -f "$COMPOSE_FILE" ]; then
    echo "ERROR: $COMPOSE_FILE is missing from this leaf." >&2
    exit 1
  fi

  # The compose v2 plugin ("docker compose") is preferred; the standalone v1
  # binary ("docker-compose") is what older RedHat hosts tend to have.
  if docker compose version >/dev/null 2>&1; then
    COMPOSE=(docker compose)
  elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE=(docker-compose)
  else
    echo "ERROR: neither 'docker compose' nor 'docker-compose' is available." >&2
    exit 1
  fi
  COMPOSE+=(-f "$COMPOSE_FILE")
  SOURCE_FILE="$COMPOSE_FILE"

  # --- Facts read from the compose file -------------------------------------
  yamlValue() {
    sed -n "s/^[[:space:]]*$1:[[:space:]]*\"\{0,1\}\([^\"[:space:]#]*\).*/\1/p" "$COMPOSE_FILE" | head -1
  }
  CONTAINER_NAME=$(yamlValue container_name)
  IMAGE=$(yamlValue image)
  # Port lines look like:   - "2224:22"      # SSH
  portLineRe='^[[:space:]]*-[[:space:]]*"\{0,1\}\([0-9][0-9]*\):[0-9][0-9]*.*'
  HOST_PORTS=$(sed -n "s/${portLineRe}/\1/p" "$COMPOSE_FILE")
  # An explicit network subnet (the cgroup v1 file has one), and that network's name.
  SUBNET=$(yamlValue "-[[:space:]]*subnet")
  NETWORK_NAME=$(sed -n '/^networks:/{n;s/^[[:space:]]*\([A-Za-z0-9_.-]*\):.*/\1/p;}' "$COMPOSE_FILE")
else
  # --- rootless podman needs cgroup v2 --------------------------------------
  if [ "$CGROUP_VER" != "v2" ]; then
    echo "ERROR: host is cgroup v1. Rootless podman with systemd needs cgroup v2 (with" >&2
    echo "       controller delegation). Use a privileged leaf on this host instead." >&2
    exit 1
  fi

  # --- Facts read from the Quadlet file -------------------------------------
  quadletFiles=(*.container)
  if [ ${#quadletFiles[@]} -ne 1 ] || [ ! -f "${quadletFiles[0]}" ]; then
    echo "ERROR: expected exactly one Podman Quadlet file (*.container) in this leaf." >&2
    exit 1
  fi
  QUADLET_FILE="${quadletFiles[0]}"
  SOURCE_FILE="$QUADLET_FILE"
  CONTAINER_NAME=$(sed -n 's/^ContainerName=[[:space:]]*\([^[:space:]]*\).*/\1/p' "$QUADLET_FILE" | head -1)
  # PublishPort=2226:22  ->  "2226:22"
  PORT_PAIRS=$(sed -n 's/^PublishPort=[[:space:]]*\([0-9][0-9]*:[0-9][0-9]*\).*/\1/p' "$QUADLET_FILE")
  HOST_PORTS=$(for pair in $PORT_PAIRS; do echo "${pair%%:*}"; done)
  # The Quadlet's own Image= names the DockerHub image, for engineers who pull
  # it. This script runs the image built locally by ./imageBuild.sh (or, for a
  # secondary instance, by the primary leaf).
  IMAGE="${PRIMARY_LEAF:-$LEAF_NAME}:latest"
fi

if [ -z "$CONTAINER_NAME" ] || [ -z "$IMAGE" ]; then
  echo "ERROR: could not read the container name / image from $SOURCE_FILE." >&2
  exit 1
fi

containerExists() { $ENGINE container inspect "$CONTAINER_NAME" >/dev/null 2>&1; }
containerState()  { $ENGINE container inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null; }
imageExists()     { $ENGINE image inspect "$IMAGE" >/dev/null 2>&1; }

# vncAuthMode --- "password" if the container holds a non-empty VNC password file,
# "none" if not. Read with "cp" (a tar stream), which works on a stopped container too.
vncAuthMode() {
  if ! containerExists; then
    echo "none (no instance yet)"
    return
  fi
  local bytes
  bytes=$($ENGINE cp "$CONTAINER_NAME:$VNC_PASSWD_PATH" - 2>/dev/null | tar -xO 2>/dev/null | wc -c)
  if [ "${bytes:-0}" -gt 0 ]; then echo "password"; else echo "none"; fi
}

portInUse() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${port}\$"
  else
    netstat -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${port}\$"
  fi
}

# --- Is the compose network's subnet free on this host? ---------------------
ip2int() { local IFS=.; set -- $1; echo $(( ($1 << 24) + ($2 << 16) + ($3 << 8) + $4 )); }

# cidrsOverlap <a.b.c.d[/n]> <e.f.g.h[/m]> --- true if the two ranges overlap.
cidrsOverlap() {
  local aNet=${1%/*} aLen=${1#*/} bNet=${2%/*} bLen=${2#*/}
  [ "$aLen" = "$1" ] && aLen=32
  [ "$bLen" = "$2" ] && bLen=32
  local len=$(( aLen < bLen ? aLen : bLen ))
  local mask=$(( len == 0 ? 0 : (0xFFFFFFFF << (32 - len)) & 0xFFFFFFFF ))
  [ $(( $(ip2int "$aNet") & mask )) -eq $(( $(ip2int "$bNet") & mask )) ]
}

# subnetConflicts --- print one line per docker network or host route that
# overlaps $SUBNET. This leaf's own compose network is reused by compose, so it
# is not a conflict.
subnetConflicts() {
  local name subnets s dest rest
  docker network ls -q | xargs -r docker network inspect \
      -f '{{.Name}} {{range .IPAM.Config}}{{.Subnet}} {{end}}' 2>/dev/null |
    while read -r name subnets; do
      case "$name" in *_"$NETWORK_NAME") continue ;; esac
      for s in $subnets; do
        [[ $s == *.*.*.*/* ]] || continue   # IPv4 only
        cidrsOverlap "$SUBNET" "$s" && echo "docker network '$name' uses $s"
      done
    done
  # Host routes (these include the host's own interface subnets). Default
  # routes and docker's bridges (checked above) are skipped.
  if command -v ip >/dev/null 2>&1; then
    ip -4 route show | while read -r dest rest; do
      [[ $dest == *.*.*.* ]] || continue
      case "$rest" in *"dev docker"*|*"dev br-"*) continue ;; esac
      cidrsOverlap "$SUBNET" "$dest" && echo "host route: $dest $rest"
    done
  fi
}

# runCmnd <command...> --- execute, or with -n only print.
runCmnd() {
  if [ $DRY_RUN == 1 ]; then
    echo "  Would run:: $*"
  else
    echo "  Running:: $*"
    "$@"
  fi
}

echo
echo "     Container: $CONTAINER_NAME"
echo "         Image: $IMAGE"
echo "        Engine: $ENGINE  ($PROFILE leaf)"
echo "        cgroup: $CGROUP_VER  ->  $SOURCE_FILE"
echo "    Host ports: $(echo $HOST_PORTS)"
echo "      VNC auth: $(vncAuthMode)"
[ -n "$SUBNET" ] && echo "        Subnet: $SUBNET  (network $NETWORK_NAME)"
[ -n "$PRIMARY_LEAF" ] && echo "      Instance: secondary --- its image is built in ../$PRIMARY_LEAF"
[ $DRY_RUN == 1 ] && echo "       Dry run: yes (nothing will be changed)"
echo

# --- The engine commands ----------------------------------------------------
# One function per verb, so the verbs below read the same for both engines.
if [ "$ENGINE" == "docker" ]; then
  # --no-build: building is ./imageBuild.sh's job, never a side effect here.
  engineCreate()  { runCmnd "${COMPOSE[@]}" up --no-start --no-build; }
  engineStart()   { runCmnd "${COMPOSE[@]}" start; }
  engineStop()    { runCmnd "${COMPOSE[@]}" stop; }
  engineRestart() { runCmnd "${COMPOSE[@]}" restart; }
  engineDelete()  { runCmnd "${COMPOSE[@]}" down; }
  enginePs()      { "${COMPOSE[@]}" ps; }
else
  # Same options as bisos.dockerProc's containerProc_instanceUp for podman.
  # --systemd=always: podman does the systemd plumbing (cgroup delegation,
  # tmpfs on /run /run/lock /tmp) inside the user's namespace. No --privileged.
  engineCreate() {
    local args=(podman create --pids-limit=16384 --systemd=always
                --stop-signal SIGRTMIN+3 --name "$CONTAINER_NAME")
    local pair
    for pair in $PORT_PAIRS; do args+=(-p "$pair"); done
    args+=(-v "$PWD:/shuttle/this" "$IMAGE")
    runCmnd "${args[@]}"
  }
  engineStart()   { runCmnd podman start "$CONTAINER_NAME"; }
  engineStop()    { runCmnd podman stop "$CONTAINER_NAME"; }
  engineRestart() { runCmnd podman restart "$CONTAINER_NAME"; }
  engineDelete()  { runCmnd podman rm -f "$CONTAINER_NAME"; }
  enginePs()      { podman ps -a --filter "name=^${CONTAINER_NAME}\$"; }
fi

# --- Verbs ------------------------------------------------------------------
requireExists() {
  if ! containerExists; then
    echo "ERROR: container $CONTAINER_NAME does not exist. Run: ./containerManage.sh create" >&2
    exit 1
  fi
}

case "$VERB" in
  create)
    problems=0
    if containerExists; then
      echo "  PROBLEM:: container $CONTAINER_NAME already exists (state: $(containerState))." >&2
      echo "            Use start/stop/restart, or delete it first." >&2
      problems=1
    fi
    for port in $HOST_PORTS; do
      if portInUse "$port"; then
        echo "  PROBLEM:: host port $port is already in use." >&2
        problems=1
      fi
    done
    if ! imageExists; then
      echo "  PROBLEM:: image $IMAGE is not in $ENGINE's local store." >&2
      if [ -n "$PRIMARY_LEAF" ]; then
        echo "            Build it in the primary leaf: ( cd ../$PRIMARY_LEAF && ./imageBuild.sh )" >&2
      else
        echo "            Run: ./imageBuild.sh" >&2
      fi
      problems=1
    fi
    if [ -n "$SUBNET" ]; then
      conflicts=$(subnetConflicts)
      if [ -n "$conflicts" ]; then
        echo "  PROBLEM:: subnet $SUBNET (from $COMPOSE_FILE) is not free on this host:" >&2
        echo "$conflicts" | sed 's/^/              /' >&2
        echo "            Pick a free subnet in $COMPOSE_FILE." >&2
        problems=1
      fi
    fi
    if [ $problems == 1 ]; then
      echo "ERROR: not creating $CONTAINER_NAME." >&2
      exit 1
    fi
    engineCreate || exit 1
    echo
    echo "Next: ./containerManage.sh start"
    ;;
  start)
    requireExists
    engineStart || exit 1
    if [ -x ./verify.sh ]; then
      echo
      echo "Verify with: ./verify.sh"
    fi
    ;;
  stop)
    requireExists
    engineStop || exit 1
    ;;
  restart)
    requireExists
    engineRestart || exit 1
    ;;
  delete)
    if ! containerExists; then
      echo "Container $CONTAINER_NAME does not exist; nothing to delete."
      exit 0
    fi
    echo "  NOTE:: deleting loses the container's writable layer; the image is kept."
    engineDelete || exit 1
    ;;
  status)
    if containerExists; then
      echo "  Container state: $(containerState)"
      enginePs
    else
      echo "  Container state: does not exist"
    fi
    for port in $HOST_PORTS; do
      if portInUse "$port"; then
        echo "  Host port $port: listening"
      else
        echo "  Host port $port: free"
      fi
    done
    ;;
  vncPassword)
    requireExists
    passwdTmp=$(mktemp) || exit 1
    trap 'rm -f "$passwdTmp"' EXIT
    # An image built before VNC passwords existed would ignore the file.
    if ! $ENGINE run --rm --network none --entrypoint test "$IMAGE" -x /usr/local/bin/vncStart.sh; then
      echo "ERROR: image $IMAGE has no /usr/local/bin/vncStart.sh, so it would ignore a VNC password." >&2
      if [ -n "$PRIMARY_LEAF" ]; then
        echo "       Rebuild it: ( cd ../$PRIMARY_LEAF && ./imageBuild.sh ), then delete and create this instance." >&2
      else
        echo "       Rebuild it (./imageBuild.sh, its confined base first), then delete and create the instance." >&2
      fi
      exit 1
    fi
    if [ "$SUBVERB" == "set" ]; then
      # The image's own vncpasswd (in a throw-away container) makes the file, so the
      # host needs no VNC tools. The password goes through stdin, never the command line.
      genCmnd=($ENGINE run --rm -i --network none --entrypoint vncpasswd "$IMAGE" -f)
      if [ $DRY_RUN == 1 ]; then
        echo "  Would ask for the new VNC password (twice), then run:"
        echo "  Would run:: <password> | ${genCmnd[*]} > <tmpFile>"
      else
        read -r -s -p "New VNC password: " vncPw1; echo
        read -r -s -p "Same password again: " vncPw2; echo
        if [ -z "$vncPw1" ]; then
          echo "ERROR: empty password. (For no password: ./containerManage.sh vncPassword clear)" >&2
          exit 1
        fi
        if [ "$vncPw1" != "$vncPw2" ]; then
          echo "ERROR: the two passwords differ; nothing changed." >&2
          exit 1
        fi
        if [ ${#vncPw1} -gt 8 ]; then
          echo "  NOTE:: VNC uses only the first 8 characters of the password."
        fi
        echo "  Running:: <password> | ${genCmnd[*]} > <tmpFile>"
        printf '%s\n' "$vncPw1" | "${genCmnd[@]}" > "$passwdTmp" || exit 1
        unset vncPw1 vncPw2
        if [ ! -s "$passwdTmp" ]; then
          echo "ERROR: vncpasswd produced no output; nothing changed." >&2
          exit 1
        fi
      fi
    fi
    # "clear" copies in an empty file: vncStart.sh then runs VNC with no password.
    runCmnd $ENGINE cp "$passwdTmp" "$CONTAINER_NAME:$VNC_PASSWD_PATH" || exit 1
    if [ "$(containerState)" == "running" ]; then
      echo "  Restarting $CONTAINER_NAME so that VNC uses the new setting."
      engineRestart || exit 1
    else
      echo "  It takes effect when the container starts."
    fi
    if [ "$SUBVERB" == "set" ]; then
      echo
      echo "VNC viewers and noVNC now ask for this password. VNC traffic is not encrypted:"
      echo "across a network, use an SSH tunnel. Back to no password: ./containerManage.sh vncPassword clear"
    fi
    ;;
esac
