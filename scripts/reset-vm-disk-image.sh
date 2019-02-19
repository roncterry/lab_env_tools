#!/bin/bash
# version: 1.0.2
# date: 2019-02-19

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

usage() {
  echo
  echo -e "${GREEN}USAGE: ${GRAY}$0 <vm_name>${NC}"
  echo
  echo -e "Where: "
  echo -e "  ${GRAY}<vm_name>${NC} is the name of a VM's directory in your current working directory"
  echo -e "  the VM's directory has a disk image file named: ${GRAY}<vm_name>.qcow2${NC}"
  echo
}

if [ -z ${1} ]
then
  usage
  exit 1
else
  VM_NAME="$(echo ${1} | sed 's+/$++g')"
fi

if ! ls ${VM_NAME} > /dev/null 2>&1
then
  echo
  echo "${LTRED}ERROR: The VM directory ./${VM_NAME} doesn't appear to exist${NC}"
  echo
  exit 2
elif ! ls ${VM_NAME}/${VM_NAME}.xml > /dev/null 2>&1
then
  echo
  echo "${LTRED}ERROR: The config file ./${VM_NAME}/${VM_NAME}.xml doesn't appear to exist${NC}"
  echo
  exit 3
elif ! ls ${VM_NAME}/${VM_NAME}.qcow2 > /dev/null 2>&1
then
  echo
  echo "${LTRED}ERROR: The disk image file ./${VM_NAME}/${VM_NAME}.qcow2 doesn't appear to exist${NC}"
  echo
  exit 4
fi

DISK_SIZE=$(qemu-img info ${VM_NAME}/${VM_NAME}.qcow2 | grep "^virtual size" | awk '{ print $3 }')

echo
echo -e "${LTBLUE}======================================================================${NC}"
echo -e "${LTBLUE}Reseting the virtual disk: ${ORANGE}./${VM_NAME}/${VM_NAME}.qcow2${NC}"
echo -e "${LTBLUE}======================================================================${NC}"
echo

echo -e "${GREEN}COMMAND: ${GRAY}cd ./${VM_NAME}${NC}"
cd ./${VM_NAME}
echo

if [ $(qemu-img snapshot -l ${VM_NAME}.qcow2 | wc -l) -gt 0 ]
then
  SNAPSHOT_LIST=$(qemu-img snapshot -l ${VM_NAME}.qcow2 | awk '{ print $2 }' | grep -v list | grep -v TAG)

  echo -e "${LTCYAN}Reverting to the first snapshot ...${NC}"
  echo -e "${LTCYAN}------------------------------------------------------"
  echo -e "${GREEN}COMMAND: ${GRAY}qemu-img snapshot -a $(echo ${SNAPSHOT_LIST} | awk '{ print $1 }') ${VM_NAME}.qcow2${NC}"
  qemu-img snapshot -a $(echo ${SNAPSHOT_LIST} | awk '{ print $1 }') ${VM_NAME}.qcow2
  echo

  echo -e "${LTCYAN}Deleting all snapshots ...${NC}"
  echo -e "${LTCYAN}------------------------------------------------------${NC}"
  for SNAPSHOT in ${SNAPSHOT_LIST}
  do
    echo -e "${GREEN}COMMAND: ${GRAY}qemu-img snapshot -d ${SNAPSHOT} ${VM_NAME}.qcow2${NC}"
    qemu-img snapshot -d ${SNAPSHOT} ${VM_NAME}.qcow2
  done
  echo
else
  echo -e "${LTCYAN}No shapshots found. Reverting to blank disk image ...${NC}"
  echo -e "${LTCYAN}------------------------------------------------------${NC}"
  echo -e "${GREEN}COMMAND: ${GRAY}rm -f ${VM_NAME}.qcow2${NC}"
  rm -f ${VM_NAME}.qcow2
  #echo -e "${GREEN}COMMAND: ${GRAY}mv ${VM_NAME}.qcow2 ${VM_NAME}.qcow2.old${NC}"
  #mv ${VM_NAME}.qcow2 ${VM_NAME}.qcow2.old

  echo -e "${GREEN}COMMAND: ${GRAY}qemu-img create -f qcow2 ${VM_NAME}.qcow2 ${DISK_SIZE}${NC}"
  echo
  qemu-img create -f qcow2 ${VM_NAME}.qcow2 ${DISK_SIZE}
  echo
  qemu-img info ${VM_NAME}.qcow2
  echo
fi


cd - > /dev/null 2>&1

echo -e "${LTBLUE}=============================  Finished  =============================${NC}"
echo
