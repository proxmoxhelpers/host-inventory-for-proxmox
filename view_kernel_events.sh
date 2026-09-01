#!/bin/sh
# ============================================================
# view_kernel_events.sh
# Collects latency-relevant kernel event history such as OOM kills, lockups, RAS, IOMMU, PCIe, storage, network and thermal faults.
#
# Version:
#   0.9.2
#
# Usage:
#   sudo ./view_kernel_events.sh
#   ./view_kernel_events.sh --file collect_kernel_events.json
#   ./view_kernel_events.sh --help
#
# Output:
#   Human-readable view by default; --json emits the raw JSON envelope.
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

app_name="view_kernel_events"
app_version=0.9.2
app_rc=0
app_compact=0
app_package_specs="jq:jq:required dmesg:util-linux:optional"

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
_inv_quiet=0
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
    if [ "$_inv_quiet" -eq 1 ]; then
        case "$im_role" in
            warn|error) : ;;
            *) return 0 ;;
        esac
    fi
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
    _inv_action=view
    app_compact=0
    while [ "$#" -gt 0 ]; do
        ipo_arg=$1
        case "$ipo_arg" in
            --help|-h|-\?|/h|/\?) _inv_action=help ;;
            --version) _inv_action=version ;;
            --json) _inv_action=run ;;
            --compact) app_compact=1; _inv_action=run ;;
            --summary) _inv_action=summary ;;
            --summary-file)
                shift
                [ "$#" -gt 0 ] || { inv_message error "ERROR: --summary-file requires a JSON file."; return 2; }
                _inv_summary_file=$1
                _inv_action=summary_file
                ;;
            --view) _inv_action=view ;;
            --file)
                shift
                [ "$#" -gt 0 ] || { inv_message error "ERROR: --file requires a JSON file."; return 2; }
                _inv_summary_file=$1
                _inv_action=view_file
                ;;
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
            --quiet) _inv_quiet=1 ;;
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
    printf '  %s--file FILE%s        Render saved collector JSON.\n' "$app_color_accent" "$app_color_reset"
    printf '  %s--json%s             Emit raw JSON instead of the view.\n' "$app_color_accent" "$app_color_reset"
    printf '  %s--compact%s          Emit compact JSON.\n' "$app_color_accent" "$app_color_reset"
    printf '  %s--summary%s          Collect now and print a human-readable summary instead of JSON.\n' "$app_color_accent" "$app_color_reset"
    printf '  %s--summary-file FILE%s Print a summary from an existing collector JSON file without probing again.\n' "$app_color_accent" "$app_color_reset"
    printf '  %s--color%s            Force ANSI color, including JSON.\n' "$app_color_accent" "$app_color_reset"
    printf '  %s--no-color%s         Disable ANSI color.\n' "$app_color_accent" "$app_color_reset"
    printf '  %s--install-missing%s  Install the listed missing APT packages without a second prompt.\n' "$app_color_accent" "$app_color_reset"
    printf '  %s--no-install%s       Do not offer package installation.\n' "$app_color_accent" "$app_color_reset"
    printf '  %s--quiet%s            Suppress routine view-script status; warnings/errors remain.\n' "$app_color_accent" "$app_color_reset"
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
view_kernel_events.sh - standalone kernel event / reliability history view

Usage:
  sudo ./view_kernel_events.sh
  ./view_kernel_events.sh --file collect_kernel_events.json
  sudo ./view_kernel_events.sh --json > collect_kernel_events.json

Default behavior:
  With no arguments, collect this aspect live and render its colorized view.

The script is self-contained and read-only except for explicitly approved
optional diagnostic package installation.
EOF
    inv_print_common_usage
    return 0
}

