#!/bin/bash
# Unattended GitLab Installation for Ubuntu Server 12.04 and 13.04 64-Bit
#
# Maintainer: @caseyscarborough
# GitLab Version: 6.1
#
# This script installs GitLab server on Ubuntu Server 12.04 or 13.04 with all dependencies.
#
# INFORMATION
# Distribution      : Ubuntu 12.04 & 13.04 64-Bit
# GitLab Version    : 6.1
# Web Server        : Nginx
# Init System       : systemd
# Database          : MySQL
# Contributors      : @caseyscarborough
#
# USAGE
# curl https://raw.github.com/caseyscarborough/gitlab-install/master/ubuntu-server-12.04.sh | 
#   sudo DOMAIN_VAR=gitlab.example.com bash

function install_packages() {
  echo -n "*== Install "
  until [ -z $1 ]
  do
    sudo DEBIAN_FRONTEND='noninteractive' apt-get install -qq -y $1 > /dev/null
    ret=$?
    if [[ $ret -ne 0 ]]
    then
      echo -n "$1(FAILED) "
    else
      echo -n "$1 "
    fi
    shift
  done
  echo -e "complete\n"
}

# Set the application user and home directory.
APP_USER=git
USER_ROOT=/home/$APP_USER

# Set the application root.
APP_ROOT=$USER_ROOT/gitlab

GITLAB_SHELL_ROOT=$USER_ROOT/gitlab-shell

# Set the URL for the GitLab instance.
GITLAB_URL="http:\/\/$DOMAIN_VAR\/"

GITLAB_SHELL_BRANCH="master"

GITLAB_BRANCH="6-4-stable"

# Check for domain variable.
if [ $DOMAIN_VAR ]; then
  echo -e "*==================================================================*\n"

  echo -e " GitLab Installation has begun!\n"
  
  echo -e "   Domain: $DOMAIN_VAR"
  echo -e "   GitLab URL: http://$DOMAIN_VAR/"
  echo -e "   Application Root: $APP_ROOT\n"
  
  echo -e "*==================================================================*\n"
  sleep 3
else
  echo "Please specify DOMAIN_VAR"
  exit
fi

## 
# Installing Packages
#
echo -e "\n*== Installing new packages...\n"
sudo DEBIAN_FRONTEND='noninteractive' apt-get update -qq -y > /dev/null
sudo DEBIAN_FRONTEND='noninteractive' apt-get upgrade -qq -y > /dev/null
install_packages build-essential makepasswd curl git-core openssh-server checkinstall libxml2-dev libxslt-dev libcurl4-openssl-dev libicu-dev python-docutils python-software-properties
# sudo DEBIAN_FRONTEND='noninteractive' apt-get install -y postfix-policyd-spf-python postfix


# Generate passwords for MySQL root and gitlab users.
MYSQL_ROOT_PASSWORD=$(makepasswd --char=25)
MYSQL_GIT_PASSWORD=$(makepasswd --char=25)

##
# Installing redis
#
echo -e "\n*== Installing redis...\n"
install_packages redis-server

##
# Download and compile Ruby
#
echo -e "\n*== Downloading and configuring Ruby...\n"
sudo DEBIAN_FRONTEND='noninteractive' add-apt-repository -y ppa:brightbox/ruby-ng-experimental >/dev/null
sudo DEBIAN_FRONTEND='noninteractive' apt-get update -qq > /dev/null
sudo DEBIAN_FRONTEND='noninteractive' apt-get purge -qq -y ruby1.8 > /dev/null
install_packages ruby2.0 ruby2.0-dev
sudo gem install bundler --no-ri --no-rdoc

# Add the git user.
sudo adduser --disabled-login --gecos 'GitLab' $APP_USER
cd $USER_ROOT
##
# MySQL Installation
# 
echo -e "\n*== Installing MySQL Server...\n"
echo mysql-server mysql-server/root_password password $MYSQL_ROOT_PASSWORD | sudo debconf-set-selections
echo mysql-server mysql-server/root_password_again password $MYSQL_ROOT_PASSWORD | sudo debconf-set-selections
install_packages mysql-server mysql-client libmysqlclient-dev

echo -e "\n*== Configuring MySQL Server...\n"
# Secure the MySQL installation and add GitLab user and database.
sudo echo -e "GRANT USAGE ON *.* TO ''@'localhost';
DROP USER ''@'localhost';
DROP DATABASE IF EXISTS test;
CREATE USER 'git'@'localhost' IDENTIFIED BY '$MYSQL_GIT_PASSWORD';
CREATE DATABASE IF NOT EXISTS gitlabhq_production DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;
GRANT SELECT, LOCK TABLES, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER ON gitlabhq_production.* TO 'git'@'localhost';
" > /tmp/gitlab.sql
mysql -u root -p$MYSQL_ROOT_PASSWORD -e "SOURCE /tmp/gitlab.sql"
sudo rm /tmp/gitlab.sql

##
# Update Git
#
echo -e "\n*== Updating Git...\n"
sudo DEBIAN_FRONTEND='noninteractive' add-apt-repository -y ppa:git-core/ppa  >/dev/null
sudo DEBIAN_FRONTEND='noninteractive' apt-get update -qq > /dev/null
install_packages git

