# Linux System Report

A Bash tool that turns a Linux machine's system information into a readable Markdown snapshot. Useful for documenting VMs, reviewing a server, and comparing a system before and after a change.

It collects local information without changing system configuration, installing software, or requesting root.

## Try the synthetic example

Requires **Bash 4 or newer**. Demo mode works in Linux and Git Bash on Windows.

~~~bash
git clone https://github.com/git-vac/linux-system-report.git
cd linux-system-report
bash scripts/linux-system-report.sh --demo
~~~

[Read the example report](examples/sample_report.md) · [Understand the code](docs/walkthrough.md)

The demo uses invented values and includes an intentional services error. It does not inspect your machine.

## Collect a Linux snapshot

Live collection requires Linux and **GNU timeout**, usually supplied by coreutils. Other commands are optional: missing tools and failed checks are recorded in the report.

~~~bash
bash scripts/linux-system-report.sh
mkdir -p reports
bash scripts/linux-system-report.sh -o reports/system.md
~~~

The output file must be new; existing files and symlink paths are protected. Parent directories must already exist. On Unix, newly created reports use restrictive permissions through umask 077.

Choose just the sections you need, in the order you want:

~~~bash
bash scripts/linux-system-report.sh --sections os,kernel,memory,disks
bash scripts/linux-system-report.sh --sections services,ports --timeout 5
bash scripts/linux-system-report.sh --help
~~~

Each live command has a 10-second deadline by default, followed by a 2-second kill grace period. Per-command results are collected sequentially, so a report is not an atomic snapshot.

| Section | Command | What it records |
| :--- | :--- | :--- |
| os | cat /etc/os-release | Distribution metadata, displayed without executing it |
| kernel | uname -srmo | Kernel and architecture |
| uptime | uptime | Uptime, logged-in users, load averages |
| cpu | lscpu | CPU topology |
| memory | free -h | Memory and swap |
| disks | df -h -l | Local filesystem usage |
| mounts | findmnt --real --output TARGET,SOURCE,FSTYPE,OPTIONS | Real mounts and their options |
| services | systemctl --no-pager --plain list-units --type=service --state=running | Running systemd services |
| ports | ss -lntu | TCP listeners and bound UDP sockets, with numeric addresses |

This covers the current host/container namespace. It does not collect firewall rules, users, credentials, package inventories, or service log contents. It does not scan other machines or resolve socket addresses.

## Read the results correctly

- **OK:** the command returned exit code 0; this is a collection result, not a health assessment.
- **Unavailable:** the command was not found on PATH.
- **Error:** the command failed; output and exit code are preserved.
- **Timed out:** GNU timeout returned 124. A forced kill can instead appear as Error with exit code 137.

An empty successful result is shown explicitly. A missing services result does not mean there are no services. A listener does not establish whether a port is reachable through the network or firewall.

The overall exit code is **0** when a report was written, even if it has collection gaps; **1** for output or demo-file errors; **2** for invalid options, unsupported platforms, or missing live prerequisites.

## Run the tests

~~~bash
bash -n scripts/linux-system-report.sh
bash -n tests/run.sh
bash tests/run.sh
~~~

Tests use synthetic fixtures and command stubs. They cover section selection, missing commands, failed collection, deadlines, literal Markdown rendering, paths with spaces, and output-file protection. GitHub Actions also runs a live smoke check on Ubuntu runners.

## Local report data

Keep generated reports in **reports/**, which Git ignores. Reports elsewhere are not automatically ignored. Review any real report before publishing: addresses, mount paths, and service names can describe your infrastructure.

## References

- [GNU Bash manual](https://www.gnu.org/software/bash/manual/bash.html): arrays, quoting, functions, conditionals, and command substitution.
- [GNU timeout](https://www.gnu.org/software/coreutils/manual/html_node/timeout-invocation.html): command deadlines and exit statuses.
- [systemctl manual](https://man7.org/linux/man-pages/man1/systemctl.1.html): service listing and states.
- [ss manual](https://man7.org/linux/man-pages/man8/ss.8.html): listening sockets and numeric output.

MIT licensed. See [LICENSE](LICENSE).
