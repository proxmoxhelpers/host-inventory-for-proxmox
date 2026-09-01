#!/bin/sh
# ============================================================
# collect_guest_runtime_detail.sh
# Collects detailed running-QEMU scheduler, memory residency, context-switch and cgroup pressure evidence.
#
# Version:
#   0.9.2
#
# Usage:
#   sudo ./collect_guest_runtime_detail.sh [--compact]
#   ./collect_guest_runtime_detail.sh --help
#   ./collect_guest_runtime_detail.sh --version
#
# Output:
#   JSON inventory envelope on stdout.
#
# Returns:
#   0 on successful collection
#   2 on invalid arguments or missing required dependencies
#
# Dependencies:
#   Bootstrap: /bin/sh and APT when package installation is approved
#   Runtime: collector-specific tools; missing safe packages are offered in setup
#
# Side Effects:
#   Read-only probing; setup may install explicitly approved APT packages.
#   Temporary files are removed before exit.
# ============================================================

app_name="collect_guest_runtime_detail"
app_version=0.9.2
app_rc=0
app_compact=0
app_package_specs="jq:jq:required ps:procps:optional"

# ============================================================
# Standalone collector runtime
# Common POSIX-shell support embedded in this script so the
# collector can be copied and executed independently.
#
# Runtime Version:
#   1.2.0
#
# Dependencies:
#   Bootstrap: /bin/sh, standard POSIX userland, apt-get when
#              package installation is requested
#   Runtime:   jq plus collector-specific diagnostic tools
#
# Side Effects:
#   May install explicitly approved packages through APT.
#   Creates a private temporary directory and removes it at exit.
# ============================================================
_inv_schema_version=0.5.0
_inv_temp_dir=
_inv_action=run
_inv_color_mode=auto
_inv_color_enabled=0
_inv_install_mode=ask
_inv_summary_file=
app_compact=${app_compact:-0}

# ============================================================
# inv_color_init
# Defines semantic ANSI colors according to output capability.
#
# Version:
#   1.0.0
#
# Usage:
#   inv_color_init
#
# Arguments:
#   None
#
# Output:
#   app_color_* semantic color variables
#
# Returns:
#   0
#
# Notes:
#   NO_COLOR disables ANSI. In auto mode, ANSI is enabled when
#   either stdout or stderr is attached to a terminal.
# ============================================================
inv_color_init() {
    ici_enable=0
    if [ -n "${NO_COLOR-}" ]; then _inv_color_mode=never; fi
    case "$_inv_color_mode" in
        always) ici_enable=1 ;;
        never) ici_enable=0 ;;
        auto) if [ -t 1 ] || [ -t 2 ]; then ici_enable=1; fi ;;
        *) _inv_color_mode=auto; if [ -t 1 ] || [ -t 2 ]; then ici_enable=1; fi ;;
    esac
    _inv_color_enabled=$ici_enable
    if [ "$ici_enable" -eq 1 ]; then
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
# inv_message
# Prints one semantic status message to stderr.
#
# Version:
#   1.0.0
#
# Usage:
#   inv_message role text
#
# Arguments:
#   role  title, info, ok, warn, error, dim, or accent
#   text  message text
#
# Output:
#   Colorized stderr when enabled.
#
# Returns:
#   0
# ============================================================
inv_message() {
    im_role=$1
    shift
    case "$im_role" in
        title) im_color=$app_color_title ;;
        info) im_color=$app_color_info ;;
        ok) im_color=$app_color_ok ;;
        warn) im_color=$app_color_warn ;;
        error) im_color=$app_color_error ;;
        dim) im_color=$app_color_dim ;;
        accent) im_color=$app_color_accent ;;
        *) im_color= ;;
    esac
    printf '%s%s%s\n' "$im_color" "$*" "$app_color_reset" >&2
    return 0
}

# ============================================================
# inv_parse_options
# Parses common collector command-line switches.
#
# Version:
#   1.1.0
#
# Usage:
#   inv_parse_options "$@"
#
# Arguments:
#   --help, -h, -?, /h, /?  request help
#   --version                print collector version
#   --compact                emit compact JSON
#   --summary                collect and print a human-readable summary
#   --summary-file FILE      summarize an existing collector JSON envelope
#   --view                   collect and print a colorized ergonomic view
#   --view-file FILE         render a colorized view from an existing collector JSON envelope
#   --color                  force ANSI color
#   --no-color               disable ANSI color
#   --install-missing        install missing packages without a second prompt
#   --no-install             never offer package installation
#
# Output:
#   _inv_action, app_compact, _inv_color_mode, _inv_install_mode
#
# Returns:
#   0 on success
#   2 on an unknown argument
# ============================================================
inv_parse_options() {
    ipo_arg=
    _inv_action=run
    app_compact=0
    while [ "$#" -gt 0 ]; do
        ipo_arg=$1
        case "$ipo_arg" in
            --help|-h|-\?|/h|/\?) _inv_action=help ;;
            --version) _inv_action=version ;;
            --compact) app_compact=1 ;;
            --summary) _inv_action=summary ;;
            --summary-file)
                shift
                [ "$#" -gt 0 ] || { inv_message error "ERROR: --summary-file requires a JSON file."; return 2; }
                _inv_summary_file=$1
                _inv_action=summary_file
                ;;
            --view) _inv_action=view ;;
            --view-file)
                shift
                [ "$#" -gt 0 ] || { inv_message error "ERROR: --view-file requires a JSON file."; return 2; }
                _inv_summary_file=$1
                _inv_action=view_file
                ;;
            --color) _inv_color_mode=always ;;
            --no-color) _inv_color_mode=never ;;
            --install-missing) _inv_install_mode=always ;;
            --no-install) _inv_install_mode=never ;;
            *) inv_message error "ERROR: Unknown argument: $ipo_arg"; return 2 ;;
        esac
        shift
    done
    return 0
}

