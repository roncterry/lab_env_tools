#!/bin/bash
# version: 1.2.0
# date: 2018-03-30

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

if [ -z ${BIOSBOOT_SIZE} ]
then
  BIOSBOOT_SIZE="7MiB"
fi

if [ -z ${SWAP_SIZE} ]
then
  SWAP_SIZE="4GiB"
fi

if [ -z ${ROOT_SIZE} ]
then
  ROOT_SIZE="100%"
fi

if [ -z ${ROOT2_SIZE} ]
then
  ROOT2_SIZE="20GiB"
fi

if [ -z ${HOME_SIZE} ]
then
  HOME_SIZE="100%"
fi


if [ -z ${ISO_MOUNT} ]
then
  ISO_MOUNT="/livecd"
fi

if [ -z ${SQUASH_MOUNT} ]
then
  SQUASH_MOUNT="/tmp/squash_mount"
fi

if [ -z ${ROOT_MOUNT} ]
then
  ROOT_MOUNT="/tmp/root_mount"
fi


BLOCK_DEV_LIST="$(fdisk -l | grep "/dev" | sed 's/Disk //g' | awk '{ print $1 }' | cut -d : -f 1 | grep -v "[0-9]$") $(fdisk -l | grep "/dev" | sed 's/Disk //g' | awk '{ print $1 }' | cut -d : -f 1 | grep nvme | grep -v "p[1-9]$")"


##############################################################################
#                          Functions 
##############################################################################

usage() {
  echo
  echo "${0} <block_device> <image_file> [ with_home ]"
  echo
  echo "  Available Disks: ${BLOCK_DEV_LIST}"
  echo
  echo "  Note: This command can be customized by exporting the following"
  echo "        environment variables:"
  echo
  echo "        BIOSBOOT_SIZE   -size of BIOS Boot partition (default: 7MiB)"
  echo "        SWAP_SIZE       -size of swap partition (default: 4GiB)"
  echo "        ROOT_SIZE       -size of root partition (default: 100%)"
  echo "        ROOT2_SIZE      -size of root partition when /home is on its"
  echo "                         own partition (default: 20GiB)"
  echo "        HOME_SIZE       -size of /home partition if \"with_home\" is"
  echo "                         supplied on the command line (default: 100%)"
  echo
}

get_partition_table_type() {
  if [ -z ${PARTITION_TABLE_TYPE} ]
  then
    CURRENT_PARTITION_TABLE_TYPE=$(parted ${DISK_DEV} print | grep "Partition Table" | awk '{ print $3 }')
    case ${CURRENT_PARTITION_TABLE_TYPE} in
      dos|msdos)
        PARTITION_TABLE_TYPE=msdos
      ;;
      gpt)
        PARTITION_TABLE_TYPE=gpt
      ;;
      *)
        PARTITION_TABLE_TYPE=msdos
      ;;
    esac
  fi
  echo -e "${LTPURPLE}Partition Table:  ${GRAY}${PARTITION_TABLE_TYPE}${NC}"
}

remove_partitions() {
  echo
  echo -e "${LTBLUE}==============================================================${NC}"
  echo -e "${LTBLUE}Removing existing partitions ...${NC}"
  echo -e "${LTBLUE}==============================================================${NC}"
  echo
  local NUM_PARTS=$(expr $(ls ${DISK_DEV}* | wc -w) - 1)
  if echo ${DISK_DEV} | grep -q nvme
  then
    for i in $(seq 1 ${NUM_PARTS})
    do
      echo -e "${LTGREEN}COMMAND:${GRAY} umount ${DISK_DEV}p${i}${NC}"
      umount ${DISK_DEV}p${i}
      echo -e "${LTGREEN}COMMAND:${GRAY} parted -s ${DISK_DEV} rm ${i}${NC}"
      parted -s ${DISK_DEV} rm ${i}
    done
    echo
  else
    for i in $(seq 1 ${NUM_PARTS})
    do
      echo -e "${LTGREEN}COMMAND:${GRAY} umount ${DISK_DEV}${i}${NC}"
      umount ${DISK_DEV}${i}
      echo -e "${LTGREEN}COMMAND:${GRAY} parted -s ${DISK_DEV} rm ${i}${NC}"
      parted -s ${DISK_DEV} rm ${i}
    done
    echo
  fi
}

