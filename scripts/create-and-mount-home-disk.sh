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


HOME_DIR_DEV=$1

#############################################################################
#                            Functions
#############################################################################

usage() {
  echo
  echo "USAGE: $0 <home_device> [no_prompt] [restart_gui]"
  echo
  echo "  Options:"
  echo "            no_prompt    -don't prompt for confirmation"
  echo "            restart_gui  -don't check if GUI is running, just stop it"
  echo "                          before the home dev creation and restart it after"
  echo "                          --MUST NOT BE RUN FROM A TERMINAL IN THE GUI!--"
}

stop_gui() {
  echo
  echo -e ${LTBLUE}"Stopping the GUI ..."${NC}
  #echo -e ${LTGREEN}"  COMMAND: ${GRAY}runlevel 3"${NC}
  #runlevel 3
  echo -e ${LTGREEN}"COMMAND: ${GRAY}systemctl isolate multi-user.target"${NC}
  systemctl isolate multi-user.target
  echo
}

start_gui() {
  echo
  echo -e ${LTBLUE}"Restarting the GUI ..."${NC}
  #echo -e ${LTGREEN}"  COMMAND: ${GRAY}runlevel 5"${NC}
  #runlevel 5
  echo -e ${LTGREEN}"COMMAND: ${GRAY}systemctl isolate graphical.target"${NC}
  systemctl isolate graphical.target
  echo
}

check_for_tty() {
  if ps | head -n 2 | tail -n 1 | awk '{ print $2 }' | grep pts
  then
    echo
    echo -e ${LTRED}"ERROR: You must run this command from a TTY not in a GUI terminal."${NC}
    echo
    exit 1
  fi
}

check_for_gui_running_pre() {
  if [ $(runlevel | awk '{ print $2 }') -eq 5 ]
  then
    if echo ${*} | grep -q "restart_gui"
    then
      stop_gui
    else
      echo
      echo -e ${LTRED}"ERROR: The GUI should not be running when running this script"${NC}
      echo -e ${LTRED}"       Stop the GUI and rerun this script"${NC}
      echo
      exit 1
    fi
  fi
}

check_for_gui_running_post() {
  if echo ${*} | grep -q "restart_gui"
  then
    if ! [ $(runlevel | awk '{ print $2 }') -eq 5 ]
    then
      start_gui
    fi
  fi
}

check_for_root_user () {
  if [ $(whoami) != root ]
  then
    echo
    echo -e ${LTRED}"ERROR: You must be root to run this script."${NC}
    echo
    echo -e ${LTRED}"       You should log in directly as root rather than using sudo or su."${NC}
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
           if ! echo ${SWAP_PARTS} | grep -q ${DEV}
           then
             local AVAILABLE_DEVICES="${AVAILABLE_DEVICES} ${DEV}"
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
    echo -e ${LTPURPLE}"Root (/) partition:  ${GRAY}${ROOT_PART}"${NC}
    echo -e ${LTPURPLE}"Boot partition:      ${GRAY}${BOOT_PART}"${NC}
    echo -e ${LTPURPLE}"EFI partition:       ${GRAY}${BOOTEFI_PART}"${NC}
    echo -e ${LTPURPLE}"BIOS Boot partition: ${GRAY}${BIOSBOOT_PART}"${NC}
    echo -e ${LTPURPLE}"Swap partition(s):   ${GRAY}${SWAP_PARTS}"${NC}
    echo
    echo -e ${LTCYAN}"Available Devices:"${NC}
    echo -e ${LTCYAN}"----------------------------"${NC}
    echo -e ${GRAY}${AVAILABLE_DEVICES} ${NC}
  fi
}

check_for_supplied_home_dev() {
  if [ -z "${HOME_DIR_DEV}" ]
  then
    echo
    echo -e ${LTRED}"ERROR: You must supply the device file for the home directory device."${NC}
    echo
    usage
    check_for_available_devices
    echo
    exit 2
  else
    if ! [ -e ${HOME_DIR_DEV} ]
    then
      echo
      echo -e ${LTRED}"ERROR: The supplied home directory device file does not exist."${NC}
      echo
      usage
      check_for_available_devices
      echo
      exit 3
    fi
  fi
}

unmount_home_dev() {
  if mount | grep -q ${HOME_DIR_DEV}
  then
    echo -e ${LTBLUE}"Device ${HOME_DIR_DEV} mounted. Unmouning ..." ${NC}
    echo -e ${LTGREEN}"COMMAND: ${GRAY}umount ${HOME_DIR_DEV}"${NC}
    umount ${HOME_DIR_DEV}
  fi
}

mount_home_dev() {
  echo -e ${LTBLUE}"Mounting the home device on /home"${NC}
  echo -e ${LTGREEN}"COMMAND: ${GRAY}mount ${HOME_DIR_DEV} /home"${NC}
  mount ${HOME_DIR_DEV} /home
  sleep 5
  echo
}

