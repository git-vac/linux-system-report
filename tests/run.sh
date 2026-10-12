#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
script="$root/scripts/linux-system-report.sh"
test_tmp=$(mktemp -d "${TMPDIR:-/tmp}/lsr-tests.XXXXXX")
cleanup() {
    # Only remove the directory created by this test run.
    case "$test_tmp" in
        "${TMPDIR:-/tmp}"/lsr-tests.*) rm -rf -- "$test_tmp" ;;
        *) printf 'Refusing cleanup outside the test directory.\n' >&2 ;;
    esac
}
trap cleanup EXIT
passed=0
skipped=0
report=''
pass() { printf 'PASS %s\n' "$1"; passed=$((passed + 1)); }
fail() { printf 'FAIL %s\n' "$1" >&2; exit 1; }
contains() { [[ $report == *"$1"* ]] || fail "Expected report content: $1"; }
not_contains() { [[ $report != *"$1"* ]] || fail "Unexpected report content: $1"; }
expect_error() {
    local expected=$1 actual=0
    shift
    if "$@" >"$test_tmp/stdout.txt" 2>"$test_tmp/stderr.txt"; then
        actual=0
    else
        actual=$?
    fi
    [[ $actual == "$expected" ]] || fail "Expected exit $expected, got $actual"
}

report=$("$BASH" "$script" --demo)
diff -u "$root/examples/sample_report.md" <(printf '%s\n' "$report")
contains 'Mode: **Synthetic demo**'
contains '| Running services | Error | 1 |'
contains 'Collection gaps: **1**'
pass 'packaged demo matches the example and exposes its intentional gap'

report=$("$BASH" "$script" --demo --sections memory,ports)
contains '## Memory'
contains '## TCP/UDP listening sockets'
not_contains '## Operating system'
pass 'section filtering excludes unrequested data'

memory_pos=${report%%'## Memory'*}
ports_pos=${report%%'## TCP/UDP listening sockets'*}
(( ${#memory_pos} < ${#ports_pos} )) || fail 'Requested order changed'
pass 'section order follows the user selection'

expect_error 2 "$BASH" "$script" --demo --sections bogus
expect_error 2 "$BASH" "$script" --demo --sections ports,ports
expect_error 2 "$BASH" "$script" --demo --sections ,ports
expect_error 2 "$BASH" "$script" --demo --sections ports,
expect_error 2 "$BASH" "$script" --demo --sections ports,,memory
expect_error 2 "$BASH" "$script" --sections
expect_error 2 "$BASH" "$script" --output ''
expect_error 2 "$BASH" "$script" --demo --timeout 0
expect_error 2 "$BASH" "$script" --demo --timeout 100
expect_error 2 "$BASH" "$script" --demo --timeout '1; echo bad'
expect_error 2 "$BASH" "$script" --unknown
pass 'malformed options and section names are rejected'

printf 'KEEP ME\n' >"$test_tmp/existing.md"
expect_error 1 "$BASH" "$script" --demo -o "$test_tmp/existing.md"
[[ $(< "$test_tmp/existing.md") == 'KEEP ME' ]] || fail 'Existing report was changed'
pass 'existing report is preserved'

"$BASH" "$script" --demo -o "$test_tmp/report with spaces.md" 2>/dev/null
diff -u "$root/examples/sample_report.md" "$test_tmp/report with spaces.md"
pass 'a path with spaces receives the full report'

expect_error 1 "$BASH" "$script" --demo -o "$test_tmp/missing-parent/report.md"
pass 'missing parent directory produces an output error'

# Some Git Bash installations emulate symlinks as files. Linux CI exercises this case.
if ln -s "$test_tmp/nonexistent-target" "$test_tmp/dangling.md" 2>/dev/null &&
    [[ -L $test_tmp/dangling.md ]]; then
    expect_error 1 "$BASH" "$script" --demo -o "$test_tmp/dangling.md"
    [[ ! -e $test_tmp/nonexistent-target ]] || fail 'Symlink target was created'
    pass 'dangling symlink output is refused'
else
    printf 'SKIP native symlink test (not supported here)\n'
    skipped=$((skipped + 1))
fi

mkdir "$test_tmp/bin" "$test_tmp/minimal"
{
    printf '#!%s\n' "$BASH"
    cat <<'STUB'
case "${0##*/}" in
    uname)
        if [[ $1 == -s ]]; then printf '%s\n' "${MOCK_OS:-Linux}"
        else printf 'Linux example x86_64 GNU/Linux\n'; fi ;;
    timeout)
        if [[ ${MOCK_TIMEOUT:-0} == 1 ]]; then printf 'Deadline example\n'; exit 124; fi
        shift 2
        exec "$@" ;;
    ss)
        if [[ ${MOCK_MODE:-ok} == error ]]; then printf 'Permission denied\n' >&2; exit 13; fi
        if [[ ${MOCK_MODE:-ok} == empty ]]; then exit 0; fi
        if [[ ${MOCK_MODE:-ok} == fence ]]; then
            printf '~~~\n<img src=x onerror=example>\n~~~~\n'
        else printf 'tcp LISTEN 0 128 127.0.0.1:22 0.0.0.0:*\n'; fi ;;
    *) printf 'Unexpected stub call\n' >&2; exit 99 ;;