# ============================================================
# inv_print_common_usage
# Prints options shared by all standalone collectors.
#
# Version:
#   1.0.0
#
# Usage:
#   inv_print_common_usage
#
# Returns:
#   0
# ============================================================
inv_print_common_usage() {
    printf '\n%sCommon options:%s\n' "$app_color_title" "$app_color_reset"
    printf '  %s--compact%s          Emit compact JSON.\n' "$app_color_accent" "$app_color_reset"
    printf '  %s--summary%s          Collect now and print a human-readable summary instead of JSON.\n' "$app_color_accent" "$app_color_reset"
    printf '  %s--summary-file FILE%s Print a summary from an existing collector JSON file without probing again.\n' "$app_color_accent" "$app_color_reset"
    printf '  %s--color%s            Force ANSI color, including JSON.\n' "$app_color_accent" "$app_color_reset"
    printf '  %s--no-color%s         Disable ANSI color.\n' "$app_color_accent" "$app_color_reset"
    printf '  %s--install-missing%s  Install the listed missing APT packages without a second prompt.\n' "$app_color_accent" "$app_color_reset"
    printf '  %s--no-install%s       Do not offer package installation.\n' "$app_color_accent" "$app_color_reset"
    printf '  %s--help%s             Show help without installing anything.\n' "$app_color_accent" "$app_color_reset"
    printf '  %s--version%s          Show version without installing anything.\n' "$app_color_accent" "$app_color_reset"
    printf '\n%sPackage policy:%s\n' "$app_color_title" "$app_color_reset"
    printf '  Missing safe diagnostic tools are mapped to APT packages. Default mode asks once\n'
    printf '  before installation. Declining optional tools does not prevent collection.\n'
    printf '  Missing required tools prevent collection when they remain unavailable.\n'
    return 0
}

# ============================================================
# inv_dependency_scan
# Detects missing commands and builds the unique APT package list.
#
# Version:
#   1.0.0
#
# Usage:
#   inv_dependency_scan
#
# Arguments:
#   Reads app_package_specs as whitespace-separated
#   command:package:required|optional entries.
#
# Output:
#   _inv_missing_packages, _inv_missing_required,
#   _inv_missing_optional, _inv_missing_map
#
# Returns:
#   0
# ============================================================
inv_dependency_scan() {
    ids_spec=; ids_command=; ids_rest=; ids_package=; ids_level=
    _inv_missing_packages=
    _inv_missing_required=
    _inv_missing_optional=
    _inv_missing_map=
    for ids_spec in ${app_package_specs-}; do
        ids_command=${ids_spec%%:*}
        ids_rest=${ids_spec#*:}
        ids_package=${ids_rest%%:*}
        ids_level=${ids_rest#*:}
        command -v "$ids_command" >/dev/null 2>&1 && continue
        case " $_inv_missing_packages " in *" $ids_package "*) : ;; *) _inv_missing_packages="${_inv_missing_packages}${_inv_missing_packages:+ }$ids_package" ;; esac
        _inv_missing_map="${_inv_missing_map}${_inv_missing_map:+\n}$ids_command -> $ids_package ($ids_level)"
        if [ "$ids_level" = required ]; then _inv_missing_required="${_inv_missing_required}${_inv_missing_required:+ }$ids_command"; else _inv_missing_optional="${_inv_missing_optional}${_inv_missing_optional:+ }$ids_command"; fi
    done
    return 0
}

# ============================================================
# inv_prompt_install
# Asks whether the currently missing APT package list may be installed.
#
# Version:
#   1.0.0
#
# Usage:
#   inv_prompt_install
#
# Output:
#   User prompt on /dev/tty when available.
#
# Returns:
#   0 when installation is approved
#   1 when declined or no interactive terminal is available
# ============================================================
inv_prompt_install() {
    ipi_answer=
    [ -n "$_inv_missing_packages" ] || return 1
    if [ "$_inv_install_mode" = always ]; then return 0; fi
    if [ "$_inv_install_mode" = never ]; then return 1; fi
    if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then inv_message warn "No interactive terminal is available; package installation was not attempted."; return 1; fi
    printf '%sInstall these missing diagnostic packages with APT?%s %s[%sy/N%s] %s' "$app_color_warn" "$app_color_reset" "$app_color_dim" "$app_color_accent" "$app_color_dim" "$app_color_reset" > /dev/tty
    IFS= read -r ipi_answer < /dev/tty || ipi_answer=
    case "$ipi_answer" in y|Y|yes|YES|Yes) return 0 ;; *) return 1 ;; esac
}