create_single_partition_with_swap() {
  echo -e "${LTBLUE}==============================================================${NC}"
  echo -e "${LTBLUE}Creating partitions ...${NC}"
  echo -e "${LTBLUE}==============================================================${NC}"
  case ${PARTITION_TABLE_TYPE} in
    msdos)
      local SWAP_PART_NUM=1
      local ROOT_PART_NUM=2
      echo
      echo -e "${LTCYAN}  -partition table${NC}"
      echo -e "${LTGREEN}  COMMAND:${GRAY} parted -s ${DISK_DEV} mklabel msdos${NC}"
      parted -s ${DISK_DEV} mklabel msdos
      echo
      echo -e "${LTCYAN}  -swap${NC}"
      echo -e "${LTGREEN}  COMMAND:${GRAY} parted -s ${DISK_DEV} mkpart primary 1 linux-swap ${SWAP_SIZE}${NC}"
      parted -s ${DISK_DEV} mkpart primary linux-swap 1 ${SWAP_SIZE}
      echo
      echo -e "${LTCYAN}  -root${NC}"
      echo -e "${LTGREEN}  COMMAND:${GRAY} parted -s ${DISK_DEV} mkpart primary ext4 ${SWAP_SIZE} ${ROOT_SIZE}${NC}"
      parted -s ${DISK_DEV} mkpart primary ext4 ${SWAP_SIZE} ${ROOT_SIZE}
      echo
  
      echo -e "${LTBLUE}==============================================================${NC}"
      echo -e "${LTBLUE}Toggling boot flag on root partition ...${NC}"
      echo -e "${LTBLUE}==============================================================${NC}"
      echo
      echo -e "${LTGREEN}COMMAND:${GRAY} parted ${DISK_DEV} set ${ROOT_PART_NUM} boot on ${NC}"
      parted ${DISK_DEV} set ${ROOT_PART_NUM} boot on > /dev/null 2>&1
      echo
    ;;
    gpt)
      local SWAP_PART_NUM=2
      local ROOT_PART_NUM=3
      echo
      echo -e "${LTCYAN}  -partition table${NC}"
      echo -e "${LTGREEN}  COMMAND:${GRAY} parted -s ${DISK_DEV} mklabel gpt${NC}"
      parted -s ${DISK_DEV} mklabel gpt
      echo
      echo -e "${LTCYAN}  -BIOS Boot${NC}"
      echo -e "${LTGREEN}  COMMAND:${GRAY} parted -s ${DISK_DEV} mkpart primary 1 ${BIOSBOOT_SIZE}${NC}"
      parted -s ${DISK_DEV} mkpart primary 1 ${BIOSBOOT_SIZE}
      echo -e "${LTGREEN}  COMMAND:${GRAY} parted ${DISK_DEV} set 1 bios_grub on ${NC}"
      parted ${DISK_DEV} set 1 bios_grub on > /dev/null 2>&1 
      echo
      echo -e "${LTCYAN}  -swap${NC}"
      echo -e "${LTGREEN}  COMMAND:${GRAY} parted -s ${DISK_DEV} mkpart primary linux-swap ${BIOSBOOT_SIZE} ${SWAP_SIZE}${NC}"
      parted -s ${DISK_DEV} mkpart primary linux-swap ${BIOSBOOT_SIZE} ${SWAP_SIZE}
      local SWAP_END=$(parted ${DISK_DEV} print | grep "^ ${SWAP_PART_NUM} " | awk '{ print $3 }')
      echo
      echo -e "${LTCYAN}  -root${NC}"
      echo -e "${LTGREEN}  COMMAND:${GRAY} parted -s ${DISK_DEV} mkpart primary ext4 ${SWAP_END} ${ROOT_SIZE}${NC}"
      parted -s ${DISK_DEV} mkpart primary ext4 ${SWAP_SIZE} ${ROOT_SIZE}
      echo
  
      echo -e "${LTBLUE}==============================================================${NC}"
      echo -e "${LTBLUE}Toggling boot flag on root partition ...${NC}"
      echo -e "${LTBLUE}==============================================================${NC}"
      echo
      echo -e "${LTGREEN}COMMAND:${GRAY} parted ${DISK_DEV} set ${ROOT_PART_NUM} boot on ${NC}"
      parted ${DISK_DEV} set ${ROOT_PART_NUM} boot on > /dev/null 2>&1 
      echo
    ;;
  esac
  echo -e "${LTBLUE}==============================================================${NC}"
  echo -e "${LTBLUE}Rereading partition table ...${NC}"
  echo -e "${LTBLUE}==============================================================${NC}"
  echo
  echo -e "${LTGREEN}COMMAND:${GRAY} partprobe${NC}"
  partprobe
  sleep 2
  echo
  #echo -e "${LTGREEN}COMMAND:${GRAY} lsblk${NC}"
  #lsblk
  echo -e "${LTGREEN}COMMAND:${GRAY} parted ${DISK_DEV} print${NC}"
  parted ${DISK_DEV} print
  echo
  sleep 2

  echo -e "${LTBLUE}==============================================================${NC}"
  echo -e "${LTBLUE}Creating Swap filesystem on swap partition${NC}"
  echo -e "${LTBLUE}==============================================================${NC}"
  echo
  if echo ${DISK_DEV} | grep -q nvme
  then
    echo -e "${LTGREEN}COMMAND:${GRAY} mkswap ${DISK_DEV}p${SWAP_PART_NUM}${NC}"
    mkswap ${DISK_DEV}p${SWAP_PART_NUM}
    SWAP_PART=${DISK_DEV}p${SWAP_PART_NUM}
  else
    echo -e "${LTGREEN}COMMAND:${GRAY} mkswap ${DISK_DEV}${SWAP_PART_NUM}${NC}"
    mkswap ${DISK_DEV}${SWAP_PART_NUM}
    SWAP_PART=${DISK_DEV}${SWAP_PART_NUM}
  fi
  echo

  echo -e "${LTBLUE}==============================================================${NC}"
  echo -e "${LTBLUE}Creating EXT4 filesystem on root partition${NC}"
  echo -e "${LTBLUE}==============================================================${NC}"
  echo
  if echo ${DISK_DEV} | grep -q nvme
  then
    echo -e "${LTGREEN}COMMAND:${GRAY} mkfs.ext4 -F -L ROOT ${DISK_DEV}p${ROOT_PART_NUM}${NC}"
    mkfs.ext4 -F -L ROOT ${DISK_DEV}p${ROOT_PART_NUM}
    ROOT_PART=${DISK_DEV}p${ROOT_PART_NUM}
  else
    echo -e "${LTGREEN}COMMAND:${GRAY} mkfs.ext4 -F -L ROOT ${DISK_DEV}${ROOT_PART_NUM}${NC}"
    mkfs.ext4 -F -L ROOT ${DISK_DEV}${ROOT_PART_NUM}
    ROOT_PART=${DISK_DEV}${ROOT_PART_NUM}
  fi
  #echo
}