##
# Set up the Git configuration.
#
echo -e "\n*== Configuring Git...\n"
sudo -u $APP_USER -H git config --global user.name "GitLab"
sudo -u $APP_USER -H git config --global user.email "gitlab@localhost"
sudo -u $APP_USER -H git config --global core.autocrlf input

## 
# Install GitLab Shell
#
echo -e "\n*== Installing GitLab Shell ($GITLAB_SHELL_BRANCH to $GITLAB_SHELL_ROOT)...\n"
sudo -u $APP_USER -H git clone https://github.com/gitlabhq/gitlab-shell.git $GITLAB_SHELL_ROOT
cd $GITLAB_SHELL_ROOT
sudo -u $APP_USER -H git checkout $GITLAB_SHELL_BRANCH
sudo -u $APP_USER -H cp config.yml.example config.yml
sudo sed -i 's/http:\/\/localhost\//'$GITLAB_URL'/' $GITLAB_SHELL_ROOT/config.yml
sudo -u $APP_USER -H ./bin/install
sudo -u $APP_USER -H git commit -am "Initial config"
cd $USER_ROOT
## 
# Install GitLab
#
echo -e "\n*== Installing GitLab ($GITLAB_BRANCH to $APP_ROOT)...\n"
sudo -u $APP_USER -H git clone https://github.com/gitlabhq/gitlabhq.git $APP_ROOT
cd $APP_ROOT
sudo -u $APP_USER -H git checkout $GITLAB_BRANCH
sudo -u $APP_USER -H mkdir $USER_ROOT/gitlab-satellites
sudo -u $APP_USER -H cp $APP_ROOT/config/gitlab.yml.example $APP_ROOT/config/gitlab.yml
sudo sed -i "s/host: localhost/host: ${DOMAIN_VAR}/" $APP_ROOT/config/gitlab.yml
sudo -u $APP_USER cp config/database.yml.mysql config/database.yml
sudo sed -i 's/"secure password"/"'$MYSQL_GIT_PASSWORD'"/' $APP_ROOT/config/database.yml
sudo -u $APP_USER -H chmod o-rwx config/database.yml
sudo -u $APP_USER -H cp config/unicorn.rb.example config/unicorn.rb
sudo -u $APP_USER -H git commit -am "Initial config"
cd $USER_ROOT
##
# Update permissions.
#
echo -e "\n*== Updating permissions...\n"

# Make sure GitLab can write to the log/ and tmp/ directories
for folder in log/ tmp/
do
	sudo chown -R $APP_USER $folder	
	sudo chmod -R u+rwX $folder
done

# Create public/uploads directory otherwise backup will fail
# Create directories for sockets/pids and make sure GitLab can write to them
for folder in tmp/pids/ tmp/sockets/ public/uploads
do
	if [[ ! -d $folder ]]
	then
		sudo -u $APP_USER -H mkdir $folder
		sudo chmod -R u+rwX $folder
	fi
done

##
# Install required Gems.
#
echo -e "\n*== Installing required gems...\n"
cd $APP_ROOT
sudo gem install charlock_holmes --version '0.6.9.4'  --no-ri --no-rdoc >/dev/null
sudo -u $APP_USER -H bundle install --deployment --without development test postgres aws >/dev/null

##
# Run setup and add startup script.
#
sudo sed -i 's/ask_to_continue/# ask_to_continue/' lib/tasks/gitlab/setup.rake
sudo -u $APP_USER -H bundle exec rake gitlab:setup RAILS_ENV=production
sudo sed -i 's/# ask_to_continue/ask_to_continue/' lib/tasks/gitlab/setup.rake
sudo cp lib/support/init.d/gitlab /etc/init.d/gitlab
sudo chmod +x /etc/init.d/gitlab
sudo update-rc.d gitlab defaults 21

##
# Nginx installation
#
echo -e "\n*== Installing Nginx...\n"
install_packages nginx
sudo cp lib/support/nginx/gitlab /etc/nginx/sites-available/gitlab
sudo ln -s /etc/nginx/sites-available/gitlab /etc/nginx/sites-enabled/gitlab
sudo sed -i "s/YOUR_SERVER_FQDN/${DOMAIN_VAR}/" /etc/nginx/sites-enabled/gitlab
sudo sed -i "s/127.0.0.1\tlocalhost/127.0.0.1\t${DOMAIN_VAR}/" /etc/hosts
cd $USER_ROOT

# Start GitLab and Nginx!
echo -e "\n*== Starting Gitlab!\n"
sudo service gitlab start
sudo service nginx restart

echo -e "root: ${MYSQL_ROOT_PASSWORD}\ngitlab: ${MYSQL_GIT_PASSWORD}"  sudo tee -a $APP_ROOT/config/mysql.yml
sudo -u $APP_USER -H chmod o-rwx $APP_ROOT/config/database.yml

echo -e "*==================================================================*\n"

echo -e " GitLab has been installed successfully!"
echo -e " Navigate to $DOMAIN_VAR in your browser to access the application.\n"

echo -e " Login with the default credentials:"
echo -e "   admin@local.host"
echo -e "   5iveL!fe\n"

echo -e " Your MySQL username and passwords are located in the following file:"
echo -e "   $APP_ROOT/config/mysql.yml\n"

echo -e " Script written by Casey Scarborough, 2013."
echo -e " https://github.com/caseyscarborough\n"

echo -e "*==================================================================*"