# ============================================================
# inv_install_packages
# Installs the approved missing package list using apt-get.
#
# Version:
#   1.0.0
#
# Usage:
#   inv_install_packages
#
# Arguments:
#   Reads _inv_missing_packages.
#
# Output:
#   APT output on the controlling terminal/stdout/stderr.
#
# Returns:
#   apt-get return code, 2 when APT/elevation is unavailable
#
# Side Effects:
#   Installs packages on the host. This function is reached only
#   after explicit consent or --install-missing.
# ============================================================
inv_install_packages() {
    iip_uid=$(id -u 2>/dev/null || printf '%s' 1)
    command -v apt-get >/dev/null 2>&1 || { inv_message error "ERROR: apt-get is unavailable; cannot install: $_inv_missing_packages"; return 2; }
    inv_message info "APT packages requested: $_inv_missing_packages"
    if [ "$iip_uid" -eq 0 ] 2>/dev/null; then
        # Package names are generated internally from app_package_specs.
        apt-get install -y $_inv_missing_packages >&2
        return $?
    fi
    if command -v sudo >/dev/null 2>&1; then
        # sudo remains interactive so the administrator can authenticate normally.
        sudo apt-get install -y $_inv_missing_packages >&2
        return $?
    fi
    inv_message error "ERROR: Package installation requires root privileges. Re-run with sudo or install manually: $_inv_missing_packages"
    return 2
}

# ============================================================
# inv_dependencies_prepare
# Reports missing tools, optionally installs mapped APT packages,
# and verifies required tools after the attempt.
#
# Version:
#   1.0.0
#
# Usage:
#   inv_dependencies_prepare
#
# Returns:
#   0 when all required tools are available
#   2 when one or more required tools remain unavailable
# ============================================================
inv_dependencies_prepare() {
    idp_install_rc=0
    inv_dependency_scan
    [ -n "$_inv_missing_packages" ] || return 0
    inv_message warn "Missing collector tools detected:"
    # %b is deliberate here: _inv_missing_map contains internally generated \n separators.
    printf '%s%b%s\n' "$app_color_dim" "$_inv_missing_map" "$app_color_reset" >&2
    inv_message accent "APT package list: $_inv_missing_packages"
    if inv_prompt_install; then
        inv_install_packages || idp_install_rc=$?
        if [ "$idp_install_rc" -eq 0 ]; then inv_message ok "APT package installation completed."; else inv_message warn "APT returned code $idp_install_rc; collection will re-check required tools."; fi
    else
        inv_message dim "Package installation skipped."
    fi
    inv_dependency_scan
    if [ -n "$_inv_missing_required" ]; then
        inv_message error "ERROR: Required command(s) still unavailable: $_inv_missing_required"
        inv_message error "Install the corresponding package(s) and retry: $_inv_missing_packages"
        return 2
    fi
    if [ -n "$_inv_missing_optional" ]; then inv_message warn "Optional command(s) unavailable; related fields will be recorded as unavailable: $_inv_missing_optional"; fi
    return 0
}

# ============================================================
# inv_initialize
# Prepares dependencies and creates private temporary state.
#
# Version:
#   1.1.0
#
# Usage:
#   inv_initialize
#
# Output:
#   _inv_temp_dir
#
# Returns:
#   0 on success
#   2 when required dependencies or temp creation are unavailable
# ============================================================
inv_initialize() {
    ini_candidate=
    inv_dependencies_prepare || return $?
    command -v mktemp >/dev/null 2>&1 || { inv_message error "ERROR: Required command not found: mktemp (package: coreutils)"; return 2; }
    ini_candidate=$(mktemp -d "${TMPDIR:-/tmp}/pve-inventory.XXXXXX" 2>/dev/null) || { inv_message error "ERROR: Could not create temporary directory."; return 2; }
    _inv_temp_dir=$ini_candidate
    return 0
}

# ============================================================
# inv_cleanup
# Removes temporary state created by inv_initialize.
#
# Version:
#   1.0.0
#
# Usage:
#   inv_cleanup
#
# Returns:
#   0
# ============================================================
inv_cleanup() {
    icu_path=$_inv_temp_dir
    if [ -n "$icu_path" ] && [ -d "$icu_path" ]; then rm -rf -- "$icu_path"; fi
    _inv_temp_dir=
    return 0
}

# ============================================================
# inv_now_iso
# Prints the local timestamp in an ISO-8601-compatible form.
#
# Version:
#   1.0.0
#
# Usage:
#   inv_now_iso
#
# Returns:
#   date return code
# ============================================================
inv_now_iso() {
    date '+%Y-%m-%dT%H:%M:%S%z'
}

# ============================================================
# inv_readlink
# Resolves a symlink/path using readlink when available.
#
# Version:
#   1.1.0
#
# Usage:
#   inv_readlink path
#
# Arguments:
#   path  path to resolve
#
# Output:
#   Resolved path on stdout when possible.
#
# Returns:
#   0 on success
#   1 when unavailable or unresolved
# ============================================================
inv_readlink() {
    irl_path=$1
    command -v readlink >/dev/null 2>&1 || return 1
    [ -L "$irl_path" ] || return 1
    readlink -f -- "$irl_path" 2>/dev/null
}

# ============================================================
# inv_strings_json
# Writes positional arguments as a JSON string array.
#
# Version:
#   1.0.0
#
# Usage:
#   inv_strings_json outputFile [strings...]
#
# Returns:
#   jq return code
# ============================================================
inv_strings_json() {
    isj_output=$1
    shift
    isj_stream=$_inv_temp_dir/strings.$$.jsonl
    : > "$isj_stream" || return 1
    for isj_value do jq -n --arg value "$isj_value" '$value' >> "$isj_stream" || return 1; done
    jq -s '.' "$isj_stream" > "$isj_output"
}

