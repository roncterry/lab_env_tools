#!/bin/bash
#
# version: 1.0.0
# date: 2019-07-11

#############################################################################
#                         Global Variables
#############################################################################

HOME_DIR_DEV=$1

#############################################################################
#                            Functions
#############################################################################

usage() {
  echo
  echo "USAGE: $0 <home_device>"
  echo
}

check_for_root_user() {
  if [ $(whoami) != root ]
  then
    echo
    echo "ERROR: You must be root to run this script."
    echo
    exit 1
  fi
}

check_for_available_devices() {
  local ROOT_PART=$(mount | grep " on / " | awk '{ print $1 }')
  local SWAP_PARTS=$(cat /proc/swaps | grep "^/.*" | awk '{ print $1 }')
  #local MOUNTED_DEVICE_LIST=$(mount | awk '{ print $1 }' | uniq | grep  "^/.*")
  local ALL_DEVICES=$(fdisk -l | grep "^/.*" | awk '{ print $1 }')

  for DEV in ${ALL_DEVICES}
  do
    if ! echo ${ROOT_PART} | grep -q ${DEV}
    then
     if ! echo ${SWAP_PARTS} | grep -q ${DEV}
     then
       local AVAILABLE_DEVICES="${AVAILABLE_DEVICES} ${DEV}"
     fi
    fi
  done

  if [ -z "${AVAILABLE_DEVICES}" ] 
  then 
    echo "No available devices found" 
  else 
    echo "Available Devices:"
    echo "----------------------------"
    echo ${AVAILABLE_DEVICES} 
  fi
}

check_for_supplied_home_dev() {
  if [ -z "${HOME_DIR_DEV}" ]
  then
    echo
    echo "ERROR: You must supply the device file for the home directory device."
    echo
    usage
    check_for_available_devices
    echo
    exit 2
  else
    if ! [ -e ${HOME_DIR_DEV} ]
    then
      echo
      echo "ERROR: The supplied home directory device file does not exist."
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
    echo "Device mounted. Unmouning ..." 
    umount ${HOME_DIR_DEV}
  fi
}

create_partition_table() {
  echo
  echo "Creating new partition table on ${HOME_DIR_DEV} ..."
  parted -s ${HOME_DIR_DEV} mklabel msdos
  #parted -s ${HOME_DIR_DEV} mklabel gpt
}

delete_existing_partitions() {
  for PART_NUM in $(seq 1 $(parted ${HOME_DIR_DEV} print | grep "^ [1-9]" | wc -l)) 
  do 
    #echo "parted -s ${HOME_DIR_DEV} ${PART_NUM}"
    echo "Deleteing partition: ${PART_NUM}"
    parted -s ${HOME_DIR_DEV} ${PART_NUM}
  done
}

partition_home_dev() {
  echo
  echo "Creating partition on ${HOME_DIR_DEV} ..."
  #echo "parted -s ${HOME_DIR_DEV} mkpart primary 0 %100" 
  parted -s ${HOME_DIR_DEV} mkpart primary 0 %100 
  echo
}

format_home_dev() {
  echo
  echo "Creating new filesystem on ${HOME_DIR_DEV} ..."
  mkfs.ext4 -L HOME ${HOME_DIR_DEV}
  if mount | grep -q ${HOME_DIR_DEV}
  then
    umount ${HOME_DIR_DEV}
  fi
}

partition_format_home_dev() {
  if [ "$(file ${HOME_DIR_DEV} | grep -o \(.* | cut -d \/ -f 2 | cut -d \) -f 1)" -ge 1 ]
  then
    format_home_dev
  elif [ "$(file ${HOME_DIR_DEV} | grep -o \(.* | cut -d \/ -f 2 | cut -d \) -f 1)" -eq 0 ]
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
  echo "Copying current /home/* to new home device ..."
  mount ${HOME_DIR_DEV} /mnt
  rsync -a /home/ /mnt/
  umount ${HOME_DIR_DEV}
}

display_message() {
  echo
  echo "----------------------------- Finished -----------------------------"
  echo
  echo "===================================================================="
  echo
  echo " To begin using the new home device:"
  echo
  echo "  -Switch to a terminal (Ctrl+Alt+F1)"
  echo "  -Log in as the root user"
  echo "  -Either:"
  echo "    Enter the following command:"
  echo 
  echo "     mount-home-disk.sh ${HOME_DIR_DEV}"
  echo
  echo "    Or simply reboot the machine"
  echo
  echo "===================================================================="
  echo
}

#############################################################################
#                          Main Code Body
#############################################################################

check_for_root_user
check_for_supplied_home_dev

echo
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "     WARNING: This will delete all data on the device ${HOME_DIR_DEV}!"
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo
echo -n "Continue? [y/N]: "
read DOIT

case ${DOIT} in
  y|Y|Yes|YES)
    unmount_home_dev
    partition_format_home_dev
    copy_current_home_to_new
    display_message
  ;;
  *)
    echo
    echo "Exiting"
    echo
    exit
  ;;
esac
