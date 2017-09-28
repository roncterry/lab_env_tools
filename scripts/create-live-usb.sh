#!/bin/bash
# version: 1.1.2
# date: 2017-09-27

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

USB_DISK=$1
LIVE_ISO=$2
if [ "${3}" == force_syslinux ]
then
  FILES_SOURCE=$4
else
  FILES_SOURCE=$3
fi

##############################################################################
#                              Functions
##############################################################################

usage() {
  echo "Usage: $0 <disk_dev>[:<part_count>[:<part1_size][:<part2_fstype>]] [<type>:]<live_iso>[,[<type>:]<live_iso>[, ...]] [<files_source>[,<files_source>,...]] [label=<volume_label>]"
  echo
  echo " <disk_dev>      --REQUIRED--"
  echo "                 The device file that corresponds to the USB disk"
  echo "                 you want to make bootable."
  echo "                 This should be a device file that represents a disk"
  echo "                 not a partition."
  echo 
  echo " <part_count>    --OPTIONAL--"
  echo "                 Number of partitions to create on the disk. "
  echo "                 Options: 1 2"
  echo
  echo "                 If omitted, a single partition will be created."
  echo
  echo " <part1_size>    --OPTIONAL--"
  echo "                 Size (in GB) to make the first partition."
  echo
  echo "                 If omitted, the size will be 3."
  echo
  echo " <part2_fstype>  --OPTIONAL--"
  echo "                 Filesystem type to put on the second partition."
  echo "                 Options: ntfs vfat ext4 xfs"
  echo
  echo "                 If omitted, ext4 will be used."
  echo "                 (The first parition will always be vfat)"
  echo
  echo " <type>          --OPTIONAL--"
  echo "                 Type for OS in the ISO image."
  echo "                 Can be one of the following:  suse fedora ubuntu mint"
  echo
  echo "                 If <type> is not specified it will be assumed "
  echo "                 to be: suse"
  echo
  echo " <live_iso>      --REQUIRED--"
  echo "                 Can be a comma separated list of paths to ISO images"
  echo "                 if you wish to have multiple boot options on the"
  echo "                 Live USB."
  echo
  echo " <file_source>   --OPTIONAL--"
  echo "                 A directory containing files that you want copied"
  echo "                 onto the USB disk after it has been made bootable."
  echo
  echo " <volume_label>  --OPTIONAL--"
  echo "                 The volume label you want to add to the first parition"
  echo "                 created on the flash drive."
  echo "                 DEFAULT=LIVE_USB"
  echo
}

check_for_root() {
  if [ $(whoami) != root ]
  then
    echo
    echo -e "${LTRED}ERROR: You must be root to run this script.${NC}"
    echo
    exit
  fi
}

check_for_usb_disk() {
  if [ -z ${USB_DISK} ]
  then
    echo
    echo -e "${LTRED}ERROR: You must provide the path to the USB disk.${NC}"
    echo
    usage
    echo
    exit 0
  else
    if echo ${USB_DISK} | grep -q ":"
    then
      DISK_DEV=$(echo ${USB_DISK} | cut -d : -f 1)
 
      PART_COUNT=$(echo ${USB_DISK} | cut -d : -f 2)
      if [ -z ${PART_COUNT} ]
      then
        PART_COUNT=1
      fi
 
      PART1_SIZE=$(echo ${USB_DISK} | cut -d : -f 3)
      if [ -z ${PART1_SIZE} ]
      then
        PART1_SIZE=3
      fi
 
      PART2_FSTYPE=$(echo ${USB_DISK} | cut -d : -f 4)
      if [ -z ${PART2_FSTYPE} ]
      then
        PART2_FSTYPE=ext4
      fi
    else
      DISK_DEV=${USB_DISK}
      PART_COUNT=1
    fi

    if ! [ -e ${DISK_DEV} ]
    then
      echo
      echo -e "${LTRED}ERROR: The provided USB disk does not seem to exist.${NC}"
      echo
      exit
    fi
  fi
}