create_partition_table() {
  echo
  echo -e ${LTBLUE}"Creating new partition table on ${HOME_DIR_DEV} ..."${NC}
  echo -e ${LTGREEN}"COMMAND: ${GRAY}parted -s ${HOME_DIR_DEV} mklabel msdos"${NC}
  parted -s ${HOME_DIR_DEV} mklabel msdos
  #parted -s ${HOME_DIR_DEV} mklabel gpt
}

delete_existing_partitions() {
  for PART_NUM in $(seq 1 $(parted ${HOME_DIR_DEV} print | grep "^ [1-9]" | wc -l)) 
  do 
    echo -e ${LTBLUE}"Deleteing partition: ${PART_NUM}"${NC}
    echo -e ${LTGREEN}"COMMAND: ${GRAY}parted -s ${HOME_DIR_DEV} rm ${PART_NUM}"${NC}
    parted -s ${HOME_DIR_DEV} rm ${PART_NUM}
  done
}

partition_home_dev() {
  echo
  echo -e ${LTBLUE}"Creating partition on ${HOME_DIR_DEV} ..."${NC}
  echo -e ${LTGREEN}"COMMAND: ${GRAY}parted -s ${HOME_DIR_DEV} mkpart primary 1 100%" ${NC}
  parted -s ${HOME_DIR_DEV} mkpart primary 1 100% 
  export HOME_DIR_DEV=${HOME_DIR_DEV}1
  export HOME_PARTITION_CREATED=Y
  echo
}

format_home_dev() {
  echo
  echo -e ${LTBLUE}"Creating new filesystem on ${HOME_DIR_DEV} ..."${NC}
  echo -e ${LTGREEN}"COMMAND: ${GRAY}mkfs.ext4 -F -L HOME ${HOME_DIR_DEV}"${NC}
  mkfs.ext4 -F -L HOME ${HOME_DIR_DEV}
  if mount | grep -q ${HOME_DIR_DEV}
  then
    echo -e ${LTGREEN}"COMMAND: ${GRAY}umount ${HOME_DIR_DEV}"${NC}
    umount ${HOME_DIR_DEV}
  fi
}

update_fstab_for_home() {
  if ! grep -q "^LABEL=HOME" /etc/fstab
  then
    echo
    echo -e ${LTBLUE}"Updating the /etc/fstab for LABEL=HOME ..."${NC}
    echo -e ${LTPURPLE}"LABEL=HOME  /home  auto  defaults,nofail,x-systemd.device-timeout=1  0 0"${NC}
    echo "LABEL=HOME  /home  auto  defaults,nofail,x-systemd.device-timeout=1  0 0" >> /etc/fstab${NC}
  fi
}

partition_format_home_dev() {
  if echo ${HOME_DIR_DEV} | grep -o "[1-9]$"
  then
    format_home_dev
  elif ! echo ${HOME_DIR_DEV} | grep -o "[1-9]$"
  then
    if ! parted -l | grep -q "Partition Table:"
    then
      create_partition_table
    fi
    if [ $(parted ${HOME_DIR_DEV} print | grep "^ [1-9]" | wc -l) -ge 1 ]
    then
      delete_existing_partitions
    fi
    partition_home_dev
    format_home_dev
  fi
}

copy_current_home_to_new() {
      echo
      echo -e ${LTBLUE}"Copying current /home/* to new home device ..."${NC}
      echo -e ${LTGREEN}"COMMAND: ${GRAY}mount ${HOME_DIR_DEV} /mnt"${NC}
      mount ${HOME_DIR_DEV} /mnt
      echo -e ${LTGREEN}"COMMAND: ${GRAY}rsync -a /home/ /mnt/"${NC}
      rsync -a /home/ /mnt/
      echo -e ${LTGREEN}"COMMAND: ${GRAY}rm -rf /mnt/lost+found"${NC}
      rm -rf /mnt/lost+found
      echo -e ${LTGREEN}"COMMAND: ${GRAY}umount ${HOME_DIR_DEV}"${NC}
      echo
      umount ${HOME_DIR_DEV}
}

#############################################################################
#                          Main Code Body
#############################################################################

#check_for_tty
check_for_root_user
check_for_supplied_home_dev
check_for_gui_running_pre ${*}

if ! echo ${*} | grep -q "no_prompt"
then
  echo
  echo -e ${ORANGE}"!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"${NC}
  echo -e ${ORANGE}"     WARNING: This will delete all data on the device ${HOME_DIR_DEV}"${NC}
  echo -e ${ORANGE}"!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"${NC}
  echo
  echo -e -n ${GRAY}"Continue? [y/N]: "${NC}
  read DOIT
else
  DOIT=y
fi

case ${DOIT} in
  y|Y|Yes|YES)
    unmount_home_dev
    partition_format_home_dev
    copy_current_home_to_new
    #unmount_home_dev
    update_fstab_for_home
    mount_home_dev
    check_for_gui_running_post ${*}
  ;;
  *)
    echo
    check_for_gui_running_post ${*}
    echo -e ${LTBLUE}"Exiting"${NC}
    echo
    exit
  ;;
esac