create_two_partitions_with_swap() {
  echo -e "${LTBLUE}==============================================================${NC}"
  echo -e "${LTBLUE}Creating partitions ...${NC}"
  echo -e "${LTBLUE}==============================================================${NC}"
  case ${PARTITION_TABLE_TYPE} in
    msdos)
      local SWAP_PART_NUM=1
      local ROOT_PART_NUM=2
      local HOME_PART_NUM=3
      echo
      echo -e "${LTCYAN}  -partition table${NC}"
      echo -e "${LTGREEN}  COMMAND:${GRAY} parted -s ${DISK_DEV} mklabel msdos${NC}"
      parted -s ${DISK_DEV} mklabel msdos
      echo
      echo -e "${LTCYAN}  -swap${NC}"
      echo -e "${LTGREEN}  COMMAND:${GRAY} parted -s ${DISK_DEV} mkpart primary linux-swap 1 ${SWAP_SIZE}${NC}"
      parted -s ${DISK_DEV} mkpart primary linux-swap 1 ${SWAP_SIZE}
      echo
      echo -e "${LTCYAN}  -root${NC}"
      echo -e "${LTGREEN}  COMMAND:${GRAY} parted -s ${DISK_DEV} mkpart primary ext4 ${SWAP_SIZE} ${ROOT2_SIZE}${NC}"
      parted -s ${DISK_DEV} mkpart primary ext4 ${SWAP_SIZE} ${ROOT2_SIZE}
      local ROOT_END=$(parted ${DISK_DEV} print | grep "^ ${ROOT_PART_NUM} " | awk '{ print $3 }')
      echo
      echo -e "${LTCYAN}  -home${NC}"
      echo -e "${LTGREEN}  COMMAND:${GRAY} parted -s ${DISK_DEV} mkpart primary ext4 ${ROOT_END} ${HOME_SIZE}${NC}"
      parted -s ${DISK_DEV} mkpart primary ext4 ${ROOT_END} ${HOME_SIZE}
      echo
  
      echo -e "${LTBLUE}==============================================================${NC}"
      echo -e "${LTBLUE}Toggling boot flag on root partition ...${NC}"
      echo -e "${LTBLUE}==============================================================${NC}"
      echo
      echo -e "${LTGREEN}COMMAND:${GRAY} parted ${DISK_DEV} set ${ROOT_PART_NUM} boot on ${NC}"
      parted ${DISK_DEV} set ${ROOT_PART_NUM} boot on > /dev/null 2>&1 
      echo
    ;;
    gpt)
      local SWAP_PART_NUM=2
      local ROOT_PART_NUM=3
      local HOME_PART_NUM=4
      echo
      echo -e "${LTCYAN}  -partition table${NC}"
      echo -e "${LTGREEN}  COMMAND:${GRAY} parted -s ${DISK_DEV} mklabel gpt${NC}"
      parted -s ${DISK_DEV} mklabel gpt
      echo
      echo -e "${LTCYAN}  -BIOS Boot${NC}"
      echo -e "${LTGREEN}  COMMAND:${GRAY} parted -s ${DISK_DEV} mkpart primary 1 ${BIOSBOOT_SIZE}${NC}"
      parted -s ${DISK_DEV} mkpart primary 1 ${BIOSBOOT_SIZE}
      echo -e "${LTGREEN}  COMMAND:${GRAY} parted ${DISK_DEV} set 1 bios_grub on ${NC}"
      parted ${DISK_DEV} set 1 bios_grub on > /dev/null 2>&1 
      echo
      echo -e "${LTCYAN}  -swap${NC}"
      echo -e "${LTGREEN}  COMMAND:${GRAY} parted -s ${DISK_DEV} mkpart primary linux-swap ${BIOSBOOT_SIZE} ${SWAP_SIZE}${NC}"
      parted -s ${DISK_DEV} mkpart primary linux-swap ${BIOSBOOT_SIZE} ${SWAP_SIZE}
      local SWAP_END=$(parted ${DISK_DEV} print | grep "^ ${SWAP_PART_NUM} " | awk '{ print $3 }')
      echo
      echo -e "${LTCYAN}  -root${NC}"
      echo -e "${LTGREEN}  COMMAND:${GRAY} parted -s ${DISK_DEV} mkpart primary ext4 ${SWAP_END} ${ROOT2_SIZE}${NC}"
      parted -s ${DISK_DEV} mkpart primary ext4 ${SWAP_END} ${ROOT2_SIZE}
      local ROOT_END=$(parted ${DISK_DEV} print | grep "^ ${ROOT_PART_NUM} " | awk '{ print $3 }')
      echo
      echo -e "${LTCYAN}  -home${NC}"
      echo -e "${LTGREEN}  COMMAND:${GRAY} parted -s ${DISK_DEV} mkpart primary ext4 ${ROOT_END} ${HOME_SIZE}${NC}"
      parted -s ${DISK_DEV} mkpart primary ext4 ${ROOT_END} ${HOME_SIZE}
      echo
  
      echo -e "${LTBLUE}==============================================================${NC}"
      echo -e "${LTBLUE}Toggling boot flag on root partition ...${NC}"
      echo -e "${LTBLUE}==============================================================${NC}"
      echo
      echo -e "${LTGREEN}COMMAND:${GRAY} parted ${DISK_DEV} set ${ROOT_PART_NUM} boot on ${NC}"
      parted ${DISK_DEV} set ${ROOT_PART_NUM} boot on > /dev/null 2>&1 
      echo
    ;;
  esac

  echo -e "${LTBLUE}==============================================================${NC}"
  echo -e "${LTBLUE}Rereading partition table ...${NC}"
  echo -e "${LTBLUE}==============================================================${NC}"
  echo
  echo -e "${LTGREEN}COMMAND:${GRAY} partprobe${NC}"
  partprobe
  sleep 2
  echo
  echo -e "${LTGREEN}COMMAND:${GRAY} lsblk${NC}"
  lsblk
  echo
  sleep 2

  echo -e "${LTBLUE}==============================================================${NC}"
  echo -e "${LTBLUE}Creating Swap filesystem on swap partition${NC}"
  echo -e "${LTBLUE}==============================================================${NC}"
  echo
  if echo ${DISK_DEV} | grep -q nvme
  then
    echo -e "${LTGREEN}COMMAND:${GRAY} mkswap ${DISK_DEV}p${SWAP_PART_NUM}${NC}"
    mkswap ${DISK_DEV}p${SWAP_PART_NUM}
    SWAP_PART=${DISK_DEV}p${SWAP_PART_NUM}
  else
    echo -e "${LTGREEN}COMMAND:${GRAY} mkswap ${DISK_DEV}${SWAP_PART_NUM}${NC}"
    mkswap ${DISK_DEV}${SWAP_PART_NUM}
    SWAP_PART=${DISK_DEV}${SWAP_PART_NUM}
  fi
  echo

  echo -e "${LTBLUE}==============================================================${NC}"
  echo -e "${LTBLUE}Creating EXT4 filesystem on root partition${NC}"
  echo -e "${LTBLUE}==============================================================${NC}"
  echo
  if echo ${DISK_DEV} | grep -q nvme
  then
    echo -e "${LTGREEN}COMMAND:${GRAY} mkfs.ext4 -F -L ROOT ${DISK_DEV}p${ROOT_PART_NUM}${NC}"
    mkfs.ext4 -F -L ROOT ${DISK_DEV}p${ROOT_PART_NUM}
    ROOT_PART=${DISK_DEV}p${ROOT_PART_NUM}
  else
    echo -e "${LTGREEN}COMMAND:${GRAY} mkfs.ext4 -F -L ROOT ${DISK_DEV}${ROOT_PART_NUM}${NC}"
    mkfs.ext4 -F -L ROOT ${DISK_DEV}${ROOT_PART_NUM}
    ROOT_PART=${DISK_DEV}${ROOT_PART_NUM}
  fi
  #echo

  echo -e "${LTBLUE}==============================================================${NC}"
  echo -e "${LTBLUE}Creating EXT4 filesystem on home partition${NC}"
  echo -e "${LTBLUE}==============================================================${NC}"
  echo
  if echo ${DISK_DEV} | grep -q nvme
  then
    echo -e "${LTGREEN}COMMAND:${GRAY} mkfs.ext4 -F -L HOME ${DISK_DEV}p${HOME_PART_NUM}${NC}"
    mkfs.ext4 -F -L ROOT ${DISK_DEV}p${HOME_PART_NUM}
    HOME_PART=${DISK_DEV}p${HOME_PART_NUM}
  else
    echo -e "${LTGREEN}COMMAND:${GRAY} mkfs.ext4 -F -L HOME ${DISK_DEV}${HOME_PART_NUM}${NC}"
    mkfs.ext4 -F -L ROOT ${DISK_DEV}${HOME_PART_NUM}
    HOME_PART=${DISK_DEV}${HOME_PART_NUM}
  fi
  #echo

  echo
}

