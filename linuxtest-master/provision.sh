#!/usr/bin/env bash

if [ "$1" == "" ] ; then
	VER="56"
else
	VER="$1"
fi

printf "\nInitializing mysql.sh Version ($VER)...\n\n"

# NOTE: EPEL repo must be enabled in base.sh script per missing dependency in Percona repo:
# https://bugs.launchpad.net/percona-xtrabackup/+bug/1526636
if [[ ! -e /etc/yum.repos.d/epel.repo ]]; then yum -y install http://mirror.pnl.gov/epel/6/x86_64/epel-release-6-8.noarch.rpm; fi

# Install Percona MySQL Repo
yum install http://www.percona.com/downloads/percona-release/redhat/0.1-3/percona-release-0.1-3.noarch.rpm -y
# Install Percona MySQL Server, server headers, toolkit and Xtrabackup
yum install Percona-Server-server-$VER Percona-Server-devel-$VER percona-toolkit percona-xtrabackup -y

# Create mysql dir
if [[ ! -d /storage/db ]]; then mkdir -p /storage/db && ln -s /storage/db/ /db; fi
ln -s /var/lib/mysql/ /storage/db/mysql > /dev/null 2>&1
chown -R mysql:mysql /db/mysql

# Start MySQL Service
if pidof systemd > /dev/null ; then
	systemctl enable mysqld
	systemctl start mysqld
else
	chkconfig --add mysql
	service mysql start
fi


if ! grep password ~/.my.cnf > /dev/null 2>&1
then
	printf "Configure desired mysql_secure_installation defaults..."
	# This is not about local security, it about making sure root can't get attacked remotly easily by guessing no password.
	# The password is always initially set here and then populated in the ~/.my.cnf file
	mysql --user=root <<- EOF
	UPDATE mysql.user SET Password=PASSWORD('Secret1') WHERE User='root';
	DELETE FROM mysql.user WHERE User='';
	DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
	DROP DATABASE IF EXISTS test;
	DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
	FLUSH PRIVILEGES;
	EOF

	# ~/.my.cnf should never be there already when this script runs - it always initializes the mysql install
	printf "\nSetting up .my.cnf..."
	printf "
	[client]
	password=Secret1" >> ~/.my.cnf

	printf "
	[client]
	password=Secret1" >> /home/vagrant/.my.cnf

	printf "Done.\n"
fi

#Set centos to get files from vault
sudo sed -i s/mirror.centos.org/vault.centos.org/g /etc/yum.repos.d/*.repo
sudo sed -i s/^#.*baseurl=http/baseurl=http/g /etc/yum.repos.d/*.repo
sudo sed -i s/^mirrorlist=http/#mirrorlist=http/g /etc/yum.repos.d/*.repo
echo "sslverify=false" | sudo tee -a /etc/yum.conf

#Update system
sudo yum -y update

#Install tools
sudo yum -y install wget git autoconf subversion pkgconfig libtool \
    gcc gcc-c++ make ncurses-devel libxml2-devel sqlite-devel

#get Asterisk download
cd /usr/src/
sudo git clone https://github.com/asterisk/asterisk asterisk-22

cd asterisk-22

#Get mp3 files and pre-reqs
sudo contrib/scripts/get_mp3_source.sh
sudo contrib/scripts/install_prereq install

#Conig asterisk
sudo ./configure --with-jansson-bundle

# Uncomment this if you want to run menuselect
# sudo make menuselect

#building and installing asterisk
sudo make
sudo make install
sudo make samples
sudo make basic-pbx
sudo make config
sudo ldconfig

#Making an asterisk user
sudo useradd -r -M -d /var/lib/asterisk -c "Asterisk PBX" asterisk


cat <<EOF > /etc/sysconfig/asterisk
AST_USER="asterisk"
AST_GROUP="asterisk"
EOF

sudo usermod -a -G dialout,audio asterisk

#Setting permissions for asterisk user
sudo chown -R asterisk: /var/{lib,log,run,spool}/asterisk /usr/lib/asterisk /etc/asterisk
sudo chmod -R 750 /var/{lib,log,run,spool}/asterisk /usr/lib/asterisk /etc/asterisk

#Turning on asterisk and enabling it
sudo systemctl start asterisk
sudo systemctl enable asterisk

yum install -y httpd
sudo systemctl start  httpd.service

echo "You should be able to reach http://localhost:8080/ now   (unless the port was redirected.)"
