#!/bin/bash
#
# version: 1.0.0
# date: 2019-07-09

#############################################################################
#                         Global Variables
#############################################################################

HOME_DIR_DEV=$1

#############################################################################
#                            Functions
#############################################################################

usage() {
  echo
  echo "USAGE: $0 [<home_device>]"
  echo
}

check_for_tty() {
  if ps | head -n 2 | tail -n 1 | awk '{ print $2 }' | grep pts
  then
    echo
    echo "ERROR: You must run this command from a TTY not in a GUI terminal."
    echo
    exit 1
  fi
}

check_for_root () {
  if [ $(whoami) != root ]
  then
    echo
    echo "ERROR: You must be root to run this script."
    echo
    echo "       You should log in directly as root rather than using sudo or su."
    echo
    exit 2
  fi
}

check_for_home_label() {
  if [ -z ${HOME_DIR_DEV} ]
  then
    if [ -e /dev/disk/by-label/HOME ]
    then
      HOME_DIR_DEV="/dev/disk/by-label/HOME"
    else
      echo
      echo "ERROR: You must supply the device file for the home directory device."
      echo
      usage
      exit 3
    fi
  else
    if ! [ -e ${HOME_DIR_DEV} ]
    then
      echo
      echo "ERROR: The supplied home directory device file does not exist."
      echo
      exit 4
    fi
  fi
}

stop_xdm() {
  echo
  echo "Stopping XDM ..."
  echo "  COMMAND: rcxdm stop"
  rcxdm stop
  echo
}

unmount_home_dev() {
  echo "Unmounting the home device ..."
  echo "  COMMAND: umount ${HOME_DIR_DEV}"
  umount ${HOME_DIR_DEV}
  sleep 5
  echo
}

mount_home_dev() {
  echo "Mounting the home device on /home"
  echo "  COMMAND: mount ${HOME_DIR_DEV} /home"
  mount ${HOME_DIR_DEV} /home
  sleep 5
  echo
}

start_xdm() {
  echo "Starting XDM ..."
  echo "  COMMAND: rcxdm start"
  rcxdm start
  echo
}

#############################################################################
#                          Main Code Body
#############################################################################

check_for_tty
check_for_root
check_for_home_label
stop_xdm
unmount_home_dev
mount_home_dev
start_xdm
