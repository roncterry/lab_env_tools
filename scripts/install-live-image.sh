#!/bin/bash
# version: 3.0.1
# date: 2019-03-06

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

if [ -z ${BOOTEFI_SIZE} ]
then
  BOOTEFI_SIZE="256MiB"
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
  if [ -d /livecd ]
  then
    ISO_MOUNT="/livecd"
  elif [ -d /run/initramfs/live/LiveOS ]
  then
    ISO_MOUNT="/run/initramfs/live/LiveOS"
  fi
fi

if [ -z ${SQUASH_MOUNT} ]
then
  SQUASH_MOUNT="/tmp/squash_mount"
fi

if [ -z ${SQUASH_ROOT_IMAGE_MOUNT} ]
then
  SQUASH_ROOT_IMAGE_MOUNT="/tmp/squash_root_image_mount"
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
  echo "${0} <block_device> <image_file> [with_home] [force_msdos|force_gpt] [force_uefi|force_bios] [no_secureboot] [enable_cloudinit|disable_cloudinit] [force_rebuild_initrd]"
  echo
  echo "  Options:"
  echo "        with_home             Create a separate partition for /home"
  echo "        force_msdos           Force creating a msdos parition table type"
  echo "        force_gpt             Force creating a gtp parition table type"
  echo "        force_uefi            Force installing for the UEFI bootloader"
  echo "        force_bios            Force installing for the BIOS bootloader"
  echo "        no_secureboot         Disable secure boot with the UEFI bootloader"
  echo "        disable_cloudinit     Disable cloud-init in the installed OS if enabled"
  echo "        enable_cloudinit      Enable cloud-init in the installed OS if disabled"
  echo "        force_rebuild_initrd  Force rebuilding of the initramfs after install"
  echo
  echo "  Available Disks: ${BLOCK_DEV_LIST}"
  echo
  echo "  Note: This command can be customized by exporting the following"
  echo "        environment variables:"
  echo
  echo "        BOOTLOADER      -Set the bootloader to use (default: BIOS)"
  echo "                         Options: BIOS UEFI"
  echo "        BIOSBOOT_SIZE   -size of BIOS Boot partition (default: 7MiB)"
  echo "        BOOTEFI_SIZE    -size of Boot EFI partition (default: 256MiB)"
  echo "        SWAP_SIZE       -size of swap partition (default: 4GiB)"
  echo "        ROOT_SIZE       -size of root partition (default: 100%)"
  echo "        ROOT2_SIZE      -size of root partition when /home is on its"
  echo "                         own partition (default: 20GiB)"
  echo "        HOME_SIZE       -size of /home partition if \"with_home\" is"
  echo "                         supplied on the command line (default: 100%)"
  echo
}

check_user() {
  if [ "$(whoami)" != root ]
  then
    echo
    echo -e "${LTRED}ERROR: You must be root to run this command. (sudo OK)${NC}"
    echo
    exit 1
  fi
}

check_for_install_block_device() {
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
      if which multipath > /dev/null 2>&1
      then
        #-- check for multipath device
        MPIO_DEV_LIST="$(multipath -ll | grep ^[a-z,A-Z,0-9] | grep -v size | awk '{ print $1 }')"
        for MPIO_DEV in ${MPIO_DEV_LIST}
        do
          if multipath -ll ${MPIO_DEV} | grep -o $(basename ${1})
          then
            DISK_DEV="/dev/mapper/${MPIO_DEV}"
            ORIG_DISK_DEV="${1}"
            break
          fi
        done
        #---------------
      fi
      if [ -z ${DISK_DEV} ]
      then
        DISK_DEV=${1}
      fi
    else
      echo
      echo -e "${LTRED}ERROR: The block device provided doesn't seem to exist. Exiting.${NC}"
      echo
      exit 1
    fi
  fi
}

check_for_live_image() {
  case ${2} in
    with_home|force_uefi|force_bios|no_secureboot|force_msdos|force_gpt|disable_cloudinit|enable_cloudinit|force_rebuild_initrd)
      if [ -z ${3} ]
      then
        if [ -d /isofrom ]
        then
          IMAGE="$(ls /isofrom/*.iso | head -n 1)"
        elif [ -d /run/initramfs/isoscan ]
        then
          IMAGE="$(ls /run/initramfs/isoscan/*.iso | head -n 1)"
        fi
        #echo -e "${LTRED}IMAGE=${IMAGE}${NC}"
      else
        case ${3} in
          with_home|force_uefi|force_bios|no_secureboot|force_msdos|force_gpt|disable_cloudinit|enable_cloudinit|force_rebuild_initrd)
            if [ -z ${4} ]
            then
              if [ -d /isofrom ]
              then
                IMAGE="$(ls /isofrom/*.iso | head -n 1)"
              elif [ -d /run/initramfs/isoscan ]
              then
                IMAGE="$(ls /run/initramfs/isoscan/*.iso | head -n 1)"
              fi
            else
              if [ -e ${4} ]
              then
                IMAGE="${4}"
              else
                echo
                echo -e "${LTRED}ERROR: The image file provided doesn't seem to exist. Exiting.${NC}"
                echo
                exit 1
              fi
            fi
          ;;
          *)
            if [ -e ${3} ]
            then
              IMAGE="${3}"
            else
              echo
              echo -e "${LTRED}ERROR: The image file provided doesn't seem to exist. Exiting.${NC}"
              echo
              exit 1
            fi
          ;;
        esac
      fi
    ;;
    *)
      if [ -z ${2} ]
      then
        if [ -d /isofrom ]
        then
          IMAGE="$(ls /isofrom/*.iso | head -n 1)"
        elif [ -d /run/initramfs/isoscan ]
        then
          IMAGE="$(ls /run/initramfs/isoscan/*.iso | head -n 1)"
        fi
      else
        if [ -e ${2} ]
        then
          IMAGE="${2}"
        else
          echo
          echo -e "${LTRED}ERROR: The image file provided doesn't seem to exist. Exiting.${NC}"
          echo
          exit 1
        fi
      fi
      #echo -e "${LTRED}IMAGE=${IMAGE}${NC}"
    ;;
  esac
}

check_for_uefi() {
  # Is the variable IS_UEFI_BOOT still needed?
  if [ -z ${BOOTLOADER} ]
  then
    if [ -d /sys/firmware/efi ]
    then
      IS_UEFI_BOOT=Y
      BOOTLOADER=UEFI
    elif echo $* | grep "force_uefi"
    then
      IS_UEFI_BOOT=Y
      BOOTLOADER=UEFI
    elif echo $* | grep "force_bios"
    then
      IS_UEFI_BOOT=N
      BOOTLOADER=BIOS
    else
      IS_UEFI_BOOT=N
      BOOTLOADER=BIOS
    fi
  else
    case ${BOOTLOADER} in
      BIOS|bios)
        IS_UEFI_BOOT=N
      ;;
      UEFI|uefi)
        IS_UEFI_BOOT=Y
      ;;
    esac
  fi
}

check_for_create_home_partition() {
  if echo $* | grep -q "with_home"
  then
    CREATE_HOME_PART=Y
  else
    CREATE_HOME_PART=N
  fi
}

check_for_enable_secure_boot() {
  if echo $* | grep -q "no_secureboot"
  then
    SECURE_BOOT=N
  else
    SECURE_BOOT=Y
  fi
}

check_for_disable_cloudinit() {
  if echo $* | grep -q "disable_cloudinit"
  then
    DISABLE_CLOUDINIT=Y
    OTHER_OPTIONS="${OTHER_OPTIONS} disable_cloudinit"
  else
    DISABLE_CLOUDINIT=N
  fi
}