collect_kernel_events() {
    cke_dir=$_inv_temp_dir/kernel-events
    cke_dm_stream=$cke_dir/dm-map.jsonl
    cke_dmesg_available=false
    cke_journal_available=false
    cke_dmesg_rc_json=null
    cke_journal_rc_json=null
    mkdir -p "$cke_dir" || return 1

    # Capture each source directly to a file. Avoid storing an entire kernel
    # log in a shell variable, and preserve source failure/availability.
    if command -v dmesg >/dev/null 2>&1; then
        cke_dmesg_available=true
        dmesg --color=never > "$cke_dir/dmesg.txt" 2> "$cke_dir/dmesg.stderr"
        cke_dmesg_rc_json=$?
    else
        : > "$cke_dir/dmesg.txt"
        : > "$cke_dir/dmesg.stderr"
    fi
    if command -v journalctl >/dev/null 2>&1; then
        cke_journal_available=true
        journalctl -k -b --no-pager -o short-monotonic > "$cke_dir/journal.txt" 2> "$cke_dir/journal.stderr"
        cke_journal_rc_json=$?
    else
        : > "$cke_dir/journal.txt"
        : > "$cke_dir/journal.stderr"
    fi

    : > "$cke_dm_stream" || return 1
    for cke_dm in /sys/block/dm-*; do
        [ -d "$cke_dm" ] || continue
        cke_dev=${cke_dm##*/}
        cke_name=$(cat "$cke_dm/dm/name" 2>/dev/null)
        cke_vmid=$(printf '%s\n' "$cke_name" | sed -nE 's/.*(vm--|base--)([0-9]+)--disk.*/\2/p' | head -1)
        cke_vg=$(printf '%s\n' "$cke_name" | sed -nE 's/^([^-]+)-.*/\1/p')
        jq -n --arg device "$cke_dev" --arg name "$cke_name" --arg vmid "$cke_vmid" --arg vg "$cke_vg" \
          '{device:$device,dm_name:(if $name=="" then null else $name end),
            vmid:(try ($vmid|tonumber) catch null),
            vg_hint:(if $vg=="" then null else $vg end)}' >> "$cke_dm_stream" || return 1
    done
    jq -s '.' "$cke_dm_stream" > "$cke_dir/dm-map.json" || return 1

    # Parse source text as individual kernel-log records. Every optional
    # capture is array-wrapped so a no-match emits null rather than an empty
    # jq stream that could delete its parent event.
    for cke_source in dmesg journal; do
        cke_input=$cke_dir/$cke_source.txt
        jq -R -s --arg source "$cke_source" '
          def clean:
            sub("^[[:space:]]*\\[[^]]+\\][[:space:]]*";"") |
            sub("^[^ ]+[[:space:]]+kernel:[[:space:]]*";"") |
            rtrimstr("\r");
          def boot_seconds:
            ([capture("^[[:space:]]*\\[[[:space:]]*(?<t>[0-9]+(?:\\.[0-9]+)?)\\]")?
              | .t | tonumber][0] // null);
          def classify:
            if test("out of memory: killed process|oom-kill:|invoked oom-killer";"i") then
              {category:"memory",event_type:"oom",severity:"error"}
            elif test("ata[0-9].*(error|reset|failed|link down)|nvme.*(reset|timeout|abort|error)|buffer i/o error|blk_update_request|i/o error|ext4-fs.*(error|warning)|xfs.*error";"i") then
              {category:"storage",event_type:"storage-io",
               severity:(if test("link down|ext4-fs.*warning";"i") then "warning" else "error" end)}
            elif test("aer:.*(corrected|uncorrected|fatal|non-fatal)|pcie bus error";"i") then
              {category:"pcie",event_type:"pcie-aer",
               severity:(if test("\\bcorrected\\b";"i") then "warning" else "error" end)}
            elif test("aer: enabled|aer: device recovery";"i") then
              {category:"pcie",event_type:"pcie-capability",severity:"info"}
            elif test("amd-vi.*(\\bfault\\b|\\berror\\b)|iommu.*\\bfault\\b|io_page_fault|event logged \\[io_page_fault";"i") then
              {category:"iommu",event_type:"iommu-fault",severity:"error"}
            elif test("edac.*(error|ce |ue )|mce:.*(hardware error|machine check)|hardware error";"i") then
              {category:"ras",event_type:"hardware-error",severity:"error"}
            elif test("edac mc: ver|mce: in-kernel mce decoding enabled";"i") then
              {category:"ras",event_type:"ras-capability",severity:"info"}
            elif test("soft lockup|hard lockup|watchdog:.*lockup|rcu.*stall|blocked for more than|hung task";"i") then
              {category:"scheduler",event_type:"stall-lockup",severity:"error"}
            elif test("netdev watchdog|tx timeout|nic.*reset|link is down|link is up";"i") then
              {category:"network",event_type:"network-link-reset",
               severity:(if test("link is up";"i") then "info" else "warning" end)}
            elif test("thermal.*thrott|temperature above|critical temperature|cpu.*thrott";"i") then
              {category:"thermal",event_type:"thermal-limit",severity:"warning"}
            elif test("bug:|oops:|kernel panic|general protection fault";"i") then
              {category:"kernel",event_type:"kernel-fault",severity:"error"}
            elif test("warning:";"i") then
              {category:"kernel",event_type:"kernel-warning",severity:"warning"}
            else null end;
          def normalized:
            gsub("logical block [0-9]+";"logical block <block>") |
            gsub("starting block [0-9]+";"starting block <block>") |
            gsub("inode [0-9]+";"inode <inode>") |
            gsub("sector [0-9]+";"sector <sector>") |
            gsub("pid=[0-9]+";"pid=<pid>") |
            gsub("Killed process [0-9]+";"Killed process <pid>") |
            gsub("total-vm:[0-9]+kB";"total-vm:<kB>") |
            gsub("anon-rss:[0-9]+kB";"anon-rss:<kB>") |
            gsub("file-rss:[0-9]+kB";"file-rss:<kB>") |
            gsub("shmem-rss:[0-9]+kB";"shmem-rss:<kB>") |
            gsub("pgtables:[0-9]+kB";"pgtables:<kB>");
          split("\n") | to_entries |
          map(. as $entry |
            ($entry.value | rtrimstr("\r")) as $raw |
            select(($raw|length)>0) |
            ($raw | boot_seconds) as $boot_seconds |
            ($raw | clean) as $msg |
            ($msg | classify) as $c |
            select($c != null) |
            ([($msg | capture("/qemu\\.slice/(?<v>[0-9]+)\\.scope")? | .v | tonumber)][0] // null) as $vmid |
            ([($msg | capture("(?:pid=|Killed process[[:space:]]+)(?<p>[0-9]+)")? | .p | tonumber)][0] // null) as $pid |
            ([($msg | capture("(?<d>dm-[0-9]+)")? | .d)][0] // null) as $dm |
            ([($msg | capture("(?<b>[0-9A-Fa-f]{4}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}\\.[0-7])")? | .b | ascii_downcase)][0] // null) as $bdf |
            ([($msg | capture("(?<a>ata[0-9]+)")? | .a)][0] // null) as $ata |
            $c + {
              source:$source,
              sequence:$entry.key,
              boot_seconds:$boot_seconds,
              message:$msg,
              normalized_message:($msg|normalized),
              vmid:$vmid,
              vmid_basis:(if $vmid==null then null else "qemu-scope" end),
              pid:$pid,
              dm_device:$dm,
              pci_bdf:$bdf,
              ata_port:$ata
            })
        ' "$cke_input" > "$cke_dir/$cke_source-events.json" || return 1
    done

    cke_boot_id=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
    cke_uptime=$(awk '{print $1}' /proc/uptime 2>/dev/null)
    jq -n \
      --arg boot_id "$cke_boot_id" \
      --arg uptime "$cke_uptime" \
      --argjson dmesg_available "$cke_dmesg_available" \
      --argjson dmesg_rc "$cke_dmesg_rc_json" \
      --argjson journal_available "$cke_journal_available" \
      --argjson journal_rc "$cke_journal_rc_json" \
      --slurpfile de "$cke_dir/dmesg-events.json" \
      --slurpfile je "$cke_dir/journal-events.json" \
      --slurpfile dm "$cke_dir/dm-map.json" '
      def absdiff($a;$b):
        ($a - $b) as $d | if $d < 0 then -$d else $d end;
      def occurrence_object($t):
        if $t == null then null
        else {scope:"current-boot-monotonic",boot_seconds:$t}
        end;
      def evidence_samples:
        map({boot_seconds:.boot_seconds,message:.message,sources:.sources}) |
        if length <= 5 then . else .[0:3] + [.[-2],.[-1]] end;

      (($de[0]//[]) + ($je[0]//[])) as $all |
      ($all|length) as $source_record_count |
      ($all
       | to_entries
       | map(.value + {_input_index:.key})
       | group_by(
           if .boot_seconds != null
           then [.category,.event_type,.message,.boot_seconds]
           else [.category,.event_type,.message,.source,._input_index]
           end)
       | map(.[0] + {sources:([.[].source]|unique)} | del(.source,._input_index))
      ) as $physical |
      ($physical|length) as $unique_kernel_records |
      ($physical |
       map(. as $r |
         if $r.event_type=="oom" and $r.vmid==null and $r.pid!=null and $r.boot_seconds!=null then
           ([$physical[] |
             select(.event_type=="oom" and .vmid!=null and .pid==$r.pid and .boot_seconds!=null) |
             select(absdiff(.boot_seconds;$r.boot_seconds) <= 5) |
             .vmid] | unique) as $nearby_vmids |
           if ($nearby_vmids|length)==1
           then $r + {vmid:$nearby_vmids[0],vmid_basis:"oom-pid-nearby"}
           else $r end
         else $r end)
      ) as $correlated |
      ($correlated |
       group_by([.category,.event_type,.severity,.normalized_message,.vmid,.dm_device,.pci_bdf,.ata_port]) |
       map(
         sort_by([if .boot_seconds==null then 1 else 0 end,(.boot_seconds//0)]) as $g |
         ($g | map(.boot_seconds) | map(select(.!=null))) as $times |
         {
           category:$g[0].category,
           event_type:$g[0].event_type,
           severity:$g[0].severity,
           message:$g[0].message,
           normalized_message:$g[0].normalized_message,
           sources:([$g[].sources[]]|unique),
           occurrences:($g|length),
           first_occurrence:occurrence_object(if ($times|length)>0 then ($times|min) else null end),
           last_occurrence:occurrence_object(if ($times|length)>0 then ($times|max) else null end),
           vmid:$g[0].vmid,
           guest_correlation:(
             if $g[0].vmid==null then null else
             {vmid:$g[0].vmid,bases:([$g[].vmid_basis|select(.!=null)]|unique),confidence:"high"}
             end),
           pids:([$g[].pid|select(.!=null)]|unique),
           dm_device:$g[0].dm_device,
           pci_bdf:$g[0].pci_bdf,
           ata_port:$g[0].ata_port,
           evidence:($g|evidence_samples)
         })
      ) as $events |
      ($events | map(. as $e |
        if $e.dm_device!=null then
          (($dm[0]//[]) | map(select(.device==$e.dm_device))[0] // null) as $m |
          $e + {
            device_mapping:$m,
            current_device_guest_hint:(
              if ($m!=null and $m.vmid!=null) then
                {vmid:$m.vmid,basis:"current-device-mapper-name",confidence:"low",historical_identity_proven:false}
              else null end)}
        else $e + {device_mapping:null,current_device_guest_hint:null} end)
      ) as $mapped |
      {
        boot_id:(if $boot_id=="" then null else $boot_id end),
        uptime_seconds:(try ($uptime|tonumber) catch null),
        source_status:{
          dmesg:{available:$dmesg_available,rc:$dmesg_rc},
          journal:{available:$journal_available,rc:$journal_rc}
        },
        events:$mapped,
        total_unique_events:($mapped|length),
        total_observations:([$mapped[].occurrences]|add//0),
        source_record_count:$source_record_count,
        cross_source_duplicates_removed:($source_record_count-$unique_kernel_records),
        counts_by_severity:($mapped|group_by(.severity)|map({key:.[0].severity,value:length})|from_entries),
        counts_by_category:($mapped|group_by(.category)|map({key:.[0].category,value:length})|from_entries),
        occurrences_by_severity:($mapped|group_by(.severity)|map({key:.[0].severity,value:([.[].occurrences]|add//0)})|from_entries),
        occurrences_by_category:($mapped|group_by(.category)|map({key:.[0].category,value:([.[].occurrences]|add//0)})|from_entries),
        qemu_oom_vmids:([$mapped[]|select(.event_type=="oom" and .vmid!=null)|.vmid]|unique),
        mapped_dm_events:([$mapped[]|select(.device_mapping!=null)]|length)
      }' > "$cke_dir/data.json" || return 1

    inv_strings_json "$cke_dir/notes.json" \
      "Kernel history is normalized as line-oriented current-boot records; equivalent dmesg/journal records with the same monotonic timestamp and message are counted once." \
      "Repeated records are grouped by a bounded normalized signature while representative evidence lines, first/last boot-relative occurrence and deduplicated occurrence counts are retained." \
      "Severity distinguishes informational capability/init messages from warnings and errors; it is still observation, not policy evaluation." \
      "OOM VM correlation uses an explicit qemu.slice scope or a same-PID event within five boot-seconds; current dm-* names are retained only as low-confidence historical guest hints because device identities can be reused." || return 1
    inv_strings_json "$cke_dir/errors.json" || return 1
    inv_emit kernel-events "$cke_dir/data.json" "$cke_dir/notes.json" "$cke_dir/errors.json"
}

print_kernel_events_view() {
    f=$1
    inv_summary_validate_file "$f" || return $?
    inv_view_header "$f" "Kernel Event / Reliability History View"
    inv_view_kv "Unique normalized events" "$(jq -r '.data.total_unique_events // 0' "$f")"
    inv_view_kv "Deduplicated observations" "$(jq -r '.data.total_observations // 0' "$f")"
    inv_view_kv "Cross-source duplicates" "$(jq -r '.data.cross_source_duplicates_removed // 0' "$f")"
    inv_view_kv "Mapped dm events" "$(jq -r '.data.mapped_dm_events // 0' "$f")"
    inv_view_kv "dmesg source" "$(jq -r 'if .data.source_status.dmesg.available==true then "rc=\(.data.source_status.dmesg.rc)" else "unavailable" end' "$f")"
    inv_view_kv "journal source" "$(jq -r 'if .data.source_status.journal.available==true then "rc=\(.data.source_status.journal.rc)" else "unavailable" end' "$f")"
    inv_view_kv "QEMU OOM VMIDs" "$(jq -r '(.data.qemu_oom_vmids//[])|if length==0 then "none observed" else map(tostring)|join(",") end' "$f")"

    inv_view_section "Normalized event entities by severity"
    jq -r '
      (.data.occurrences_by_severity//{}) as $occ |
      .data.counts_by_severity|to_entries[]?|
      "\(.key)=\(.value) entities, \($occ[.key]//0) occurrences"' "$f" |
    while IFS= read -r line; do inv_view_item "$line"; done

    inv_view_section "Categories"
    jq -r '
      (.data.occurrences_by_category//{}) as $occ |
      .data.counts_by_category|to_entries[]?|
      "\(.key)=\(.value) entities, \($occ[.key]//0) occurrences"' "$f" |
    while IFS= read -r line; do inv_view_item "$line"; done

    inv_view_section "Errors / warnings"
    jq -r '
      .data.events[]? |
      select(.severity!="info") |
      (.first_occurrence.boot_seconds // null) as $first |
      (.last_occurrence.boot_seconds // null) as $last |
      (.sources//[]|join(",")) as $sources |
      (if .vmid!=null then "VM=\(.vmid)"
       elif .current_device_guest_hint.vmid!=null then "VM-hint=\(.current_device_guest_hint.vmid)(current-dm/low)"
       else "VM=n/a" end) as $guest |
      "[\(.severity)/\(.category)/\(.event_type)] occurrences=\(.occurrences) first=\($first//"n/a") last=\($last//"n/a") \($guest) DM=\(.dm_device//"n/a") PCI=\(.pci_bdf//"n/a") sources=\($sources) :: \(.message)"' "$f" |
    head -30 |
    while IFS= read -r line; do inv_view_item "$line"; done
    inv_view_metadata "$f"
}

print_kernel_events_summary() { print_kernel_events_view "$1"; }

# ============================================================
# main
# ============================================================
main() {
    case "$_inv_action" in
        help) usage; return 0 ;;
        version) printf '%s %s\n' "$app_name" "$app_version"; return 0 ;;
        summary_file|view_file)
            command -v jq >/dev/null 2>&1 || { inv_message error "ERROR: jq is required to render views and summaries."; return 2; }
            print_kernel_events_view "$_inv_summary_file"
            return $?
            ;;
    esac
    inv_message title "Host Inventory for Proxmox - $app_name $app_version"
    inv_initialize || return $?
    inv_message info "Collecting host state..."
    if [ "$_inv_action" = summary ] || [ "$_inv_action" = view ]; then
        main_summary_file=$_inv_temp_dir/collect_kernel_events.summary-source.json
        collect_kernel_events > "$main_summary_file" || return $?
        print_kernel_events_view "$main_summary_file"
        return $?
    fi
    collect_kernel_events
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
