#!/bin/sh
set -euo pipefail

BOOTSTRAP_REPO="https://github.com/apisnetworks/apnscp-boostrapper.git"
LICENSE_URL="https://license.apnscp.com/"
LICENSE_KEY=/usr/local/apnscp/config/license.pem

BOLD="\e[1m"
EMODE="\e[0m"
RED="\e[31m"
ECOLOR="\e[39m"

function install_yum_pkg {
  PKGS=$@
  yum -y install $@
  [[ $? -ne 0 ]] && fatal "failed to install RPM $@"
}

TMPDIR=`mktemp -d tmp.XXXXXX`
pushd $TMPDIR > /dev/null || ( echo "failed to create temp dir?" && exit 1 )

function fatal {
  echo -e "${RED}${BOLD}ERR:${EMODE} $1"
  echo -e "${RED}Installation failed${EMODE}, temporary work files left in ${RED}$TMPDIR${EMODE}"
  popd > /dev/null
  #rm -rf $TMPDIR
  exit 1
}

function trial {
  echo "Visit https://my.apnscp.com/ to get an activation key for a free 30-day trial."
  exit 0
}

function get_key {
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
  [[ -f $LICENSE_KEY ]] && mv ${LICENSE_KEY}{,.old}
  mkdir -p `dirname $LICENSE_KEY`
  mv $KEY $LICENSE_KEY

  return 0
}

function install {
  install_yum_pkg epel-release
  install_yum_pkg ansible git
  git clone $BOOTSTRAP_REPO apnscp-bootstrapper
  exec ./apnscp-bootstrapper/install.sh
}

while getopts "hk:t" opt ; do 
  case $opt in
    "h")
      echo -e "${BOLD}Usage${EBOLD}: `basename $0` [-k KEYFILE] | KEY"
      echo "Install apnscp release. Either a key file in PEM format required (license.pem)"
      echo "or if a fresh license activated, the license key necessary"
      exit 1
    ;; 
    "k") 
      install_key $OPTARG && install
      exit 0
      ;;
    "t")
      trial
      exit 0
      ;;
    \?)
      fatal "Unknown option \`$opt'"
    ;;
  esac
done
[[ $# -ne 1 ]] && fatal "Missing license key"
get_key $1 && install