check_for_live_iso() {
  if [ -z ${LIVE_ISO} ]
  then
    if ls /isofrom/*.iso > /dev/null 2>&1
    then
      cd /isofrom
      if [ "$(ls *.iso | wc -l)" -gt 1 ]
      then
        echo
        echo -e "${LTRED}ERROR: You must provide the path to the live ISO image(s).${NC}"
        echo
        usage
        echo
        exit 1
      else
        LIVE_ISO=$(ls *.iso)
      fi
    else
      echo
      echo -e "${LTRED}ERROR: You must provide the path to the live ISO image(s).${NC}"
      echo
      usage
      echo
      exit 1
    fi
  else
    local ISO_LIST=$(echo ${LIVE_ISO} | sed 's/,/ /g')
    for ISO in ${ISO_LIST}
    do
      if echo ${ISO} | grep -q ":"
      then
        local TYPE=$(echo ${ISO} | cut -d : -f 1)
        local ISO_IMAGE=$(echo ${ISO} | cut -d : -f 2)
      else
        local TYPE=suse
        local ISO_IMAGE=${ISO}
      fi

      if ! [ -e ${ISO_IMAGE} ]
      then
        echo
        echo -e "${LTPURPLE}ISO Image:i ${GRAY}${ISO_IMAGE}${NC}"
        echo -e "${LTRED}ERROR: The provided live ISO does not seem to exist.${NC}"
        echo
        exit
      fi
    done
  fi
}

remove_partitions() {
  echo
  echo -e "${LTBLUE}==============================================================${NC}"
  echo -e "${LTBLUE}Removing existing partitions ...${NC}"
  echo -e "${LTBLUE}==============================================================${NC}"
  echo
  for i in $(seq 1 4)
  do
    echo -e "${LTGREEN}COMMAND:${GRAY} umount ${DISK_DEV}${i}${NC}"
    umount ${DISK_DEV}${i}
    echo -e "${LTGREEN}COMMAND:${GRAY} parted -s ${DISK_DEV} rm ${i}${NC}"
    parted -s ${DISK_DEV} rm ${i}
  done
  echo
}

create_single_partition() {
  echo -e "${LTBLUE}==============================================================${NC}"
  echo -e "${LTBLUE}Creating partition ...${NC}"
  echo -e "${LTBLUE}==============================================================${NC}"
  echo
  echo -e "${LTCYAN}  -root${NC}"
  echo -e "${LTGREEN}  COMMAND:${GRAY} parted -s ${DISK_DEV} mkpart primary fat32 1 100%${NC}"
  parted -s ${DISK_DEV} mkpart primary fat32 1 100%
  echo

  echo -e "${LTBLUE}==============================================================${NC}"
  echo -e "${LTBLUE}Toggling boot flag on root partition ...${NC}"
  echo -e "${LTBLUE}==============================================================${NC}"
  echo
  echo -e "${LTGREEN}COMMAND:${GRAY} parted ${DISK_DEV} set  1 boot on ${NC}"
  parted ${DISK_DEV} set  1 boot on 
  echo

  echo -e "${LTBLUE}==============================================================${NC}"
  echo -e "${LTBLUE}Rereading partition table ...${NC}"
  echo -e "${LTBLUE}==============================================================${NC}"
  echo
  echo -e "${LTGREEN}COMMAND:${GRAY} partprobe${NC}"
  partprobe
  echo
  echo -e "${LTGREEN}COMMAND:${GRAY} lsblk${NC}"
  lsblk
  sleep 2

  echo -e "${LTBLUE}==============================================================${NC}"
  echo -e "${LTBLUE}Creating FAT32 filesystem on root partition${NC}"
  echo -e "${LTBLUE}==============================================================${NC}"
  echo
  echo -e "${LTGREEN}COMMAND:${GRAY} mkfs.vfat -n ${LABEL} ${DISK_DEV}1${NC}"
  mkfs.vfat -n ${LABEL} ${DISK_DEV}1
}

create_multiple_partitions() {
  echo -e "${LTBLUE}==============================================================${NC}"
  echo -e "${LTBLUE}Creating partitions ...${NC}"
  echo -e "${LTBLUE}==============================================================${NC}"
  echo
  echo -e "${LTCYAN}  -root${NC}"
  echo -e "${LTGREEN}   COMMAND:${GRAY} parted -s ${DISK_DEV} mkpart primary fat32 1 ${PART1_SIZE}GiB${NC}"
  parted -s ${DISK_DEV} mkpart primary fat32 1 ${PART1_SIZE}GiB
  echo

  echo -e "${LTCYAN}  -data${NC}"
  echo -e "${LTGREEN}   COMMAND:${GRAY} parted ${DISK_DEV} mkpart primary ${PART2_FSTYPE} ${PART1_SIZE}GiB 100%${NC}"
  parted -s ${DISK_DEV} mkpart primary ${PART2_FSTYPE} ${PART1_SIZE}GiB 100%
  echo

  echo -e "${LTBLUE}==============================================================${NC}"
  echo -e "${LTBLUE}Toggling boot flag on root partition ...${NC}"
  echo -e "${LTBLUE}==============================================================${NC}"
  echo
  echo -e "${LTGREEN}COMMAND:${GRAY} parted ${DISK_DEV} set  1 boot on ${NC}"
  parted ${DISK_DEV} set  1 boot on 
  echo

  echo
  echo -e "${LTBLUE}==============================================================${NC}"
  echo -e "${LTBLUE}Rereading partition table ...${NC}"
  echo -e "${LTBLUE}==============================================================${NC}"
  echo
  echo -e "${LTGREEN}COMMAND:${GRAY} partprobe${NC}"
  partprobe
  echo
  echo -e "${LTGREEN}COMMAND:${GRAY} lsblk${NC}"
  lsblk
  sleep 2

  echo
  echo -e "${LTBLUE}==============================================================${NC}"
  echo -e "${LTBLUE}Creating FAT32 filesystem on root partition${NC}"
  echo -e "${LTBLUE}==============================================================${NC}"
  echo
  echo -e "${LTGREEN}COMMAND:${GRAY} mkfs.vfat -n ${LABEL} ${DISK_DEV}1${NC}"
  mkfs.vfat -n ${LABEL} ${DISK_DEV}1

  case ${PART2_FSTYPE} in
    ntfs|NTFS)
      echo
      echo -e "${LTBLUE}==============================================================${NC}"
      echo -e "${LTBLUE}Creating NTFS filesystem on data partition${NC}"
      echo -e "${LTBLUE}==============================================================${NC}"
      echo
      echo -e "${LTGREEN}COMMAND:${GRAY} mkfs.ntfs -Q ${DISK_DEV}2${NC}"
      mkfs.ntfs -L ${LABEL2} -Q ${DISK_DEV}2
    ;;
    vfat|fat32|FAT32)
      echo
      echo -e "${LTBLUE}==============================================================${NC}"
      echo -e "${LTBLUE}Creating FAT32 filesystem on data partition${NC}"
      echo -e "${LTBLUE}==============================================================${NC}"
      echo
      echo -e "${LTGREEN}COMMAND:${GRAY} mkfs.vfat ${DISK_DEV}2${NC}"
      mkfs.vfat -n ${LABEL2} ${DISK_DEV}2
    ;;
    ext4|EXT4)
      echo
      echo -e "${LTBLUE}==============================================================${NC}"
      echo -e "${LTBLUE}Creating EXT4 filesystem on data partition${NC}"
      echo -e "${LTBLUE}==============================================================${NC}"
      echo
      echo -e "${LTGREEN}COMMAND:${GRAY} mkfs.ext4 ${DISK_DEV}2${NC}"
      mkfs.ext4 -L ${LABEL2} ${DISK_DEV}2
    ;;
    xfs|XFS)
      echo
      echo -e "${LTBLUE}==============================================================${NC}"
      echo -e "${LTBLUE}Creating XFS filesystem on data partition${NC}"
      echo -e "${LTBLUE}==============================================================${NC}"
      echo
      echo -e "${LTGREEN}COMMAND:${GRAY} mkfs.xfs -f ${DISK_DEV}2${NC}"
      mkfs.xfs -f -L ${LABEL2} ${DISK_DEV}2
    ;;
  esac
}

create_live_usb_syslinux() {
  local ISO_LIST=$(echo ${LIVE_ISO} | sed 's/,/ /g')

  echo
  echo -e "${LTBLUE}==============================================================${NC}"
  echo -e "${LTBLUE}Making Live USB (Syslinux) ...${NC}"
  echo -e "${LTBLUE}==============================================================${NC}"
  echo

  for ISO in ${ISO_LIST}
  do
    if echo ${ISO} | grep -q ":"
    then
      local TYPE=$(echo ${ISO} | cut -d : -f 1)
      local ISO_IMAGE=$(echo ${ISO} | cut -d : -f 2)
    else
      local TYPE=suse
      local ISO_IMAGE=${ISO}
    fi

    case ${TYPE} in
      clonezilla)
        echo 
        echo -e "(Clonezilla not supported with live-fat-stick. Skipping ...)"
        echo 
      ;;
      *)
        echo 
        echo -e "${LTCYAN}Copying ${TYPE} image to USB drive ...${NC}"
        echo -e "${LTCYAN}------------------------------------------------------------${NC}"
        echo
        echo -e "${LTGREEN}COMMAND:${GRAY} live-fat-stick --${TYPE} ${ISO_IMAGE} ${DISK_DEV}1${NC}"
        echo
        echo y | live-fat-stick --${TYPE} ${ISO_IMAGE} ${DISK_DEV}1
        echo
      ;;
    esac
  done
}

create_live_usb_grub() {
  local ISO_LIST=$(echo ${LIVE_ISO} | sed 's/,/ /g')
  local RAND=$(date +%s)

  echo
  echo -e "${LTBLUE}==============================================================${NC}"
  echo -e "${LTBLUE}Making Live USB (GRUB) ...${NC}"
  echo -e "${LTBLUE}==============================================================${NC}"
  echo

  COUNT=1
  for ISO in ${ISO_LIST}
  do
    if echo ${ISO} | grep -q ":"
    then
      local TYPE=$(echo ${ISO} | cut -d : -f 1)
      local ISO_IMAGE=$(echo ${ISO} | cut -d : -f 2)
    else
      local TYPE=suse
      local ISO_IMAGE=${ISO}
    fi

    case ${TYPE} in
      clonezilla)
        case ${COUNT} in
          1)
            echo
            echo -e "(Clonzilla not support as the first ISO image.  Skipping ...)"
          ;;
          *)
            echo 
            echo -e "${LTCYAN}Copying ${TYPE} image to USB drive ...${NC}"
            echo -e "${LTCYAN}------------------------------------------------------------${NC}"
            echo
            echo -e "${LTCYAN}Mounting ${DISK_DEV}1 on /mnt/${RAND}${NC}"
            echo -e "${LTGREEN}COMMAND:${GRAY} mkdir -p /mnt/${RAND}${NC}"
            mkdir -p /mnt/${RAND}

            echo -e "${LTGREEN}COMMAND:${GRAY} mount ${DISK_DEV}1 /mnt/${RAND}${NC}"
            mount ${DISK_DEV}1 /mnt/${RAND}
            echo 
  
            echo -e "${LTCYAN}Copying ISO image to flash drive ...${NC}"
            echo
            echo -e "${LTGREEN}COMMAND:${GRAY} cp ${ISO_IMAGE} /mnt/${RAND}${NC}"
            cp ${ISO_IMAGE} /mnt/${RAND}
            echo 
  
            echo -e "${LTCYAN}Updating grub.cfg${NC}"
            echo 
            echo "" >> /mnt/${RAND}/boot/grub2/grub.cfg
            echo 'menuentry "Clonezilla live" {' >> /mnt/${RAND}/boot/grub2/grub.cfg
            echo "	set isofile=\"/$(basename ${ISO_IMAGE})\"" >> /mnt/${RAND}/boot/grub2/grub.cfg
            echo '	loopback loop $isofile' >> /mnt/${RAND}/boot/grub2/grub.cfg
            echo '	linux (loop)/live/vmlinuz boot=live union=overlay username=user config components quiet noswap nolocales edd=on nomodeset nodmraid ocs_live_run=\"ocs-live-general\" ocs_live_extra_param=\"\" keyboard-layouts= ocs_live_batch=\"no\" locales= vga=788 ip=frommedia nosplash toram=filesystem.squashfs findiso=$isofile' >> /mnt/${RAND}/boot/grub2/grub.cfg
            echo '	initrd (loop)/live/initrd.img' >> /mnt/${RAND}/boot/grub2/grub.cfg
            echo '}' >> /mnt/${RAND}/boot/grub2/grub.cfg
  
            echo 
            echo -e "${LTCYAN}Mounting ${DISK_DEV}1 on /mnt/${RAND}${NC}"
            echo -e "${LTGREEN}COMMAND:${GRAY} umount ${DISK_DEV}1${NC}"
            umount ${DISK_DEV}1

            echo -e "${LTGREEN}COMMAND:${GRAY} rm -rf /mnt/${RAND}${NC}"
            rm -rf /mnt/${RAND}
            echo 
          ;;
        esac
      ;;
      suse)
        echo
        echo -e "${LTCYAN}Copying ${TYPE} image to USB drive ...${NC}"
        echo -e "${LTCYAN}------------------------------------------------------------${NC}"
        echo
        echo -e "${LTGREEN}COMMAND:${GRAY} live-grub-stick --${TYPE} ${ISO_IMAGE} ${DISK_DEV}1${NC}"
        echo
        echo y | live-grub-stick --${TYPE} ${ISO_IMAGE} ${DISK_DEV}1
        echo

        echo -e "${LTGREEN}COMMAND:${GRAY} mkdir /tmp/isomount-${RAND}${NC}"
        mkdir -p /tmp/isomount-${RAND}

        echo -e "${LTGREEN}COMMAND:${GRAY} mount -o loop ${ISO_IMAGE} /tmp/isomount-${RAND}${NC}"
        mount -o loop ${ISO_IMAGE} /tmp/isomount-${RAND}
        echo

        if $(file $(ls /tmp/isomount-${RAND}/*read-only*) | grep -q "Squashfs filesystem") > /dev/null
        then
          echo -e "${LTCYAN}Copying grub2 files from squashfs image to USB drive ...${NC}"
          echo -e "${LTCYAN}------------------------------------------------------------${NC}"

          echo -e "${LTGREEN}COMMAND:${GRAY} mkdir -p /tmp/usbmount-${RAND}${NC}"
          mkdir -p /tmp/usbmount-${RAND}

          echo -e "${LTGREEN}COMMAND:${GRAY} mount ${DISK_DEV}1 /tmp/usbmount-${RAND}${NC}"
          mount ${DISK_DEV}1 /tmp/usbmount-${RAND}

          echo -e "${LTGREEN}COMMAND:${GRAY} mkdir -p /tmp/squashmount-${RAND}${NC}"
          mkdir -p /tmp/squashmount-${RAND}

          echo -e "${LTGREEN}COMMAND:${GRAY} mount -o loop -t squashfs $(ls /tmp/isomount-${RAND}/*read-only*) /tmp/squashmount-${RAND}${NC}"
          mount -o loop -t squashfs $(ls /tmp/isomount-${RAND}/*read-only*) /tmp/squashmount-${RAND}

          echo -e "${LTGREEN}COMMAND:${GRAY} cp -a /tmp/squashmount-${RAND}/boot/grub2/* /tmp/usbmount-${RAND}/boot/grub2/${NC}"
          cp -a /tmp/squashmount-${RAND}/boot/grub2/* /tmp/usbmount-${RAND}/boot/grub2/

          echo -e "${LTGREEN}COMMAND:${GRAY} umount /tmp/squashmount-${RAND}${NC}"
          umount /tmp/squashmount-${RAND}

          echo -e "${LTGREEN}COMMAND:${GRAY} rm -rf /tmp/squashmount-${RAND}${NC}"
          rm -rf /tmp/squashmount-${RAND}

          echo -e "${LTGREEN}COMMAND:${GRAY} umount /tmp/usbmount-${RAND}${NC}"
          umount /tmp/usbmount-${RAND}

          echo -e "${LTGREEN}COMMAND:${GRAY} rm -rf /tmp/usbmount-${RAND}${NC}"
          rm -rf /tmp/usbmount-${RAND}

          echo -e "${LTCYAN}------------------------------------------------------------${NC}"
          echo
        fi

        echo -e "${LTGREEN}COMMAND:${GRAY} umount /tmp/isomount-${RAND}${NC}"
        umount /tmp/isomount-${RAND}

        echo -e "${LTGREEN}COMMAND:${GRAY} rm -rf /tmp/isomount-${RAND}${NC}"
        rm -rf /tmp/isomount-${RAND}

        echo
      ;;
      *)
        echo
        echo -e "${LTCYAN}Copying ${TYPE} image to USB drive ...${NC}"
        echo -e "${LTCYAN}------------------------------------------------------------${NC}"
        echo
        echo -e "${LTGREEN}COMMAND:${GRAY} live-grub-stick --${TYPE} ${ISO_IMAGE} ${DISK_DEV}1${NC}"
        echo
        echo y | live-grub-stick --${TYPE} ${ISO_IMAGE} ${DISK_DEV}1
        echo
      ;;
      esac
    ((COUNT++))
  done
}

copy_files_to_usb() {
  local RAND=$(date +%s)

  if [ -z ${PART_NUM} ]
  then
    PART_NUM=1
  fi

  if ! [ -z ${FILES_SOURCE} ]
  then
    if [ -e $(echo ${FILES_SOURCE} | cut -d , -f 1) ]
    then
      echo
      echo -e "${LTCYAN}Copying files to USB ...${NC}"
      echo -e "${LTCYAN}-------------------------------------------${NC}"
      echo
      echo -e "${LTGREEN}COMMAND:${GRAY} mkdir -p /mnt/${RAND}${NC}"
      mkdir -p /mnt/${RAND}

      echo -e "${LTGREEN}COMMAND:${GRAY} mount ${DISK_DEV}${PART_NUM} /mnt/${RAND}${NC}"
      mount ${DISK_DEV}${PART_NUM} /mnt/${RAND}

      for DIR in $(echo ${FILES_SOURCE} | sed 's/,/ /g')
      do
        #echo "rsync -a ${DIR} /mnt/${RAND}/"
        #rsync -a "${DIR}" /mnt/${RAND}/ > /dev/null 2>&1
        echo -e "${LTGREEN}COMMAND:${GRAY} cp -a ${DIR}/* /mnt/${RAND}/${NC}"
        cp -a "${DIR}"/* /mnt/${RAND}/ > /dev/null 2>&1
      done

      echo -e "${LTGREEN}COMMAND:${GRAY} sync${NC}"
      sync
      echo -e "${LTGREEN}COMMAND:${GRAY} umount ${DISK_DEV}${PART_NUM}${NC}"
      umount ${DISK_DEV}${PART_NUM}

      echo -e "${LTGREEN}COMMAND:${GRAY} rm -rf /mtn/${RAND}${NC}"
      rm -rf /mnt/${RAND}
      echo
    fi
  fi
}

print_iso_list() {
  local ISO_LIST=$(echo ${LIVE_ISO} | sed 's/,/ /g')

  local COUNT=0

  for ISO in ${ISO_LIST}
  do
    echo -e "${LTPURPLE}Live ISO ${COUNT}: ${GRAY}${ISO}${NC}"
    ((COUNT++))
  done
}

print_files_source_list() {
  local FILES_SOURCE_LIST=$(echo ${FILES_SOURCE} | sed 's/,/ /g')

  local COUNT=0

  for DIR in ${FILES_SOURCE_LIST}
  do
    echo -e "${LTPURPLE}Files Source ${COUNT}: ${GRAY}${DIR}${NC}"
    ((COUNT++))
  done
}

##################### main function #########################################

main() {
  if echo $* | grep -q force_syslinux
  then
    MODE=syslinux
  else
    if which live-grub-stick > /dev/null
    then
      MODE=grub
    else
      MODE=syslinux
    fi
  fi
 
  if echo $* | grep -q "label="
  then
    LABEL=$(echo $* | grep -o "label=.*" | cut -d ' '  -f 1 | cut -d = -f 2)
  else
    LABEL=LIVE_USB
  fi
 
  if echo $* | grep -q "label2="
  then
    LABEL2=$(echo $* | grep -o "label2=.*" | cut -d ' '  -f 1 | cut -d = -f 2)
  else
    LABEL2=LIVE_USB_HOME
  fi
 
  check_for_root
  check_for_usb_disk
  check_for_live_iso
  
  echo
  echo -e "${LTCYAN}#####################################################################${NC}"
  echo -e "${LTCYAN}                        Creating Live USB${NC}"
  echo -e "${LTCYAN}#####################################################################${NC}"
  echo
  echo -e "${LTPURPLE}Boot Mode:  ${GRAY}${MODE}${NC}"
  echo -e "${LTPURPLE}Label:      ${GRAY}${LABEL}${NC}"
  echo -e "${LTPURPLE}USB Device: ${GRAY}${DISK_DEV}${NC}"
  echo -e "${LTPURPLE}Partitions: ${GRAY}${PART_COUNT}${NC}"
  case ${PART_COUNT} in
    2)
      echo -e "${LTPURPLE}1st size:   ${GRAY}${PART1_SIZE}${NC}"
      echo -e "${LTPURPLE}2nd fstype: ${GRAY}${PART2_FSTYPE}${NC}"
      echo -e "${LTPURPLE}2nd Label:  ${GRAY}${LABEL2}${NC}"
    ;;
  esac
  print_iso_list
  print_files_source_list
  #echo "Live ISO:  ${LIVE_ISO}"
  #echo "Files:      ${FILES_SOURCE}"
  echo
  echo -e "${ORANGE}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}"
  echo -e "${ORANGE}        WARNING: This will delete ALL data from the USB disk${NC}"
  echo -e "${ORANGE}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}"
  echo
  
  echo -n "Proceed? [y/N]: "
  read DOIT
  case ${DOIT} in
    y|Y|yes|Yes|YES)
      remove_partitions
      case ${PART_COUNT} in
        1)
          create_single_partition
        ;;
        2)
          create_multiple_partitions
        ;;
      esac
      case ${MODE} in
        grub)
          create_live_usb_grub
        ;;
        syslinux)
          create_live_usb_syslinux
        ;;
      esac
      copy_files_to_usb
      echo
      echo -e "${LTCYAN}#####################################################################${NC}"
      echo -e "${LTCYAN}                              Finished${NC}"
      echo -e "${LTCYAN}#####################################################################${NC}"
      echo
    ;;
    *)
      echo
      echo -e "${LTCYAN}#####################################################################${NC}"
      echo -e "${LTCYAN}                               Exiting${NC}"
      echo -e "${LTCYAN}#####################################################################${NC}"
      echo
    ;;
  esac
  }

##############################################################################
#                            Main Code Body
##############################################################################
time main $*
echo -e "${LTCYAN}---------------------------------------------------------------------${NC}"
