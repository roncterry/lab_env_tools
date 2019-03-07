#!/bin/bash
# version: 1.0.1
# date: 2019-03-07

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
#echo -e "${LTBLUE}==============================================================${NC}"
#echo -e "${LTBLUE}${NC}"
#echo -e "${LTBLUE}==============================================================${NC}"
#echo -e "${LTCYAN}  -${NC}"
#echo -e "${LTGREEN}COMMAND:${GRAY} ${NC}"
#echo -e "${LTRED}ERROR: ${NC}"
#echo -e "${LTPURPLE}  VAR=${GRAY}${VAR}${NC}"
##############

##############################################################################
#                          Functions
##############################################################################

usage() {
  echo "USAGE: ${0} <root_block_device>"
  echo
}

##############################################################################
#                           Main Code Body
##############################################################################

if [ -z ${1} ]
then
  usage
  exit
else
  if [ -e ${1} ]
  then
    ROOT_BLOCK_DEV=${1}
  else
    echo -e "${LTRED}ERROR: ${1} does not exist. Exiting.${NC}"
    exit
  fi
fi

echo -e "${LTBLUE}==============================================================${NC}"
echo -e "${LTBLUE} Mounting ${ROOT_BLOCK_DEV} onto /rescue ${NC}"
echo -e "${LTBLUE}==============================================================${NC}"

if ! [ -d /rescue ]
then
  echo -e "${LTGREEN}COMMAND:${GRAY} sudo mkdir /rescue${NC}"
  sudo mkdir /rescue
  echo
fi

if [ -d /rescue ]
then
  echo -e "${LTGREEN}COMMAND:${GRAY} sudo mount ${ROOT_BLOCK_DEV} /rescue${NC}"
  sudo mount ${1} /rescue

  if mount | grep -q /rescue
  then
    if grep -q "/boot/efi" /rescue/etc/fstab
    then
      echo -e "${LTGREEN}COMMAND:${GRAY} sudo mount $(grep /boot/efi /rescue/etc/fstab | awk '{ print $1 }') /rescue/boot/efi${NC}"
      sudo mount $(grep /boot/efi /rescue/etc/fstab | awk '{ print $1 }') /rescue/boot/efi
    fi
 
    if grep -q "/home" /rescue/etc/fstab
    then
      echo -e "${LTGREEN}COMMAND:${GRAY} sudo mount $(grep /home /rescue/etc/fstab | awk '{ print $1 }') /rescue/home${NC}"
      sudo mount $(grep /home /rescue/etc/fstab | awk '{ print $1 }') /rescue/home
    fi
 
    echo -e "${LTGREEN}COMMAND:${GRAY} sudo mount --bind /dev /rescue/dev${NC}"
    sudo mount --bind /dev /rescue/dev
 
    echo -e "${LTGREEN}COMMAND:${GRAY} sudo mount --bind /proc /rescue/proc${NC}"
    sudo mount --bind /proc /rescue/proc
 
    echo -e "${LTGREEN}COMMAND:${GRAY} sudo mount --bind /sys /rescue/sys${NC}"
    sudo mount --bind /sys /rescue/sys
  else
    echo
    echo -e "${LTRED}ERROR: ${1} could not be mounted on /rescue. Exiting.${NC}"
    exit
  fi

  echo
fi

echo -e "${LTBLUE}${ROOT_BLOCK_DEV} is now mounted on: ${GRAY} /rescue ${NC}"
echo -e "${LTBLUE}-----------------------------------------------------------------------------${NC}"
mount | grep "/rescue"
echo -e "${LTBLUE}-----------------------------------------------------------------------------${NC}"
echo
echo -e "${LTPURPLE}You may now ${LTGREEN}chroot${LTPURPLE} into ${GRAY}/rescue${NC}"
echo
echo -e "${ORANGE}Note: When finished, exit the chroot and run: ${GRAY}umount-rescue.sh${NC}"
echo
