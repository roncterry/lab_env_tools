#!/bin/bash
#
# version: 1.0.0
# date: 2019-07-16

#############################################################################
#                         Global Variables
#############################################################################

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


COURSES_DIR_DEV=$1

#############################################################################
#                            Functions
#############################################################################

usage() {
  echo
  echo "USAGE: $0 <courses_device> [no_prompt]"
  echo
  echo "  Options:"
  echo "            no_prompt    -don't prompt for confirmation"
}

check_for_root_user () {
  if [ $(whoami) != root ]
  then
    echo
    echo -e ${LTRED}"ERROR: You must be root to run this script."${NC}
    echo
    exit 2
  fi
}

check_for_available_devices() {
  local ROOT_PART=$(mount | grep " on / " | awk '{ print $1 }')
  local BOOT_PART=$(mount | grep " on /boot " | awk '{ print $1 }')
  local BOOTEFI_PART=$(mount | grep " on /boot/efi " | awk '{ print $1 }')
  local BIOSBOOT_PART=$(fdisk -l | grep "BIOS boot" | awk '{ print $1 }')
  local SWAP_PARTS=$(cat /proc/swaps | grep "^/.*" | awk '{ print $1 }')
  local HOME_PART=$(ls -l /dev/disk/by-label/ | grep HOME | awk '{ print $11 }' | sed 's+\.\.\/\.\.\/+\/dev\/+')
  #local MOUNTED_DEVICE_LIST=$(mount | awk '{ print $1 }' | uniq | grep  "^/.*")
  local ALL_DEVICES=$(fdisk -l | grep "^Disk /" | awk '{ print $2 }' | cut -d \: -f 1)

  for DEV in ${ALL_DEVICES}
  do
    if ! echo ${ROOT_PART} | grep -q ${DEV}
    then
     if ! echo ${BOOT_PART} | grep -q ${DEV}
     then
       if ! echo ${BOOTEFI_PART} | grep -q ${DEV}
       then
         if ! echo ${BIOSBOOT_PART} | grep -q ${DEV}
         then
           if ! echo ${HOME_PART} | grep -q ${DEV}
           then
             if ! echo ${SWAP_PARTS} | grep -q ${DEV}
             then
               local AVAILABLE_DEVICES="${AVAILABLE_DEVICES} ${DEV}"
             fi
           fi
         fi
       fi
     fi
    fi
  done

  if [ -z "${AVAILABLE_DEVICES}" ] 
  then 
    echo -e ${LTPURPLE}"No available devices found" ${NC}
  else 
    echo
    echo -e ${LTPURPLE}"Root (/) partition:  ${ROOT_PART}"${NC}
    echo -e ${LTPURPLE}"Boot partition:      ${BOOT_PART}"${NC}
    echo -e ${LTPURPLE}"EFI partition:       ${BOOTEFI_PART}"${NC}
    echo -e ${LTPURPLE}"BIOS Boot partition: ${BIOSBOOT_PART}"${NC}
    echo -e ${LTPURPLE}"Home partition:      ${HOME_PART}"${NC}
    echo -e ${LTPURPLE}"Swap partition(s):   ${SWAP_PARTS}"${NC}
    echo
    echo -e ${LTCYAN}"Available Devices:"${NC}
    echo -e ${LTCYAN}"----------------------------"${NC}
    echo -e ${GRAY}${AVAILABLE_DEVICES} ${NC}
  fi
}

check_for_supplied_courses_dev() {
  if [ -z "${COURSES_DIR_DEV}" ]
  then
    echo
    echo -e ${LTRED}"ERROR: You must supply the device file for the courses directory device."${NC}
    echo
    usage
    check_for_available_devices
    echo
    exit 2
  else
    if ! [ -e ${COURSES_DIR_DEV} ]
    then
      echo
      echo -e ${LTRED}"ERROR: The supplied courses directory device file does not exist."${NC}
      echo
      usage
      check_for_available_devices
      echo
      exit 3
    fi
  fi
}

unmount_courses_dev() {
  if mount | grep -q ${COURSES_DIR_DEV}
  then
    echo -e ${LTBLUE}"Device ${COURSES_DIR_DEV} mounted. Unmouning ..." ${NC}
    echo -e ${LTGREEN}"COMMAND: ${GRAY}umount ${COURSES_DIR_DEV}"${NC}
    umount ${COURSES_DIR_DEV}
  fi
}

mount_courses_dev() {
  echo -e ${LTBLUE}"Mounting the courses device on /install/courses"${NC}
  echo -e ${LTGREEN}"COMMAND: ${GRAY}mount ${COURSES_DIR_DEV} /install/courses"${NC}
  mount ${COURSES_DIR_DEV} /install/courses
  sleep 5
  echo
}

