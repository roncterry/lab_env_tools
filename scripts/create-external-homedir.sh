#!/bin/bash
#
# version: 0.2.3
# date: 2017-09-28

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

check_for_root() {
  if [ $(whoami) != root ]
  then
    echo
    echo "ERROR: You must be root to run this script."
    echo
    exit 1
  fi
}

check_for_available_devices() {
  local MOUNTED_DEVICE_LIST=$(mount | awk '{ print $1 }' | uniq | grep  "^/.*")
  local ALL_DEVICES=$(fdisk -l | grep "^/.*" | awk '{ print $1 }')

  for DEV in ${ALL_DEVICES}
  do
    if ! echo ${MOUNTED_DEVICE_LIST} | grep -q ${DEV}
    then
     if ! grep -q ${DEV} /proc/swaps
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

check_for_home_dev() {
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

format_home_dev() {
  echo
  echo "Creating new filesystem on ${HOME_DIR_DEV} ..."
  mkfs.ext4 -L LIVE_HOME ${HOME_DIR_DEV}
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
  echo "  -Log in as the root user (default password=linux)"
  echo "  -Enter the following command:"
  echo 
  echo "    mount-external-homedir.sh ${HOME_DIR_DEV}"
  echo
  echo
  echo " NOTE: If you are using a Live DVD or Live USB you will need to"
  echo "       follow that procedure every time you boot."
  echo
  echo "===================================================================="
  echo
}

#############################################################################
#                          Main Code Body
#############################################################################

check_for_root
check_for_home_dev

echo
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "     WARNING: This will delete all data on the device ${HOME_DIR_DEV}!"
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo
echo -n "Continue? [y/N]: "
read DOIT

case ${DOIT} in
  y|Y|Yes|YES)
    format_home_dev
    display_message
  ;;
  *)
    echo
    echo "Exiting"
    echo
    exit
  ;;
esac
