#!/bin/bash
# Version: 1.0.0
# Date: 2017-05-16

### Colors ###
RED='\e[0;31m'
LTRED='\e[1;31m'
BLUE='\e[0;34m'
LTBLUE='\e[1;34m'
GREEN='\e[0;32m'
LTGREEN='\e[1;32m'
ORANGE='\e[0;33m'
YELLOW='\e[1;33m'
CYAN='\e[0;36m'
LTCYAN='\e[1;36m'
PURPLE='\e[0;35m'
LTPURPLE='\e[1;35m'
GRAY='\e[1;30m'
LTGRAY='\e[0;37m'
WHITE='\e[1;37m'
NC='\e[0m'
##############

##############################################################################
#                 Functions
##############################################################################

usage() {
  echo
  echo "USAGE: $0 <Course VM Directory> <New VM Directory Path>"
  echo
}

change_vm_disk_paths() {
  echo
  echo -e "${LTBLUE}================================================${NC}"
  echo -e "${LTBLUE}  Updating VM: ${ORANGE}$(basename ${PWD})${NC}"
  echo -e "${LTBLUE}================================================${NC}"
  echo

  echo -e "${CYAN}  Changing disk paths to: ${LTPURPLE}${NEW_VM_DIR}${NC}"
  echo

  if ls *.xml > /dev/null 2>&1
  then
    for CONFIG_FILE in $(ls *.xml)
    do
      VM_DIR=$(dirname $(grep "source file" ${CONFIG_FILE} | cut -d \' -f 2 | head -1))
      DIR_DEPTH=$(echo ${VM_DIR} | grep -o "/" | wc -l)
      ORIG_VM_DIR=$(echo ${VM_DIR} | cut -d \/ -f $(seq -s , 1 ${DIR_DEPTH}))
  
      echo -e "${LTBLUE}  CONFIG_FILE: ${PURPLE}${CONFIG_FILE}${NC}"
      sed -i "s+${ORIG_VM_DIR}+${NEW_VM_DIR}+g" ${CONFIG_FILE}
    done
    echo
  else
    echo -e "${LTBLUE}(nothing to do)${NC}"
    echo
  fi

  cd - >/dev/null 2>&1
  echo 
}

##############################################################################
#                 Main Function
##############################################################################

main() {
  if ! [ -z ${1} ]
  then
    SOURCE_VM_DIR=${1}
  else
    echo
    echo -e "${LTRED}ERROR: You must supply a course VM directory.${NC}"
    usage
    exit 1
  fi

  if ! [ -z ${2} ]
  then
    NEW_VM_DIR=${2}
  else
    echo
    echo -e "${LTRED}ERROR: You must supply a new VM directory path.${NC}"
    usage
    exit 1
  fi

  echo 
  echo -e "${LTCYAN}####################################################################${NC}"
  echo -e "${LTCYAN}  Changing to course VM dir: ${ORANGE}${SOURCE_VM_DIR} ${NC}"
  echo -e "${LTCYAN}####################################################################${NC}"
  echo
  cd ${SOURCE_VM_DIR}

  for DIR in $(ls)
  do 
    cd ${DIR}
    change_vm_disk_paths
  done

  echo "############################  Finished  ###########################"
  echo
}

##############################################################################
#                 Main Code Body
##############################################################################

main $*
