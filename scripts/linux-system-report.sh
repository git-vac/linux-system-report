#!/usr/bin/env bash
# Read-only Linux inventory. See docs/walkthrough.md for the control flow.
set -uo pipefail
export LC_ALL=C
export SYSTEMD_COLORS=0

usage() {
    cat <<'HELP'
Linux System Report
Usage: bash scripts/linux-system-report.sh [OPTIONS]

  --demo               Use packaged synthetic data; no host inspection
  --sections LIST      Comma-separated section names, in the requested order
  --timeout SECONDS    Per-command deadline, 1-99 seconds (default: 10)
  -o, --output FILE    Write a new Markdown file; existing paths are protected
  -h, --help           Show this help

Sections: os,kernel,uptime,cpu,memory,disks,mounts,services,ports
Live collection requires Linux, Bash 4+, and GNU timeout.
Demo mode also works in Git Bash. Run with bash, not sh.
HELP
}

die() {
    printf 'Error: %s\n' "$1" >&2
    exit "${2:-2}"
}

(( BASH_VERSINFO[0] >= 4 )) || die 'Bash 4 or newer is required.'
demo=false
output_file=''
deadline=10
section_list='os,kernel,uptime,cpu,memory,disks,mounts,services,ports'
while (( $# )); do
    case "$1" in
        --demo) demo=true; shift ;;
        --sections|--timeout|-o|--output)
            (( $# >= 2 )) || die "Missing value for $1."
            [[ -n $2 ]] || die "Empty value for $1."
            case "$1" in
                --sections) section_list=$2 ;;
                --timeout) deadline=$2 ;;
                *) output_file=$2 ;;
            esac
            shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) die "Unknown argument: $1" ;;
    esac
done
[[ $deadline =~ ^[1-9][0-9]?$ ]] || die '--timeout must be an integer from 1 to 99.'
[[ $section_list != ,* && $section_list != *, && $section_list != *,,* ]] ||
    die 'The section list contains an empty entry.'
IFS=, read -r -a sections <<< "$section_list"
declare -A seen=()
for key in "${sections[@]}"; do
    case "$key" in
        os|kernel|uptime|cpu|memory|disks|mounts|services|ports) ;;
        *) die "Unknown section: $key" ;;
    esac
    [[ -z ${seen[$key]+present} ]] || die "Duplicate section: $key"
    seen[$key]=1
done
if [[ -n $output_file && ( -e $output_file || -L $output_file ) ]]; then
    die 'The output path already exists. Choose a new filename.' 1
fi

