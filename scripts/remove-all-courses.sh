#!/bin/bash
#
# version: 20161113.001

###############################################################################
#                global vars
###############################################################################

if [ -z ${1} ]then
  LAB_USER=tux
else
  if grep -q ${1} /etc/passwd
  then
    LAB_USER=${1}
  else
    LAB_USER=tux
  fi
fi

if [ -z ${2} ]then
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

remove_all_courses() {
  for COURSE in $(ls /home/${LAB_USER}/scripts)
  do 
    if [ -e  /home/${LAB_USER}/scripts/${COURSE}/remove_lab_env.sh ]
    then
      cd /home/${LAB_USER}/scripts/${COURSE}
      bash remove_lab_env.sh
      cd -
    else
      echo "No course to remove."
    fi
  done
}

main() {
  echo
  echo "----------------------------------------------------------------------"
  echo "Removing all installed courses for user ${LAB_USER} ..."
  echo
  remove_all_courses
}


###############################################################################
#                main code body
###############################################################################

main