check_for_enable_cloudinit() {
  if echo $* | grep -q "enable_cloudinit"
  then
    ENABLE_CLOUDINIT=Y
    OTHER_OPTIONS="${OTHER_OPTIONS} enable_cloudinit"
  else
    ENABLE_CLOUDINIT=N
  fi
}

check_for_force_rebuild_initrd() {
  if echo $* | grep -q "force_rebuild_initrd"
  then
    FORCE_REBUILD_INITRD=Y
    OTHER_OPTIONS="${OTHER_OPTIONS} force_rebuild_initrd"
  else
    FORCE_REBUILD_INITRD=N
  fi
}

get_partition_table_type() {
  if echo $* | grep -q "force_msdos"
  then
    PARTITION_TABLE_TYPE=msdos
  fi

  if echo $* | grep -q "force_gpt"
  then
    PARTITION_TABLE_TYPE=gpt
  fi

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
}

remove_partitions() {
  echo
  echo -e "${LTBLUE}==============================================================${NC}"
  echo -e "${LTBLUE}Removing existing partitions ...${NC}"
  echo -e "${LTBLUE}==============================================================${NC}"
  echo
  echo -e "${LTGREEN}COMMAND:${GRAY} swapoff -av${NC}"
  swapoff -av
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
  elif echo ${DISK_DEV} | grep -q "/dev/mapper"
  then
    for i in $(seq 1 ${NUM_PARTS})
    do
      echo -e "${LTGREEN}COMMAND:${GRAY} umount ${DISK_DEV}-part${i}${NC}"
      umount ${DISK_DEV}-part${i}
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

#####################  BIOS Boot Functions  ##################################

create_single_partition_with_swap_bios_boot() {
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
      local BIOSBOOT_PART_NUM=1
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
      parted -s ${DISK_DEV} mkpart primary ext4 ${SWAP_END} ${ROOT_SIZE}
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
  elif echo ${DISK_DEV} | grep -q "/dev/mapper"
  then
    echo -e "${LTGREEN}COMMAND:${GRAY} mkswap ${DISK_DEV}-part${SWAP_PART_NUM}${NC}"
    mkswap ${DISK_DEV}-part${SWAP_PART_NUM}
    SWAP_PART=${DISK_DEV}-part${SWAP_PART_NUM}
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
  elif echo ${DISK_DEV} | grep -q "/dev/mapper"
  then
    echo -e "${LTGREEN}COMMAND:${GRAY} mkfs.ext4 -F -L ROOT ${DISK_DEV}-part${ROOT_PART_NUM}${NC}"
    mkfs.ext4 -F -L ROOT ${DISK_DEV}-part${ROOT_PART_NUM}
    ROOT_PART=${DISK_DEV}-part${ROOT_PART_NUM}
  else
    echo -e "${LTGREEN}COMMAND:${GRAY} mkfs.ext4 -F -L ROOT ${DISK_DEV}${ROOT_PART_NUM}${NC}"
    mkfs.ext4 -F -L ROOT ${DISK_DEV}${ROOT_PART_NUM}
    ROOT_PART=${DISK_DEV}${ROOT_PART_NUM}
  fi
  #echo
}

create_two_partitions_with_swap_bios_boot() {
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
      local BIOSBOOT_PART_NUM=1
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
  elif echo ${DISK_DEV} | grep -q "/dev/mapper"
  then
    echo -e "${LTGREEN}COMMAND:${GRAY} mkswap ${DISK_DEV}-part${SWAP_PART_NUM}${NC}"
    mkswap ${DISK_DEV}-part${SWAP_PART_NUM}
    SWAP_PART=${DISK_DEV}-part${SWAP_PART_NUM}
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
  elif echo ${DISK_DEV} | grep -q "/dev/mapper"
  then
    echo -e "${LTGREEN}COMMAND:${GRAY} mkfs.ext4 -F -L ROOT ${DISK_DEV}-part${ROOT_PART_NUM}${NC}"
    mkfs.ext4 -F -L ROOT ${DISK_DEV}-part${ROOT_PART_NUM}
    ROOT_PART=${DISK_DEV}-part${ROOT_PART_NUM}
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
  elif echo ${DISK_DEV} | grep -q "/dev/mapper"
  then
    echo -e "${LTGREEN}COMMAND:${GRAY} mkfs.ext4 -F -L HOME ${DISK_DEV}-part${HOME_PART_NUM}${NC}"
    mkfs.ext4 -F -L ROOT ${DISK_DEV}-part${HOME_PART_NUM}
    HOME_PART=${DISK_DEV}-part${HOME_PART_NUM}
  else
    echo -e "${LTGREEN}COMMAND:${GRAY} mkfs.ext4 -F -L HOME ${DISK_DEV}${HOME_PART_NUM}${NC}"
    mkfs.ext4 -F -L ROOT ${DISK_DEV}${HOME_PART_NUM}
    HOME_PART=${DISK_DEV}${HOME_PART_NUM}
  fi
  #echo

  echo
}

#######################  UEFI Boot Functions  ####################################

create_single_partition_with_swap_uefi_boot() {
  echo -e "${LTBLUE}==============================================================${NC}"
  echo -e "${LTBLUE}Creating partitions ...${NC}"
  echo -e "${LTBLUE}==============================================================${NC}"
  echo

  local BOOTEFI_PART_NUM=1
  local SWAP_PART_NUM=2
  local ROOT_PART_NUM=3

  echo -e "${LTCYAN}  -partition table${NC}"
  echo -e "${LTGREEN}  COMMAND:${GRAY} parted -s ${DISK_DEV} mklabel gpt${NC}"
  parted -s ${DISK_DEV} mklabel gpt
  echo

  echo -e "${LTCYAN}  -boot/efi${NC}"
  echo -e "${LTGREEN}  COMMAND:${GRAY} parted -s ${DISK_DEV} mkpart primary 1 ${BOOTEFI_SIZE}${NC}"
  parted -s ${DISK_DEV} mkpart primary 1 ${BOOTEFI_SIZE}
  local BOOTEFI_END=$(parted ${DISK_DEV} print | grep "^ ${BOOTEFI_PART_NUM} " | awk '{ print $3 }')
  echo

  echo -e "${LTCYAN}  -swap${NC}"
  echo -e "${LTGREEN}  COMMAND:${GRAY} parted -s ${DISK_DEV} mkpart primary linux-swap ${BOOTEFI_END} ${SWAP_SIZE}${NC}"
  parted -s ${DISK_DEV} mkpart primary linux-swap ${BOOTEFI_END} ${SWAP_SIZE}
  local SWAP_END=$(parted ${DISK_DEV} print | grep "^ ${SWAP_PART_NUM} " | awk '{ print $3 }')
  echo

  echo -e "${LTCYAN}  -root${NC}"
  echo -e "${LTGREEN}  COMMAND:${GRAY} parted -s ${DISK_DEV} mkpart primary ext4 ${SWAP_END} ${ROOT_SIZE}${NC}"
  parted -s ${DISK_DEV} mkpart primary ext4 ${SWAP_END} ${ROOT_SIZE}
  echo

  echo -e "${LTBLUE}==============================================================${NC}"
  echo -e "${LTBLUE}Toggling boot flag on boot/efi partition ...${NC}"
  echo -e "${LTBLUE}==============================================================${NC}"
  echo
  echo -e "${LTGREEN}COMMAND:${GRAY} parted ${DISK_DEV} set ${BOOTEFI_PART_NUM} boot on ${NC}"
  parted ${DISK_DEV} set ${BOOTEFI_PART_NUM} boot on > /dev/null 2>&1 
  #echo -e "${LTGREEN}COMMAND:${GRAY} parted ${DISK_DEV} set ${BOOTEFI_PART_NUM} esp on ${NC}"
  #parted ${DISK_DEV} set ${BOOTEFI_PART_NUM} esp on > /dev/null 2>&1 

  echo
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
  echo -e "${LTBLUE}Creating vfat filesystem on boot/efi partition${NC}"
  echo -e "${LTBLUE}==============================================================${NC}"
  echo
  if echo ${DISK_DEV} | grep -q nvme
  then
    echo -e "${LTGREEN}COMMAND:${GRAY} mkfs.vfat -F 32 -n EFI ${DISK_DEV}p${BOOTEFI_PART_NUM}${NC}"
    mkfs.vfat -F 32 -n EFI ${DISK_DEV}p${BOOTEFI_PART_NUM}
    BOOTEFI_PART=${DISK_DEV}p${BOOTEFI_PART_NUM}
  elif echo ${DISK_DEV} | grep -q "/dev/mapper"
  then
    echo -e "${LTGREEN}COMMAND:${GRAY} mkfs.vfat -F 32 -n EFI ${DISK_DEV}-part${BOOTEFI_PART_NUM}${NC}"
    mkfs.vfat -F 32 -n EFI ${DISK_DEV}-part${BOOTEFI_PART_NUM}
    BOOTEFI_PART=${DISK_DEV}-part${BOOTEFI_PART_NUM}
  else
    echo -e "${LTGREEN}COMMAND:${GRAY} mkfs.vfat -F 32 -n EFI ${DISK_DEV}${BOOTEFI_PART_NUM}${NC}"
    mkfs.vfat -F 32 -n EFI ${DISK_DEV}${BOOTEFI_PART_NUM}
    BOOTEFI_PART=${DISK_DEV}${BOOTEFI_PART_NUM}
  fi

  echo -e "${LTBLUE}==============================================================${NC}"
  echo -e "${LTBLUE}Creating Swap filesystem on swap partition${NC}"
  echo -e "${LTBLUE}==============================================================${NC}"
  echo
  if echo ${DISK_DEV} | grep -q nvme
  then
    echo -e "${LTGREEN}COMMAND:${GRAY} mkswap ${DISK_DEV}p${SWAP_PART_NUM}${NC}"
    mkswap ${DISK_DEV}p${SWAP_PART_NUM}
    SWAP_PART=${DISK_DEV}p${SWAP_PART_NUM}
  elif echo ${DISK_DEV} | grep -q "/dev/mapper"
  then
    echo -e "${LTGREEN}COMMAND:${GRAY} mkswap ${DISK_DEV}-part${SWAP_PART_NUM}${NC}"
    mkswap ${DISK_DEV}-part${SWAP_PART_NUM}
    SWAP_PART=${DISK_DEV}-part${SWAP_PART_NUM}
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
  elif echo ${DISK_DEV} | grep -q "/dev/mapper"
  then
    echo -e "${LTGREEN}COMMAND:${GRAY} mkfs.ext4 -F -L ROOT ${DISK_DEV}-part${ROOT_PART_NUM}${NC}"
    mkfs.ext4 -F -L ROOT ${DISK_DEV}-part${ROOT_PART_NUM}
    ROOT_PART=${DISK_DEV}-part${ROOT_PART_NUM}
  else
    echo -e "${LTGREEN}COMMAND:${GRAY} mkfs.ext4 -F -L ROOT ${DISK_DEV}${ROOT_PART_NUM}${NC}"
    mkfs.ext4 -F -L ROOT ${DISK_DEV}${ROOT_PART_NUM}
    ROOT_PART=${DISK_DEV}${ROOT_PART_NUM}
  fi
  #echo
}

create_two_partitions_with_swap_uefi_boot() {
  echo -e "${LTBLUE}==============================================================${NC}"
  echo -e "${LTBLUE}Creating partitions ...${NC}"
  echo -e "${LTBLUE}==============================================================${NC}"
  echo

  local BOOTEFI_PART_NUM=1
  local SWAP_PART_NUM=2
  local ROOT_PART_NUM=3
  local HOME_PART_NUM=4

  echo -e "${LTCYAN}  -partition table${NC}"
  echo -e "${LTGREEN}  COMMAND:${GRAY} parted -s ${DISK_DEV} mklabel gpt${NC}"
  parted -s ${DISK_DEV} mklabel gpt
  echo
  echo -e "${LTCYAN}  -boot/uefi${NC}"
  echo -e "${LTGREEN}  COMMAND:${GRAY} parted -s ${DISK_DEV} mkpart primary 1 ${BOOTEFI_SIZE}${NC}"
  parted -s ${DISK_DEV} mkpart primary 1 ${BOOTEFI_SIZE}
  local BOOTEFI_END=$(parted ${DISK_DEV} print | grep "^ ${BOOTEFI_PART_NUM} " | awk '{ print $3 }')
  echo

  echo -e "${LTCYAN}  -swap${NC}"
  echo -e "${LTGREEN}  COMMAND:${GRAY} parted -s ${DISK_DEV} mkpart primary linux-swap ${BOOTEFI_END} ${SWAP_SIZE}${NC}"
  parted -s ${DISK_DEV} mkpart primary linux-swap ${BOOTEFI_END} ${SWAP_SIZE}
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
  echo -e "${LTBLUE}Toggling boot flag on boot/efi partition ...${NC}"
  echo -e "${LTBLUE}==============================================================${NC}"
  echo
  echo -e "${LTGREEN}COMMAND:${GRAY} parted ${DISK_DEV} set ${BOOTEFI_PART_NUM} boot on ${NC}"
  parted ${DISK_DEV} set ${BOOTEFI_PART_NUM} boot on > /dev/null 2>&1 
  echo

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
  echo -e "${LTBLUE}Creating vfat filesystem on boot/efi partition${NC}"
  echo -e "${LTBLUE}==============================================================${NC}"
  echo
  if echo ${DISK_DEV} | grep -q nvme
  then
    echo -e "${LTGREEN}COMMAND:${GRAY} mkfs.vfat -F 32 -n EFI ${DISK_DEV}p${BOOTEFI_PART_NUM}${NC}"
    mkfs.vfat -F 32 -n EFI ${DISK_DEV}p${BOOTEFI_PART_NUM}
    BOOTEFI_PART=${DISK_DEV}p${BOOTEFI_PART_NUM}
  elif echo ${DISK_DEV} | grep -q "/dev/mapper"
  then
    echo -e "${LTGREEN}COMMAND:${GRAY} mkfs.vfat -F 32 -n EFI ${DISK_DEV}-part${BOOTEFI_PART_NUM}${NC}"
    mkfs.vfat -F 32 -n EFI ${DISK_DEV}-part${BOOTEFI_PART_NUM}
    BOOTEFI_PART=${DISK_DEV}-part${BOOTEFI_PART_NUM}
  else
    echo -e "${LTGREEN}COMMAND:${GRAY} mkfs.vfat -F 32 -n EFI ${DISK_DEV}${BOOTEFI_PART_NUM}${NC}"
    mkfs.vfat -F 32 -n EFI ${DISK_DEV}${BOOTEFI_PART_NUM}
    BOOTEFI_PART=${DISK_DEV}${BOOTEFI_PART_NUM}
  fi

  echo -e "${LTBLUE}==============================================================${NC}"
  echo -e "${LTBLUE}Creating Swap filesystem on swap partition${NC}"
  echo -e "${LTBLUE}==============================================================${NC}"
  echo
  if echo ${DISK_DEV} | grep -q nvme
  then
    echo -e "${LTGREEN}COMMAND:${GRAY} mkswap ${DISK_DEV}p${SWAP_PART_NUM}${NC}"
    mkswap ${DISK_DEV}p${SWAP_PART_NUM}
    SWAP_PART=${DISK_DEV}p${SWAP_PART_NUM}
  elif echo ${DISK_DEV} | grep -q "/dev/mapper"
  then
    echo -e "${LTGREEN}COMMAND:${GRAY} mkswap ${DISK_DEV}-part${SWAP_PART_NUM}${NC}"
    mkswap ${DISK_DEV}-part${SWAP_PART_NUM}
    SWAP_PART=${DISK_DEV}-part${SWAP_PART_NUM}
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
  elif echo ${DISK_DEV} | grep -q "/dev/mapper"
  then
    echo -e "${LTGREEN}COMMAND:${GRAY} mkfs.ext4 -F -L ROOT ${DISK_DEV}-part${ROOT_PART_NUM}${NC}"
    mkfs.ext4 -F -L ROOT ${DISK_DEV}-part${ROOT_PART_NUM}
    ROOT_PART=${DISK_DEV}-part${ROOT_PART_NUM}
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
  elif echo ${DISK_DEV} | grep -q "/dev/mapper"
  then
    echo -e "${LTGREEN}COMMAND:${GRAY} mkfs.ext4 -F -L HOME ${DISK_DEV}-part${HOME_PART_NUM}${NC}"
    mkfs.ext4 -F -L ROOT ${DISK_DEV}-part${HOME_PART_NUM}
    HOME_PART=${DISK_DEV}-part${HOME_PART_NUM}
  else
    echo -e "${LTGREEN}COMMAND:${GRAY} mkfs.ext4 -F -L HOME ${DISK_DEV}${HOME_PART_NUM}${NC}"
    mkfs.ext4 -F -L ROOT ${DISK_DEV}${HOME_PART_NUM}
    HOME_PART=${DISK_DEV}${HOME_PART_NUM}
  fi
  #echo

  echo
}

#######################  Copy Live Filesystem to Disk Function  ####################################

copy_live_filesystem_to_disk() {
  echo -e "${LTBLUE}==============================================================${NC}"
  case ${BOOTLOADER} in
    BIOS|bios)
      echo -e "${LTBLUE}Copying live image filesystem to disk (for BIOS Booting)...${NC}"
    ;;
    UEFI|uefi)
      echo -e "${LTBLUE}Copying live image filesystem to disk (for UEFI Booting)...${NC}"
    ;;
  esac
  echo -e "${LTBLUE}==============================================================${NC}"
  echo

  for FILE_ON_ISO in $(ls ${ISO_MOUNT})
  do
    if [ -d ${ISO_MOUNT}/LiveOS ]
    then
      if file ${ISO_MOUNT}/LiveOS/${FILE_ON_ISO} | grep -q "Squashfs filesystem"
      then
        SQUASH_IMAGE=${ISO_MOUNT}/LiveOS/${FILE_ON_ISO}
      fi
    else
      if file ${ISO_MOUNT}/${FILE_ON_ISO} | grep -q "Squashfs filesystem"
      then
        SQUASH_IMAGE=${ISO_MOUNT}/${FILE_ON_ISO}
      fi
    fi
  done

  echo -e "${LTPURPLE}  SQUASH_IMAGE=${GRAY}${SQUASH_IMAGE}${NC}"

  if ! [ -z ${SQUASH_IMAGE} ]
  then
    echo -e "${LTCYAN}  -Mounting Squashfs ...${NC}"
    echo -e "${LTGREEN}  COMMAND:${GRAY} mkdir ${SQUASH_MOUNT}${NC}"
    mkdir ${SQUASH_MOUNT}
    echo -e "${LTGREEN}  COMMAND:${GRAY} mount ${SQUASH_IMAGE} ${SQUASH_MOUNT}${NC}"
    mount ${SQUASH_IMAGE} ${SQUASH_MOUNT}
    echo
    if [ -e ${SQUASH_MOUNT}/LiveOS/rootfs.img ]
    then
      SQUASH_ROOT_IMAGE=${SQUASH_MOUNT}/LiveOS/rootfs.img
      echo -e "${LTPURPLE}  SQUASH_ROOT_IMAGE=${GRAY}${SQUASH_ROOT_IMAGE}${NC}"

      #for FILE_IN_SQUASH_IMAGE in $(ls ${SQUASH_MOUNT}/LiveOS)
      #do
      #  echo FILE_IN_SQUASH_IMAGE=${FILE_IN_SQUASH_IMAGE};read
      #  if file ${SQUASH_MOUNT}/LiveOS/${FILE_IN_SQUASH_IMAGE} | grep -q "Squashfs filesystem"
      #  then
      #    SQUASH_ROOT_IMAGE=${SQUASH_MOUNT}/LiveOS/${FILE_IN_SQUASH_IMAGE}
      #    echo SQUASH_ROOT_IMAGE=${SQUASH_ROOT_IMAGE};read
      #  fi
      #done

      echo -e "${LTCYAN}  -Mounting Root Image in Squashfs ...${NC}"
      echo -e "${LTGREEN}  COMMAND:${GRAY} mkdir ${SQUASH_ROOT_IMAGE_MOUNT}${NC}"
      mkdir ${SQUASH_ROOT_IMAGE_MOUNT}
      echo -e "${LTGREEN}  COMMAND:${GRAY} mount ${SQUASH_ROOT_IMAGE} ${SQUASH_ROOT_IMAGE_MOUNT}${NC}"
      mount ${SQUASH_ROOT_IMAGE} ${SQUASH_ROOT_IMAGE_MOUNT}
      echo
    fi

    echo -e "${LTCYAN}  -Mounting Root Partition ...${NC}"
    echo -e "${LTGREEN}  COMMAND:${GRAY} mkdir ${ROOT_MOUNT}${NC}"
    mkdir ${ROOT_MOUNT}
    echo -e "${LTGREEN}  COMMAND:${GRAY} mount ${ROOT_PART} ${ROOT_MOUNT}${NC}"
    mount ${ROOT_PART} ${ROOT_MOUNT}
    echo

    case ${BOOTLOADER} in
      UEFI|uefi)
        echo -e "${LTCYAN}  -Mounting EFI Partition ...${NC}"
        echo -e "${LTGREEN}  COMMAND:${GRAY} mkdir -p ${ROOT_MOUNT}/boot/efi${NC}"
        mkdir -p ${ROOT_MOUNT}/boot/efi
        echo -e "${LTGREEN}  COMMAND:${GRAY} mount ${BOOTEFI_PART} ${ROOT_MOUNT}/boot/efi${NC}"
        mount ${BOOTEFI_PART} ${ROOT_MOUNT}/boot/efi
        echo
      ;;
    esac

    case ${CREATE_HOME_PART} in
      Y)
        echo -e "${LTCYAN}  -Mounting Home Partition ...${NC}"
        echo -e "${LTGREEN}  COMMAND:${GRAY} mkdir -p ${ROOT_MOUNT}/home${NC}"
        mkdir -p ${ROOT_MOUNT}/home
        echo -e "${LTGREEN}  COMMAND:${GRAY} mount ${HOME_PART} ${ROOT_MOUNT}/home${NC}"
        mount ${HOME_PART} ${ROOT_MOUNT}/home
        echo
      ;;
    esac

    echo -e "${LTCYAN}  -Copying filesystem to root partition (this may take a while) ...${NC}"
    #echo -e "${LTGREEN}  COMMAND:${GRAY} rsync -ah --progress ${SQUASH_MOUNT}/* ${ROOT_MOUNT}/${NC}"
    #rsync -ah --progress ${SQUASH_MOUNT}/* ${ROOT_MOUNT}/
    if [ -z ${SQUASH_ROOT_IMAGE} ]
    then
      echo -e "${LTGREEN}  COMMAND:${GRAY} cp -a ${SQUASH_MOUNT}/* ${ROOT_MOUNT}/${NC}"
      cp -a ${SQUASH_MOUNT}/* ${ROOT_MOUNT}/
    else
      echo -e "${LTGREEN}  COMMAND:${GRAY} cp -a ${SQUASH_ROOT_IMAGE_MOUNT}/* ${ROOT_MOUNT}/${NC}"
      cp -a ${SQUASH_ROOT_IMAGE_MOUNT}/* ${ROOT_MOUNT}/
    fi
    echo

    echo -e "${LTCYAN}  -Updating /etc/fstab ...${NC}"

    if echo ${DISK_DEV} | grep -q "/dev/mapper"
    then
      # Note: BIOSBOOT_PART variable is not needed here
      local ORIGINAL_BOOTEFI_PART=${BOOTEFI_PART}
      local ORIGINAL_ROOT_PART=${ROOT_PART}
      local ORIGINAL_SWAP_PART=${SWAP_PART}
      local BOOTEFI_PART=$(ls -l /dev/mapper/ | grep "$(basename ${ORIGINAL_BOOTEFI_PART})" | cut -d \> -f 2 | sed 's+^ ..+/dev+')
      local ROOT_PART=$(ls -l /dev/mapper/ | grep "$(basename ${ORIGINAL_ROOT_PART})" | cut -d \> -f 2 | sed 's+^ ..+/dev+')
      local SWAP_PART=$(ls -l /dev/mapper/ | grep "$(basename ${ORIGINAL_SWAP_PART})" | cut -d \> -f 2 | sed 's+^ ..+/dev+')
    fi

    SWAP_UUID=$(ls -l /dev/disk/by-uuid | grep $(basename ${SWAP_PART}) | awk '{ print $9 }')
    echo -e "${LTPURPLE}   SWAP: ${GRAY}UUID=${SWAP_UUID}  swap  swap  defaults  0 0${NC}" 
    echo "UUID=${SWAP_UUID}  swap  swap  defaults  0 0" > ${ROOT_MOUNT}/etc/fstab

    ROOT_UUID=$(ls -l /dev/disk/by-uuid | grep $(basename ${ROOT_PART}) | awk '{ print $9 }')
    echo -e "${LTPURPLE}   ROOT: ${GRAY}UUID=${ROOT_UUID}  /  ext4  acl,user_xattr  1 1${NC}"
    echo "UUID=${ROOT_UUID}  /  ext4  acl,user_xattr  1 1" >> ${ROOT_MOUNT}/etc/fstab

    case ${BOOTLOADER} in
      UEFI|uefi)
        BOOTEFI_UUID=$(ls -l /dev/disk/by-uuid | grep $(basename ${BOOTEFI_PART}) | awk '{ print $9 }')
        echo -e "${LTPURPLE}   BOOTEFI: ${GRAY}UUID=${BOOTEFI_UUID}  /boot/efi  vfat  defaults  0 0${NC}" 
        echo "UUID=${BOOTEFI_UUID}  /boot/efi  vfat  defaults  0 0" >> ${ROOT_MOUNT}/etc/fstab
        if ! [ -d ${ROOT_MOUNT}/boot/efi ]
        then
          mkdir -p ${ROOT_MOUNT}/boot/efi 
        fi
      ;;
    esac

    if echo ${DISK_DEV} | grep -q "/dev/mapper"
    then
      # Note: ORIGINAL_BIOSBOOT_PART/BIOSBOOT_PART variables are not needed here
      local BOOTEFI_PART=${ORIGINAL_BOOTEFI_PART}
      local ROOT_PART=${ORIGINAL_ROOT_PART}
      local SWAP_PART=${ORIGINAL_SWAP_PART}
    fi

    case ${CREATE_HOME_PART} in
      Y)
        if echo ${DISK_DEV} | grep -q "/dev/mapper"
        then
          local ORIGINAL_HOME_PART=${HOME_PART}
          local HOME_PART=$(ls -l /dev/mapper/ | grep "$(basename ${ORIGINAL_HOME_PART})" | cut -d \> -f 2 | sed 's+^ ..+/dev+')
        fi

        HOME_UUID=$(ls -l /dev/disk/by-uuid | grep $(basename ${HOME_PART}) | awk '{ print $9 }')
        echo "UUID=${HOME_UUID}  /home  ext4  acl,user_xattr  0 0" >> ${ROOT_MOUNT}/etc/fstab
        echo -e "${LTPURPLE}   HOME: ${GRAY}UUID=${HOME_UUID}  /home  ext4  acl,user_xattr  0 0${NC}"

        if echo ${DISK_DEV} | grep -q "/dev/mapper"
        then
          local HOME_PART=${ORIGINAL_HOME_PART}
        fi
      ;;
    esac
    echo

    echo -e "${LTCYAN}  -Bind Mounting dev,proc,sys Filesystems ...${NC}"
    echo -e "${LTGREEN}  COMMAND:${GRAY} mount --bind ${ROOT_MOUNT}/dev${NC}"
    mount --bind /dev ${ROOT_MOUNT}/dev
    echo -e "${LTGREEN}  COMMAND:${GRAY} mount --bind ${ROOT_MOUNT}/proc${NC}"
    mount --bind /proc ${ROOT_MOUNT}/proc
    echo -e "${LTGREEN}  COMMAND:${GRAY} mount --bind ${ROOT_MOUNT}/sys${NC}"
    mount --bind /sys ${ROOT_MOUNT}/sys
    echo

    echo -e "${LTCYAN}  -Generating New initramfs ...${NC}"
    case ${FORCE_REBUILD_INITRD} in
      Y)
        echo -e "${LTGREEN}  COMMAND:${GRAY} chroot ${ROOT_MOUNT} /usr/bin/dracut --force${NC}"
        chroot ${ROOT_MOUNT} /usr/bin/dracut --force
      ;;
      N)
        echo -e "${LTGREEN}  COMMAND:${GRAY} chroot ${ROOT_MOUNT} /usr/bin/dracut${NC}"
        chroot ${ROOT_MOUNT} /usr/bin/dracut
      ;;
    esac
    echo

    case ${DISABLE_CLOUDINIT} in
      Y)
        echo -e "${LTCYAN}  -Disabling cloud-init ...${NC}"
        echo -e "${LTGREEN}  COMMAND:${GRAY} chroot ${ROOT_MOUNT} /usr/bin/systemctl disable cloud-init${NC}"
        chroot ${ROOT_MOUNT} /usr/bin/systemctl disable cloud-init

        echo -e "${LTGREEN}  COMMAND:${GRAY} chroot ${ROOT_MOUNT} /usr/bin/systemctl disable cloud-init-local${NC}"
        chroot ${ROOT_MOUNT} /usr/bin/systemctl disable cloud-init-local

        echo -e "${LTGREEN}  COMMAND:${GRAY} chroot ${ROOT_MOUNT} /usr/bin/systemctl disable cloud-config${NC}"
        chroot ${ROOT_MOUNT} /usr/bin/systemctl disable cloud-config

        echo -e "${LTGREEN}  COMMAND:${GRAY} chroot ${ROOT_MOUNT} /usr/bin/systemctl disable cloud-final${NC}"
        chroot ${ROOT_MOUNT} /usr/bin/systemctl disable cloud-final
        echo
      ;;
    esac

    case ${ENABLE_CLOUDINIT} in
      Y)
        echo -e "${LTCYAN}  -Enabling cloud-init ...${NC}"
        echo -e "${LTGREEN}  COMMAND:${GRAY} chroot ${ROOT_MOUNT} /usr/bin/systemctl enable cloud-init${NC}"
        chroot ${ROOT_MOUNT} /usr/bin/systemctl enable cloud-init

        echo -e "${LTGREEN}  COMMAND:${GRAY} chroot ${ROOT_MOUNT} /usr/bin/systemctl enable cloud-init-local${NC}"
        chroot ${ROOT_MOUNT} /usr/bin/systemctl enable cloud-init-local

        echo -e "${LTGREEN}  COMMAND:${GRAY} chroot ${ROOT_MOUNT} /usr/bin/systemctl enable cloud-config${NC}"
        chroot ${ROOT_MOUNT} /usr/bin/systemctl enable cloud-config

        echo -e "${LTGREEN}  COMMAND:${GRAY} chroot ${ROOT_MOUNT} /usr/bin/systemctl enable cloud-final${NC}"
        chroot ${ROOT_MOUNT} /usr/bin/systemctl enable cloud-final
        echo
      ;;
    esac

    #echo -e "${LTCYAN}  -Copying in installer script ...${NC}"
    #echo -e "${LTGREEN}  COMMAND:${GRAY} cp ${0} ${ROOT_MOUNT}/usr/local/bin/${NC}"
    #cp ${0} ${ROOT_MOUNT}/usr/local/bin/
    #echo -e "${LTGREEN}  COMMAND:${GRAY} chmod +x ${ROOT_MOUNT}/usr/local/bin/install-live-image.sh${NC}"
    #chmod +x ${ROOT_MOUNT}/usr/local/bin/install-live-image.sh

    echo -e "${LTCYAN}  -Unmounting dev,proc,sys Filesystems ...${NC}"
    echo -e "${LTGREEN}  COMMAND:${GRAY} umount -R ${ROOT_MOUNT}/proc${NC}"
    umount -R ${ROOT_MOUNT}/proc
    echo -e "${LTGREEN}  COMMAND:${GRAY} umount -R ${ROOT_MOUNT}/dev${NC}"
    umount -R ${ROOT_MOUNT}/dev
    echo -e "${LTGREEN}  COMMAND:${GRAY} umount -R ${ROOT_MOUNT}/sys${NC}"
    umount -R ${ROOT_MOUNT/sys}
    echo

    case ${CREATE_HOME_PART} in
      Y)
        echo -e "${LTCYAN}  -Unmounting Home Partition ...${NC}"
        echo -e "${LTGREEN}  COMMAND:${GRAY} umount ${HOME_PART}${NC}"
        umount ${HOME_PART}
        echo
      ;;
    esac

    if ! [ -z ${SQUASH_ROOT_IMAGE} ]
    then
      echo -e "${LTCYAN}  -Unmounting Root Image in Squashfs ...${NC}"
      echo -e "${LTGREEN}  COMMAND:${GRAY} umount ${SQUASH_ROOT_IMAGE}${NC}"
      umount ${SQUASH_ROOT_IMAGE_MOUNT}
      echo -e "${LTGREEN}  COMMAND:${GRAY} rmdir ${SQUASH_ROOT_IMAGE_MOUNT}${NC}"
      rmdir ${SQUASH_ROOT_IMAGE_MOUNT}
      echo
      echo -e "${LTCYAN}  -Unmounting Squashfs ...${NC}"
      echo -e "${LTGREEN}  COMMAND:${GRAY} umount ${SQUASH_IMAGE}${NC}"
      umount ${SQUASH_IMAGE}
      echo -e "${LTGREEN}  COMMAND:${GRAY} rmdir ${SQUASH_MOUNT}${NC}"
      rmdir ${SQUASH_MOUNT}
      echo
    else
      echo -e "${LTCYAN}  -Unmounting Squashfs ...${NC}"
      echo -e "${LTGREEN}  COMMAND:${GRAY} umount ${SQUASH_IMAGE}${NC}"
      umount ${SQUASH_IMAGE}
      echo -e "${LTGREEN}  COMMAND:${GRAY} rmdir ${SQUASH_MOUNT}${NC}"
      rmdir ${SQUASH_MOUNT}
      echo
    fi

  else
    echo
    echo "${LTRED}ERROR: No Squashfs image found. Exiting.${NC}"
    echo
    exit 1
  fi
  echo
}

#######################  Install GRUB Function  ####################################

install_grub() {
  echo -e "${LTBLUE}==============================================================${NC}"
  case ${BOOTLOADER} in
    BIOS|bios)
      echo -e "${LTBLUE}Installing GRUB ...${NC}"
    ;;
    UEFI|uefi)
      echo -e "${LTBLUE}Installing GRUB for UEFI ...${NC}"
    ;;
  esac
  echo -e "${LTBLUE}==============================================================${NC}"
  echo

  case ${BOOTLOADER} in
    BIOS|bios)
      case ${PARTITION_TABLE_TYPE} in
        msdos)
          local SWAP_PART_NUM=1
          local ROOT_PART_NUM=2
          local HOME_PART_NUM=3
        ;;
        gpt)
          local BIOSBOOT_PART_NUM=1
          local SWAP_PART_NUM=2
          local ROOT_PART_NUM=3
          local HOME_PART_NUM=4
        ;;
      esac
    ;;
    UEFI|uefi)
      local BOOTEFI_PART_NUM=1
      local SWAP_PART_NUM=2
      local ROOT_PART_NUM=3
      local HOME_PART_NUM=4
    ;;
  esac

  if echo ${DISK_DEV} | grep -q nvme
  then
    local BIOSBOOT_PART=${DISK_DEV}p${BIOSBOOT_PART_NUM}
    local BOOTEFI_PART=${DISK_DEV}p${BOOTEFI_PART_NUM}
    local ROOT_PART=${DISK_DEV}p${ROOT_PART_NUM}
    local SWAP_PART=${DISK_DEV}p${SWAP_PART_NUM}
    local HOME_PART=${DISK_DEV}p${HOME_PART_NUM}
  elif echo ${DISK_DEV} | grep -q "/dev/mapper"
  then
    local MAPPER_BIOSBOOT_PART=${DISK_DEV}-part${BIOSBOOT_PART_NUM}
    local MAPPER_BOOTEFI_PART=${DISK_DEV}-part${BOOTEFI_PART_NUM}
    local MAPPER_ROOT_PART=${DISK_DEV}-part${ROOT_PART_NUM}
    local MAPPER_SWAP_PART=${DISK_DEV}-part${SWAP_PART_NUM}
    local MAPPER_HOME_PART=${DISK_DEV}-part${HOME_PART_NUM}
    local BIOSBOOT_PART=$(ls -l /dev/mapper/ | grep "$(basename ${DISK_DEV}-part${BIOSBOOT_PART_NUM})" | cut -d \> -f 2 | sed 's+^ ..+/dev+')
    local BOOTEFI_PART=$(ls -l /dev/mapper/ | grep "$(basename ${DISK_DEV}-part${BOOTEFI_PART_NUM})" | cut -d \> -f 2 | sed 's+^ ..+/dev+')
    local ROOT_PART=$(ls -l /dev/mapper/ | grep "$(basename ${DISK_DEV}-part${ROOT_PART_NUM})" | cut -d \> -f 2 | sed 's+^ ..+/dev+')
    local SWAP_PART=$(ls -l /dev/mapper/ | grep "$(basename ${DISK_DEV}-part${SWAP_PART_NUM})" | cut -d \> -f 2 | sed 's+^ ..+/dev+')
    local HOME_PART=$(ls -l /dev/mapper/ | grep "$(basename ${DISK_DEV}-part${HOME_PART_NUM})" | cut -d \> -f 2 | sed 's+^ ..+/dev+')
  else
    local BIOSBOOT_PART=${DISK_DEV}${BIOSBOOT_PART_NUM}
    local BOOTEFI_PART=${DISK_DEV}${BOOTEFI_PART_NUM}
    local ROOT_PART=${DISK_DEV}${ROOT_PART_NUM}
    local SWAP_PART=${DISK_DEV}${SWAP_PART_NUM}
    local HOME_PART=${DISK_DEV}${HOME_PART_NUM}
  fi

  #echo
  #echo "BIOSBOOT_PART=${BIOSBOOT_PART}"
  #echo "BIOSBOOT_MOUNT=${BIOSBOOT_MOUNT}"
  #echo "BOOTEFI_PART=${BOOTEFI_PART}"
  #echo "BOOTEFI_MOUNT=${BOOTEFI_MOUNT}"
  #echo "ROOT_PART=${ROOT_PART}"
  #echo "ROOT_MOUNT=${ROOT_MOUNT}"
  #echo "SWAP_PART=${SWAP_PART}"
  #echo "SWAP_MOUNT=${SWAP_MOUNT}"
  #echo "HOME_PART=${HOME_PART}"
  #echo "HOME_MOUNT=${HOME_MOUNT}"
  #echo

  if ! mount | grep -q ${ROOT_PART}
  then
    if ! [ -d ${ROOT_MOUNT} ]
    then
      echo -e "${LTCYAN}  -Creating Root Mountpoint ...${NC}"
      echo -e "${LTGREEN}  COMMAND:${GRAY} mkdir -p ${ROOT_MOUNT}${NC}"
      mkdir -p ${ROOT_MOUNT}
    fi
    echo -e "${LTCYAN}  -Mounting Root Partition ...${NC}"
    echo -e "${LTGREEN}  COMMAND:${GRAY} mount ${ROOT_PART} ${ROOT_MOUNT}${NC}"
    mount ${ROOT_PART} ${ROOT_MOUNT}
  fi

  case ${BOOTLOADER} in
    UEFI|uefi)
      if ! mount | grep -q ${BOOTEFI_PART}
      then
        if ! [ -d ${ROOT_MOUNT}/boot/efi ]
        then
          echo -e "${LTCYAN}  -Creating /boot/efi Mountpoint ...${NC}"
          echo -e "${LTGREEN}  COMMAND:${GRAY} mkdir -p ${ROOT_MOUNT}/boot/efi${NC}"
          mkdir -p ${ROOT_MOUNT}/boot/efi
        fi
        echo -e "${LTCYAN}  -Mounting boot/efi Partition ...${NC}"
        echo -e "${LTGREEN}  COMMAND:${GRAY} mount ${ROOT_PART} ${ROOT_MOUNT}/boot/efi${NC}"
        mount ${BOOTEFI_PART} ${ROOT_MOUNT}/boot/efi
      fi
    ;;
  esac

  echo
  echo -e "${LTCYAN}  -Bind Mounting dev,sys,proc Filesystems ...${NC}"
  echo -e "${LTGREEN}  COMMAND:${GRAY} mount --bind ${ROOT_MOUNT}/dev${NC}"
  mount --bind /dev ${ROOT_MOUNT}/dev
  echo -e "${LTGREEN}  COMMAND:${GRAY} mount --bind ${ROOT_MOUNT}/proc${NC}"
  mount --bind /proc ${ROOT_MOUNT}/proc
  echo -e "${LTGREEN}  COMMAND:${GRAY} mount --bind ${ROOT_MOUNT}/sys${NC}"
  mount --bind /sys ${ROOT_MOUNT}/sys
  echo

  echo -e "${LTCYAN}  -Updating /etc/default/grub Config ...${NC}"
  local ORIG_GRUB_CMDLINE_LINUX_DEFAULT="$(grep ^GRUB_CMDLINE_LINUX_DEFAULT ${ROOT_MOUNT}/etc/default/grub | cut -d \" -f 2)"
  local NEW_GRUB_CMDLINE_LINUX_DEFAULT=$(echo ${ORIG_GRUB_CMDLINE_LINUX_DEFAULT} | sed "s+resume=/dev/[a-z0-9]*+resume=${SWAP_PART}+g")

  #echo "ORIG_GRUB_CMDLINE_LINUX_DEFAULT=\"${ORIG_GRUB_CMDLINE_LINUX_DEFAULT}\""
  #echo "NEW_GRUB_CMDLINE_LINUX_DEFAULT=\"${NEW_GRUB_CMDLINE_LINUX_DEFAULT}\""
  #echo

  echo -e "${LTGREEN}  COMMAND:${GRAY} cp ${ROOT_MOUNT}/etc/default/grub /tmp/grub.tmp${NC}"
  cp ${ROOT_MOUNT}/etc/default/grub /tmp/grub.tmp

  echo -e "${LTGREEN}  COMMAND:${GRAY} sed -i "s+^GRUB_CMDLINE_LINUX_DEFAULT=.*+GRUB_CMDLINE_LINUX_DEFAULT=\"${NEW_GRUB_CMDLINE_LINUX_DEFAULT}\"+" /tmp/grub.tmp${NC}"
  sed -i "s+^GRUB_CMDLINE_LINUX_DEFAULT=.*+GRUB_CMDLINE_LINUX_DEFAULT=\"${NEW_GRUB_CMDLINE_LINUX_DEFAULT}\"+" /tmp/grub.tmp

  echo -e "${LTGREEN}  COMMAND:${GRAY} cp /tmp/grub.tmp ${ROOT_MOUNT}/etc/default/grub${NC}"
  cp /tmp/grub.tmp ${ROOT_MOUNT}/etc/default/grub

  echo -e "${LTGREEN}  COMMAND:${GRAY} rm -f /tmp/grub.tmp${NC}"
  rm -f /tmp/grub.tmp

  case ${BOOTLOADER} in
    BIOS|bios)
      echo -e "${LTCYAN}  -Generating Grub Config ...${NC}"
      echo -e "${LTGREEN}  COMMAND:${GRAY} chroot ${ROOT_MOUNT} /usr/sbin/grub2-mkconfig -o /boot/grub2/grub.cfg${NC}"
      chroot ${ROOT_MOUNT} /usr/sbin/grub2-mkconfig -o /boot/grub2/grub.cfg
      echo

      echo -e "${LTCYAN}  -Installing Grub ...${NC}"
      echo -e "${LTGREEN}  COMMAND:${GRAY} chroot ${ROOT_MOUNT} /usr/sbin/grub2-install ${DISK_DEV}${NC}"
      chroot ${ROOT_MOUNT} /usr/sbin/grub2-install ${DISK_DEV} 2> /dev/null
      echo
    ;;
    UEFI|uefi)
      echo
      echo -e "${LTCYAN}  -Loading efivars Module ...${NC}"
      echo -e "${LTGREEN}  COMMAND:${GRAY} modprobe efivars${NC}"
      modprobe efivars
      echo

      echo -e "${LTCYAN}  -Installing Grub ...${NC}"
      echo -e "${LTGREEN}  COMMAND:${GRAY} chroot ${ROOT_MOUNT} /usr/sbin/grub2-install --target=x86_64-efi ${DISK_DEV}${NC}"
      chroot ${ROOT_MOUNT} /usr/sbin/grub2-install --target=x86_64-efi ${DISK_DEV} 2> /dev/null
      echo
  
      case ${SECURE_BOOT} in
        Y)
          echo -e "${LTCYAN}  -Installing Secure Boot ...${NC}"
          echo -e "${LTGREEN}  COMMAND:${GRAY} chroot ${ROOT_MOUNT} /usr/sbin/shim-install ${DISK_DEV}${NC}"
          chroot ${ROOT_MOUNT} /usr/sbin/shim-install ${DISK_DEV} 2> /dev/null
          echo
        ;;
      esac

      echo -e "${LTCYAN}  -Generating Grub Config ...${NC}"
      echo -e "${LTGREEN}  COMMAND:${GRAY} chroot ${ROOT_MOUNT} /usr/sbin/grub2-mkconfig -o /boot/grub2/grub.cfg${NC}"
      chroot ${ROOT_MOUNT} /usr/sbin/grub2-mkconfig -o /boot/grub2/grub.cfg
      echo

      echo -e "${LTCYAN}  -Unmounting boot/efi Partition ...${NC}"
      echo -e "${LTGREEN}  COMMAND:${GRAY} umount -R ${ROOT_MOUNT}/boot/efi${NC}"
      umount -R ${ROOT_MOUNT}/boot/efi
      sleep 2
    ;;
  esac

  echo -e "${LTCYAN}  -Unmounting Root Partition ...${NC}"
  echo -e "${LTGREEN}  COMMAND:${GRAY} umount -R ${ROOT_MOUNT}/proc${NC}"
  umount -R ${ROOT_MOUNT}/proc
  sleep 2
  echo -e "${LTGREEN}  COMMAND:${GRAY} umount -R ${ROOT_MOUNT}/dev${NC}"
  umount -R ${ROOT_MOUNT}/dev
  sleep 2
  echo -e "${LTGREEN}  COMMAND:${GRAY} umount -R ${ROOT_MOUNT}/sys${NC}"
  umount -R ${ROOT_MOUNT/sys}
  sleep 2
  echo -e "${LTGREEN}  COMMAND:${GRAY} umount -R ${ROOT_MOUNT}${NC}"
  umount -R ${ROOT_MOUNT}
  sleep 2
  echo -e "${LTGREEN}  COMMAND:${GRAY} rmdir ${ROOT_MOUNT}${NC}"
  rmdir ${ROOT_MOUNT}
  echo
}

#############################################################################
####################       main function      ###############################
#############################################################################

main() {
  #--  check to see if you are root
  check_user $*

  #--  check to see if the install block dev was supplied
  check_for_install_block_device $*

  #-- check to see if the live image was supplied or detected
  check_for_live_image $*

  #--  check to see if we need to create a home partition
  check_for_create_home_partition $*

  #--  check for UEFI booting
  check_for_uefi $*

  #--  check for enableing secure boot
  check_for_enable_secure_boot $*

  #--  check for disabling cloud-init
  check_for_disable_cloudinit $*

  #--  check for enabling cloud-init
  check_for_enable_cloudinit $*

  #--  check for forcing the rebuild of the initrd
  check_for_force_rebuild_initrd $*

  #--  get/set partition type
  case ${BOOTLOADER} in
    UEFI|uefi)
      PARTITION_TABLE_TYPE=gpt
    ;;
    BIOS|bios)
      get_partition_table_type $*
    ;;
  esac

  #--  display output of what we are going to do
  echo 
  echo -e "${LTRED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}"
  echo -e "${LTRED}!!!!             WARNING: ALL DATA ON DISK WILL BE LOST!             !!!!${NC}"
  echo -e "${LTRED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}"
  echo -e "${LTPURPLE}=========================================================================${NC}"
  if ! [ -z ${ORIG_DISK_DEV} ]
  then
	  echo -e "${LTPURPLE}Disk Device:      ${GRAY}${ORIG_DISK_DEV} ${LTPURPLE}(using MPIO Disk Device)${NC}"
    echo -e "${LTPURPLE}MPIO Disk Device: ${GRAY}${DISK_DEV}${NC}"
  else
    echo -e "${LTPURPLE}Disk Device:      ${GRAY}${DISK_DEV}${NC}"
  fi
  echo -e "${LTPURPLE}Live Image:       ${GRAY}${IMAGE}${NC}"

  echo -e "${LTPURPLE}Bootloader:       ${GRAY}${BOOTLOADER}${NC}"
  case ${BOOTLOADER} in
    UEFI)
      case ${SECURE_BOOT} in
        Y)
          echo -e "${LTPURPLE}Secure Boot:      ${GRAY}Yes${NC}"
        ;;
        N)
          echo -e "${LTPURPLE}Secure Boot:      ${GRAY}No${NC}"
        ;;
      esac
    ;;
  esac

  echo -e "${LTPURPLE}Partition Table:  ${GRAY}${PARTITION_TABLE_TYPE}${NC}"
  case ${CREATE_HOME_PART} in
    Y)
      echo -e "${LTPURPLE}Create /home:     ${GRAY}Yes${NC}"
    ;;
    N)
      echo -e "${LTPURPLE}Create /home:     ${GRAY}No${NC}"
    ;;
  esac
  echo -e "${LTPURPLE}--------------------------------------------${NC}"
  echo -e "${LTPURPLE}Partitions:${NC}"
  case ${BOOTLOADER} in
    UEFI|uefi)
      echo -e "${LTPURPLE}             /boot/efi: ${GRAY}${BOOTEFI_SIZE}${NC}"
    ;;
    BIOS|bios)
      case ${PARTITION_TABLE_TYPE} in
        gpt)
          echo -e "${LTPURPLE}             bios-boot: ${GRAY}${BIOSBOOT_SIZE}${NC}"
        ;;
      esac
    ;;
  esac
  echo -e "${LTPURPLE}             swap:      ${GRAY}${SWAP_SIZE}${NC}"
  case ${CREATE_HOME_PART} in
    Y)
      echo -e "${LTPURPLE}             /:         ${GRAY}${ROOT2_SIZE}${NC}"
      echo -e "${LTPURPLE}             /home:     ${GRAY}${HOME_SIZE}${NC}"
    ;;
    N)
      echo -e "${LTPURPLE}             /:         ${GRAY}${ROOT_SIZE}${NC}"
    ;;
  esac
  echo -e "${LTPURPLE}--------------------------------------------${NC}"

  echo -e "${LTPURPLE}Other Options:   ${GRAY}${OTHER_OPTIONS}${NC}"
  echo -e "${ORANGE}-------------------------------------------------------------${NC}"
  echo -e "${ORANGE}NOTE: Some of these configuration options can be overridden.${NC}"
  echo -e "${ORANGE}      Run this command without arguments for instructions.${NC}"
  echo -e "${ORANGE}-------------------------------------------------------------${NC}"
  echo -e "${LTPURPLE}=========================================================================${NC}"

  echo -n -e "${LTRED}Enter ${GRAY}Y${LTRED} to continue or ${GRAY}N${LTRED} to quit (${GRAY}y${LTRED}/${GRAY}N${LTRED}): ${NC}"
  read DOIT

#--  do the install
  case ${DOIT} in
    Y|y|Yes|YES)
      case ${BOOTLOADER} in
        BIOS)
          remove_partitions $*
    
          case ${CREATE_HOME_PART} in
            Y)
              create_two_partitions_with_swap_bios_boot
            ;;
            *)
              create_single_partition_with_swap_bios_boot
            ;;
          esac
        ;;
        UEFI)
          remove_partitions $*
    
          case ${CREATE_HOME_PART} in
            Y)
              create_two_partitions_with_swap_uefi_boot
            ;;
            *)
              create_single_partition_with_swap_uefi_boot
            ;;
          esac
        ;;
      esac

      copy_live_filesystem_to_disk

      install_grub
    ;;
    *)
      echo
      echo -e "${LTRED}No installation performed. Exiting.${NC}"
      echo
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

