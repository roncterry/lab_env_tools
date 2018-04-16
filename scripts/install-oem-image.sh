#!/bin/bash
# version: 1.0.0
# date: 2017-12-20

##############################################################################
#                           Global Variables
##############################################################################

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
#                          Functions 
##############################################################################

usage() {
  echo
  echo "${0} <block_device> <image_file>"
  echo
}

write_oem_image_to_disk() {
  local SQUASH_MOUNT="/tmp/squash_mount"
  echo
  echo -e "${LTBLUE}==============================================================${NC}"
  echo -e "${LTBLUE}Writing Image to Disk ...${NC}"
  echo -e "${LTBLUE}==============================================================${NC}"
  echo

  if file ${IMAGE} | grep -q "XZ compressed data"
  then
    echo -e "${LTGREEN}COMMAND:${GRAY} xzcat | dd_rescue -A -b 4M -y 4M - ${DISK_DEV} ${NC}"
    xzcat ${IMAGE} | dd_rescue -A -b 4M -y 4M - ${DISK_DEV}

  elif file ${IMAGE} | grep -q "bzip2 compressed data"
  then
    echo -e "${LTGREEN}COMMAND:${GRAY} bzcat | dd_rescue -A -b 4M -y 4M - ${DISK_DEV} ${NC}"
    bzcat ${IMAGE} | dd_rescue -A -b 4M -y 4M - ${DISK_DEV}

  elif file ${IMAGE} | grep -q "gzip compressed data"
  then
    echo -e "${LTGREEN}COMMAND:${GRAY} zcat | dd_rescue -A -b 4M -y 4M - ${DISK_DEV} ${NC}"
    zcat ${IMAGE} | dd_rescue -A -b 4M -y 4M - ${DISK_DEV}

  elif file ${IMAGE} | grep -q "Squashfs filesystem"
  then
    echo -e "${LTGREEN}COMMAND:${GRAY} mkdir -p ${SQUASH_MOUNT}${NC}"
    mkdir -p ${SQUASH_MOUNT}
    echo -e "${LTGREEN}COMMAND:${GRAY} mount ${IMAGE} ${SQUASH_MOUNT}${NC}"
    mount ${IMAGE} ${SQUASH_MOUNT}
    for FILE_IN_SQUASH in $(ls ${SQUASH_MOUNT}/)
    do
      if echo ${SQUASH_MOUNT}/${FILE_iN_SQUASH} | grep -q "DOS/MBR boot sector"
      then
        local RAW_IMAGE=${SQUASH_MOUNT}/${FILE_iN_SQUASH}
      fi
    done
    echo -e "${LTGREEN}COMMAND:${GRAY} dd_rescue -A -b 4M -y 4M \"${RAW_IMAGE}\" ${DISK_DEV} ${NC}"
    dd_rescue -A -b 4M -y 4M "${RAW_IMAGE}" ${DISK_DEV}
    echo -e "${LTGREEN}COMMAND:${GRAY} umount ${IMAGE} ${SQUASH_MOUNT}${NC}"
    umount ${IMAGE} ${SQUASH_MOUNT}
    echo -e "${LTGREEN}COMMAND:${GRAY} rmdir -p ${SQUASH_MOUNT}${NC}"
    rmdir -p ${SQUASH_MOUNT}

  elif file ${IMAGE} | grep -q "DOS/MBR boot sector"
  then
    echo -e "${LTGREEN}COMMAND:${GRAY} dd_rescue -A -b 4M -y 4M \"${IMAGE}\" ${DISK_DEV} ${NC}"
    dd_rescue -A -b 4M -y 4M "${IMAGE}" ${DISK_DEV}

  fi
  echo
}

main() {
  if [ "$(whoami)" != root ]
  then
    echo
    echo -e "${LTRED}ERROR: You must be root to run this command. (sudo OK)${NC}"
    echo
    exit 1
  fi

  if [ -z ${1} ]
  then
    echo
    echo -e "${LTRED}ERROR: You must supply a block device to install the image to.${NC}"
    usage
    echo
    exit 1
  else
    if [ -e ${1} ]
    then
      DISK_DEV=${1}
    else
      echo
      echo -e "${LTRED}ERROR: The block device provided doesn't seem to exist. Exiting.${NC}"
      echo
      exit 1
    fi
  fi

  if [ -z ${2} ]
  then
    echo
    echo -e "${LTRED}ERROR: You must supply a image file to write out.${NC}"
    usage
    echo
    exit 1
  else
    if [ -e ${2} ]
    then
      IMAGE=${2}
    else
      echo
      echo -e "${LTRED}ERROR: The image file provided doesn't seem to exist. Exiting.${NC}"
      echo
      exit 1
    fi
  fi

  echo 
  echo -e "${LTRED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}"
  echo -e "${LTRED}!!!!         WARNING: ALL DATA ON DISK WILL BE LOST!         !!!!${NC}"
  echo -e "${LTRED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}"
  echo
  echo -n -e "${LTRED}Enter Y to continue or N to quit (y/N): ${NC}"
  read DOIT
  case ${DOIT} in
    Y|y|Yes|YES)
      write_oem_image_to_disk
    ;;
    *)
      exit 
    ;;
  esac

  echo -e "${LTPURPLE}==============================================================${NC}"
  echo
  echo -e "${LTPURPLE}  OEM image installation finished.${NC}"
  echo
  echo -e "${LTPURPLE}  You may now reboot into the newly installed system.${NC}"
  echo
  echo -e "${LTPURPLE}==============================================================${NC}"
  echo

  echo
}

##############################################################################
#                           Main Code Body
##############################################################################

time main $*
