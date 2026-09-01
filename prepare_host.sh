#!/bin/sh
# ============================================================
# prepare_host.sh
# Prepares a Proxmox host for Host Inventory for Proxmox by
# checking the complete safe diagnostic-tool set and offering
# to install missing APT packages once.
#
# Version:
#   0.9.2
#
# Usage:
#   sudo ./prepare_host.sh
#   sudo ./prepare_host.sh --install-missing
#   ./prepare_host.sh --no-install
#
# Output:
#   Colorized human-readable preparation status.
#
# Returns:
#   0 when required preparation dependencies are available
#   1 when an approved APT installation fails
#   2 on invalid arguments or missing required dependencies
#
# Dependencies:
#   /bin/sh, standard Debian userland, apt-get for installation
#
# Side Effects:
#   Installs packages only after explicit approval or when
#   --install-missing is supplied. It does not upgrade packages.
# ============================================================
app_name=prepare_host
app_version=0.9.2
app_rc=0
app_install_mode=ask
app_color_mode=auto

# command:package:required|optional
# Packages are limited to diagnostic/userland tools used by the
# collectors. Vendor GPU drivers are intentionally excluded.
app_package_specs="jq:jq:required mokutil:mokutil:optional efibootmgr:efibootmgr:optional gzip:gzip:optional lscpu:util-linux:optional lstopo-no-graphics:hwloc:optional cpupower:linux-cpupower:optional turbostat:linux-cpupower:optional lspci:pciutils:optional ps:procps:optional pgrep:procps:optional swapon:util-linux:optional lsblk:util-linux:optional findmnt:util-linux:optional blkid:util-linux:optional nvme:nvme-cli:optional lvs:lvm2:optional vgs:lvm2:optional pvs:lvm2:optional zpool:zfsutils-linux:optional zfs:zfsutils-linux:optional iostat:sysstat:optional ip:iproute2:optional bridge:iproute2:optional tc:iproute2:optional ethtool:ethtool:optional sensors:lm-sensors:optional dmidecode:dmidecode:optional acpidump:acpica-tools:optional lsusb:usbutils:optional aplay:alsa-utils:optional decode-dimms:i2c-tools:optional mpstat:sysstat:optional rtla:rtla:optional perf:linux-perf:optional"

# ============================================================
# color_init
# Defines semantic ANSI colors.
#
# Version:
#   1.0.0
#
# Usage:
#   color_init
#
# Output:
#   app_color_*
#
# Returns:
#   0
# ============================================================
color_init() {
    ci_enable=0
    [ -n "${NO_COLOR-}" ] && app_color_mode=never
    case "$app_color_mode" in
        always) ci_enable=1 ;;
        never) ci_enable=0 ;;
        auto) [ -t 1 ] || [ -t 2 ] && ci_enable=1 ;;
        *) app_color_mode=auto; [ -t 1 ] || [ -t 2 ] && ci_enable=1 ;;
    esac
    if [ "$ci_enable" -eq 1 ]; then
        app_color_reset=$(printf '\033[0m')
        app_color_dim=$(printf '\033[90m')
        app_color_title=$(printf '\033[1;96m')
        app_color_info=$(printf '\033[96m')
        app_color_ok=$(printf '\033[92m')
        app_color_warn=$(printf '\033[93m')
        app_color_error=$(printf '\033[91m')
        app_color_accent=$(printf '\033[95m')
    else
        app_color_reset=; app_color_dim=; app_color_title=; app_color_info=; app_color_ok=; app_color_warn=; app_color_error=; app_color_accent=
    fi
    return 0
}

# ============================================================
# message
# Prints one semantic status line.
#
# Version:
#   1.0.0
#
# Usage:
#   message role text
#
# Returns:
#   0
# ============================================================
message() {
    msg_role=$1
    shift
    case "$msg_role" in
        title) msg_color=$app_color_title ;;
        info) msg_color=$app_color_info ;;
        ok) msg_color=$app_color_ok ;;
        warn) msg_color=$app_color_warn ;;
        error) msg_color=$app_color_error ;;
        accent) msg_color=$app_color_accent ;;
        *) msg_color=$app_color_dim ;;
    esac
    printf '%s%s%s\n' "$msg_color" "$*" "$app_color_reset"
    return 0
}

# ============================================================
# usage
# Prints command usage.
#
# Version:
#   1.0.0
#
# Returns:
#   0
# ============================================================
usage() {
    cat <<'EOF'
prepare_host.sh - prepare dependencies for all Proxmox inventory collectors

Usage:
  sudo ./prepare_host.sh
  sudo ./prepare_host.sh --install-missing
  ./prepare_host.sh --no-install

Options:
  --install-missing  Install the complete missing package list without a second prompt.
  --no-install       Report missing packages but do not offer installation.
  --color            Force ANSI color.
  --no-color         Disable ANSI color.
  --help             Show help.
  --version          Show version.

Default behavior asks once before installing the aggregated missing package list.
EOF
    return 0
}

