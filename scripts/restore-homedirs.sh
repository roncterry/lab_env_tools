#!/bin/bash

restore_all_homedirs()
{
  for HOME_DIR in $(ls /home | grep -Ev 'backups|images|iso|VMs|vmware')
  do
    sudo /usr/sbin/rcxdm stop
    #sleep 5

    if ls /home/backups | grep -q ${HOME_DIR}
    then
      cd /home
      sudo rm -rf /home/${HOME_DIR}
      sudo tar xzf /home/backups/${HOME_DIR}.tgz
      echo "restored: $(date)" > /home/${HOME_DIR}/RESTORED
      sudo chown -R ${HOME_DIR} /home/${HOME_DIR}
    fi

    sleep 5
    sudo /usr/sbin/rcxdm start
  done
}

restore_one_homedir() {
  if ls /home/backups | grep -q ${1}.tgz
  then
    sudo /usr/sbin/rcxdm stop
    #sleep 5

    cd /home
    sudo rm -rf /home/${1}
    sudo tar xzf /home/backups/${1}.tgz
    echo "restored: $(date)" > /home/${1}/RESTORED
    sudo chown -R ${1} /home/${1}

    sleep 5
    sudo /usr/sbin/rcxdm start
  else
    echo "There does not seem to be a backup for \"${1}\"."
  fi
}

##############################################################################

cd /home

if [ -z ${1} ]
then
  restore_all_homedirs $*
else
  restore_one_homedir $*
fi

