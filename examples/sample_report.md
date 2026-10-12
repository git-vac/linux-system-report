# Linux System Report

Mode: **Synthetic demo**  
Generated (UTC): Not applicable: packaged example data

> All values are synthetic. The services error is an intentional example.

## Collection summary

| Section | Collection status | Exit code |
| :--- | :--- | ---: |
| Operating system | OK | 0 |
| Kernel & architecture | OK | 0 |
| Uptime & load | OK | 0 |
| CPU | OK | 0 |
| Memory | OK | 0 |
| Local disk usage | OK | 0 |
| Mounts | OK | 0 |
| Running services | Error | 1 |
| TCP/UDP listening sockets | OK | 0 |

Collection gaps: **1**. OK means the command completed, not that the system is healthy or secure.

## Operating system

Distribution metadata; this file is displayed, never sourced as shell code.

Command: **cat /etc/os-release**  
Collection status: **OK** (exit 0)

~~~text
NAME="Example Linux"
VERSION="1.0 (synthetic)"
ID=example
~~~

## Kernel & architecture

Kernel release and machine architecture.

Command: **uname -srmo**  
Collection status: **OK** (exit 0)

~~~text
Linux 6.8.0-example x86_64 GNU/Linux
~~~

## Uptime & load

Uptime, logged-in users, and load averages; load is not CPU percentage.

Command: **uptime**  
Collection status: **OK** (exit 0)

~~~text
12:00:00 up 3 days, 2:15, 1 user, load average: 0.10, 0.15, 0.12
~~~

## CPU

CPU topology visible to this environment.

Command: **lscpu**  
Collection status: **OK** (exit 0)

~~~text
Architecture:             x86_64
CPU(s):                   4
Model name:               Synthetic example CPU
~~~

## Memory

Reported memory and swap; available memory is more useful than free alone.

Command: **free -h**  
Collection status: **OK** (exit 0)

~~~text
               total        used        free      shared  buff/cache   available
Mem:           7.8Gi       2.0Gi       3.8Gi       128Mi       2.0Gi       5.4Gi
Swap:          2.0Gi          0B       2.0Gi
~~~

## Local disk usage

Space on local filesystems. Remote filesystems are excluded from df.

Command: **df -h -l**  
Collection status: **OK** (exit 0)

~~~text
Filesystem      Size  Used Avail Use% Mounted on
/dev/vda1        40G   12G   26G  32% /
~~~

## Mounts

Real mounts and their options, including any remote mounts.

Command: **findmnt --real --output TARGET,SOURCE,FSTYPE,OPTIONS**  
Collection status: **OK** (exit 0)

~~~text
TARGET SOURCE    FSTYPE OPTIONS
/      /dev/vda1 ext4   rw,relatime
~~~

## Running services

Services whose systemd substate is running; other init systems are not covered.

Command: **systemctl --no-pager --plain list-units --type=service --state=running**  
Collection status: **Error** (exit 1)

~~~text
System has not been booted with systemd as init system (PID 1). Cannot operate.
~~~

## TCP/UDP listening sockets

Local TCP listeners and bound UDP sockets. These do not prove remote reachability.

Command: **ss -lntu**  
Collection status: **OK** (exit 0)

~~~text
Netid State  Recv-Q Send-Q Local Address:Port Peer Address:Port
udp   UNCONN 0      0      127.0.0.1:53       0.0.0.0:*
tcp   LISTEN 0      128    0.0.0.0:22         0.0.0.0:*
~~~

## Interpretation

- This is a point-in-time inventory, not a vulnerability scan or security score.
- Check collection gaps before drawing conclusions from missing information.
- Listening sockets require network and firewall context to assess exposure.
- Containers, namespaces, and permissions can limit what is visible.
- Reports may contain addresses, mount paths, and service details. Review before sharing.
