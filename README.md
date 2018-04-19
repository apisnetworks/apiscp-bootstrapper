Bootstrap provides an automated installation process to setup apnscp on a compatible CentOS/RHEL machine.

# Usage
After registering on [my.apnscp.com](https://my.apnscp.com), use the token to automatically download the key.
```shell
./bootstrap.sh <api token>
```

Alternatively, if you have the x509 key (license.key) available,
```shell
./bootstrap.sh -k <key file>
```

