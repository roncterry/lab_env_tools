#!/bin/bash
# ver: 2019021201

if [ -e /etc/host-sshfs-dirs.cfg ]
then
  . /etc/host-sshfs-dirs.cfg
fi

if [ -z ${DIR_LIST} ]
then
  DIR_LIST="/home/VMs /home/iso /home/images /home/tux/scripts /home/tux/course_files /home/tux/pdf"
fi

if [ -z ${REMOTE_IP} ]
then
  REMOTE_IP=$(ip route show | grep default | awk '{ print $3 }')
fi

if [ -z ${REMOTE_USER} ]
then
  REMOTE_USER=tux
fi

if [ -z ${REMOTE_USER_PASSWD} ]
then
  REMOTE_USER_PASSWD=linux
fi

usage() {
  echo
  echo "USAGE:  ${0} mount|umount|list"
  echo
}

get_ssh_keys() {
  if ! grep -q ${REMOTE_IP} ~/.ssh/known_hosts
  then
    ssh-keyscan ${REMOTE_IP} > ~/.ssh/known_hosts
  fi
}

mount_sshfs_dirs() {
  for DIR in ${DIR_LIST}
  do
    echo "Mounting: ${REMOTE_USER}@${REMOTE_IP}:${DIR} ${DIR}"
    echo ${REMOTE_USER_PASSWD} | sshfs -o allow_other,default_permissions,nonempty,password_stdin ${REMOTE_USER}@${REMOTE_IP}:${DIR} ${DIR}
    mount | grep ${DIR}
    echo
  done
  echo "Currently Mounted Directories:"
  echo "---------------------------------------------------------------------"
  mount | grep sshfs | cut -d " " -f 1,2,3
  echo
}

umount_sshfs_dirs() {
  for DIR in ${DIR_LIST}
  do
    echo "Unmounting: ${REMOTE_USER}@${REMOTE_IP}:${DIR} from ${DIR}"
    umount ${DIR}
    echo
  done
  echo "Currently Mounted Directories:"
  echo "---------------------------------------------------------------------"
  mount | grep sshfs | cut -d " " -f 1,2,3
  echo
}

list_sshfs_dirs() {
  echo
  echo "SSHFS Directories to be mounted:"
  echo "-------------------------------------------------------"
  for DIR in ${DIR_LIST}
  do
    echo "${REMOTE_USER}@${REMOTE_IP}:${DIR} ${DIR}"
  done
  echo
}

show_sshfs_dirs() {
  echo
  echo "Currently Mounted Directories:"
  echo "---------------------------------------------------------------------"
  mount | grep sshfs | cut -d " " -f 1,2,3
  echo
}

#############################################################################

if id | grep -q "uid=0(root)"
then 
  if [ -z ${REMOTE_IP} ]
  then
    echo
    echo "ERROR: REMOTE_IP is not set."
    echo
    exit 1
  fi

  if [ -z ${1} ]
  then
    echo 
    echo "ERROR: You must specify either mount, umount or list."
    usage
    exit 1
  fi

  get_ssh_keys

  case ${1} in
    mount)
      mount_sshfs_dirs ${*}
    ;;
    umount)
      umount_sshfs_dirs ${*}
    ;;
    list)
      list_sshfs_dirs ${*}
    ;;
    show)
      show_sshfs_dirs ${*}
    ;;
    *)
      usage
    ;;
  esac
else
  echo
  echo "ERROR: You must be root to run this script (sudo OK)"
  echo
  exit
fi
