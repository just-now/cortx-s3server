#!/bin/sh

set -xe

SCRIPT_PATH=$(readlink -f "$0")
BASEDIR=$(dirname "$SCRIPT_PATH")
S3_SRC_DIR="$BASEDIR/../../../"
CURRENT_DIR=`pwd`

OS=$(cat /etc/os-release | grep -w ID | cut -d '=' -f 2)
source ${S3_SRC_DIR}/scripts/env/common.sh

yum install rpm-build -y
rpm -q git || yum install -y git

#It seems mero dependency script install s3cmd(2.0.0)
#for s3 system test we need patched s3cmd(1.6.1), which s3 ansible installs
rpm -q s3cmd && rpm -e s3cmd --nodeps

if [ "$os_major_version" = "8" ]; then
  yum install @development -y
fi

cd $BASEDIR

# Attempt ldap clean up since ansible openldap setup is not idempotent
systemctl stop slapd 2>/dev/null || /bin/true
yum remove -y openldap-servers openldap-clients || /bin/true
rm -f /etc/openldap/slapd.d/cn\=config/cn\=schema/cn\=\{1\}s3user.ldif
rm -rf /var/lib/ldap/*
rm -f /etc/sysconfig/slapd* 2>/dev/null || /bin/true
rm -f /etc/openldap/slapd* 2>/dev/null || /bin/true
rm -rf /etc/openldap/slapd.d/*

# Tools for ssl certificate generation
yum install -y openssl java-1.8.0-openjdk-headless

# Generate the certificates rpms for dev setup
# clean up
rm -f ~/rpmbuild/RPMS/x86_64/stx-s3-certs*
rm -f ~/rpmbuild/RPMS/x86_64/stx-s3-client-certs*

cd ${BASEDIR}/../../../rpms/s3certs
# Needs openssl and jre which are installed with rpm_build_env
./buildrpm.sh -T s3dev

# install the built certs
rpm -e stx-s3-certs stx-s3-client-certs || /bin/true
yum install openldap-servers haproxy -y # so we have "ldap" and "haproxy" users.
yum localinstall -y ~/rpmbuild/RPMS/x86_64/stx-s3-certs*
yum localinstall -y ~/rpmbuild/RPMS/x86_64/stx-s3-client-certs*

# Configure dev env
yum install -y ansible facter

cd ${BASEDIR}/../../../ansible

# Update ansible/hosts file with local ip
cp -f ./hosts ./hosts_local
sed -i "s/^xx.xx.xx.xx/127.0.0.1/" ./hosts_local

# Setup dev env
ansible-playbook -i ./hosts_local --connection local setup_s3dev_centos75_8.yml -v  -k --extra-vars "s3_src=${S3_SRC_DIR}"

rm -f ./hosts_local

systemctl restart haproxy

sed  -ie '/secure_path/s/$/:\/opt\/seagate\/s3\/bin/' /etc/sudoers

if ! command -v python36 &>/dev/null; then
  if command -v python3.6 &>/dev/null; then
    ln -s "`command -v python3.6`" /usr/bin/python36
  else
    echo "Python v3.6 is not installed (neither python36 nor python3.6 are found in PATH)."
    exit 1
  fi
fi

cd ${CURRENT_DIR}
