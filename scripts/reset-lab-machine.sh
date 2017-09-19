#!/bin/bash
#
# version: 20170919.001

###############################################################################
#                global vars
###############################################################################

if [ -z ${1} ]
then
  LAB_USER=tux
else
  if grep -q ${1} /etc/passwd
  then
    LAB_USER=${1}
  else
    LAB_USER=tux
  fi
fi

if [ -z ${2} ]
then
  COURSE_INSTALLER_DIR=/install/courses
else
  if [ -e ${2} ]
  then
    COURSE_INSTALLER_DIR=${2}
  else
    COURSE_INSTALLER_DIR=/install/courses
  fi
fi

###############################################################################
#                functions
###############################################################################

main() {
  echo
  echo "----------------------------------------------------------------------"
  echo "Removing all installed courses ..."
  echo
  /usr/local/bin/remove-all-courses.sh ${LAB_USER} ${COURSE_INSTALLER_DIR}

  echo
  echo "----------------------------------------------------------------------"
  echo "Removing all Libvirt VMs ..."
  echo
  /usr/local/bin/remove-all-vms.sh

  echo
  echo "----------------------------------------------------------------------"
  echo "Removing all Libvirt virtual networks ..."
  echo
  /usr/local/bin/remove-all-vnets.sh

  echo "----------------------------------------------------------------------"
  echo "Restoring home directories ..."
  echo
  /usr/local/bin/restore-homedirs.sh ${LAB_USER}
}


###############################################################################
#                main code body
###############################################################################

main