# ============================================================
# inv_command_json
# Executes an optional diagnostic command and records its result.
#
# Version:
#   1.0.0
#
# Usage:
#   inv_command_json outputFile timeoutSeconds command [arguments...]
#
# Output:
#   JSON object with available, rc, timed_out, stdout and stderr.
#
# Returns:
#   0 when the JSON record was written
#   1 on internal serialization failure
# ============================================================
inv_command_json() {
    icj_output=$1
    icj_timeout=$2
    shift 2
    icj_command=${1-}
    icj_stdout=$_inv_temp_dir/command.$$.out
    icj_stderr=$_inv_temp_dir/command.$$.err
    icj_rc=0
    icj_timed_out=false
    : > "$icj_stdout"; : > "$icj_stderr"
    if [ -z "$icj_command" ] || ! command -v "$icj_command" >/dev/null 2>&1; then
        jq -n --arg stderr "${icj_command:-<empty command>} not found" '{available:false,rc:null,timed_out:false,stdout:"",stderr:$stderr}' > "$icj_output"
        return $?
    fi
    if [ "$icj_timeout" -gt 0 ] 2>/dev/null && command -v timeout >/dev/null 2>&1; then timeout "${icj_timeout}s" "$@" > "$icj_stdout" 2> "$icj_stderr"; icj_rc=$?; else "$@" > "$icj_stdout" 2> "$icj_stderr"; icj_rc=$?; fi
    if [ "$icj_rc" -eq 124 ]; then icj_timed_out=true; fi
    jq -n --argjson rc "$icj_rc" --argjson timed_out "$icj_timed_out" --rawfile stdout "$icj_stdout" --rawfile stderr "$icj_stderr" '{available:true,rc:$rc,timed_out:$timed_out,stdout:($stdout|rtrimstr("\n")),stderr:($stderr|rtrimstr("\n"))}' > "$icj_output"
}

# ============================================================
# inv_flat_dir_json
# Serializes readable regular files directly under a directory.
#
# Version:
#   1.0.0
#
# Usage:
#   inv_flat_dir_json outputFile directory [nameRegex]
#
# Returns:
#   0 on success
# ============================================================
inv_flat_dir_json() {
    ifd_output=$1
    ifd_dir=$2
    ifd_regex=${3-}
    ifd_stream=$_inv_temp_dir/flatdir.$$.jsonl
    : > "$ifd_stream" || return 1
    if [ -d "$ifd_dir" ]; then
        for ifd_path in "$ifd_dir"/*; do
            [ -f "$ifd_path" ] || continue
            ifd_name=${ifd_path##*/}
            if [ -n "$ifd_regex" ] && ! printf '%s\n' "$ifd_name" | grep -Eq "$ifd_regex"; then continue; fi
            ifd_value=$(cat -- "$ifd_path" 2>/dev/null) || continue
            jq -n --arg key "$ifd_name" --arg value "$ifd_value" '{($key):$value}' >> "$ifd_stream" || return 1
        done
    fi
    jq -s 'reduce .[] as $item ({}; . * $item)' "$ifd_stream" > "$ifd_output"
}