create_partition_table() {
  echo
  echo -e ${LTBLUE}"Creating new partition table on ${COURSES_DIR_DEV} ..."${NC}
  echo -e "${LTGREEN}COMMAND:  ${GRAY}parted -s ${COURSES_DIR_DEV} mklabel msdos${NC}"
  parted -s ${COURSES_DIR_DEV} mklabel msdos
  #parted -s ${COURSES_DIR_DEV} mklabel gpt
}

delete_existing_partitions() {
  for PART_NUM in $(seq 1 $(parted ${COURSES_DIR_DEV} print | grep "^ [1-9]" | wc -l)) 
  do 
    echo -e ${LTBLUE}"Deleteing partition: ${PART_NUM}"${NC}
    echo -e "${LTGREEN}COMMAND:  ${GRAY} parted -s ${COURSES_DIR_DEV} rm ${PART_NUM}${NC}"
    parted -s ${COURSES_DIR_DEV} rm ${PART_NUM}
  done
}

partition_courses_dev() {
  echo
  echo -e ${LTBLUE}"Creating partition on ${COURSES_DIR_DEV} ..."${NC}
  echo -e "${LTGREEN}COMMAND:  ${GRAY}parted -s ${COURSES_DIR_DEV} mkpart primary 1 100% ${NC}"
  parted -s ${COURSES_DIR_DEV} mkpart primary 1 100% 
  export COURSES_DIR_DEV=${COURSES_DIR_DEV}1
  export COURSES_PARTITION_CREATED=Y
  echo
}

format_courses_dev() {
  echo
  echo -e ${LTBLUE}"Creating new filesystem on ${COURSES_DIR_DEV} ..."${NC}
  echo -e "${LTGREEN}COMMAND:  ${GRAY} mkfs.ext4 -F -L COURSES ${COURSES_DIR_DEV}${NC}"
  mkfs.ext4 -F -L COURSES ${COURSES_DIR_DEV}
  if mount | grep -q ${COURSES_DIR_DEV}
  then
    echo -e ${LTGREEN}"COMMAND: ${GRAY}umount ${HOME_DIR_DEV}"${NC}
    umount ${COURSES_DIR_DEV}
  fi
}

update_fstab_for_courses() {
  if ! grep -q "^LABEL=COURSES" /etc/fstab
  then
    echo
    echo -e ${LTBLUE}"Updating the /etc/fstab for LABEL=COURSES ..."${NC}
    echo -e ${LTPURPLE}"LABEL=COURSES  /install/courses  auto  defaults,nofail,x-systemd.device-timeout=1  0 0"${NC}
    echo "LABEL=COURSES  /install/courses  auto  defaults,nofail,x-systemd.device-timeout=1  0 0" >> /etc/fstab
  fi
}

partition_format_courses_dev() {
  if echo ${COURSES_DIR_DEV} | grep -o "[1-9]$"
  then
    format_courses_dev
  elif ! echo ${COURSES_DIR_DEV} | grep -o "[1-9]$"
  then
    if ! parted -l | grep -q "Partition Table:"
    then
      create_partition_table
    fi
    if [ $(parted ${COURSES_DIR_DEV} print | grep "^ [1-9]" | wc -l) -ge 1 ]
    then
      delete_existing_partitions
    fi
    partition_courses_dev
    format_courses_dev
  fi
}

copy_current_courses_to_new() {
  echo
  echo -e ${LTBLUE}"Copying current /install/courses/* to new courses device ..."${NC}
  echo -e "${LTGREEN}COMMAND:  ${GRAY} mount ${COURSES_DIR_DEV} /mnt${NC}"
  mount ${COURSES_DIR_DEV} /mnt
  echo -e "${LTGREEN}COMMAND:  ${GRAY} rsync -a /install/courses/ /mnt/${NC}"
  rsync -a /install/courses/ /mnt/
  echo -e "${LTGREEN}COMMAND:  ${GRAY} rm -rf /mnt/lost+found${NC}"
  rm -rf /mnt/lost+found
  echo -e "${LTGREEN}COMMAND:  ${GRAY} umount ${COURSES_DIR_DEV}${NC}"
  echo
  umount ${COURSES_DIR_DEV}
}

#############################################################################
#                          Main Code Body
#############################################################################

#check_for_tty
check_for_root_user
check_for_supplied_courses_dev

if ! echo ${*} | grep -q "no_prompt"
then
  echo
  echo -e ${ORANGE}"!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"${NC}
  echo -e ${ORANGE}"     WARNING: This will delete all data on the device ${COURSES_DIR_DEV}"${NC}
  echo -e ${ORANGE}"!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"${NC}
  echo
  echo -e -n ${GRAY}"Continue? [y/N]: "${NC}
  read DOIT
else
  DOIT=y
fi

case ${DOIT} in
  y|Y|Yes|YES)
    unmount_courses_dev
    partition_format_courses_dev
    copy_current_courses_to_new
    #unmount_courses_dev
    update_fstab_for_courses
    mount_courses_dev
  ;;
  *)
    echo
    echo -e ${LTBLUE}"Exiting"${NC}
    echo
    exit
  ;;
esac
