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
  echo -e "${GREEN}USAGE: ${GRAY}$0 <disk_image_file>${NC}"
  echo
  echo -e "Where ${GRAY}<disk_image_file>${NC} is the name of a disk image in your current working${NC} "
  echo
}

if [ -z ${1} ]
then
  usage
  exit 1
else
  DISK_IMAGE="$(echo ${1} | sed 's+/$++g')"
fi

if ! ls ${DISK_IMAGE} > /dev/null 2>&1
then
  echo
  echo "${LTRED}ERROR: The disk image file ${DISK_IMAGE} doesn't appear to exist${NC}"
  echo
  exit 2
fi

DISK_SIZE=$(qemu-img info ${DISK_IMAGE} | grep "^virtual size" | awk '{ print $3 }')

echo
echo -e "${LTBLUE}======================================================================${NC}"
echo -e "${LTBLUE}Reseting the virtual disk: ${ORANGE}${DISK_IMAGE}${NC}"
echo -e "${LTBLUE}======================================================================${NC}"
echo

#echo -e "${GREEN}COMMAND: ${GRAY}cd $(dirname ${DISK_IMAGE})${NC}"
#cd $(dirname ${DISK_IMAGE})
#echo

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
  echo -e "${GREEN}COMMAND: ${GRAY}sudo rm -f ${DISK_IMAGE}${NC}"
  sudo rm -f ${DISK_IMAGE}
  #echo -e "${GREEN}COMMAND: ${GRAY}sudo mv ${DISK_IMAGE} ${DISK_IMAGE}.old${NC}"
  #sudo mv ${DISK_IMAGE} ${DISK_IMAGE}.old

  echo -e "${GREEN}COMMAND: ${GRAY}qemu-img create -f qcow2 ${DISK_IMAGE} ${DISK_SIZE}${NC}"
  echo
  qemu-img create -f qcow2 ${DISK_IMAGE} ${DISK_SIZE}
  echo
  qemu-img info ${DISK_IMAGE}
  echo
fi


cd - > /dev/null 2>&1

echo -e "${LTBLUE}=============================  Finished  =============================${NC}"
echo
