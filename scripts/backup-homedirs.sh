#!/bin/bash

backup_all_homedirs() {
  for HOME_DIR in $(ls /home | grep -Ev 'backups|images|iso|VMs|vmware')
  do
    sudo tar czf /home/backups/${HOME_DIR}.tgz ${HOME_DIR}
  done
}

backup_one_homedir() {
  if ls /home | grep -q ${1}
  then
    sudo tar czf /home/backups/${1}.tgz ${1}
  else
    echo "The home directory \"${1}\" doesn't seem to exist."
  fi
}

##############################################################################

cd /home

if ! [ -e /home/backups ]
then
  sudo mkdir /home/backups
fi

if [ -z ${1} ]
then
  backup_all_homedirs $*
else
  backup_one_homedir $*
fi

