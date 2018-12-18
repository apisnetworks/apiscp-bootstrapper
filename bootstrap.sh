#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

APNSCP_REPO="${APNSCP_REPO:-https://gitlab.com/apisnetworks/apnscp.git}"
LICENSE_URL="https://bootstrap.apnscp.com/"
APNSCP_HOME=/usr/local/apnscp
LICENSE_KEY="${APNSCP_HOME}/config/license.pem"
LOG_PATH="${LOG_PATH:-/root/apnscp-bootstrapper.log}"
# Feeling feisty and want to use screen or nohup
WRAPPER=${WRAPPER:-""}
APNSCP_YUM="http://yum.apnscp.com/apnscp-release-latest-7.noarch.rpm"
RHEL_EPEL_URL="https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm"
APNSCP_VARS_FILE="${APNSCP_HOME}/resources/playbooks/apnscp-vars.yml"
BOOTSTRAP_STUB="/root/resume_apnscp_setup.sh"
BOOTSTRAP_COMMAND="cd "${APNSCP_HOME}/resources/playbooks" && env ANSIBLE_LOG_PATH=${LOG_PATH} $WRAPPER ansible-playbook -l localhost -c local bootstrap.yml"
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


test -z "${DEBUG+x}" && test -f "$(dirname "$LICENSE_KEY")/config.ini" && fatal "apnscp already installed"

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
  [[ ${#KEY} == 60 ]] || fatal "Invalid activation key. Must be 60 characters long. Visit https://my.apnscp.com"
  return "$(fetch_license /activate/"$KEY")"
}

fetch_license() {
  URL=${1:-""}
  TMPKEY=$(mktemp license.XXXXXX)
  install_yum_pkg curl
  curl -A "$KEY_UA" -o "$TMPKEY" "${LICENSE_URL}${URL}"
  STATUS=$?
  [[ $STATUS -ne 0 ]] && fatal "Failed to fetch activation key."
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
  if is_os centos; then
    install_yum_pkg epel-release
  elif is_os redhat; then
    rpm -Uhv "$RHEL_EPEL_URL" || true
  fi
  install_yum_pkg gawk ansible git yum-plugin-priorities yum-plugin-fastestmirror nano yum-utils screen
  install_dev
  install_apnscp_rpm
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
  git init
  git remote add origin "$APNSCP_REPO"
  git fetch --depth=1
  git checkout -t origin/master
  git submodule update --init --recursive
  pushd $APNSCP_HOME/config
  find . -type f -iname '*.dist' | while read -r file ; do cp "$file" "${file%.dist}" ; done
  popd
}

#install_bootstrapper
#exit
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
	[[ $# != 0 ]] && activate_key "$1"
	[[ $# == 0 ]] && fetch_license
fi

install
