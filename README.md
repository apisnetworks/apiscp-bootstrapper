[![Build Status](https://travis-ci.org/apisnetworks/apnscp-bootstrapper.svg?branch=master)](https://travis-ci.org/apisnetworks/apnscp-bootstrapper)

# apnscp Bootstrap Utility
Bootstrap Utility ("bootstrap.sh") provides an automated installation process to setup [apnscp](https://apnscp.com) on a compatible CentOS/RHEL machine. Not to be confused with apnscp Bootstrapper, which is a specific component of apnscp's [playbooks](https://github.com/apisnetworks/apnscp-playbooks) and called by this utility once the minimum environment is setup.

# Usage
## Trial mode
Trials are valid for 30 days and during development may be continuously rearmed as necessary. Trials can also be used to benchmark cloud providers (see below).

```shell
curl https://raw.githubusercontent.com/apisnetworks/apnscp-bootstrapper/master/bootstrap.sh | bash
```

## Registered licenses

After registering on [my.apnscp.com](https://my.apnscp.com), use the token to automatically download the key.
```bash
curl https://raw.githubusercontent.com/apisnetworks/apnscp-bootstrapper/master/bootstrap.sh | bash -s - <api token> <optional common name>
```

Alternatively, if you have the x509 key ("license.pem") available where &lt;keyfile&gt; is the absolute path.
```shell
curl https://raw.githubusercontent.com/apisnetworks/apnscp-bootstrapper/master/bootstrap.sh | bash -s - -k <keyfile>
```

### Optional common name

An optional common name may be specified after &lt;api token&gt;. This is a 64 character long unique identifier that describes your certificate and may be any printable character. Emojis will be transcoded to their 4-byte sequence. Sorry 🍆!

## Setting initial configuration

apnscp may be customized via [apnscp.com's customizer](https://apnscp.com/#customize) or command-line. apnscp.com provides a selection of options that are adequate for most environments. Any variable may be overwritten for any play in the playbook. Common options are located in [`apnscp-vars.yml`](https://github.com/apisnetworks/apnscp-playbooks/blob/master/apnscp-vars.yml) and [`apnscp-internals.yml`](https://github.com/apisnetworks/apnscp-playbooks/blob/master/roles/common/vars/apnscp-internals.yml).

### Command-line overrides

`-s` may be used to set variables at installation in [`apnscp-vars.yml`](https://github.com/apisnetworks/apnscp-playbooks/blob/master/apnscp-vars.yml), which is the initial configuration template for apnscp. Additionally any role defaults may be overridden through this usage (such as "[rspamd_enabled](https://github.com/apisnetworks/apnscp-playbooks/blob/master/roles/mail/rspamd/defaults/main.yml)"). Escape sequences and quote when necessary because variables are passed as-is to apnscp-vars.yml.

```shell
# Run bootstrap.sh from CLI setting apnscp_admin_email and ssl_hostnames in unattended installation
bootstrap.sh -s apnscp_admin_email=matt@apisnetworks.com -s ssl_hostnames="['apnscp.com','apisnetworks.com']"
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

```shell
curl https://raw.githubusercontent.com/apisnetworks/apnscp-bootstrapper/master/bootstrap.sh | env RELEASE=benchmark bash 
```

Check back in ~2 hours then run the following command:

```bash
IFS=$'\n' ; DATES=($((tail -n 1 /root/apnscp-bootstrapper.log | grep failed=0 ; grep -m 1 -P '^\d{4}-.*u=root' /root/apnscp-bootstrapper.log ) | awk '{print $1, $2}')) ; [[ ${#DATES[@]} -eq 2 ]] && python -c 'from datetime import datetime; import sys; format="%Y-%m-%d %H:%M:%S,%f";print datetime.strptime(sys.argv[1], format)-datetime.strptime(sys.argv[2], format)' "${DATES[0]}" "${DATES[1]}" || (echo -e "\n>>> Unable to verify Bootstrapper completed - is Ansible still running or did it fail? Last 10 lines follow" && tail -n 10 /root/apnscp-bootstrapper.log)
```

A duration will appear or the last 10 lines of `/root/apnscp-bootstrapper.log` if it failed. This tests network/IO/CPU. A second test of backend performance once apnscp is setup gives the baseline performance between frontend/backend communication. This can be tested as follows,

```bash
cpcmd config_set apnscp.debug true  ; sleep 5 ; cpcmd test_backend_performance ; cpcmd config_set apnscp.debug false
```

debug mode will be temporarily enabled, which opens up access to the [test module](https://api.apnscp.com/class-Test_Module.html) API.

## Provider stats

Bootstrapping should complete within 90 minutes on a single core VPS. Under 60 minutes is impressive. These are stats taken from [Bootstrapper](https://github.com/apisnetworks/apnscp-playbooks) initial runs as bundled with part of [apnscp](https://apisnetworks.com). Note that as with shared hosting, or any shared resource, performance is adversely affected by oversubscription and noisy neighbors. Newer hypervisors show better benchmark numbers whereas older hypervisors show lower performance figures.

* AWS t3.small
    * **Install:** 1:15:48, **Backend:** 7331 requests/second (2 GB, 2x vCPU, 2.5 GHz, P-8175 - 5000 bogomips)
* AWS Lightsail
    * **Install:** 2:31:08, **Backend:** 1475 requests/second (2 GB, 1x E5-2676 - 4789 bogomips)
* DigitalOcean
    * **Install:** 1:40:55, **Backend:** 6234 requests/second (2 GB, 1x E5-2650 - 4399 bogomips)
* Hetzner
    * **Install:** 1:05:52, **Backend:** 11397 requests/second (2 GB, 1x Skylake, IBRS - 4199 bogomips)
    * **Install:** 1:26:13, **Backend:** 10776 requests/second (2 GB, 1x Skylake, IBRS - 4199 bogomips)
* Linode
    * **Install:** 1:12:16, **Backend:** 8199 requests/second (2 GB, 1x E5-2697 - 4599 bogomips)
* OVH
    * **Install:** 1:22:54, **Backend:** 7232 requests/second (2 GB, 1x "Haswell, no TSX" - 6185 bogomips)
* Virmach
    * **Install:** 3:27:12, **Backend:** 1302 requests/second (4 GB, 3x "QEMU Virtual CPU" - 4399 bogomips)
* Vultr
    * **Install:** 0:59:09, **Backend:** 11568 requests/second (2 GB, 1x "Virtual CPU" - 5187 bogomips)

## Contributing

Fork, benchmark, and submit a PR - even for benchmark results. This project is licensed under MIT. Have fun!
