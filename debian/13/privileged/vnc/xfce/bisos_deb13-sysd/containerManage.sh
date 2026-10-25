#!/bin/bash
#
# containerManage.sh --- Manage the deb13 privileged (bisos_deb13-sysd) container with docker compose.
#
# STANDALONE PATH. This script needs nothing but docker and compose --- no
# BISOS, no pip install. It is the run-side companion of ./imageBuild.sh and a
# permanent peer of ./dockerProc.spcs (containerProc_instance* commands); the
# two must be kept at parity. See ./README.org.
#
# The host's cgroup version selects the compose file, and only that one is
# used:
#   cgroup v2 (cgroup2fs)  -> docker-compose.yml
#   cgroup v1 (tmpfs)      -> docker-compose.cgv1.yml
# The container name, image, host ports and subnet are read from that compose
# file, so the yml stays the single source of truth for them.
#
# A leaf named <primary>-<N> (a numeric suffix) is a secondary instance: it runs
# the image of ../<primary> under its own container name, ports and subnet, and
# has no image of its own.
#
# Usage:
#   ./containerManage.sh [-n] <verb>
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
#   delete     Stop and remove the container and its compose network. The
#              container's writable layer is lost; the image is kept.
#   status     Show cgroup version, compose file, container state and ports.

# All paths below are relative to this leaf, wherever the script is run from.
cd "$(dirname "$(readlink -f "$0")")" || exit 1

COMPOSE_FILE_CGV2="docker-compose.yml"
COMPOSE_FILE_CGV1="docker-compose.cgv1.yml"

usage() {
  sed -n '/^# Usage:/,/^$/s/^# \{0,1\}//p' "$0" >&2
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
[ $# -eq 1 ] || usage
VERB="$1"
case "$VERB" in
  create|start|stop|restart|delete|status) ;;
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

# --- cgroup version selects the compose file --------------------------------
cgroupFsType=$(stat -fc %T /sys/fs/cgroup 2>/dev/null)
case "$cgroupFsType" in
  cgroup2fs) CGROUP_VER="v2"; COMPOSE_FILE="$COMPOSE_FILE_CGV2" ;;
  tmpfs)     CGROUP_VER="v1"; COMPOSE_FILE="$COMPOSE_FILE_CGV1" ;;
  *)
    echo "ERROR: cannot tell the host's cgroup version (/sys/fs/cgroup is '${cgroupFsType:-?}')." >&2
    exit 1
    ;;
esac
if [ ! -f "$COMPOSE_FILE" ]; then
  echo "ERROR: host is cgroup $CGROUP_VER but $COMPOSE_FILE is missing from this leaf." >&2
  exit 1
fi

# --- docker and compose -----------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker is not installed on this host." >&2
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  echo "ERROR: cannot talk to the docker daemon. Is it running? Are you in the" >&2
  echo "       docker group (or do you need sudo)?" >&2
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

# --- Facts read from the compose file ---------------------------------------
yamlValue() {
  sed -n "s/^[[:space:]]*$1:[[:space:]]*\"\{0,1\}\([^\"[:space:]#]*\).*/\1/p" "$COMPOSE_FILE" | head -1
}
CONTAINER_NAME=$(yamlValue container_name)
IMAGE=$(yamlValue image)
# Port lines look like:   - "2224:22"      # SSH
portLineRe='^[[:space:]]*-[[:space:]]*"\{0,1\}\([0-9][0-9]*\):[0-9][0-9]*.*'
HOST_PORTS=$(sed -n "s/${portLineRe}/\1/p" "$COMPOSE_FILE")
if [ -z "$CONTAINER_NAME" ] || [ -z "$IMAGE" ]; then
  echo "ERROR: could not read container_name / image from $COMPOSE_FILE." >&2
  exit 1
fi
# An explicit network subnet (the cgroup v1 file has one), and that network's name.
SUBNET=$(yamlValue "-[[:space:]]*subnet")
NETWORK_NAME=$(sed -n '/^networks:/{n;s/^[[:space:]]*\([A-Za-z0-9_.-]*\):.*/\1/p;}' "$COMPOSE_FILE")

# --- A numeric suffix means a secondary instance ----------------------------
# A leaf named <primary>-<N> (e.g. bisos_deb13-sysd-2) is another instance of
# the image of ../<primary>, which is where that image is built.
LEAF_NAME=$(basename "$PWD")
PRIMARY_LEAF=""
if [[ $LEAF_NAME =~ ^(.+)-([0-9]+)$ ]]; then
  PRIMARY_LEAF="${BASH_REMATCH[1]}"
fi

containerExists() { docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; }
containerState()  { docker container inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null; }

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
echo "        cgroup: $CGROUP_VER  ->  $COMPOSE_FILE"
echo "    Host ports: $(echo $HOST_PORTS)"
[ -n "$SUBNET" ] && echo "        Subnet: $SUBNET  (network $NETWORK_NAME)"
[ -n "$PRIMARY_LEAF" ] && echo "      Instance: secondary --- its image is built in ../$PRIMARY_LEAF"
[ $DRY_RUN == 1 ] && echo "       Dry run: yes (nothing will be changed)"
echo

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
    if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
      echo "  PROBLEM:: image $IMAGE is not in docker's local store." >&2
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
    # --no-build: building is ./imageBuild.sh's job, never a side effect here.
    runCmnd "${COMPOSE[@]}" up --no-start --no-build || exit 1
    echo
    echo "Next: ./containerManage.sh start"
    ;;
  start)
    requireExists
    runCmnd "${COMPOSE[@]}" start || exit 1
    echo
    echo "Verify with: ./verify.sh"
    ;;
  stop)
    requireExists
    runCmnd "${COMPOSE[@]}" stop || exit 1
    ;;
  restart)
    requireExists
    runCmnd "${COMPOSE[@]}" restart || exit 1
    ;;
  delete)
    if ! containerExists; then
      echo "Container $CONTAINER_NAME does not exist; nothing to delete."
      exit 0
    fi
    echo "  NOTE:: deleting loses the container's writable layer; the image is kept."
    runCmnd "${COMPOSE[@]}" down || exit 1
    ;;
  status)
    if containerExists; then
      echo "  Container state: $(containerState)"
      "${COMPOSE[@]}" ps
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
esac
