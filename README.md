[![Build Status](https://travis-ci.org/apisnetworks/apnscp-bootstrapper.svg?branch=master)](https://travis-ci.org/apisnetworks/apnscp-bootstrapper)

# ApisCP Bootstrap Utility
Bootstrap Utility ("bootstrap.sh") provides an automated installation process to setup [ApisCP](https://apiscp.com) on a compatible CentOS/RHEL machine. Not to be confused with apnscp Bootstrapper, which is a specific component of ApisCP's [playbooks](https://github.com/apisnetworks/apnscp-playbooks) and called by this utility once the minimum environment is setup.

# Usage
## Trial mode
Trials are valid for 30 days and during development may be continuously rearmed as necessary. Trials can also be used to benchmark cloud providers (see below).

```bash
curl https://raw.githubusercontent.com/apisnetworks/apnscp-bootstrapper/master/bootstrap.sh | bash
```

## Registered licenses

After registering on [my.apiscp.com](https://my.apiscp.com), use the token to automatically download the key.
```bash
curl https://raw.githubusercontent.com/apisnetworks/apnscp-bootstrapper/master/bootstrap.sh | bash -s - <api token> <optional common name>
```

Alternatively, if you have the x509 key ("license.pem") available where &lt;keyfile&gt; is the absolute path.
```bash
curl https://raw.githubusercontent.com/apisnetworks/apnscp-bootstrapper/master/bootstrap.sh | bash -s - -k <keyfile>
```

### Optional common name

An optional common name may be specified after &lt;api token&gt;. This is a 64 character long unique identifier that describes your certificate and may be any printable character. Emojis will be transcoded to their 4-byte sequence. Sorry 🍆!

## Setting initial configuration

ApisCP may be customized via [ApisCP's customizer](https://apiscp.com/#customize) or command-line. apiscp.com provides a selection of options that are adequate for most environments. Any variable may be overwritten for any play in the playbook. Common options are located in [`apnscp-vars.yml`](https://github.com/apisnetworks/apnscp-playbooks/blob/master/apnscp-vars.yml) and [`apnscp-internals.yml`](https://github.com/apisnetworks/apnscp-playbooks/blob/master/roles/common/vars/apnscp-internals.yml).

### Command-line overrides

`-s` may be used to set variables at installation in [`apnscp-vars.yml`](https://github.com/apisnetworks/apnscp-playbooks/blob/master/apnscp-vars.yml), which is the initial configuration template for ApisCP. Additionally any role defaults may be overridden through this usage (such as "[rspamd_enabled](https://github.com/apisnetworks/apnscp-playbooks/blob/master/roles/mail/rspamd/defaults/main.yml)"). Escape sequences and quote when necessary because variables are passed as-is to apnscp-vars.yml.

```bash
# Run bootstrap.sh from CLI setting apnscp_admin_email and ssl_hostnames in unattended installation
bootstrap.sh -s apnscp_admin_email=matt@apisnetworks.com -s ssl_hostnames="['apiscp.com','apisnetworks.com']"
```

These arguments may be passed as part of the one-liner too. *Note usage of `-` after first `-s`.*

```bash
curl https://raw.githubusercontent.com/apisnetworks/apnscp-bootstrapper/master/bootstrap.sh | bash -s - -s apnscp_admin_email=matt@apisnetworks.com -s ssl_hostnames="['apnscp.com','apisnetworks.com']"
```

Standard bootstrap.sh options may also be applied after the options, for example

```bash
curl https://raw.githubusercontent.com/apisnetworks/apnscp-bootstrapper/master/bootstrap.sh | bash -s - -s apnscp_admin_email=matt@apisnetworks.com someactivationkey
```

# Benchmarking providers

bootstrap.sh can also be used to benchmark a provider since it runs unassisted from start to finish. For consistency commit [3f2944ae](https://gitlab.com/apisnetworks/apnscp/tree/benchmark) is referenced ("benchmark" tag). If `RELEASE` is omitted bootstrap.sh will use master, which may produce different results than the stats below.

```bash
curl https://raw.githubusercontent.com/apisnetworks/apnscp-bootstrapper/master/bootstrap.sh | env RELEASE=benchmark bash 
```

Check back in ~2 hours then run the following command:

```bash
IFS=$'\n' ; DATES=($((tail -n 1 /root/apnscp-bootstrapper.log | grep failed=0 ; grep -m 1 -P '^\d{4}-.*[u|p]=root' /root/apnscp-bootstrapper.log ) | awk '{print $1, $2}')) ; [[ ${#DATES[@]} -eq 2 ]] && python2 -c 'from datetime import datetime; import sys; format="%Y-%m-%d %H:%M:%S,%f";print datetime.strptime(sys.argv[1], format)-datetime.strptime(sys.argv[2], format)' "${DATES[0]}" "${DATES[1]}" || (echo -e "\n>>> Unable to verify Bootstrapper completed - is Ansible still running or did it fail? Last 10 lines follow" && tail -n 10 /root/apnscp-bootstrapper.log)
```

A duration will appear or the last 10 lines of `/root/apnscp-bootstrapper.log` if it failed. This tests network/IO/CPU. 

A second test of backend performance once ApisCP is setup gives the baseline performance between frontend/backend communication to a single vCPU. This can be tested as follows.

First update the shell with helpers from .bashrc,
```bash
exec $SHELL -i
```

Then run the cpcmd helper,
```bash
cpcmd scope:set cp.debug true; systemctl restart apiscp; sleep 10; cpcmd test:backend-performance 100000; cpcmd scope:set apnscp.debug false
```

debug mode will be temporarily enabled, which opens up access to the [test module](https://api.apnscp.com/class-Test_Module.html) API.

### Converting into production panel

A server provisioned using the *benchmark* branch can be converted to a normal build without resetting the server. Use cpcmd to set any [apnscp-vars.yml](https://github.com/apisnetworks/apnscp-playbooks/blob/master/apnscp-vars.yml) value; use the [Customization Utility](https://apnscp.com/#customize) on apnscp as cross-reference.

```bash
# Launch new bash shell with apnscp helper functions
exec $SHELL -i
cd /usr/local/apnscp
# Save remote URL, should be gitlab.com/apisnetworks/apnscp.git
REMOTE="$(git config --get remote.origin.url)"
git remote remove origin
git remote add -f -t master origin "$REMOTE"
git reset --hard origin/master
cpcmd auth:change-password newadminpassword
cpcmd common:set-email your@email.address
env "BSARGS=--extra-vars='populate_filesystem_template=true'" upcp -sb
# After Bootstrapper completes - it will take 5-30 minutes to do so
```

`populate_filesystem_template` must be enabled to update any packages that have been added/removed in apnscp. Once everything is done, access [apnscp's interface](https://hq.apnscp.com/apnscp-pre-alpha-technical-release/#loggingintoapnscp) to get started.

## Provider stats

Bootstrapping should complete within 90 minutes on a single core VPS. Under 60 minutes is impressive. These are stats taken from [Bootstrapper](https://github.com/apisnetworks/apnscp-playbooks) initial runs as bundled with part of [apnscp](https://apisnetworks.com). Note that as with shared hosting, or any shared resource, performance is adversely affected by oversubscription and noisy neighbors. Newer hypervisors show better benchmark numbers whereas older hypervisors show lower performance figures.

*Updated July 30, 2022*

* **AWS**
    * t3.small (*2 GB **†**, 2x Xeon Platinum 8259CL @ 2.5 GHz; 5000 bogomips*)
        * **Install** 00:55:47 **Backend** 6026 req/sec **Resync** 54.4 s
    * c3.large (*3.75 GB, 2x Xeon E5-2680 v2 @ 2.8 GHz; 5600 bogomips*)
        * **Install** 1:01:14.4 **Backend** 3779 req/sec **Resync** 58.6 s
    * 2 GB Lightsail  (*2 GB; 1x Xeon E5-2686 v4 @ 2.3 GHz; 4600 bogomips*)
        * **Install** 01:02:27 **Backend** 5309 req/sec **Resync** 59.8 s
* **Azure**
    * B1ms (*2 GB **†**, 1x Xeon Platinum 8370C @ 2.8 GHz; 5587 bogomips*)
        * **Install** 00:55:24 **Backend** 8661 req/sec **Resync** 48.4 s
    * D4as_v5 (*16 GB, 4x AMD EPYC 7763 @ 2.9 GHz; 4891 bogomips*)
        * **Install** 00:33:48.9 **Backend** 10396 req/sec **Resync** 32.9 s
    * F4s v2 (*8 GB, 4x Xeon Platinum 8370C @ 2.8 GHz; 2793 bogomips*)
        * **Install** 00:39:36 **Backend** 8368 req/sec **Resync** 40.8 s
* **Contabo**
    * **Cloud VPS S** (*8 GB, 4x AMD EPYC 7282 @ 2.8 GHz; 5600 bogomips*)
        * **Install** 00:44:05 **Backend** 4018 req/sec **Resync** 68.6 s
* **DigitalOcean**
    * Shared CPU (Basic, Regular w/ SSD) (*2 GB, 1x "DO-Regular" @ 2.3 GHz; 4589 bogomips*)
        * **Install** 1:33:55 **Backend** 4253 req/sec **Resync** 107.0 s
    * CPU Optimized (*4 GB, 2x Xeon Platinum 8168 @ 2.7 GHz; 5387 bogomips*)
        * **Install** 00:48:10 **Backend** 5252 req/sec **Resync** 44.0 s
* **Hetzner**
    * CPX11 (*2 GB **†**, 2x AMD EPYC @ 2.4 GHz; 4891 bogomips*)
        * **Install** 1:33:55 **Backend** 6701 req/sec **Resync** 62.6 s
    * CCX12 (*8 GB, 2x AMD EPYC @ 2.4 GHz; 4981 bogomips*)
        * **Install** 00:38:02 **Backend** 8486 req/sec **Resync** 33.2 s
* **Katapult**
    * ROCK-3 (*3 GB, 1 AMD EPYC 7642 @ 2.3 GHz; 2900 bogomips*)
        * **Install** 00:40:38 **Backend** 10006 req/sec **Resync** 33.3 s
    * ROCK-24 (*24 GB, 8x AMD EPYC 7542 @ 2.9 GHz; 5800 bogomips*)
        * **Install** 00:23:21 **Backend** 11284 req/sec **Resync** 31.1 s
* **Linode**
    * Linode 2 GB (*2 GB, 1x AMD EPYC 7642 @ 2.3 GHz; 4600 bogomips*)
        * **Install** 00:45:46 **Backend** 7717 req/sec **Resync** 66.1 s
    * Dedicated 4 GB (*4 GB, 1x AMD EPYC 7642 @ 2.3 GHz; 4000 bogomips*)
        * **Install** 00:51:11 **Backend** 7935 req/sec **Resync** 48.5 s
* **OVH**
    * VPS Value 1 (*2 GB **†**, 1x Intel Core (Haswell, no TSX) @ 2.4 GHz; 4789 bogomips*)
        * **Install** 1:04:25 **Backend** 5548 req/sec **Resync** 49.9 s
* **UpCloud**
    * 2 GB (*2GB, 1x AMD EPYC 7542 @ 2.9 GHz; 5789 bogomips*)
        * **Install** 00:52:51 **Backend** 9794 req/sec **Resync** 35.6 s
* **Virmach**
    * NVMe4G (*4 GB, 3x Ryzen 9 3900X @ 3.8 GHz; 7600 bogomips*)
        * **Install** 00:31:26 **Backend** 10885 req/sec **Resync** 35.6 s
* **Vultr**
    * Intel (Regular Performance) (*2 GB; 1x Intel Xeon Processor (Skylake, IBRS) @ 2.593 GHz; 5188 bogomips*)
        * **Install** 00:51:30 **Backend** 7421 req/sec **Resync** 49.6 s
    * Intel (High Performance) (*2 GB; 1x Xeon Processor (Cascadelake) @ 2.9 GHz; 5986 bogomips*)
        * **Install** 00:48:45 **Backend** 7784 req/sec **Resync** 44.4 s
    * CPU Optimized Cloud Compute (*2 GB; 1x AMD EPYC-Rome Processor @ 2 GHz; 3992 bogomips*)
        * **Install** 00:48:21 **Backend** 8735 req/sec **Resync** 115.2 s

**†**: Available memory less than minimum threshold of 1790 MB. `limit_memory_2gb` overridden to accommodate.

## Storage benchmark
FST replication is the best indicator of filesystem performance in ApisCP. This can be achieved using yum-post, which queries all installed packages from PostgreSQL, enumerates contents (`rpm -ql`), then creates the analogous file structure within /home/virtual/FILESYSTEMTEMPLATE.

```bash
cpcmd scope:set cp.debug false; systemctl restart apiscp; sleep 10; time (/usr/local/apnscp/bin/scripts/yum-post.php resync --force 2> /dev/null)
```

A sample result from Vultr's 2 GB machine in Atlanta:
```
real    1m8.748s
user    0m49.031s
sys     0m17.572s
```

## Role profiling

bootstrap.sh includes role profiling. Set `ANSIBLE_STDOUT_CALLBACK=profile_roles` as a wrapper:

```bash
curl https://raw.githubusercontent.com/apisnetworks/apnscp-bootstrapper/master/bootstrap.sh | env WRAPPER='ANSIBLE_STDOUT_CALLBACK=profile_roles' bash
```

An average runtime of the top 20 most expensive roles. This completed 1:00:05 on February 10, 2019 (Vultr, 2 GB).

| Role                                  | Time (seconds) |
| ------------------------------------- | -------------- |
| php/build-from-source                 | 887.54         |
| packages/install                      | 603.77         |
| apnscp/initialize-filesystem-template | 569.42         |
| software/passenger                    | 322.41         |
| mail/webmail-horde                    | 253.48         |
| clamav/support                        | 74.50          |
| mail/configure-postfix                | 71.56          |
| common                                | 71.20          |
| mail/spamassassin                     | 52.93          |
| apnscp/install-vendor-library         | 38.34          |
| php/install-pecl-module               | 34.33          |
| clamav/setup                          | 32.24          |
| network/setup-firewall                | 19.58          |
| mail/configure-dovecot                | 18.82          |
| apnscp/bootstrap                      | 17.55          |
| system/pam                            | 13.15          |
| software/argos                        | 12.14          |
| software/rbenv-support                | 9.67           |
| software/watchdog                     | 9.19           |

## Contributing

Fork, benchmark, and submit a PR - even for benchmark results. This project is licensed under MIT. Have fun!