# ============================================================
# inv_file_map_json
# Serializes named files into one JSON object.
#
# Version:
#   1.0.0
#
# Usage:
#   inv_file_map_json outputFile key=path [key=path...]
#
# Returns:
#   0 on success
# ============================================================
inv_file_map_json() {
    ifm_output=$1
    shift
    ifm_stream=$_inv_temp_dir/filemap.$$.jsonl
    : > "$ifm_stream" || return 1
    for ifm_spec do
        ifm_key=${ifm_spec%%=*}
        ifm_path=${ifm_spec#*=}
        if [ -r "$ifm_path" ]; then
            ifm_value=$(cat -- "$ifm_path" 2>/dev/null)
            jq -n --arg key "$ifm_key" --arg value "$ifm_value" '{($key):$value}' >> "$ifm_stream" || return 1
        else
            jq -n --arg key "$ifm_key" '{($key):null}' >> "$ifm_stream" || return 1
        fi
    done
    jq -s 'reduce .[] as $item ({}; . * $item)' "$ifm_stream" > "$ifm_output"
}

# ============================================================
# inv_emit
# Emits the standard collector JSON envelope with terminal-aware color.
#
# Version:
#   1.1.0
#
# Usage:
#   inv_emit collectorName dataFile notesFile errorsFile
#
# Output:
#   Collector envelope on stdout. ANSI is used only when explicitly
#   forced or when stdout is a terminal. Redirected output is plain JSON.
#
# Returns:
#   jq return code
# ============================================================
inv_emit() {
    iem_collector=$1
    iem_data=$2
    iem_notes=$3
    iem_errors=$4
    iem_time=$(inv_now_iso)
    iem_host=$(hostname 2>/dev/null || uname -n)
    iem_color=0
    if [ "$_inv_color_mode" = always ]; then iem_color=1; elif [ "$_inv_color_mode" = auto ] && [ -t 1 ]; then iem_color=1; fi
    if [ "$app_compact" -eq 1 ]; then
        if [ "$iem_color" -eq 1 ]; then iem_flags=-cC; else iem_flags=-cM; fi
    else
        if [ "$iem_color" -eq 1 ]; then iem_flags=-C; else iem_flags=-M; fi
    fi
    jq "$iem_flags" -n --arg schema "$_inv_schema_version" --arg collector "$iem_collector" --arg collected_at "$iem_time" --arg hostname "$iem_host" --slurpfile data "$iem_data" --slurpfile notes "$iem_notes" --slurpfile errors "$iem_errors" '{schema_version:$schema,collector:$collector,collected_at:$collected_at,hostname:$hostname,data:$data[0],notes:$notes[0],errors:$errors[0]}'
}


# ============================================================
# inv_summary_validate_file
# Validates a saved collector envelope before summary rendering.
#
# Version:
#   1.0.0
#
# Usage:
#   inv_summary_validate_file path
#
# Arguments:
#   path  collector-envelope JSON file
#
# Returns:
#   0 when the file is readable and has the collector envelope shape
#   2 otherwise
# ============================================================
inv_summary_validate_file() {
    isvf_file=$1
    [ -n "$isvf_file" ] && [ -r "$isvf_file" ] || { inv_message error "ERROR: Summary JSON is not readable: $isvf_file"; return 2; }
    jq -e 'type=="object" and (.collector|type=="string") and (.data|type=="object") and (.notes|type=="array") and (.errors|type=="array")' "$isvf_file" >/dev/null 2>&1 || { inv_message error "ERROR: Invalid collector envelope: $isvf_file"; return 2; }
    return 0
}

# ============================================================
# inv_summary_header
# Prints the common summary heading and collection identity.
#
# Version:
#   1.0.0
#
# Usage:
#   inv_summary_header jsonFile title
#
# Returns:
#   0
# ============================================================
inv_summary_header() {
    ish_file=$1
    ish_title=$2
    ish_host=$(jq -r '.hostname // "unknown"' "$ish_file")
    ish_time=$(jq -r '.collected_at // "unknown"' "$ish_file")
    printf '%s%s%s\n' "$app_color_title" "$ish_title" "$app_color_reset"
    printf '%s%-22s%s %s\n' "$app_color_accent" "Host:" "$app_color_reset" "$ish_host"
    printf '%s%-22s%s %s\n' "$app_color_accent" "Collected:" "$app_color_reset" "$ish_time"
    return 0
}

# ============================================================
# inv_summary_section
# Prints a human-readable summary section heading.
#
# Version:
#   1.0.0
#
# Usage:
#   inv_summary_section text
#
# Returns:
#   0
# ============================================================
inv_summary_section() {
    printf '\n%s%s%s\n' "$app_color_info" "$1" "$app_color_reset"
    return 0
}

# ============================================================
# inv_summary_field
# Prints one label/value summary field.
#
# Version:
#   1.0.0
#
# Usage:
#   inv_summary_field label value
#
# Returns:
#   0
# ============================================================
inv_summary_field() {
    isf_label=$1
    isf_value=$2
    [ -n "$isf_value" ] || isf_value="unknown"
    printf '%s%-22s%s %s\n' "$app_color_accent" "$isf_label:" "$app_color_reset" "$isf_value"
    return 0
}

# ============================================================
# inv_summary_item
# Prints one indented summary item.
#
# Version:
#   1.0.0
#
# Usage:
#   inv_summary_item text
#
# Returns:
#   0
# ============================================================
inv_summary_item() {
    printf '  %s-%s %s\n' "$app_color_dim" "$app_color_reset" "$1"
    return 0
}

# ============================================================
# inv_summary_footer
# Prints note/error counts from a collector envelope.
#
# Version:
#   1.0.0
#
# Usage:
#   inv_summary_footer jsonFile
#
# Returns:
#   0
# ============================================================
inv_summary_footer() {
    isfo_file=$1
    isfo_notes=$(jq -r '.notes | length' "$isfo_file")
    isfo_errors=$(jq -r '.errors | length' "$isfo_file")
    inv_summary_section "Collector metadata"
    inv_summary_field "Notes" "$isfo_notes"
    if [ "$isfo_errors" -gt 0 ] 2>/dev/null; then
        printf '%s%-22s%s %s\n' "$app_color_error" "Errors:" "$app_color_reset" "$isfo_errors"
    else
        inv_summary_field "Errors" "$isfo_errors"
    fi
    return 0
}


# ============================================================
# inv_view_divider
# Prints a horizontal divider for human-readable collector views.
#
# Version:
#   1.0.0
#
# Returns:
#   0
# ============================================================
inv_view_divider() {
    printf '%s%s%s\n' "$app_color_dim" '======================================================================' "$app_color_reset"
    return 0
}

# ============================================================
# inv_view_header
# Prints the common view heading and collection identity.
#
# Version:
#   1.0.0
#
# Usage:
#   inv_view_header jsonFile title
#
# Returns:
#   0
# ============================================================
inv_view_header() {
    ivh_file=$1
    ivh_title=$2
    ivh_host=$(jq -r '.hostname // "unknown"' "$ivh_file")
    ivh_time=$(jq -r '.collected_at // "unknown"' "$ivh_file")
    inv_view_divider
    printf '%s%s%s\n' "$app_color_title" "$ivh_title" "$app_color_reset"
    inv_view_divider
    inv_view_kv "Host" "$ivh_host"
    inv_view_kv "Collected" "$ivh_time"
    return 0
}

# ============================================================
# inv_view_section
# Prints one major view section heading.
#
# Version:
#   1.0.0
#
# Usage:
#   inv_view_section text
#
# Returns:
#   0
# ============================================================
inv_view_section() {
    printf '\n%s%s%s\n' "$app_color_info" "$1" "$app_color_reset"
    return 0
}

# ============================================================
# inv_view_subsection
# Prints one minor view section heading.
#
# Version:
#   1.0.0
#
# Usage:
#   inv_view_subsection text
#
# Returns:
#   0
# ============================================================
inv_view_subsection() {
    printf '%s%s%s\n' "$app_color_warn" "$1" "$app_color_reset"
    return 0
}

# ============================================================
# inv_view_kv
# Prints one aligned key/value line for a collector view.
#
# Version:
#   1.0.0
#
# Usage:
#   inv_view_kv label value
#
# Returns:
#   0
# ============================================================
inv_view_kv() {
    ivk_label=$1
    ivk_value=$2
    [ -n "$ivk_value" ] || ivk_value="unknown"
    printf '  %s%-24s%s %s\n' "$app_color_accent" "$ivk_label:" "$app_color_reset" "$ivk_value"
    return 0
}

# ============================================================
# inv_view_item
# Prints one indented list item in a collector view.
#
# Version:
#   1.0.0
#
# Usage:
#   inv_view_item text
#
# Returns:
#   0
# ============================================================
inv_view_item() {
    printf '    %s-%s %s\n' "$app_color_dim" "$app_color_reset" "$1"
    return 0
}

# ============================================================
# inv_view_metadata
# Prints notes and errors for a collector envelope.
#
# Version:
#   1.0.0
#
# Usage:
#   inv_view_metadata jsonFile
#
# Returns:
#   0
# ============================================================
inv_view_metadata() {
    ivm_file=$1
    ivm_notes=$(jq -r '.notes | length' "$ivm_file")
    ivm_errors=$(jq -r '.errors | length' "$ivm_file")
    inv_view_section "Collector metadata"
    inv_view_kv "Notes" "$ivm_notes"
    if [ "$ivm_notes" -gt 0 ] 2>/dev/null; then
        jq -r '.notes[]' "$ivm_file" | while IFS= read -r ivm_note; do
            inv_view_item "$ivm_note"
        done
    fi
    inv_view_kv "Errors" "$ivm_errors"
    if [ "$ivm_errors" -gt 0 ] 2>/dev/null; then
        jq -r '.errors[]' "$ivm_file" | while IFS= read -r ivm_error; do
            printf '    %s-%s %s\n' "$app_color_error" "$app_color_reset" "$ivm_error"
        done
    fi
    return 0
}

# ============================================================
# usage
# Prints collector-specific help.
# Version: 1.0.0
# ============================================================
usage() {
    cat <<'EOF'
collect_guest_runtime_detail.sh - collect detailed running-QEMU scheduler, memory and cgroup evidence

Usage:
  ./collect_guest_runtime_detail.sh [--compact|--summary|--view]
  ./collect_guest_runtime_detail.sh --help
  ./collect_guest_runtime_detail.sh --version

The collector is read-only. Unavailable optional facilities remain unavailable
rather than being inferred.
EOF
    inv_print_common_usage
    return 0
}

collect_guest_runtime_detail() {
    cgd_dir=$_inv_temp_dir/guest-runtime-detail
    mkdir -p "$cgd_dir" || return 1
    cgd_stream="$cgd_dir/vms.jsonl"
    : > "$cgd_stream" || return 1

    for cgd_pidfile in /run/qemu-server/[0-9]*.pid; do
        [ -f "$cgd_pidfile" ] || continue
        cgd_vmid=${cgd_pidfile##*/}
        cgd_vmid=${cgd_vmid%.pid}
        cgd_pid=$(cat "$cgd_pidfile" 2>/dev/null)
        case "$cgd_pid" in *[!0-9]*|"") continue ;; esac
        [ -d "/proc/$cgd_pid" ] || continue

        cgd_status="/proc/$cgd_pid/status"
        cgd_sched="/proc/$cgd_pid/sched"
        cgd_cpus=$(awk -F: '$1=="Cpus_allowed_list"{gsub(/^[ \t]+/,"",$2);print $2}' "$cgd_status" 2>/dev/null)
        cgd_vol=$(awk -F: '$1=="voluntary_ctxt_switches"{gsub(/[ \t]/,"",$2);print $2}' "$cgd_status" 2>/dev/null)
        cgd_invol=$(awk -F: '$1=="nonvoluntary_ctxt_switches"{gsub(/[ \t]/,"",$2);print $2}' "$cgd_status" 2>/dev/null)
        cgd_policy=$(awk '$1=="policy"{print $3}' "$cgd_sched" 2>/dev/null)
        cgd_prio=$(awk '$1=="prio"{print $3}' "$cgd_sched" 2>/dev/null)
        cgd_migrations=$(awk '$1=="se.nr_migrations"{print $3}' "$cgd_sched" 2>/dev/null)
        cgd_schedstat=$(cat "/proc/$cgd_pid/schedstat" 2>/dev/null)
        cgd_cgroup_raw=$(cat "/proc/$cgd_pid/cgroup" 2>/dev/null)
        cgd_cgroup_path=$(printf '%s\n' "$cgd_cgroup_raw" | awk -F: '$1=="0"{print $3;exit}')
        cgd_cgroup_dir=/sys/fs/cgroup$cgd_cgroup_path

        cgd_rss=$(awk '$1=="Rss:"{print $2}' "/proc/$cgd_pid/smaps_rollup" 2>/dev/null)
        cgd_pss=$(awk '$1=="Pss:"{print $2}' "/proc/$cgd_pid/smaps_rollup" 2>/dev/null)
        cgd_anon=$(awk '$1=="Anonymous:"{print $2}' "/proc/$cgd_pid/smaps_rollup" 2>/dev/null)
        cgd_ahp=$(awk '$1=="AnonHugePages:"{print $2}' "/proc/$cgd_pid/smaps_rollup" 2>/dev/null)
        cgd_locked=$(awk '$1=="Locked:"{print $2}' "/proc/$cgd_pid/smaps_rollup" 2>/dev/null)
        cgd_numa=$(cat "/proc/$cgd_pid/numa_maps" 2>/dev/null)

        cgd_tasks="$cgd_dir/tasks.$cgd_pid.jsonl"
        : > "$cgd_tasks" || return 1
        for cgd_taskdir in /proc/"$cgd_pid"/task/[0-9]*; do
            [ -d "$cgd_taskdir" ] || continue
            cgd_tid=${cgd_taskdir##*/}
            cgd_comm=$(cat "$cgd_taskdir/comm" 2>/dev/null)
            cgd_tstatus="$cgd_taskdir/status"
            cgd_tsched="$cgd_taskdir/sched"
            cgd_tcpus=$(awk -F: '$1=="Cpus_allowed_list"{gsub(/^[ \t]+/,"",$2);print $2}' "$cgd_tstatus" 2>/dev/null)
            cgd_tvol=$(awk -F: '$1=="voluntary_ctxt_switches"{gsub(/[ \t]/,"",$2);print $2}' "$cgd_tstatus" 2>/dev/null)
            cgd_tinvol=$(awk -F: '$1=="nonvoluntary_ctxt_switches"{gsub(/[ \t]/,"",$2);print $2}' "$cgd_tstatus" 2>/dev/null)
            cgd_tpolicy=$(awk '$1=="policy"{print $3}' "$cgd_tsched" 2>/dev/null)
            cgd_tprio=$(awk '$1=="prio"{print $3}' "$cgd_tsched" 2>/dev/null)
            cgd_tmig=$(awk '$1=="se.nr_migrations"{print $3}' "$cgd_tsched" 2>/dev/null)
            cgd_tstat=$(cat "$cgd_taskdir/schedstat" 2>/dev/null)
            cgd_procstat=$(cat "$cgd_taskdir/stat" 2>/dev/null | sed -E 's/^[0-9]+ \(.*\) //')
            cgd_minflt=$(printf '%s\n' "$cgd_procstat" | awk '{print $8}')
            cgd_majflt=$(printf '%s\n' "$cgd_procstat" | awk '{print $10}')
            cgd_delayticks=$(printf '%s\n' "$cgd_procstat" | awk '{print $40}')
            cgd_io=$(cat "$cgd_taskdir/io" 2>/dev/null)
            cgd_psr=$(ps -o psr= -p "$cgd_tid" 2>/dev/null | tr -d ' ')
            jq -n --arg tid "$cgd_tid" --arg comm "$cgd_comm" --arg cpus "$cgd_tcpus" \
              --arg vol "$cgd_tvol" --arg invol "$cgd_tinvol" --arg policy "$cgd_tpolicy" \
              --arg prio "$cgd_tprio" --arg migrations "$cgd_tmig" --arg schedstat "$cgd_tstat" \
              --arg psr "$cgd_psr" --arg minflt "$cgd_minflt" --arg majflt "$cgd_majflt" \
              --arg delayticks "$cgd_delayticks" --arg io "$cgd_io" '
              {tid:($tid|tonumber),comm:$comm,cpus_allowed_list:$cpus,
               current_cpu:(try ($psr|tonumber) catch null),
               voluntary_context_switches:(try ($vol|tonumber) catch null),
               involuntary_context_switches:(try ($invol|tonumber) catch null),
               scheduler_policy:(try ($policy|tonumber) catch null),
               scheduler_prio:(try ($prio|tonumber) catch null),
               migrations:(try ($migrations|tonumber) catch null),
               minor_faults:(try ($minflt|tonumber) catch null),major_faults:(try ($majflt|tonumber) catch null),
               delayacct_blkio_ticks:(try ($delayticks|tonumber) catch null),io_raw:$io,
               schedstat_raw:$schedstat}' >> "$cgd_tasks" || return 1
        done
        jq -s '.' "$cgd_tasks" > "$cgd_dir/tasks.$cgd_pid.json" || return 1

        cgd_cpu_stat=$(cat "$cgd_cgroup_dir/cpu.stat" 2>/dev/null)
        cgd_cpu_pressure=$(cat "$cgd_cgroup_dir/cpu.pressure" 2>/dev/null)
        cgd_mem_current=$(cat "$cgd_cgroup_dir/memory.current" 2>/dev/null)
        cgd_mem_events=$(cat "$cgd_cgroup_dir/memory.events" 2>/dev/null)
        cgd_mem_pressure=$(cat "$cgd_cgroup_dir/memory.pressure" 2>/dev/null)
        cgd_mem_swap=$(cat "$cgd_cgroup_dir/memory.swap.current" 2>/dev/null)
        cgd_io_stat=$(cat "$cgd_cgroup_dir/io.stat" 2>/dev/null)
        cgd_io_pressure=$(cat "$cgd_cgroup_dir/io.pressure" 2>/dev/null)
        cgd_io_weight=$(cat "$cgd_cgroup_dir/io.weight" 2>/dev/null)
        cgd_io_max=$(cat "$cgd_cgroup_dir/io.max" 2>/dev/null)

        jq -n --arg vmid "$cgd_vmid" --arg pid "$cgd_pid" --arg cpus "$cgd_cpus" \
          --arg vol "$cgd_vol" --arg invol "$cgd_invol" --arg policy "$cgd_policy" \
          --arg prio "$cgd_prio" --arg migrations "$cgd_migrations" --arg schedstat "$cgd_schedstat" \
          --arg rss "$cgd_rss" --arg pss "$cgd_pss" --arg anon "$cgd_anon" --arg ahp "$cgd_ahp" \
          --arg locked "$cgd_locked" --arg numa "$cgd_numa" --arg cgroup_path "$cgd_cgroup_path" \
          --arg cpu_stat "$cgd_cpu_stat" --arg cpu_pressure "$cgd_cpu_pressure" \
          --arg mem_current "$cgd_mem_current" --arg mem_events "$cgd_mem_events" \
          --arg mem_pressure "$cgd_mem_pressure" --arg mem_swap "$cgd_mem_swap" \
          --arg io_stat "$cgd_io_stat" --arg io_pressure "$cgd_io_pressure" \
          --arg io_weight "$cgd_io_weight" --arg io_max "$cgd_io_max" \
          --slurpfile tasks "$cgd_dir/tasks.$cgd_pid.json" '
          {vmid:$vmid,pid:($pid|tonumber),
           process:{cpus_allowed_list:$cpus,
             voluntary_context_switches:(try ($vol|tonumber) catch null),
             involuntary_context_switches:(try ($invol|tonumber) catch null),
             scheduler_policy:(try ($policy|tonumber) catch null),
             scheduler_prio:(try ($prio|tonumber) catch null),
             migrations:(try ($migrations|tonumber) catch null),schedstat_raw:$schedstat},
           memory:{rss_kb:(try ($rss|tonumber) catch null),pss_kb:(try ($pss|tonumber) catch null),
             anonymous_kb:(try ($anon|tonumber) catch null),anon_huge_pages_kb:(try ($ahp|tonumber) catch null),
             locked_kb:(try ($locked|tonumber) catch null),numa_maps_raw:$numa},
           cgroup:{path:($cgroup_path|select(length>0)),cpu_stat:$cpu_stat,cpu_pressure:$cpu_pressure,
             memory_current:(try ($mem_current|tonumber) catch null),memory_events:$mem_events,
             memory_pressure:$mem_pressure,memory_swap_current:(try ($mem_swap|tonumber) catch null),
             io_stat:$io_stat,io_pressure:$io_pressure,io_weight:$io_weight,io_max:$io_max},
           tasks:$tasks[0]}' >> "$cgd_stream" || return 1
    done

    jq -s '.' "$cgd_stream" > "$cgd_dir/vms.json" || return 1
    cgd_delay=$(cat /proc/sys/kernel/task_delayacct 2>/dev/null)
    jq -n --arg delay "$cgd_delay" --slurpfile vms "$cgd_dir/vms.json" \
      '{task_delayacct:(try ($delay|tonumber) catch null),qemu_vms:$vms[0],qemu_count:($vms[0]|length)}' \
      > "$cgd_dir/data.json" || return 1
    inv_strings_json "$cgd_dir/notes.json" \
      "QEMU scheduler/memory/cgroup evidence is point-in-time and can change immediately after collection." \
      "Task delay accounting is observed only; the collector does not enable it." || return 1
    inv_strings_json "$cgd_dir/errors.json" || return 1
    inv_emit guest-runtime-detail "$cgd_dir/data.json" "$cgd_dir/notes.json" "$cgd_dir/errors.json"
}

print_guest_runtime_detail_view() {
    f=$1; inv_summary_validate_file "$f" || return $?
    inv_view_header "$f" "Guest Runtime Scheduler / Memory Detail View"
    inv_view_kv "QEMU processes" "$(jq -r '.data.qemu_count // 0' "$f")"
    inv_view_kv "Task delayacct" "$(jq -r '.data.task_delayacct // "unknown"' "$f")"
    jq -r '.data.qemu_vms[]? | [.vmid,.pid,(.process.cpus_allowed_list//"unknown"),
      (.memory.rss_kb//"unknown"),(.memory.anon_huge_pages_kb//"unknown"),(.tasks|length)]|@tsv' "$f" |
    while IFS="$(printf '\t')" read -r vmid pid cpus rss ahp tasks; do
        inv_view_section "VM $vmid / PID $pid"
        inv_view_kv "Allowed CPUs" "$cpus"
        inv_view_kv "RSS" "$rss kB"
        inv_view_kv "AnonHugePages" "$ahp kB"
        inv_view_kv "Threads" "$tasks"
    done
    inv_view_metadata "$f"
}

# ============================================================
# print_guest_runtime_detail_summary
# Factual human-readable summary.
# Version: 1.0.0
# ============================================================
print_guest_runtime_detail_summary() { print_guest_runtime_detail_view "$1"; }

# ============================================================
# main
# ============================================================
main() {
    case "$_inv_action" in
        help) usage; return 0 ;;
        version) printf '%s %s\n' "$app_name" "$app_version"; return 0 ;;
        summary_file|view_file)
            command -v jq >/dev/null 2>&1 || { inv_message error "ERROR: jq is required to render views and summaries."; return 2; }
            print_guest_runtime_detail_view "$_inv_summary_file"
            return $?
            ;;
    esac
    inv_message title "Host Inventory for Proxmox - $app_name $app_version"
    inv_initialize || return $?
    inv_message info "Collecting host state..."
    if [ "$_inv_action" = summary ] || [ "$_inv_action" = view ]; then
        main_summary_file=$_inv_temp_dir/collect_guest_runtime_detail.summary-source.json
        collect_guest_runtime_detail > "$main_summary_file" || return $?
        print_guest_runtime_detail_view "$main_summary_file"
        return $?
    fi
    collect_guest_runtime_detail
}

# ------------------------------ setup ------------------------------
inv_color_init
inv_parse_options "$@"
app_rc=$?
inv_color_init

# ------------------------------- main -------------------------------
if [ "$app_rc" -eq 0 ]; then main; app_rc=$?; fi

# -------------------------------- end -------------------------------
inv_cleanup
exit "$app_rc"