copy_live_filesystem_to_disk() {
  echo -e "${LTBLUE}==============================================================${NC}"
  echo -e "${LTBLUE}Copying live image filesystem to disk ...${NC}"
  echo -e "${LTBLUE}==============================================================${NC}"
  echo

  for FILE_ON_ISO in $(ls ${ISO_MOUNT})
  do
    if file ${ISO_MOUNT}/${FILE_ON_ISO} | grep -q "Squashfs filesystem"
    then
      SQUASH_IMAGE=${ISO_MOUNT}/${FILE_ON_ISO}
    fi
  done

  if ! [ -z ${SQUASH_IMAGE} ]
  then
    echo -e "${LTCYAN}  -Mounting Squashfs ...${NC}"
    echo -e "${LTGREEN}  COMMAND:${GRAY} mkdir ${SQUASH_MOUNT}${NC}"
    mkdir ${SQUASH_MOUNT}
    echo -e "${LTGREEN}  COMMAND:${GRAY} mount ${SQUASH_IMAGE} ${SQUASH_MOUNT}${NC}"
    mount ${SQUASH_IMAGE} ${SQUASH_MOUNT}
    echo

    echo -e "${LTCYAN}  -Mounting Root Partition ...${NC}"
    echo -e "${LTGREEN}  COMMAND:${GRAY} mkdir ${ROOT_MOUNT}${NC}"
    mkdir ${ROOT_MOUNT}
    echo -e "${LTGREEN}  COMMAND:${GRAY} mount ${ROOT_PART} ${ROOT_MOUNT}${NC}"
    mount ${ROOT_PART} ${ROOT_MOUNT}
    echo

    case ${CREATE_HOME_PART} in
      Y)
        echo -e "${LTCYAN}  -Mounting Home Partition ...${NC}"
        echo -e "${LTGREEN}  COMMAND:${GRAY} mount ${HOME_PART} ${ROOT_MOUNT}/home${NC}"
        mount ${HOME_PART} ${ROOT_MOUNT}/home
        echo
      ;;
    esac

    echo -e "${LTCYAN}  -Copying filesystem to root partition (this may take a while) ...${NC}"
    #echo -e "${LTGREEN}  COMMAND:${GRAY} rsync -ah --progress ${SQUASH_MOUNT}/* ${ROOT_MOUNT}/${NC}"
    #rsync -ah --progress ${SQUASH_MOUNT}/* ${ROOT_MOUNT}/
    echo -e "${LTGREEN}  COMMAND:${GRAY} cp -a ${SQUASH_MOUNT}/* ${ROOT_MOUNT}/${NC}"
    cp -a ${SQUASH_MOUNT}/* ${ROOT_MOUNT}/
    echo

    echo -e "${LTCYAN}  -Updating /etc/fstab ...${NC}"
    SWAP_UUID=$(ls -l /dev/disk/by-uuid | grep $(basename ${SWAP_PART}) | awk '{ print $9 }')
    echo -e "${LTPURPLE}   SWAP: ${GRAY}UUID=${SWAP_UUID}  /  swap  defaults  0 0${NC}" 
    echo "UUID=${SWAP_UUID}  /  swap  defaults  0 0" > ${ROOT_MOUNT}/etc/fstab

    ROOT_UUID=$(ls -l /dev/disk/by-uuid | grep $(basename ${ROOT_PART}) | awk '{ print $9 }')
    echo -e "${LTPURPLE}   ROOT: ${GRAY}UUID=${ROOT_UUID}  /  ext4  acl,user_xattr  1 1${NC}"
    echo "UUID=${ROOT_UUID}  /  ext4  acl,user_xattr  1 1" >> ${ROOT_MOUNT}/etc/fstab

    case ${CREATE_HOME_PART} in
      Y)
        HOME_UUID=$(ls -l /dev/disk/by-uuid | grep $(basename ${HOME_PART}) | awk '{ print $9 }')
        echo "LABEL=${HOME_UUID}  /  ext4  acl,user_xattr  0 0" >> ${ROOT_MOUNT}/etc/fstab
        echo -e "${LTPURPLE}   HOME: ${GRAY}UUID=${HOME_UUID}  /  ext4  acl,user_xattr  0 0${NC}"
      ;;
    esac
    echo

    case ${CREATE_HOME_PART} in
      Y)
        echo -e "${LTCYAN}  -Unmounting Home Partition ...${NC}"
        echo -e "${LTGREEN}  COMMAND:${GRAY} umount ${HOME_PART}${NC}"
        umount ${HOME_PART}
        echo
      ;;
    esac

    echo -e "${LTCYAN}  -Unmounting Squashfs ...${NC}"
    echo -e "${LTGREEN}  COMMAND:${GRAY} umount ${SQUASH_IMAGE}${NC}"
    umount ${SQUASH_IMAGE}
    echo -e "${LTGREEN}  COMMAND:${GRAY} rmdir ${SQUASH_MOUNT}${NC}"
    rmdir ${SQUASH_MOUNT}
    echo

  else
    echo
    echo "${LTRED}ERROR: No Squashfs image found. Exiting.${NC}"
    echo
    exit 1
  fi
  echo
}

install_grub() {
  echo -e "${LTBLUE}==============================================================${NC}"
  echo -e "${LTBLUE}Installing GRUB ...${NC}"
  echo -e "${LTBLUE}==============================================================${NC}"
  echo

  case ${PARTITION_TABLE_TYPE} in
    msdos)
      local SWAP_PART_NUM=1
      local ROOT_PART_NUM=2
      local HOME_PART_NUM=3
    ;;
    gpt)
      local SWAP_PART_NUM=2
      local ROOT_PART_NUM=3
      local HOME_PART_NUM=4
    ;;
  esac

  if echo ${DISK_DEV} | grep -q nvme
  then
    local ROOT_PART=${DISK_DEV}p${ROOT_PART_NUM}
    local SWAP_PART=${DISK_DEV}p${SWAP_PART_NUM}
    local HOME_PART=${DISK_DEV}p${HOME_PART_NUM}
  else
    local ROOT_PART=${DISK_DEV}${ROOT_PART_NUM}
    local SWAP_PART=${DISK_DEV}${SWAP_PART_NUM}
    local HOME_PART=${DISK_DEV}${HOME_PART_NUM}
  fi

  #echo "ROOT_PART=${ROOT_PART}"
  #echo "ROOT_MOUNT=${ROOT_MOUNT}"
  #echo "SWAP_PART=${SWAP_PART}"
  #echo "HOME_PART=${HOME_PART}"

  if ! mount | grep -q ${ROOT_PART}
  then
    if ! [ -d ${ROOT_MOUNT} ]
    then
      echo -e "${LTGREEN}COMMAND:${GRAY} mkdir -p ${ROOT_MOUNT}${NC}"
      mkdir -p ${ROOT_MOUNT}
    fi
    echo -e "${LTGREEN}COMMAND:${GRAY} mount ${ROOT_PART} ${ROOT_MOUNT}${NC}"
    mount ${ROOT_PART} ${ROOT_MOUNT}
  fi

  echo
  echo -e "${LTGREEN}COMMAND:${GRAY} mount -bind ${ROOT_MOUNT}/dev${NC}"
  mount --bind /dev ${ROOT_MOUNT}/dev
  echo -e "${LTGREEN}COMMAND:${GRAY} mount -bind ${ROOT_MOUNT}/proc${NC}"
  mount --bind /proc ${ROOT_MOUNT}/proc
  echo -e "${LTGREEN}COMMAND:${GRAY} mount -bind ${ROOT_MOUNT}/sys${NC}"
  mount --bind /sys ${ROOT_MOUNT}/sys
  echo

  local ORIG_GRUB_CMDLINE_LINUX_DEFAULT="$(grep ^GRUB_CMDLINE_LINUX_DEFAULT ${ROOT_MOUNT}/etc/default/grub | cut -d \" -f 2)"
  local NEW_GRUB_CMDLINE_LINUX_DEFAULT=$(echo ${ORIG_GRUB_CMDLINE_LINUX_DEFAULT} | sed "s+resume=/dev/[a-z0-9]*+resume=${SWAP_PART}+g")

  #echo "ORIG_GRUB_CMDLINE_LINUX_DEFAULT=\"${ORIG_GRUB_CMDLINE_LINUX_DEFAULT}\""
  #echo "NEW_GRUB_CMDLINE_LINUX_DEFAULT=\"${NEW_GRUB_CMDLINE_LINUX_DEFAULT}\""
  #echo

  echo -e "${LTGREEN}COMMAND:${GRAY} cp ${ROOT_MOUNT}/etc/default/grub /tmp/grub.tmp${NC}"
  cp ${ROOT_MOUNT}/etc/default/grub /tmp/grub.tmp

  echo -e "${LTGREEN}COMMAND:${GRAY} sed -i "s+^GRUB_CMDLINE_LINUX_DEFAULT=.*+GRUB_CMDLINE_LINUX_DEFAULT=\"${NEW_GRUB_CMDLINE_LINUX_DEFAULT}\"+" /tmp/grub.tmp${NC}"
  sed -i "s+^GRUB_CMDLINE_LINUX_DEFAULT=.*+GRUB_CMDLINE_LINUX_DEFAULT=\"${NEW_GRUB_CMDLINE_LINUX_DEFAULT}\"+" /tmp/grub.tmp

  echo -e "${LTGREEN}COMMAND:${GRAY} cp /tmp/grub.tmp ${ROOT_MOUNT}/etc/default/grub${NC}"
  cp /tmp/grub.tmp ${ROOT_MOUNT}/etc/default/grub

  echo -e "${LTGREEN}COMMAND:${GRAY} rm -f /tmp/grub.tmp${NC}"
  rm -f /tmp/grub.tmp

  echo
  echo -e "${LTGREEN}COMMAND:${GRAY} chroot ${ROOT_MOUNT} /usr/sbin/grub2-mkconfig -o /boot/grub2/grub.cfg${NC}"
  chroot ${ROOT_MOUNT} /usr/sbin/grub2-mkconfig -o /boot/grub2/grub.cfg

  echo -e "${LTGREEN}COMMAND:${GRAY} chroot ${ROOT_MOUNT} /usr/sbin/grub2-install ${DISK_DEV}${NC}"
  chroot ${ROOT_MOUNT} /usr/sbin/grub2-install ${DISK_DEV} 2> /dev/null

  echo
  echo -e "${LTCYAN}-Unmounting Root Partition ...${NC}"
  echo -e "${LTGREEN}COMMAND:${GRAY} umount ${ROOT_MOUNT}/proc${NC}"
  umount ${ROOT_MOUNT}/proc
  sleep 2
  echo -e "${LTGREEN}COMMAND:${GRAY} umount ${ROOT_MOUNT}/dev${NC}"
  umount ${ROOT_MOUNT}/dev
  sleep 2
  echo -e "${LTGREEN}COMMAND:${GRAY} umount ${ROOT_MOUNT}/sys${NC}"
  umount ${ROOT_MOUNT/sys}
  sleep 2
  echo -e "${LTGREEN}COMMAND:${GRAY} umount -R ${ROOT_MOUNT}${NC}"
  umount -R ${ROOT_MOUNT}
  sleep 2
  echo -e "${LTGREEN}COMMAND:${GRAY} rmdir ${ROOT_MOUNT}${NC}"
  rmdir ${ROOT_MOUNT}
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
    exit
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

  case ${2} in
    with_home)
      IMAGE="$(ls /isofrom/*.iso | head -n 1)"
    ;;
    *)
      if [ -z ${2} ]
      then
        IMAGE="$(ls /isofrom/*.iso | head -n 1)"
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
    ;;
  esac

  if echo $* | grep -q "with_home"
  then
    CREATE_HOME_PART=Y
  else
    CREATE_HOME_PART=N
  fi

  echo 
  echo -e "${LTRED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}"
  echo -e "${LTRED}!!!!         WARNING: ALL DATA ON DISK WILL BE LOST!         !!!!${NC}"
  echo -e "${LTRED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}"
  echo
  echo -e "${LTPURPLE}Disk Device:      ${GRAY}${DISK_DEV}${NC}"
  get_partition_table_type
  echo
  echo -n -e "${LTRED}Enter Y to continue or N to quit (y/N): ${NC}"
  read DOIT
  case ${DOIT} in
    Y|y|Yes|YES)
      remove_partitions
      echo remove_partitions

      case ${CREATE_HOME_PART} in
        Y)
          create_two_partitions_with_swap
          echo create_two_partitions_with_swap
        ;;
        *)
          create_single_partition_with_swap
          echo create_single_partition_with_swap
        ;;
      esac
  
      copy_live_filesystem_to_disk
      echo copy_live_filesystem_to_disk
  
      install_grub
    ;;
    *)
      exit
    ;;
  esac

  echo -e "${LTPURPLE}==============================================================${NC}"
  echo
  echo -e "${LTPURPLE}  Live image installation finished.${NC}"
  echo
  echo -e "${LTPURPLE}  You may now reboot into the newly installed system.${NC}"
  echo
  echo -e "${LTPURPLE}==============================================================${NC}"
  echo
}

##############################################################################
#                           Main Code Body
##############################################################################

time main $*

