#!/bin/sh
# ============================================================
# collect_gpu_vfio.sh
# Collects GPU devices, sibling functions, driver/VFIO binding and power-state evidence.
#
# Version:
#   0.9.2
#
# Usage:
#   sudo ./collect_gpu_vfio.sh [--compact]
#   ./collect_gpu_vfio.sh --help
#   ./collect_gpu_vfio.sh --version
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

app_name="collect_gpu_vfio"
app_version=0.9.2
app_rc=0
app_compact=0
app_package_specs="jq:jq:required lspci:pciutils:optional"

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
#
# Version: 1.0.0
# Returns: 0
# ============================================================
usage() {
    cat <<'EOF'
collect_gpu_vfio.sh - collect GPU, multifunction-device and VFIO binding state
Usage: ./collect_gpu_vfio.sh [--compact|--help|--version]
EOF
    inv_print_common_usage
    return 0
}

# ============================================================
# collect_gpu_vfio
# Collects display-class PCI devices, sibling functions and VFIO config evidence.
#
# Version:
#   1.0.0
#
# Returns:
#   0 on success
#   1 on serialization failure
# ============================================================
collect_gpu_vfio() {
    cgv_dir=$_inv_temp_dir/gpu-vfio
    cgv_gpu_stream=$cgv_dir/gpus.jsonl
    mkdir -p "$cgv_dir" || return 1
    : > "$cgv_gpu_stream"
    for cgv_dev in /sys/bus/pci/devices/*; do
        [ -d "$cgv_dev" ] || continue
        cgv_class=$(cat "$cgv_dev/class" 2>/dev/null)
        case "$cgv_class" in 0x0300*|0x0302*) ;; *) continue ;; esac
        cgv_bdf=${cgv_dev##*/}
        cgv_slot=${cgv_bdf%.*}
        cgv_driver=$(inv_readlink "$cgv_dev/driver" 2>/dev/null); cgv_driver=${cgv_driver##*/}
        cgv_group_path=$(inv_readlink "$cgv_dev/iommu_group" 2>/dev/null); cgv_group=${cgv_group_path##*/}
        cgv_sib_stream=$cgv_dir/siblings.jsonl
        : > "$cgv_sib_stream"
        for cgv_sib in /sys/bus/pci/devices/"$cgv_slot".*; do
            [ -d "$cgv_sib" ] || continue
            cgv_sib_driver=$(inv_readlink "$cgv_sib/driver" 2>/dev/null); cgv_sib_driver=${cgv_sib_driver##*/}
            cgv_sib_group_path=$(inv_readlink "$cgv_sib/iommu_group" 2>/dev/null); cgv_sib_group=${cgv_sib_group_path##*/}
            jq -n --arg bdf "${cgv_sib##*/}" --arg class "$(cat "$cgv_sib/class" 2>/dev/null)" --arg vendor "$(cat "$cgv_sib/vendor" 2>/dev/null)" --arg device "$(cat "$cgv_sib/device" 2>/dev/null)" --arg driver "$cgv_sib_driver" --arg iommu_group "$cgv_sib_group" '{bdf:$bdf,class:$class,vendor:$vendor,device:$device,driver:(if $driver=="" then null else $driver end),iommu_group:(if $iommu_group=="" then null else $iommu_group end)}' >> "$cgv_sib_stream" || return 1
        done
        jq -s '.' "$cgv_sib_stream" > "$cgv_dir/siblings.json" || return 1
        if [ -e "$cgv_dev/rom" ]; then cgv_rom=true; else cgv_rom=false; fi
        jq -n --arg bdf "$cgv_bdf" --arg vendor "$(cat "$cgv_dev/vendor" 2>/dev/null)" --arg device "$(cat "$cgv_dev/device" 2>/dev/null)" --arg subsystem_vendor "$(cat "$cgv_dev/subsystem_vendor" 2>/dev/null)" --arg subsystem_device "$(cat "$cgv_dev/subsystem_device" 2>/dev/null)" --arg driver "$cgv_driver" --arg iommu_group "$cgv_group" --arg boot_vga "$(cat "$cgv_dev/boot_vga" 2>/dev/null)" --arg power_runtime_status "$(cat "$cgv_dev/power/runtime_status" 2>/dev/null)" --arg power_control "$(cat "$cgv_dev/power/control" 2>/dev/null)" --argjson rom_present "$cgv_rom" --slurpfile siblings "$cgv_dir/siblings.json" '{bdf:$bdf,vendor:$vendor,device:$device,subsystem_vendor:$subsystem_vendor,subsystem_device:$subsystem_device,driver:(if $driver=="" then null else $driver end),iommu_group:(if $iommu_group=="" then null else $iommu_group end),slot_functions:$siblings[0],rom_present:$rom_present,boot_vga:$boot_vga,power_runtime_status:$power_runtime_status,power_control:$power_control}' >> "$cgv_gpu_stream" || return 1
    done
    jq -s '.' "$cgv_gpu_stream" > "$cgv_dir/gpus.json" || return 1
    inv_command_json "$cgv_dir/vfio_config.json" 8 sh -c "grep -RnsHE '(^|[[:space:]])(options[[:space:]]+vfio-pci|vfio|blacklist[[:space:]]+(nouveau|nvidia|amdgpu|radeon))' /etc/modprobe.d /etc/modules /etc/modules-load.d 2>/dev/null || true" || return 1
    inv_command_json "$cgv_dir/lspci.json" 10 sh -c "lspci -Dnnk | grep -A4 -Ei 'VGA|3D controller|Display controller|Audio device' || true" || return 1
    inv_command_json "$cgv_dir/nvidia.json" 15 nvidia-smi -q || return 1
    if [ -d /sys/module/vfio_pci ]; then cgv_vfio_loaded=true; else cgv_vfio_loaded=false; fi
    inv_flat_dir_json "$cgv_dir/vfio_params.json" /sys/module/vfio_pci/parameters || return 1
    jq -n --argjson vfio_loaded "$cgv_vfio_loaded" --arg vga_arbiter "$(cat /proc/vga_arbiter/vga_arbiter 2>/dev/null)" --slurpfile gpus "$cgv_dir/gpus.json" --slurpfile params "$cgv_dir/vfio_params.json" --slurpfile config "$cgv_dir/vfio_config.json" --slurpfile lspci "$cgv_dir/lspci.json" --slurpfile nvidia "$cgv_dir/nvidia.json" '{gpus:$gpus[0],vfio_module_loaded:$vfio_loaded,vfio_pci_parameters:$params[0],vfio_related_configuration:$config[0],vga_arbiter:$vga_arbiter,raw:{lspci_display_audio:$lspci[0],nvidia_smi:$nvidia[0]}}' > "$cgv_dir/data.json" || return 1
    inv_strings_json "$cgv_dir/notes.json" || return 1
    inv_strings_json "$cgv_dir/errors.json" || return 1
    inv_emit gpu-vfio "$cgv_dir/data.json" "$cgv_dir/notes.json" "$cgv_dir/errors.json"
}



# ============================================================
# print_gpu_vfio_view
# Presents a colorized GPU / VFIO view.
#
# Version:
#   1.1.0
# ============================================================
print_gpu_vfio_view() {
    pgvv_file=$1
    inv_summary_validate_file "$pgvv_file" || return $?
    inv_view_header "$pgvv_file" "GPU / VFIO View"

    inv_view_section "Overview"
    inv_view_kv "GPU count" "$(jq -r '.data.gpus|length' "$pgvv_file")"
    inv_view_kv "vfio-pci loaded" "$(jq -r '.data.vfio_module_loaded|tostring' "$pgvv_file")"
    inv_view_kv "VFIO config probe" "rc=$(jq -r '.data.vfio_related_configuration.rc // "unavailable"' "$pgvv_file")"

    jq -r '.data.gpus | sort_by(.bdf)[] | [.bdf,.vendor,.device,(.driver//"unbound"),(.iommu_group//"none"),(.boot_vga//"?"),(.rom_present|tostring),(.power_runtime_status//"?"),(.power_control//"?")] | @tsv' "$pgvv_file" |
    while IFS="$(printf '\t')" read -r pgvv_bdf pgvv_vendor pgvv_device pgvv_driver pgvv_group pgvv_boot pgvv_rom pgvv_power pgvv_control; do
        inv_view_section "GPU $pgvv_bdf"
        inv_view_kv "PCI ID" "$pgvv_vendor:$pgvv_device"
        inv_view_kv "Driver" "$pgvv_driver"
        inv_view_kv "IOMMU group" "$pgvv_group"
        inv_view_kv "Boot VGA" "$pgvv_boot"
        inv_view_kv "ROM exposed" "$pgvv_rom"
        inv_view_kv "Runtime power" "$pgvv_power / control=$pgvv_control"
    done

    inv_view_section "Multifunction slot functions"
    jq -r '.data.gpus[].slot_functions[] | [.bdf,.class,.vendor,.device,(.driver//"unbound"),(.iommu_group//"none")] | @tsv' "$pgvv_file" |
    while IFS="$(printf '\t')" read -r pgvv_bdf pgvv_class pgvv_vendor pgvv_device pgvv_driver pgvv_group; do
        inv_view_item "$pgvv_bdf class=$pgvv_class id=$pgvv_vendor:$pgvv_device driver=$pgvv_driver group=$pgvv_group"
    done

    inv_view_section "Host GPU tooling"
    inv_view_kv "nvidia-smi" "rc=$(jq -r '.data.raw.nvidia_smi.rc // "unavailable"' "$pgvv_file")"

    inv_view_metadata "$pgvv_file"
}

# ============================================================
# print_gpu_vfio_summary
# Presents GPU functions, VFIO binding and GPU power state.
#
# Version:
#   1.1.0
#
# Usage:
#   print_gpu_vfio_summary collectorEnvelope.json
#
# Returns:
#   0 on success
#   2 when the input envelope is invalid
# ============================================================
print_gpu_vfio_summary() {
    print_gpu_vfio_view "$1"
}


# ============================================================
# main
# Dispatches common actions and collection.
#
# Version: 1.0.0
# Returns: collector return code
# ============================================================
main() {
    case "$_inv_action" in
        help) usage; return 0 ;;
        version) printf '%s %s\n' "$app_name" "$app_version"; return 0 ;;
        summary_file|view_file)
            command -v jq >/dev/null 2>&1 || { inv_message error "ERROR: jq is required to render views and summaries."; return 2; }
            print_gpu_vfio_view "$_inv_summary_file"
            return $?
            ;;
    esac
    inv_message title "Host Inventory for Proxmox - $app_name $app_version"
    inv_initialize || return $?
    inv_message info "Collecting host state..."
    if [ "$_inv_action" = summary ] || [ "$_inv_action" = view ]; then
        main_summary_file=$_inv_temp_dir/collect_gpu_vfio.summary-source.json
        collect_gpu_vfio > "$main_summary_file" || return $?
        print_gpu_vfio_view "$main_summary_file"
        return $?
    fi
    collect_gpu_vfio
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