source_path=${BASH_SOURCE[0]}
source_dir=.
[[ $source_path != */* ]] || source_dir=${source_path%/*}
script_dir=$(cd -- "$source_dir" && pwd -P) || die 'Cannot locate the script directory.' 1
demo_dir="$script_dir/../examples/demo-data"
if "$demo"; then
    for key in "${sections[@]}"; do
        [[ -f $demo_dir/$key.txt && -r $demo_dir/$key.txt ]] ||
            die "Missing demo fixture: $key" 1
    done
    mode='Synthetic demo'
    generated='Not applicable: packaged example data'
else
    command -v uname >/dev/null 2>&1 || die 'uname is required for live collection.'
    [[ $(uname -s) == Linux ]] || die 'Live collection requires Linux. Use --demo on other systems.'
    command -v timeout >/dev/null 2>&1 || die 'GNU timeout is required for live collection.'
    mode='Local Linux snapshot'
    generated=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null) || generated='Not recorded'
fi

declare -A titles=(
    [os]='Operating system' [kernel]='Kernel & architecture' [uptime]='Uptime & load'
    [cpu]='CPU' [memory]='Memory' [disks]='Local disk usage' [mounts]='Mounts'
    [services]='Running services' [ports]='TCP/UDP listening sockets'
)
declare -A descriptions=(
    [os]='Distribution metadata; this file is displayed, never sourced as shell code.'
    [kernel]='Kernel release and machine architecture.'
    [uptime]='Uptime, logged-in users, and load averages; load is not CPU percentage.'
    [cpu]='CPU topology visible to this environment.'
    [memory]='Reported memory and swap; available memory is more useful than free alone.'
    [disks]='Space on local filesystems. Remote filesystems are excluded from df.'
    [mounts]='Real mounts and their options, including any remote mounts.'
    [services]='Services whose systemd substate is running; other init systems are not covered.'
    [ports]='Local TCP listeners and bound UDP sockets. These do not prove remote reachability.'
)
declare -A commands=() statuses=() codes=() results=()
command_args=()

choose_command() {
    case "$1" in
        os) command_args=(cat /etc/os-release) ;;
        kernel) command_args=(uname -srmo) ;;
        uptime) command_args=(uptime) ;;
        cpu) command_args=(lscpu) ;;
        memory) command_args=(free -h) ;;
        disks) command_args=(df -h -l) ;;
        mounts) command_args=(findmnt --real --output TARGET,SOURCE,FSTYPE,OPTIONS) ;;
        services) command_args=(systemctl --no-pager --plain list-units --type=service --state=running) ;;
        ports) command_args=(ss -lntu) ;;
    esac
}

collect_section() {
    local key=$1 rc=0 captured=''
    choose_command "$key"
    commands[$key]="${command_args[*]}"
    if "$demo"; then
        captured=$(< "$demo_dir/$key.txt")
        if [[ $key == services ]]; then
            statuses[$key]='Error'
            rc=1
        else
            statuses[$key]='OK'
        fi
    elif ! command -v "${command_args[0]}" >/dev/null 2>&1; then
        statuses[$key]='Unavailable'
        rc=127
        captured="Required command is not installed or not on PATH: ${command_args[0]}"
    else
        if captured=$(timeout --kill-after=2s "${deadline}s" "${command_args[@]}" 2>&1); then
            statuses[$key]='OK'
        else
            rc=$?
            if (( rc == 124 )); then
                statuses[$key]='Timed out'
            else
                statuses[$key]='Error'
            fi
        fi
    fi
    codes[$key]=$rc
    results[$key]=$captured
}

# A fence longer than any matching run in the output keeps text inside its code block.
print_literal_block() {
    local text=$1 fence='~~~'
    while [[ $text == *"$fence"* ]]; do fence+='~'; done
    printf '%stext\n%s\n%s\n\n' "$fence" "$text" "$fence"
}

render_report() {
    local key gaps=0
    for key in "${sections[@]}"; do
        [[ ${statuses[$key]} == OK ]] || (( gaps += 1 ))
    done
    printf '# Linux System Report\n\n'
    printf 'Mode: **%s**  \nGenerated (UTC): %s\n\n' "$mode" "$generated"
    if "$demo"; then
        printf '> All values are synthetic. The services error is an intentional example.\n\n'
    fi
    printf '## Collection summary\n\n'
    printf '| Section | Collection status | Exit code |\n| :--- | :--- | ---: |\n'
    for key in "${sections[@]}"; do
        printf '| %s | %s | %s |\n' "${titles[$key]}" "${statuses[$key]}" "${codes[$key]}"
    done
    printf '\nCollection gaps: **%s**. OK means the command completed, not that the system is healthy or secure.\n\n' "$gaps"
    for key in "${sections[@]}"; do
        printf '## %s\n\n%s\n\n' "${titles[$key]}" "${descriptions[$key]}"
        printf 'Command: **%s**  \nCollection status: **%s** (exit %s)\n\n' \
            "${commands[$key]}" "${statuses[$key]}" "${codes[$key]}"
        if [[ -n ${results[$key]} ]]; then
            print_literal_block "${results[$key]}"
        else
            printf '_The command returned no output._\n\n'
        fi
    done
    printf '## Interpretation\n\n'
    printf '%s\n' \
        '- This is a point-in-time inventory, not a vulnerability scan or security score.' \
        '- Check collection gaps before drawing conclusions from missing information.' \
        '- Listening sockets require network and firewall context to assess exposure.' \
        '- Containers, namespaces, and permissions can limit what is visible.' \
        '- Reports may contain addresses, mount paths, and service details. Review before sharing.'
}

for key in "${sections[@]}"; do collect_section "$key"; done
if [[ -n $output_file ]]; then
    # noclobber also handles a file created after the initial existence check.
    if ! (umask 077; set -C; render_report > "$output_file"); then
        die 'Cannot write the report. Check the parent directory, permissions, and existing paths.' 1
    fi
    printf 'Report written successfully.\n' >&2
else
    render_report || die 'Cannot write the report to standard output.' 1
fi
