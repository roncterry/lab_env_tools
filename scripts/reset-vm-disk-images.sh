#!/bin/bash
# version: 1.0.0
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
  echo -e "Where ${GRAY}<vm_name>${NC} is the name of a VM's directory in your current working "
  echo -e "directory and the VM's directory has a disk image file named: ${GRAY}<vm_name>.qcow2${NC}"
  echo
}

get_vm_disk_images() {
  if virsh list --all | grep -q ${VM_NAME}
  then
    DISK_IMAGE_LIST=$(virsh dumpxml ${VM_NAME} | grep "source file=.*.qcow2" | cut -d \' -f 2)
  else
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
    else
      DISK_IMAGE_LIST=$(grep "source file=.*.qcow2" ./${VM_NAME}/${VM_NAME}.xml | cut -d \' -f 2)
    fi
  fi

  echo
  echo -e "${LTBLUE}======================================================================${NC}"
  echo -e "${LTBLUE}Disks for VM: ${LTPURPLE}${VM_NAME}${NC}"
  for DISK_IMAGE in ${DISK_IMAGE_LIST}
  do
  echo -e "${LTBLUE}${ORANGE}${DISK_IMAGE}${NC}"
  done
  echo -e "${LTBLUE}======================================================================${NC}"
  echo
}

if [ -z ${1} ]
then
  usage
  exit 1
else
  VM_NAME="$(echo ${1} | sed 's+/$++g')"
fi

#echo -e "${GREEN}COMMAND: ${GRAY}cd ./${VM_NAME}${NC}"
#cd ./${VM_NAME}
#echo

get_vm_disk_images 

for DISK_IMAGE in ${DISK_IMAGE_LIST}
do
  DISK_SIZE=$(qemu-img info ${DISK_IMAGE} | grep "^virtual size" | awk '{ print $3 }')

  echo
  echo -e "${LTBLUE}======================================================================${NC}"
  echo -e "${LTBLUE}Reseting the virtual disk: ${ORANGE}${DISK_IMAGE}${NC}"
  echo -e "${LTBLUE}======================================================================${NC}"
  echo

  if [ $(qemu-img snapshot -l ${DISK_IMAGE} | wc -l) -gt 0 ]
  then
    SNAPSHOT_LIST=$(qemu-img snapshot -l ${DISK_IMAGE} | awk '{ print $2 }' | grep -v list | grep -v TAG)
  
    echo -e "${LTCYAN}Reverting to the first snapshot ...${NC}"
    echo -e "${LTCYAN}------------------------------------------------------"
    echo -e "${GREEN}COMMAND: ${GRAY}qemu-img snapshot -a $(echo ${SNAPSHOT_LIST} | awk '{ print $1 }') ${DISK_IMAGE}${NC}"
    qemu-img snapshot -a $(echo ${SNAPSHOT_LIST} | awk '{ print $1 }') ${DISK_IMAGE}
    echo

    echo -e "${LTCYAN}Deleting all snapshots ...${NC}"
    echo -e "${LTCYAN}------------------------------------------------------${NC}"
    for SNAPSHOT in ${SNAPSHOT_LIST}
    do
      echo -e "${GREEN}COMMAND: ${GRAY}qemu-img snapshot -d ${SNAPSHOT} ${DISK_IMAGE}${NC}"
      qemu-img snapshot -d ${SNAPSHOT} ${DISK_IMAGE}
    done
    echo
  else
    echo -e "${LTCYAN}No shapshots found. Reverting to blank disk image ...${NC}"
    echo -e "${LTCYAN}------------------------------------------------------${NC}"
    echo -e "${GREEN}COMMAND: ${GRAY}rm -f ${DISK_IMAGE}${NC}"
    rm -f ${DISK_IMAGE}
    #echo -e "${GREEN}COMMAND: ${GRAY}mv ${DISK_IMAGE} ${DISK_IMAGE}.old${NC}"
    #mv ${DISK_IMAGE} ${DISK_IMAGE}.old

    echo -e "${GREEN}COMMAND: ${GRAY}qemu-img create -f qcow2 ${DISK_IMAGE} ${DISK_SIZE}${NC}"
    echo
    qemu-img create -f qcow2 ${DISK_IMAGE} ${DISK_SIZE}
    echo
    qemu-img info ${DISK_IMAGE}
    echo
  fi
done


cd - > /dev/null 2>&1

echo -e "${LTBLUE}=============================  Finished  =============================${NC}"
echo
