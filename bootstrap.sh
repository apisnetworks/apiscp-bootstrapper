#!/bin/sh
set -euo pipefail
IFS=$'\n\t'

BOOTSTRAP_REPO="https://github.com/apisnetworks/apnscp-bootstrapper.git"
APNSCP_DEV_REPO="${APNSCP_DEV_REPO:-https://bitbucket.org/apisnetworks/apnscp.git}"
LICENSE_URL="https://bootstrap.apnscp.com/"
APNSCP_HOME=/usr/local/apnscp
LICENSE_KEY="${APNSCP_HOME}/config/license.pem"
LOG_PATH="${LOG_PATH:-/root/apnscp-bootstrapper.log}"
# Feeling feisty and want to use screen or nohup
WRAPPER=${WRAPPER:-""}
TEMP_KEY="~/.apnscp.key"
APNSCP_YUM="http://yum.apnscp.com/apnscp-release-latest-7.noarch.rpm"
BOLD="\e[1m"
EMODE="\e[0m"
RED="\e[31m"
GREEN="\e[32m"
ECOLOR="\e[39m"
BOOTSTRAP_STUB="/root/resume_apnscp_setup.sh"
BOOTSTRAP_COMMAND="cd "${APNSCP_HOME}/resources/playbooks" && env ANSIBLE_LOG_PATH="${LOG_PATH}" $WRAPPER ansible-playbook -l localhost -c local bootstrap.yml"

function fatal {
  echo -e "${RED}${BOLD}ERR:${EMODE} $1"
  echo -e "${RED}Installation failed${EMODE}"
  popd > /dev/null
  exit 1
}

[[ -f `dirname $LICENSE_KEY`/config.ini ]] && fatal "apnscp already installed"

function install_yum_pkg {
  yum -y install $@
  if [[ $? -ne 0 ]] ; then
    fatal "failed to install RPM $@"
  fi
}

function trial {
  echo "Visit https://my.apnscp.com/ to get an activation key for a free 30-day trial."
  exit 0
}

function prompt_edit {
  test -t 1 || return 1
  while true; do
    read -p "Do you wish to edit initial configuration? [y/n]" yn < /dev/tty
    case $yn in
        [Yy]* ) return 0;;
        [Nn]* ) return 1;;
        * ) echo "Please answer yes or no.";;
    esac
  done
}

function save_exit {
  echo -e "#!/bin/sh\n${BOOTSTRAP_COMMAND}" > "${BOOTSTRAP_STUB}"
  chmod 755 "${BOOTSTRAP_STUB}"
  cp "${APNSCP_HOME}/resources/playbooks/apnscp-vars.yml" /root
  echo -e "${GREEN}SUCCESS! apnscp-vars.yml has been copied to /root${EMODE}"
  echo ""
  echo "Edit apnscp-vars.yml with nano or vi:"
  echo -e "${BOLD}nano /root/apnscp-vars.yml${EMODE}"
  echo ""
  echo "Make changes then rerun the bootstrapper as:"
  echo -e "${BOLD}sh ${BOOTSTRAP_STUB}${EMODE}"
  exit 0
}

function request_key {
  KEY=$1
  [[ ${#KEY} == 32 ]] || fatal "Invalid activation key. Must be 32 characters long. Visit https://my.apnscp.com"
  TMPKEY=`mktmp license.XXXXXX`
  install_yum_pkg curl 
  curl -O $TMPKEY $LICENSE_URL/activate/$KEY
  [[ $? -ne 0 ]] && fatal "Failed to fetch activation key."
  install_key $TMPKEY
  return 0
}

function install_key {
  KEY=$1
  [[ -f $KEY ]] || fatal "License key ${KEY} does not exist"
  [[ -f $LICENSE_KEY ]] && mv -f ${LICENSE_KEY}{,.old}
  mkdir -p `dirname $LICENSE_KEY`
  cp $KEY $LICENSE_KEY
  return 0
}

function install {
  install_yum_pkg epel-release
  install_yum_pkg ansible git yum-plugin-priorities nano yum-utils screen
  install_dev
  install_apnscp_rpm
  echo "Switching to stage 2 bootstrapper..."
  echo ""
  sleep 1
  prompt_edit && save_exit
  pushd $APNSCP_HOME/resources/playbooks
  trap 'fatal "Stage 2 bootstrap failed\nRun '\''$BOOTSTRAP_COMMAND\'' to resume"' EXIT
  eval $BOOTSTRAP_COMMAND
  trap - EXIT
}

function install_apnscp_rpm {
  rpm -ihv --force $APNSCP_YUM
}

function install_dev {
  pushd $APNSCP_HOME
  git init
  git remote add origin $APNSCP_DEV_REPO
  git fetch --depth=1
  git checkout -t origin/master
  git submodule update --init --recursive
  pushd $APNSCP_HOME/config
  find . -type f -iname '*.dist' | while read file ; do cp "$file" "${file%.dist}" ; done
  popd
}

#install_bootstrapper
#exit

while getopts "hk:t" opt ; do 
  case $opt in
    "h")
      echo -e "${BOLD}Usage${EBOLD}: `basename $0` [-k KEYFILE] | <ACTIVATION KEY>"
      echo "Install apnscp release. Either a key file in PEM format required (license.pem)"
      echo "or if a fresh license activated, the license key necessary"
      exit 1
    ;; 
    "k")
      KEY=$OPTARG
      [[ ${OPTARG:0:1} != "/" ]] && KEY=$PWD/$KEY
      install_key `realpath $OPTARG` && install
      exit 0
    ;;
    "t")
      trial
      exit 0
    ;;
    "i")
      install
      exit 0
    ;;
    \?)
      fatal "Unknown option \`$opt'"
    ;;
  esac
done
[[ $# -ne 1 ]] && fatal "Missing license key"
request_key $1 && install