# ============================================================
# parse_options
# Parses preparation options.
#
# Version:
#   1.0.0
#
# Returns:
#   0 on success
#   2 on an unknown argument
# ============================================================
parse_options() {
    po_action=run
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --install-missing) app_install_mode=always ;;
            --no-install) app_install_mode=never ;;
            --color) app_color_mode=always ;;
            --no-color) app_color_mode=never ;;
            --help|-h|-\?|/h|/\?) po_action=help ;;
            --version) po_action=version ;;
            *) printf 'ERROR: Unknown argument: %s\n' "$1" >&2; return 2 ;;
        esac
        shift
    done
    return 0
}

# ============================================================
# dependency_scan
# Builds the unique missing package list for the whole suite.
#
# Version:
#   1.0.0
#
# Output:
#   dep_missing_packages
#   dep_missing_required
#   dep_missing_optional
#   dep_missing_map
#
# Returns:
#   0
# ============================================================
dependency_scan() {
    dep_missing_packages=
    dep_missing_required=
    dep_missing_optional=
    dep_missing_map=
    for dep_spec in $app_package_specs; do
        dep_command=${dep_spec%%:*}
        dep_rest=${dep_spec#*:}
        dep_package=${dep_rest%%:*}
        dep_level=${dep_rest#*:}
        command -v "$dep_command" >/dev/null 2>&1 && continue
        case " $dep_missing_packages " in
            *" $dep_package "*) : ;;
            *) dep_missing_packages="${dep_missing_packages}${dep_missing_packages:+ }$dep_package" ;;
        esac
        dep_missing_map="${dep_missing_map}${dep_missing_map:+
}$dep_command -> $dep_package ($dep_level)"
        if [ "$dep_level" = required ]; then
            dep_missing_required="${dep_missing_required}${dep_missing_required:+ }$dep_command"
        else
            dep_missing_optional="${dep_missing_optional}${dep_missing_optional:+ }$dep_command"
        fi
    done
    return 0
}

# ============================================================
# prompt_install
# Asks once whether the aggregated package list may be installed.
#
# Version:
#   1.0.0
#
# Returns:
#   0 when approved
#   1 when declined or noninteractive
# ============================================================
prompt_install() {
    [ -n "$dep_missing_packages" ] || return 1
    [ "$app_install_mode" = always ] && return 0
    [ "$app_install_mode" = never ] && return 1
    if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
        message warn "No interactive terminal is available; installation was not attempted."
        return 1
    fi
    printf '%sInstall all missing collector packages?%s %s[y/N]%s ' "$app_color_warn" "$app_color_reset" "$app_color_accent" "$app_color_reset" > /dev/tty
    IFS= read -r pi_answer < /dev/tty || pi_answer=
    case "$pi_answer" in y|Y|yes|YES|Yes) return 0 ;; *) return 1 ;; esac
}

# ============================================================
# install_packages
# Installs the approved package list with apt-get.
#
# Version:
#   1.0.0
#
# Side Effects:
#   Installs packages. No upgrade/dist-upgrade is performed.
#
# Returns:
#   apt-get return code
#   2 when elevation/APT is unavailable
# ============================================================
install_packages() {
    command -v apt-get >/dev/null 2>&1 || { message error "apt-get is unavailable."; return 2; }
    message info "Installing: $dep_missing_packages"
    if [ "$(id -u 2>/dev/null)" = 0 ]; then
        apt-get install -y $dep_missing_packages
        return $?
    fi
    if command -v sudo >/dev/null 2>&1; then
        sudo apt-get install -y $dep_missing_packages
        return $?
    fi
    message error "Root privileges are required to install packages."
    return 2
}

# ============================================================
# main
# Performs the complete suite dependency preparation.
#
# Version:
#   1.0.0
#
# Returns:
#   0 when required tools are available
#   1 on failed approved installation
#   2 when required tools remain unavailable
# ============================================================
main() {
    case "$po_action" in
        help) usage; return 0 ;;
        version) printf '%s %s\n' "$app_name" "$app_version"; return 0 ;;
    esac
    message title "Host Inventory for Proxmox - Preparation $app_version"
    dependency_scan
    if [ -z "$dep_missing_packages" ]; then
        message ok "All collector diagnostic packages are already available."
        return 0
    fi
    message warn "Missing collector tools:"
    printf '%s%s%s\n' "$app_color_dim" "$dep_missing_map" "$app_color_reset"
    message accent "APT packages: $dep_missing_packages"
    if prompt_install; then
        install_packages || return 1
        dependency_scan
    else
        message dim "Package installation skipped."
    fi
    if [ -n "$dep_missing_required" ]; then
        message error "Required command(s) unavailable: $dep_missing_required"
        message error "The suite cannot run until the required package(s) are installed."
        return 2
    fi
    if [ -n "$dep_missing_optional" ]; then
        message warn "Optional command(s) remain unavailable: $dep_missing_optional"
        message warn "Collectors will record those probes as unavailable."
    else
        message ok "All collector tools are available."
    fi
    message dim "Vendor GPU drivers are intentionally never installed by preparation."
    return 0
}

# ------------------------------ setup ------------------------------
color_init
parse_options "$@"
app_rc=$?
color_init

# ------------------------------- main -------------------------------
if [ "$app_rc" -eq 0 ]; then main; app_rc=$?; fi

# -------------------------------- end -------------------------------
exit "$app_rc"
