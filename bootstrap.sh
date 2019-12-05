#!/bin/bash
# shellcheck disable=2031,2030
set -euo pipefail
IFS=$'\n\t'

APNSCP_REPO="${APNSCP_REPO:-https://gitlab.com/apisnetworks/apnscp.git}"
LICENSE_URL="https://bootstrap.apnscp.com/"
APNSCP_HOME=/usr/local/apnscp
LICENSE_KEY="${APNSCP_HOME}/config/license.pem"
LOG_PATH="${LOG_PATH:-/root/apnscp-bootstrapper.log}"
# Feeling feisty and want to use screen or nohup
WRAPPER=${WRAPPER:-""}
RELEASE="${RELEASE:-""}"
# Further adjustments unnecessary
APNSCP_YUM="http://yum.apnscp.com/apnscp-release-latest-7.noarch.rpm"
RHEL_EPEL_URL="https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm"
APNSCP_VARS_FILE="${APNSCP_HOME}/resources/playbooks/apnscp-vars.yml"
#PYTHON_VERSION="python2.7"
#STRATEGY_PLUGIN_DIR="/usr/lib/${PYTHON_VERSION}/site-packages/ansible_mitogen/plugins/strategy"
BOOTSTRAP_STUB="/root/resume_apnscp_setup.sh"
BOOTSTRAP_COMMAND="cd "${APNSCP_HOME}/resources/playbooks" && env ANSIBLE_LOG_PATH=${LOG_PATH} BOOTSTRAP_SH=${BOOTSTRAP_STUB} $WRAPPER ansible-playbook -l localhost -c local bootstrap.yml"
KEY_UA="apnscp bootstrapper"
EXTRA_VARS=()
BOLD="\e[1m"
EMODE="\e[0m"
RED="\e[31m"
GREEN="\e[32m"

fatal() {
	echo -e "${RED}${BOLD}ERR:${EMODE} $1"
	echo -e "${RED}Installation failed${EMODE}"
	popd > /dev/null 2>&1
	exit 1
}

is_os() {
	case ${1,,} in
		"redhat") [[ -f /etc/redhat-release ]] && grep -q "Red Hat" /etc/redhat-release
			return $?;;
		"centos") [[ -f /etc/centos-release ]] && grep -q "CentOS" /etc/centos-release
			return $?;;
		*) fatal "Unknown OS $1"
	esac
}

is_8() {
	local FILE=/etc/centos-release
	[[ -f /etc/redhat-release ]] && FILE=/etc/redhat-release
	grep -qE '\b8\.' $FILE
	return $?
}

test -z "${DEBUG+x}" && test -f "$(dirname "$LICENSE_KEY")/config.ini" && fatal "apnscp already installed"

force_upgrade() {
	VERFILE="/etc/centos-release"
	if is_os redhat; then
		VERFILE="/etc/redhat-release"
	fi
	if grep -qE '\b(7\.7|8\.)' "$VERFILE"; then
		return 0
	fi
	echo -e "${BOLD}Updating OS. Old version detected!${EMODE}"
	yum upgrade -y
}

install_yum_pkg() {
	yum -y install "$@"
	STATUS=$?
	if [[ $STATUS -ne 0 ]] ; then
		fatal "failed to install RPM $*"
	fi
}

provisional_copy_config() {
	([[ ! -f /root/"$(basename "${APNSCP_VARS_FILE}")" ]] && cp "${APNSCP_VARS_FILE}" /root) || true
}

set_vars() {
	test "${#EXTRA_VARS[@]}" -eq 0 && return
	provisional_copy_config
	VARS_FILE="/root/$(basename "${APNSCP_VARS_FILE}")"
	for VAR in "${EXTRA_VARS[@]}"; do
		( gawk '
		{
			idx = index($0,"=")
			if (idx == 0) {
				# Garbage input
				exit
			}
			VAR[1] = substr($0, 0, idx-1);
			VAR[2] = substr($0, idx+1);
			regex = "^"VAR[1]":"
			found = 0
			if (VAR[2] ~ /^\[/) {
				VAR[2] = "\042"VAR[2]"\042"
			}
			while (( getline line < "'"$VARS_FILE"'") > 0 ) {
				where = match(line, regex)
				if (where != 0) {
					print VAR[1]": "VAR[2]
					found=1
				} else {
					print line;
				}
			}
			if (!found) {
				print VAR[1]": "VAR[2]
			}
		}' <<< "$VAR") > "${VARS_FILE}.$$" && mv "${VARS_FILE}.$$" "$VARS_FILE"
	done
}

prompt_edit() {
	test -t 1 || return 1
	while true; do
		read -r -t 30 -p "Do you wish to edit initial configuration? Installation resumes in 30 seconds automatically. [y/n] " yn < /dev/tty
		STATUS=$?
		test $STATUS -ne 0 && return 1
		case $yn in
				[Yy]* ) return 0;;
				[Nn]* ) return 1;;
				* ) echo "Please answer yes or no.";;
		esac
	done
}

save_exit() {
	echo -e "#!/bin/sh\n${BOOTSTRAP_COMMAND}" > "${BOOTSTRAP_STUB}"
	chmod 755 "${BOOTSTRAP_STUB}"
	provisional_copy_config
	echo -e "${GREEN}SUCCESS! apnscp-vars.yml has been copied to /root${EMODE}"
	echo ""
	echo "Edit apnscp-vars.yml with nano or vi:"
	echo -e "${BOLD}nano /root/apnscp-vars.yml${EMODE}"
	echo ""
	echo "Make changes then rerun the bootstrapper as:"
	echo -e "${BOLD}sh ${BOOTSTRAP_STUB}${EMODE}"
	exit 0
}