esac
STUB
} >"$test_tmp/stub"
cp "$test_tmp/stub" "$test_tmp/bin/uname"
cp "$test_tmp/stub" "$test_tmp/bin/timeout"
cp "$test_tmp/stub" "$test_tmp/bin/ss"
cp "$test_tmp/stub" "$test_tmp/minimal/uname"
cp "$test_tmp/stub" "$test_tmp/minimal/timeout"
chmod +x "$test_tmp"/bin/* "$test_tmp"/minimal/*

report=$(PATH="$test_tmp/bin:$PATH" "$BASH" "$script" --sections ports)
contains '| TCP/UDP listening sockets | OK | 0 |'
contains '127.0.0.1:22'
pass 'live collector captures controlled command output'

report=$(PATH="$test_tmp/minimal" "$BASH" "$script" --sections ports)
contains '| TCP/UDP listening sockets | Unavailable | 127 |'
contains 'Required command is not installed or not on PATH: ss'
pass 'missing command is distinct from empty successful output'

report=$(MOCK_MODE=error PATH="$test_tmp/bin:$PATH" "$BASH" "$script" --sections ports)
contains '| TCP/UDP listening sockets | Error | 13 |'
contains 'Permission denied'
pass 'failure exit code and stderr are retained'

report=$(MOCK_TIMEOUT=1 PATH="$test_tmp/bin:$PATH" "$BASH" "$script" --sections ports)
contains '| TCP/UDP listening sockets | Timed out | 124 |'
pass 'a command deadline is reported explicitly'

report=$(MOCK_MODE=empty PATH="$test_tmp/bin:$PATH" "$BASH" "$script" --sections ports)
contains '| TCP/UDP listening sockets | OK | 0 |'
contains '_The command returned no output._'
pass 'empty successful collection remains an explicit observation'

report=$(MOCK_MODE=fence PATH="$test_tmp/bin:$PATH" "$BASH" "$script" --sections ports)
fence_length=0
while IFS= read -r line; do
    if [[ $line =~ ^(~+)text$ ]]; then fence_length=${#BASH_REMATCH[1]}; fi
done <<< "$report"
(( fence_length > 4 )) || fail 'Embedded output could close its code block'
contains '<img src=x onerror=example>'
pass 'embedded Markdown delimiters remain inside a literal code block'

expect_error 2 env MOCK_OS=Other PATH="$test_tmp/bin:$PATH" "$BASH" "$script" --sections ports
pass 'unsupported live platforms are rejected'

# File output permissions are meaningful on Linux, but not identical under Windows/MSYS.
if [[ $(uname -s) == Linux ]]; then
    mode=$(stat -c '%a' "$test_tmp/report with spaces.md")
    [[ $mode == 600 ]] || fail "Expected private file mode 600, got $mode"
    pass 'new reports have restrictive Unix permissions'
else
    printf 'SKIP Unix mode test (not a Linux host)\n'
    skipped=$((skipped + 1))
fi
printf '\n%s tests passed; %s platform-dependent tests skipped.\n' "$passed" "$skipped"
