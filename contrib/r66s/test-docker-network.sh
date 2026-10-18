#!/bin/sh
# Shell-level checks for the R66S Docker network initializer.
#
# The real service and uci are replaced by stubs: the dockerd init script through
# R66S_DOCKERD_INIT and uci through PATH. The checks cover the commands that are
# sent to uci, the retry contract of the uci-defaults wrapper and the guard that
# keeps a forwarding away from a firewall configuration fw4 could not load.
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
initializer="$script_dir/r66s-docker-network"

work=$(mktemp -d "${TMPDIR:-/tmp}/r66s-docker-network.XXXXXX")
trap 'rm -rf "$work"' EXIT

bin="$work/bin"
state="$work/state"
log="$work/log"
running="$work/dockerd-running"
mkdir -p "$bin"
export R66S_FAKE_STATE="$state" R66S_FAKE_LOG="$log" R66S_FAKE_RUNNING="$running"

fail() {
    echo "test-docker-network: $*" >&2
    exit 1
}

# Minimal uci: one key=value per line, no sections, enough for this script.
cat > "$bin/uci" <<'UCI_EOF'
#!/bin/sh
state=$R66S_FAKE_STATE

while [ "${1-}" = "-q" ]; do
    shift
done
# Log the effective command, without the quiet flag.
printf '%s\n' "$*" >> "$R66S_FAKE_LOG"
cmd=${1-}
[ "$#" -gt 0 ] && shift

key_of() {
    case "$1" in
        *=*) printf '%s\n' "${1%%=*}" ;;
        *) printf '%s\n' "$1" ;;
    esac
}

value_of() {
    awk -v key="$1" '
        { pos = index($0, "=") }
        pos > 0 && substr($0, 1, pos - 1) == key { value = substr($0, pos + 1) }
        END { if (value == "") exit 1; print value }
    ' "$state"
}

case "$cmd" in
    get)
        value_of "${1-}" || exit 1
        ;;
    set)
        awk -v key="$(key_of "${1-}")" -v value="${1#*=}" '
            BEGIN { seen = 0 }
            {
                pos = index($0, "=")
                if (pos > 0 && substr($0, 1, pos - 1) == key) {
                    if (!seen) { print key "=" value; seen = 1 }
                    next
                }
                print
            }
            END { if (!seen) print key "=" value }
        ' "$state" > "$state.new"
        mv "$state.new" "$state"
        ;;
    delete)
        awk -v key="$(key_of "${1-}")" '
            {
                pos = index($0, "=")
                candidate = (pos > 0 ? substr($0, 1, pos - 1) : $0)
                if (candidate == key || substr(candidate, 1, length(key) + 1) == key ".") next
                print
            }
        ' "$state" > "$state.new"
        mv "$state.new" "$state"
        ;;
    add_list)
        printf '%s\n' "${1-}" >> "$state"
        ;;
    del_list)
        grep -Fvx -- "${1-}" "$state" > "$state.new" || :
        mv "$state.new" "$state"
        ;;
    commit)
        ;;
    *)
        echo "stub uci: unsupported command '$cmd'" >&2
        exit 1
        ;;
esac
exit 0
UCI_EOF
chmod 755 "$bin/uci"

# Dockerd's init script only creates the zone while the daemon is stopped.
cat > "$work/dockerd-init" <<'DOCKERD_EOF'
#!/bin/sh
printf 'dockerd-init %s\n' "$*" >> "$R66S_FAKE_LOG"
case "${1-}" in
    running)
        [ -f "$R66S_FAKE_RUNNING" ] && exit 0
        exit 1
        ;;
    uciadd)
        [ -f "$R66S_FAKE_RUNNING" ] && exit 0
        [ -f "$R66S_FAKE_ZONE_STAYS_MISSING" ] && exit 0
        {
            printf 'firewall.docker=docker\n'
            printf 'network.docker=docker\n'
        } >> "$R66S_FAKE_STATE"
        ;;
esac
exit 0
DOCKERD_EOF
chmod 755 "$work/dockerd-init"

reset_fakes() {
    : > "$state"
    : > "$log"
    rm -f "$running" "$work/zone-stays-missing"
    printf 'dockerd.globals=globals\n' >> "$state"
}

run_initializer() {
    PATH="$bin:$PATH" R66S_DOCKERD_INIT="$work/dockerd-init" \
        sh "$initializer"
}

expect_command() {
    grep -Fxq -- "$1" "$log" || fail "uci never received: $1"
}

expect_no_configuration() {
    if grep -Eq '^(set|add_list) (firewall|dockerd)\.' "$log"; then
        fail 'the initializer changed configuration before the zone existed'
    fi
}

count_state() {
    grep -Fc -- "$1" "$state" || :
}

# First boot: the daemon is down, create the zone, then configure around it.
reset_fakes
run_initializer
expect_command 'dockerd-init uciadd'
expect_command 'set firewall.r66s_docker_lan=forwarding'
expect_command 'set firewall.r66s_docker_lan.src=lan'
expect_command 'set firewall.r66s_docker_lan.dest=docker'
expect_command 'set firewall.r66s_docker_wan=forwarding'
expect_command 'set firewall.r66s_docker_wan.src=docker'
expect_command 'set firewall.r66s_docker_wan.dest=wan'
expect_command 'commit firewall'
expect_command 'del_list dockerd.globals.dns=192.168.77.1'
expect_command 'add_list dockerd.globals.dns=192.168.77.1'
expect_command 'commit dockerd'
test "$(count_state 'dockerd.globals.dns=192.168.77.1')" -eq 1

# A retried first boot must not stack a second resolver entry.
run_initializer
test "$(count_state 'dockerd.globals.dns=192.168.77.1')" -eq 1

# The daemon is already running, so uciadd is skipped but the zone is usable.
reset_fakes
touch "$running"
printf 'firewall.docker=docker\nnetwork.docker=docker\n' >> "$state"
run_initializer
if grep -Fxq 'dockerd-init uciadd' "$log"; then
    fail 'uciadd must not run while the daemon is up'
fi
expect_command 'set firewall.r66s_docker_lan.dest=docker'

# Without the zone the script reports and stays for the next boot instead of
# leaving a forwarding that fw4 would refuse to load.
reset_fakes
touch "$running" "$work/zone-stays-missing"
export R66S_FAKE_ZONE_STAYS_MISSING="$work/zone-stays-missing"
if run_initializer; then
    fail 'expected a non-zero status while the Docker zone is missing'
fi
expect_no_configuration

# An image without the dockerd service cannot wire anything either.
reset_fakes
unset R66S_FAKE_ZONE_STAYS_MISSING
if PATH="$bin:$PATH" R66S_DOCKERD_INIT="$work/missing-init" sh "$initializer"; then
    fail 'expected a non-zero status without the dockerd service'
fi
expect_no_configuration

echo 'Docker network initializer checks passed.'