activate_key() {
	KEY=$1
	CN=${2:+/$2}
	[[ ${#KEY} -ge 10 ]] || fatal "Invalid activation key. Visit https://my.apnscp.com to purchase a key"
	fetch_license /activate/"$KEY""$CN"
	return 0
}

fetch_license() {
	URL=${1:-""}
	TMPKEY=$(mktemp license.XXXXXX)
	CODE=""
	ERROR=""
	yum clean all
	install_yum_pkg curl

	# Capturing stderr and stdout and the HTTP status message is a little harder than anticipated
	eval "$( (curl -sS -w '%{http_code}' -A "$KEY_UA" -o "$TMPKEY" "${LICENSE_URL}${URL}") \
		2> >(readarray -t ERROR; typeset -p ERROR) \
		 > >(readarray -t CODE; typeset -p CODE) )"

	STATUS=$?
	if [[ $CODE -ge 300 || $CODE -lt 200 ]]; then
		ERROR="$(cat "$TMPKEY")"
		rm -f "$TMPKEY"
	fi
	[[ $STATUS -ne 0 || $CODE -ge 300 || $CODE -lt 200 ]] && fatal "Failed to fetch activation key: ($CODE) ${ERROR:-rate-limited}"
	install_key "$TMPKEY"
	return 0
}

install_key() {
	KEY=$1
	[[ -f $KEY ]] || fatal "License key ${KEY} does not exist"
	[[ -f $LICENSE_KEY ]] && mv -f ${LICENSE_KEY}{,.old}
	mkdir -p "$(dirname "$LICENSE_KEY")"
	cp "$KEY" "$LICENSE_KEY"
	return 0
}

install() {
	if is_8; then
		fatal "CentOS/RHEL 8 is not supported yet"
	fi
	force_upgrade
	if is_os centos; then
		install_yum_pkg epel-release
	elif is_os redhat; then
		rpm -Uhv "$RHEL_EPEL_URL" || true
	fi
	install_yum_pkg gawk ansible libselinux-python git yum-plugin-priorities yum-plugin-fastestmirror nano yum-utils screen
	install_apnscp_rpm
	install_dev
	echo "Switching to stage 2 bootstrapper..."
	echo ""
	sleep 1
	set_vars
	prompt_edit && save_exit
	pushd $APNSCP_HOME/resources/playbooks
	trap 'fatal "Stage 2 bootstrap failed\nRun '\''$BOOTSTRAP_COMMAND'\'' to resume"' EXIT
	eval "$BOOTSTRAP_COMMAND"
	trap - EXIT
}

install_apnscp_rpm() {
	rpm -ihv --force "$APNSCP_YUM"
}

install_dev() {
	pushd "$APNSCP_HOME"
	if test "$RELEASE" == ""; then
		git init
		git remote add origin "$APNSCP_REPO"
		git fetch --tags
		git checkout "$(git for-each-ref --sort=taggerdate --format '%(tag)' refs/tags | grep '^v' | tail -n 1)"
	else
		git clone --bare --depth=1 --branch "$RELEASE" "$APNSCP_REPO" .git
		git config --unset core.bare
		git reset --hard
	fi
	git submodule update --init --recursive
	pushd $APNSCP_HOME/config
	find . -type f -iname '*.dist' | while read -r file ; do cp "$file" "${file%.dist}" ; done
	popd
}

MODE=""

while getopts "hs:k:t" opt ; do
	case $opt in
		"s")
			if [[ ! $OPTARG =~ ^[a-z]{1,}[a-z_0-9]{1,}=.+$ ]] ; then
				echo -e \
						"Invalid argument ${OPTARG} - pass as key=val\n" \
						"Yaml must be doubly escaped with \"\" and ''\n" \
						"\n" \
						"Examples:\n" \
						"-s apnscp_admin_email=me@apnscp.com -s apnscp_admin_password=superinsecure\n" \
						"-s ssl_certificates=\\"['apnscp.com','someotherdomain.com']\\"\n" \
						"-s watchdog_load_threshold=\"'{{ ansible_processor_count * 15 }}'\"\n"
				exit
			fi
			EXTRA_VARS+=("$OPTARG")
		;;

		"h")
			echo -e "${BOLD}Usage${EMODE}: $(basename "$0") [-s OPTION=VALUE...] [-k KEYFILE] | <ACTIVATION KEY>\n"
			echo "Install apnscp release. Either a key file in PEM format required (license.pem)"
			echo "or if a fresh license activated, the license key necessary"
			exit 1
		;;
		"k")
			KEY=$OPTARG
			[[ ${OPTARG:0:1} != "/" ]] && KEY=$PWD/$KEY
			install_key "$(realpath "$OPTARG")"
			MODE=install
		;;
		"t")
			# Same as trial
			MODE="install"
		;;
		\?)
			fatal "Incomplete or unknown option \`$opt'"
		;;
	esac
done
shift $((OPTIND-1))

if [[ "$MODE" != "install" ]]; then
	[[ $# != 0 ]] && activate_key "$1" "${2:-}"
	[[ $# == 0 ]] && fetch_license
fi

install
