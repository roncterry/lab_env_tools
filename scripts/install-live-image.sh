#!/bin/bash
# version: 3.4.0
# date: 2021-07-16

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

###########################################################################################################
# User customizable variables (via environment variables)
###########################################################################################################

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
  ROOT2_SIZE="30GiB"
fi

if [ -z ${HOME_SIZE} ]
then
  HOME_SIZE="100%"
fi

if [ -z ${ROOT_FS_TYPE} ]
then
  export ROOT_FS_TYPE="ext4"
#else
#  export ROOT_FS_TYPE
fi

if [ -z ${HOME_FS_TYPE} ]
then
  export HOME_FS_TYPE="ext4"
else
  export HOME_FS_TYPE
fi

###########################################################################################################
# Non user customizable variables
###########################################################################################################

if [ -z ${SQUASH_MOUNT} ]
then
  SQUASH_MOUNT="/tmp/squash_mount"
fi

if [ -z ${ROOTFS_IMAGE_MOUNT} ]
then
  ROOTFS_IMAGE_MOUNT="/tmp/rootfs_image_mount"
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
  echo "USAGE: $(basename ${0}) <block_device> [<image_file>] [root_fs=<fs_type>] [with_home [home_fs=<fs_type>]] [force_msdos|force_gpt] [force_uefi|force_bios] [no_secureboot] [enable_cloudinit|disable_cloudinit] [force_rebuild_initrd]"
  echo
  echo "  <image_file> is the path to the Live ISO image you wish to install from."
  echo
  echo "  If <image_file> is not provided and you are booted into a Live image, the"
  echo "  script will attempt to either find a Live ISO image in known locations or"
  echo "  attempt to locate the squashfs.img image or rootfs.img you are booted into"
  echo "  and use that as the source image."
  echo
  echo "  Options:"
  echo "        root_fs=<fs_type>         Specify the filesystem to use on the root volume"
  echo "                                    Supported filesystem types: ext4 xfs"
  echo "                                    (default: ext4)"
  echo "        root_size=<size>          Specify the size of the root volume"
  echo "                                    For Megabytes use the MiB extension (example: 500MiB)"
  echo "                                    For Gigabytes use the GiB extension (example: 500GiB)"
  echo "                                    For Teraabytes use the TiB extension (example: 1TiB)"
  echo "                                    To use all remaining space use: 100%"
  echo "                                    (Note: Other percentages can be used as well to specify size)"
  echo "        with_home                 Create a separate partition for /home"
  echo "        home_fs=<fs_type>         Specify the filesystem to use on the home volume"
  echo "                                    Supported filesystem types: ext4 xfs"
  echo "                                    (default: ext4)"
  echo "        home_size=<size>          Specify the size of the home volume"
  echo "                                    For Megabytes use the MiB extension (example: 500MiB)"
  echo "                                    For Gigabytes use the GiB extension (example: 500GiB)"
  echo "                                    For Teraabytes use the TiB extension (example: 1TiB)"
  echo "                                    To use all remaining space use: 100%"
  echo "                                    (Note: Other percentages can be used as well to specify size)"
  echo "        force_msdos               Force creating a msdos parition table type"
  echo "        force_gpt                 Force creating a gtp parition table type"
  echo "        force_uefi                Force installing for the UEFI bootloader"
  echo "        force_bios                Force installing for the BIOS bootloader"
  echo "        no_secureboot             Disable secure boot with the UEFI bootloader"
  echo "        disable_cloudinit         Disable cloud-init in the installed OS if enabled"
  echo "        enable_cloudinit          Enable cloud-init in the installed OS if disabled"
  echo "        force_rebuild_initrd      Force rebuilding of the initramfs after install"
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
  echo "  =============================================================================="
  echo "  Available Disks to Install To:"
  echo
  for BLOCK_DEV in ${BLOCK_DEV_LIST}
  do
    echo "   ${BLOCK_DEV}"
  done
  echo
  echo "  ------------------------------------------------------------------------------"
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
        ##################################
        # Check for multipath device
        ##################################
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
  ################################################
  # Try to set ${ISO_IMAGE} and ${ISO_MOUNT}
  ################################################
    case ${2} in
      with_home|force_uefi|force_bios|no_secureboot|force_msdos|force_gpt|disable_cloudinit|enable_cloudinit|force_rebuild_initrd)
        ######################################################################
        # If another arg is supplied as $2 then check if $3 is the ISO image
        ######################################################################
        if [ -z ${3} ]
        then
          ############################################################
          # First check if there is a dir /isofrom
          ############################################################
          if [ -d /isofrom ]
          then
            ISO_IMAGE="$(ls /isofrom/*.iso | head -n 1)"
          ###############################################################################################
          # If not then check if there is a directory /run/initramfs/isoscan/ that contains and ISO image
          ###############################################################################################
          elif [ -d /run/initramfs/isoscan ]
          then
            ISO_IMAGE="$(ls /run/initramfs/isoscan/*.iso | head -n 1)"
          fi
          #echo -e "${LTRED}ISO_IMAGE=${ISO_IMAGE}${NC}"
        else
 
          ######################################################################
          # If another arg is supplied as $3 then check if $4 is the ISO image
          #
          # Then same as before: look for /isofrm then /run/initramfs/isoscan/
          ######################################################################
          case ${3} in
            with_home|force_uefi|force_bios|no_secureboot|force_msdos|force_gpt|disable_cloudinit|enable_cloudinit|force_rebuild_initrd)
              if [ -z ${4} ]
              then
                if [ -d /isofrom ]
                then
                  ISO_IMAGE="$(ls /isofrom/*.iso | head -n 1)"
                elif [ -d /run/initramfs/isoscan ]
                then
                  ISO_IMAGE="$(ls /run/initramfs/isoscan/*.iso | head -n 1)"
                fi
              else
                ###################################################################
                # If ISO ($4) not found in those 2 places use $4 as the ISO image
                ###################################################################
                if [ -e ${4} ]
                then
                  ISO_IMAGE="${4}"
                  ISO_MOUNT="/tmp/iso_mount"
                else
                  echo
                  echo -e "${LTRED}ERROR: The image file provided doesn't seem to exist. Exiting.${NC}"
                  echo
                  exit 1
                fi
              fi
            ;;
            *)
              ###################################################################
              # If ISO ($3) not found in those 2 places use $3 as the ISO image
              ###################################################################
              if [ -e ${3} ]
              then
                ISO_IMAGE="${3}"
                ISO_MOUNT="/tmp/iso_mount"
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
        ##################################################################
        # Check for ISO image in /isofrom and /run/initramfs/isoscan/
        ##################################################################
        if [ -z ${2} ]
        then
          if [ -d /isofrom ]
          then
            ISO_IMAGE="$(ls /isofrom/*.iso | head -n 1)"
          elif [ -d /run/initramfs/isoscan ]
          then
            ISO_IMAGE="$(ls /run/initramfs/isoscan/*.iso | head -n 1)"
          fi
        else
          ###################################################################
          # If ISO ($2) not found in those 2 places use $2 as the ISO image
          ###################################################################
          if [ -e ${2} ]
          then
            ISO_IMAGE="${2}"
            ISO_MOUNT="/tmp/iso_mount"
          else
            echo
            echo -e "${LTRED}ERROR: The image file provided doesn't seem to exist. Exiting.${NC}"
            echo
            exit 1
          fi
        fi
        #echo -e "${LTRED}ISO_IMAGE=${ISO_IMAGE}${NC}"
      ;;
    esac

  ###################################################################################
  # If ${ISO_MOUNT} isn't set and if /livecd exists ISO_MOUNT=/livecd
  #  If not ...
  # If /run/initramfs/live/LiveOS exists the ISO_MOUNT=/run/initramfs/live/LiveOS
  ###################################################################################
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

  ##########################################################################
  # If none of this works then ${ISO_IMAGE} and ${ISO_MOUNT} are left empty
  ##########################################################################
}

check_for_squash_image() {
  ###########################################################################
  # Trying to se ${SQUASH_IMAGE}
  # If ISO_MOUNT is set, look in ${ISO_MOUNT}/LiveOS/ for a squashfs image
  ###########################################################################
    if ! [ -z ${ISO_IMAGE} ]
    then
      if [ -d ${ISO_MOUNT}/LiveOS ]
      then
        for FILE_ON_ISO in $(ls ${ISO_MOUNT}/LiveOS)
        do
          if file ${ISO_MOUNT}/LiveOS/${FILE_ON_ISO} | grep -q "Squashfs filesystem"
          then
            SQUASH_IMAGE=${ISO_MOUNT}/LiveOS/${FILE_ON_ISO}
          fi
        done
      fi
    else
    #######################################################
    # See if we can find an ISOimage in $ISO_MOUNT/LiveOS/
    #######################################################
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
    fi

  ##########################################################################
  # If none of this works then ${SQUASH_IMAGE} is left empty
  ##########################################################################
}

check_for_rootfs_image() {
  ##########################################################################################
  # Check to see if a rootfs.img is already mounted and of so use it for the install source
  ##########################################################################################
    if mount | grep -q rootfs.img
    then
      export ROOTFS_IMAGE_MOUNTED=Y
      export ROOTFS_IMAGE="$(mount | grep rootfs.img | awk '{ print $1 }')"
      export ROOTFS_IMAGE_MOUNT="$(mount | grep rootfs.img | awk '{ print $3 }')"
    fi
    if mount | grep -q squashfs.img
    then
      export SQUASHFS_IMAGE_MOUNTED=Y
      export SQUASH_IMAGE="$(mount | grep squashfs.img | awk '{ print $1 }')"
      export SQUASH_MOUNT="$(mount | grep squashfs.img | awk '{ print $3 }')"
    fi
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

check_for_root_size() {
  if echo $* | grep -q "root_size="
  then
    ROOT_SIZE=$(echo $* | grep -o "root_size=.*" | awk '{ print $1 }' | cut -d \= -f 2)
  else
    if [ -z ${ROOT_SIZE} ]
    then
      ROOT_SIZE="100%"
    fi
  fi
}

check_for_root_fs_type() {
  if echo $* | grep -q "root_fs="
  then
    ROOT_FS_TYPE=$(echo $* | grep -o "root_fs=.*" | awk '{ print $1 }' | cut -d \= -f 2 | tr '[:upper:]' '[:lower:]')
  else
    if [ -z ${ROOT_FS_TYPE} ]
    then
      ROOT_FS_TYPE=ext4
    fi
  fi

  case ${ROOT_FS_TYPE} in
    ext4)
      ROOT_MKFS_OPTS="-F"
      ROOT_FSTAB_OPTS="acl,user_xattr"
    ;;
    xfs)
      ROOT_MKFS_OPTS="-f"
      ROOT_FSTAB_OPTS="defaults"
    ;;
    btrfs)
      ROOT_MKFS_OPTS="-f"
      ROOT_FSTAB_OPTS="defaults"
      BTRFS_DEFAULT_SUBVOLUMES="/var /usr/local /tmp /srv /root /opt /home /boot/grub2/x8_4-efi /boot/grub2/i386-pc /.snapshots"
    ;;
    *)
      echo
      echo -e "${LTRED}ERROR: \"${ROOT_FS_TYPE}\" is not a supported filesystem type for the root filesystem. Exiting."${NC}
      echo
      exit
    ;;
  esac
}

check_for_create_home_partition() {
  if echo $* | grep -q "with_home"
  then
    CREATE_HOME_PART=Y

    if echo $* | grep -q "root_size="
    then
      ROOT2_SIZE=$(echo $* | grep -o "root_size=.*" | awk '{ print $1 }' | cut -d \= -f 2)
    else
      if [ -z ${ROOT2_SIZE} ]
      then
        ROOT2_SIZE="20GiB"
      fi
    fi
 
    if echo $* | grep -q "home_size="
    then
      HOME_SIZE=$(echo $* | grep -o "home_size=.*" | awk '{ print $1 }' | cut -d \= -f 2)
    else
      if [ -z ${HOME_SIZE} ]
      then
        HOME_SIZE="100%"
      fi
    fi
 
    if echo $* | grep -q "home_fs="
    then
      HOME_FS_TYPE=$(echo $* | grep -o "home_fs=.*" | awk '{ print $1 }' | cut -d \= -f 2 | tr '[:upper:]' '[:lower:]')
    else
      if [ -z ${HOME_FS_TYPE} ]
      then
        HOME_FS_TYPE=ext4
      fi
    fi
 
    case ${HOME_FS_TYPE} in
      ext4)
        HOME_MKFS_OPTS="-F"
        HOME_FSTAB_OPTS="acl,user_xattr"
      ;;
      xfs)
        HOME_MKFS_OPTS="-f"
        HOME_FSTAB_OPTS="defaults"
      ;;
      #btrfs)
      #  HOME_MKFS_OPTS="-f"
      #  HOME_FSTAB_OPTS="defaults"
      #;;
      *)
        echo
        echo -e "${LTRED}ERROR: \"${ROOT_FS_TYPE}\" is not a supported filesystem type for the home filesystem. Exiting."${NC}
        echo
        exit
      ;;
    esac
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

create_root_fs() {
  echo -e "${LTBLUE}==============================================================${NC}"
  echo -e "${LTBLUE}Creating filesystem on root partition${NC}"
  echo -e "${LTBLUE}==============================================================${NC}"
  echo
  case ${ROOT_FS_TYPE} in
    ext4|xfs)
      if echo ${DISK_DEV} | grep -q nvme
      then
        echo -e "${LTGREEN}COMMAND:${GRAY} mkfs.${ROOT_FS_TYPE} ${ROOT_MKFS_OPTS} -L ROOT ${DISK_DEV}p${ROOT_PART_NUM}${NC}"
        mkfs.${ROOT_FS_TYPE} ${ROOT_MKFS_OPTS} -L ROOT ${DISK_DEV}p${ROOT_PART_NUM}
        ROOT_PART=${DISK_DEV}p${ROOT_PART_NUM}
      elif echo ${DISK_DEV} | grep -q "/dev/mapper"
      then
        echo -e "${LTGREEN}COMMAND:${GRAY} mkfs.${ROOT_FS_TYPE} ${ROOT_MKFS_OPTS} -L ROOT ${DISK_DEV}-part${ROOT_PART_NUM}${NC}"
        mkfs.${ROOT_FS_TYPE} ${ROOT_MKFS_OPTS} -L ROOT ${DISK_DEV}-part${ROOT_PART_NUM}
        ROOT_PART=${DISK_DEV}-part${ROOT_PART_NUM}
      else
        echo -e "${LTGREEN}COMMAND:${GRAY} mkfs.${ROOT_FS_TYPE} ${ROOT_MKFS_OPTS} -L ROOT ${DISK_DEV}${ROOT_PART_NUM}${NC}"
        mkfs.${ROOT_FS_TYPE} ${ROOT_MKFS_OPTS} -L ROOT ${DISK_DEV}${ROOT_PART_NUM}
        ROOT_PART=${DISK_DEV}${ROOT_PART_NUM}
      fi
    ;;
    btrfs)
      if echo ${DISK_DEV} | grep -q nvme
      then
        echo -e "${LTGREEN}COMMAND:${GRAY} mkfs.${ROOT_FS_TYPE} ${ROOT_MKFS_OPTS} -L ROOT ${DISK_DEV}p${ROOT_PART_NUM}${NC}"
        mkfs.${ROOT_FS_TYPE} ${ROOT_MKFS_OPTS} -L ROOT ${DISK_DEV}p${ROOT_PART_NUM}
        ROOT_PART=${DISK_DEV}p${ROOT_PART_NUM}
      elif echo ${DISK_DEV} | grep -q "/dev/mapper"
      then
        echo -e "${LTGREEN}COMMAND:${GRAY} mkfs.${ROOT_FS_TYPE} ${ROOT_MKFS_OPTS} -L ROOT ${DISK_DEV}-part${ROOT_PART_NUM}${NC}"
        mkfs.${ROOT_FS_TYPE} ${ROOT_MKFS_OPTS} -L ROOT ${DISK_DEV}-part${ROOT_PART_NUM}
        ROOT_PART=${DISK_DEV}-part${ROOT_PART_NUM}
      else
        echo -e "${LTGREEN}COMMAND:${GRAY} mkfs.${ROOT_FS_TYPE} ${ROOT_MKFS_OPTS} -L ROOT ${DISK_DEV}${ROOT_PART_NUM}${NC}"
        mkfs.${ROOT_FS_TYPE} ${ROOT_MKFS_OPTS} -L ROOT ${DISK_DEV}${ROOT_PART_NUM}
        ROOT_PART=${DISK_DEV}${ROOT_PART_NUM}
      fi

      local BTRFS_ROOT_TMP="/tmp/btrfs_root_tmp"
      echo -e "${LTGREEN}COMMAND:${GRAY} mkdir -p ${BTRFS_ROOT_TMP}${NC}"
      mkdir -p ${BTRFS_ROOT_TMP}
      echo -e "${LTGREEN}COMMAND:${GRAY} mount ${ROOT_PART} ${BTRFS_ROOT_TMP}${NC}"
      mount ${ROOT_PART} ${BTRFS_ROOT_TMP}
      for SUBVOL in ${BTRFS_DEFAULT_SUBVOLUMES}
      do
        echo -e "${LTGREEN}COMMAND:${GRAY} btrfs subvolume create ${BTRFS_ROOT_TMP}${SUBVOL}${NC}"
        btrfs subvolume create ${BTRFS_ROOT_TMP}${SUBVOL}
      done
      echo -e "${LTGREEN}COMMAND:${GRAY} umount ${ROOT_PART} ${BTRFS_ROOT_TMP}${NC}"
      umount ${ROOT_PART} ${BTRFS_ROOT_TMP}
      echo -e "${LTGREEN}COMMAND:${GRAY} rm -rf  -p ${BTRFS_ROOT_TMP}${NC}"
      rm -rf  -p ${BTRFS_ROOT_TMP}
    ;;
  esac
}

create_home_fs() {
  echo -e "${LTBLUE}==============================================================${NC}"
  echo -e "${LTBLUE}Creating filesystem on home partition${NC}"
  echo -e "${LTBLUE}==============================================================${NC}"
  echo
  case ${HOME_FS_TYPE} in
    ext4|xfs)
      if echo ${DISK_DEV} | grep -q nvme
      then
        echo -e "${LTGREEN}COMMAND:${GRAY} mkfs.${HOME_FS_TYPE} ${HOME_MKFS_OPTS} -L HOME ${DISK_DEV}p${HOME_PART_NUM}${NC}"
        mkfs.${HOME_FS_TYPE} ${HOME_MKFS_OPTS} -L HOME ${DISK_DEV}p${HOME_PART_NUM}
        HOME_PART=${DISK_DEV}p${HOME_PART_NUM}
      elif echo ${DISK_DEV} | grep -q "/dev/mapper"
      then
        echo -e "${LTGREEN}COMMAND:${GRAY} mkfs.${HOME_FS_TYPE} ${HOME_MKFS_OPTS} -L HOME ${DISK_DEV}-part${HOME_PART_NUM}${NC}"
        mkfs.${HOME_FS_TYPE} ${HOME_MKFS_OPTS} -L HOME ${DISK_DEV}-part${HOME_PART_NUM}
        HOME_PART=${DISK_DEV}-part${HOME_PART_NUM}
      else
        echo -e "${LTGREEN}COMMAND:${GRAY} mkfs.${HOME_FS_TYPE} ${HOME_MKFS_OPTS} -L HOME ${DISK_DEV}${HOME_PART_NUM}${NC}"
        mkfs.${HOME_FS_TYPE} ${HOME_MKFS_OPTS} -L HOME ${DISK_DEV}${HOME_PART_NUM}
        HOME_PART=${DISK_DEV}${HOME_PART_NUM}
      fi
    ;;
  esac
}

create_swap_fs() {
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
}

create_boot_efi_fs() {
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
}

###########################################################################################################
#####################                   BIOS Boot Functions              ##################################
###########################################################################################################

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

  create_swap_fs
  echo
  create_root_fs
  echo
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

  create_swap_fs
  echo
  create_root_fs
  echo
  create_home_fs
  echo
}

##########################################################################################################
#######################              UEFI Boot Functions              ####################################
##########################################################################################################

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

  create_boot_efi_fs
  echo
  create_swap_fs
  echo
  create_root_fs
  echo
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

  create_boot_efi_fs
  echo
  create_swap_fs
  echo
  create_root_fs
  echo
  create_home_fs
  echo
}

####################################################################################################
#######################  Copy Live Filesystem to Disk Function  ####################################
####################################################################################################

copy_live_filesystem_to_disk() {
  ###############################################################
  # Display different output depending on BIOS v UEFI bootloader
  ###############################################################
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

  #################################################################################
  # If the rootfs.img is mounted then use it, if not try to use the squashfs.img
  #################################################################################
    case ${ROOTFS_IMAGE_MOUNTED} in
      Y|y)
        echo -e "${ORANGE}[ squashfs.img and rootfs.img already mounted ]${NC}"
        echo
      ;;
      *)
        echo -e "${ORANGE}[ Mounting Source Images ]${NC}"
 
        #######################################
        # If ${ISO_IMAGE} is set then mount it
        #######################################
        if ! [ -z ${ISO_IMAGE} ]
        then
          HAD_TO_MOUNT_ISO_IMAGE=Y

          echo -e "${LTPURPLE}  ISO_IMAGE=${GRAY}${ISO_IMAGE}${NC}"
          echo -e "${LTCYAN}  -Mounting ISO Image ...${NC}"
          echo -e "${LTGREEN}  COMMAND:${GRAY} mkdir ${ISO_MOUNT}${NC}"
          mkdir ${ISO_MOUNT}
          echo -e "${LTGREEN}  COMMAND:${GRAY} mount ${ISO_IMAGE} ${ISO_MOUNT}${NC}"
          mount -o loop ${ISO_IMAGE} ${ISO_MOUNT}
          echo
        fi
    
        ########################################
        # Check for and mount the squashfs.img
        ########################################
        check_for_squash_image
    
        echo -e "${LTPURPLE}  SQUASH_IMAGE=${GRAY}${SQUASH_IMAGE}${NC}"
    
        if ! [ -z ${SQUASH_IMAGE} ]
        then
          HAD_TO_MOUNT_SQUASH_IMAGE=Y

          echo -e "${LTCYAN}  -Mounting Squashfs ...${NC}"
          echo -e "${LTGREEN}  COMMAND:${GRAY} mkdir ${SQUASH_MOUNT}${NC}"
          mkdir ${SQUASH_MOUNT}
          echo -e "${LTGREEN}  COMMAND:${GRAY} mount ${SQUASH_IMAGE} ${SQUASH_MOUNT}${NC}"
          mount ${SQUASH_IMAGE} ${SQUASH_MOUNT}
          echo
 
          #################################
          # Check for and mount rootfs.img
          #################################
          if [ -e ${SQUASH_MOUNT}/LiveOS/rootfs.img ]
          then
            HAD_TO_MOUNT_ROOTFS_IMAGE=Y

            ROOTFS_IMAGE=${SQUASH_MOUNT}/LiveOS/rootfs.img
            echo -e "${LTPURPLE}  ROOTFS_IMAGE=${GRAY}${ROOTFS_IMAGE}${NC}"
    
            #for FILE_IN_SQUASH_IMAGE in $(ls ${SQUASH_MOUNT}/LiveOS)
            #do
            #  echo FILE_IN_SQUASH_IMAGE=${FILE_IN_SQUASH_IMAGE};read
            #  if file ${SQUASH_MOUNT}/LiveOS/${FILE_IN_SQUASH_IMAGE} | grep -q "Squashfs filesystem"
            #  then
            #    ROOTFS_IMAGE=${SQUASH_MOUNT}/LiveOS/${FILE_IN_SQUASH_IMAGE}
            #    echo ROOTFS_IMAGE=${ROOTFS_IMAGE};read
            #  fi
            #done
    
            echo -e "${LTCYAN}  -Mounting Root Image in Squashfs ...${NC}"
            echo -e "${LTGREEN}  COMMAND:${GRAY} mkdir ${ROOTFS_IMAGE_MOUNT}${NC}"
            mkdir ${ROOTFS_IMAGE_MOUNT}
            echo -e "${LTGREEN}  COMMAND:${GRAY} mount ${ROOTFS_IMAGE} ${ROOTFS_IMAGE_MOUNT}${NC}"
            mount ${ROOTFS_IMAGE} ${ROOTFS_IMAGE_MOUNT}
            echo
          fi
        else
          echo
          echo "${LTRED}ERROR: No Squashfs image found. Exiting.${NC}"
          echo
          exit 1
        fi
      ;;
    esac

  ##################################################
  # Mount the destination partitions to install into
  ##################################################

    ##########################
    # Mount the root parition
    ##########################
    echo -e "${ORANGE}[ Mounting Destination Partition(s) ]${NC}"
    echo -e "${LTCYAN}  -Mounting Root Partition ...${NC}"
    echo -e "${LTGREEN}  COMMAND:${GRAY} mkdir ${ROOT_MOUNT}${NC}"
    mkdir ${ROOT_MOUNT}
    echo -e "${LTGREEN}  COMMAND:${GRAY} mount ${ROOT_PART} ${ROOT_MOUNT}${NC}"
    mount ${ROOT_PART} ${ROOT_MOUNT}
    echo
 
    ##########################
    # Mount the EFI parition
    ##########################
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
 
    ##########################
    # Mount the home parition
    ##########################
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

  ##########################
  # Install the OS image
  ##########################
    echo -e "${ORANGE}[ Installing OS Image ]${NC}"
    echo -e "${LTCYAN}  -Copying filesystem to root partition (this may take a while) ...${NC}"
    #echo -e "${LTGREEN}  COMMAND:${GRAY} rsync -ah --progress ${SQUASH_MOUNT}/* ${ROOT_MOUNT}/${NC}"
    #rsync -ah --progress ${SQUASH_MOUNT}/* ${ROOT_MOUNT}/

  ############################################################################
  # If there is no rootfs.img then install directly from the squashfs.img
  #  or
  # If there is a rootfs.img then install from it
  ############################################################################
    if [ -z ${ROOTFS_IMAGE} ]
    then
      echo -e "${LTGREEN}  COMMAND:${GRAY} cp -a ${SQUASH_MOUNT}/* ${ROOT_MOUNT}/${NC}"
      cp -a ${SQUASH_MOUNT}/* ${ROOT_MOUNT}/

     # DIRS_TO_COPY="$(ls ${SQUASH_MOUNT})"
     # case ${PRESERVE_HOME_DIR} in
     #   Y)
     #     for COPY_DIR in ${DIRS_TO_COPY}
     #     do
     #       if ! echo ${COPY_DIR} grep "home" 
     #       then
     #         echo -e "${LTGREEN}  COMMAND:${GRAY} cp -a ${SQUASH_MOUNT}/${COPY_DIR} ${ROOT_MOUNT}/${NC}"
     #         cp -a ${SQUASH_MOUNT}/${COPY_DIR} ${ROOT_MOUNT}/
     #       fi
     #     done
     #   ;;
     #   *)
     #     echo -e "${LTGREEN}  COMMAND:${GRAY} cp -a ${SQUASH_MOUNT}/${COPY_DIR} ${ROOT_MOUNT}/${NC}"
     #     cp -a ${SQUASH_MOUNT}/${COPY_DIR} ${ROOT_MOUNT}/
     #   ;;
     # esac
    else
      echo -e "${LTGREEN}  COMMAND:${GRAY} cp -a ${ROOTFS_IMAGE_MOUNT}/* ${ROOT_MOUNT}/${NC}"
      cp -a ${ROOTFS_IMAGE_MOUNT}/* ${ROOT_MOUNT}/

     # DIRS_TO_COPY="$(ls ${ROOTFS_IMAGE_MOUNT})"
     # case ${PRESERVE_HOME_DIR} in
     #   Y)
     #     for COPY_DIR in ${DIRS_TO_COPY}
     #     do
     #       if ! echo ${COPY_DIR} grep "home" 
     #       then
     #         echo -e "${LTGREEN}  COMMAND:${GRAY} cp -a ${ROOTFS_IMAGE_MOUNT}/${COPY_DIR} ${ROOT_MOUNT}/${NC}"
     #         cp -a ${ROOTFS_IMAGE_MOUNT}/${COPY_DIR} ${ROOT_MOUNT}/
     #       fi
     #     done
     #   ;;
     #   *)
     #     echo -e "${LTGREEN}  COMMAND:${GRAY} cp -a ${ROOTFS_IMAGE_MOUNT}/${COPY_DIR} ${ROOT_MOUNT}/${NC}"
     #     cp -a ${ROOTFS_IMAGE_MOUNT}/${COPY_DIR} ${ROOT_MOUNT}/
     #   ;;
     # esac
    fi
    echo

  #######################################################################################
  # Update the /etc/fstab in the newly installed OS image
  #######################################################################################
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
    case ${ROOT_FS_TYPE}
    in
      ext4|xfs)
        echo -e "${LTPURPLE}   ROOT: ${GRAY}UUID=${ROOT_UUID}  /  ${ROOT_FS_TYPE}  ${ROOT_FSTAB_OPTS}  1 1${NC}"
        echo "UUID=${ROOT_UUID}  /  ${ROOT_FS_TYPE}  ${ROOT_FSTAB_OPTS}  1 1" >> ${ROOT_MOUNT}/etc/fstab
      ;;
      btrfs)
        echo -e "${LTPURPLE}   ROOT: ${GRAY}UUID=${ROOT_UUID}  /  btrfs  ${ROOT_FSTAB_OPTS}  0 0${NC}"
        echo "UUID=${ROOT_UUID}  /  btrfs  ${ROOT_FSTAB_OPTS}  0 0" >> ${ROOT_MOUNT}/etc/fstab
        for SUBVOL in ${BTRFS_DEFAULT_SUBVOLUMES}
        do
          echo -e "${LTPURPLE}   ${SUBVOL}: ${GRAY}UUID=${ROOT_UUID}  ${SUBVOL}  btrfs  subvol=/@${SUBVOL}  0 0${NC}"
          echo "UUID=${ROOT_UUID}  ${SUBVOL}  btrfs  subvol=/@${SUBVOL}  0 0" >> ${ROOT_MOUNT}/etc/fstab
        done
      ;;
    esac

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
        echo "UUID=${HOME_UUID}  /home  ${HOME_FS_TYPE}  ${HOME_FSTAB_OPTS}  0 0" >> ${ROOT_MOUNT}/etc/fstab
        echo -e "${LTPURPLE}   HOME: ${GRAY}UUID=${HOME_UUID}  /home  ${HOME_FS_TYPE}  ${HOME_FSTAB_OPTS}  0 0${NC}"
 
        if echo ${DISK_DEV} | grep -q "/dev/mapper"
        then
          local HOME_PART=${ORIGINAL_HOME_PART}
        fi
      ;;
    esac
    echo

  ###############################################################################
  # Bind mount the dev/proc/sys filesystems in order to rebuild the initramfs
  ###############################################################################
    echo -e "${LTCYAN}  -Bind Mounting dev,proc,sys Filesystems ...${NC}"
    echo -e "${LTGREEN}  COMMAND:${GRAY} mount --bind ${ROOT_MOUNT}/dev${NC}"
    mount --bind /dev ${ROOT_MOUNT}/dev
    echo -e "${LTGREEN}  COMMAND:${GRAY} mount --bind ${ROOT_MOUNT}/proc${NC}"
    mount --bind /proc ${ROOT_MOUNT}/proc
    echo -e "${LTGREEN}  COMMAND:${GRAY} mount --bind ${ROOT_MOUNT}/sys${NC}"
    mount --bind /sys ${ROOT_MOUNT}/sys
    echo

  ##############################################################################
  # Generate a new initramfs for the newly installed OS image
  ##############################################################################
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

  #############################################################
  # Disable cloud-init if required
  #############################################################
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

  #############################################################
  # Enable cloud-init if required
  #############################################################
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

  ####################################################################
  # Unmount the desitnation partitions that we just installed into
  ####################################################################

  ##################################
  # Unmount /dev, /proc, /sys
  ##################################
    echo -e "${ORANGE}[ Unmounting Destination Partition(s) ]${NC}"
    echo -e "${LTCYAN}  -Unmounting dev,proc,sys Filesystems ...${NC}"
    echo -e "${LTGREEN}  COMMAND:${GRAY} umount -R ${ROOT_MOUNT}/proc${NC}"
    umount -R ${ROOT_MOUNT}/proc
    echo -e "${LTGREEN}  COMMAND:${GRAY} umount -R ${ROOT_MOUNT}/dev${NC}"
    umount -R ${ROOT_MOUNT}/dev
    echo -e "${LTGREEN}  COMMAND:${GRAY} umount -R ${ROOT_MOUNT}/sys${NC}"
    umount -R ${ROOT_MOUNT/sys}
    echo

  ##################################
  # Unmount /home
  ##################################
    case ${CREATE_HOME_PART} in
      Y)
        echo -e "${LTCYAN}  -Unmounting Home Partition ...${NC}"
        echo -e "${LTGREEN}  COMMAND:${GRAY} umount ${HOME_PART}${NC}"
        umount ${HOME_PART}
        echo
      ;;
    esac

  ##################################
  # Unmount /
  ##################################
    echo -e "${LTCYAN}  -Unmounting Root Partition ...${NC}"
    echo -e "${LTGREEN}  COMMAND:${GRAY} umount -R ${ROOT_MOUNT}${NC}"
    umount -R ${ROOT_MOUNT}
    sleep 2
    echo -e "${LTGREEN}  COMMAND:${GRAY} rmdir ${ROOT_MOUNT}${NC}"
    rmdir ${ROOT_MOUNT}
    echo

  ###################################################################
  # Unmount the rootfs.ing, squashfs.img and ISO image if required
  ###################################################################
    
    ##########################################
    # Unmount rootfs.img
    ##########################################
    case ${HAD_TO_MOUNT_ROOTFS_IMAGE} in
      Y)
        echo -e "${LTCYAN}  -Unmounting RootFS Image in Squashfs ...${NC}"
        echo -e "${LTGREEN}  COMMAND:${GRAY} umount ${ROOTFS_IMAGE}${NC}"
        umount ${ROOTFS_IMAGE_MOUNT}
        echo -e "${LTGREEN}  COMMAND:${GRAY} rmdir ${ROOTFS_IMAGE_MOUNT}${NC}"
        rmdir ${ROOTFS_IMAGE_MOUNT}
        echo
      ;;
    esac
 
    ##########################################
    # Unmount squashfs.img
    ##########################################
    case ${HAD_TO_MOUNT_SQUASH_IMAGE} in
      Y)
        echo -e "${LTCYAN}  -Unmounting Squashfs ...${NC}"
        echo -e "${LTGREEN}  COMMAND:${GRAY} umount ${SQUASH_IMAGE}${NC}"
        umount ${SQUASH_IMAGE}
        echo -e "${LTGREEN}  COMMAND:${GRAY} rmdir ${SQUASH_MOUNT}${NC}"
        rmdir ${SQUASH_MOUNT}
        echo
        echo -e "${LTCYAN}  -Unmounting Squashfs ...${NC}"
        echo -e "${LTGREEN}  COMMAND:${GRAY} umount ${SQUASH_IMAGE}${NC}"
        umount ${SQUASH_IMAGE}
        echo -e "${LTGREEN}  COMMAND:${GRAY} rmdir ${SQUASH_MOUNT}${NC}"
        rmdir ${SQUASH_MOUNT}
        echo
      ;;
    esac
 
    ##########################################
    # Unmount ISO image
    ##########################################
    case ${HAD_TO_MOUNT_ISO_IMAGE} in
      Y)
        echo -e "${LTCYAN}  -Unmounting ISO Image ...${NC}"
        echo -e "${LTGREEN}  COMMAND:${GRAY} umount ${ISO_MOUNT}${NC}"
        umount ${ISO_MOUNT}
        echo -e "${LTGREEN}  COMMAND:${GRAY} rmdir ${ISO_MOUNT}${NC}"
        rmdir ${ISO_MOUNT}
        echo
      ;;
    esac

  echo
}

####################################################################################################
#######################           Install GRUB Function         ####################################
####################################################################################################

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

####################################################################################################
####################                   main function                 ###############################
####################################################################################################

main() {

  case ${1} in
    help|--help|-h)
      usage
      exit
    ;;
  esac

  #######################################3
  # Check to see if you are root
  #######################################3
    check_user $*

  ###########################################################
  # Check to see if the install block dev was supplied
  ###########################################################
    check_for_install_block_device $*

  ####################################################################
  # Check to see if a rootfs.img is already mounted
  ####################################################################
    check_for_rootfs_image $*

  ##############################################################################################
  # If a rootfs.img is already mounted then use it and skip using the ISO image or squashfs.img
  ##############################################################################################
    case ${ROOTFS_IMAGE_MOUNTED}
    in
      Y|y)
        echo -e "${LTBLUE}The rootfs.img is already mounted. Will use it."${NC}
        echo
      ;;
      *)
        ###########################################################
        # Check to see if the live image was supplied or detected
        ###########################################################
        check_for_live_image $*
    
        ############################################################
        # if the live ISO image is empty look for a squashfs image
        ############################################################
        if [ -z ${ISO_IMAGE} ]
        then
          check_for_squash_image $*
    
          if [ -z ${SQUASH_IMAGE} ]
          then
            echo -e "${LTRED}ERROR: Source image not found. Exiting.${NC}"
            echo
            exit 99
          fi
        fi
      ;;
    esac

  ###########################################
  # Check for other CLI arguments
  ###########################################

    ################################################################
    # Check to see what filesystem to use for the root partition
    ################################################################
    check_for_root_fs_type $*

    ################################################################
    # Check to see how large to make the root partition
    ################################################################
    check_for_root_size $*

    ################################################################
    # Check to see if we need to create a home partition
    ################################################################
    check_for_create_home_partition $*

    ################################################################
    # Check for UEFI booting
    ################################################################
    check_for_uefi $*

    ################################################################
    # Check for enableing secure boot
    ################################################################
    check_for_enable_secure_boot $*

    ################################################################
    # Check for disabling cloud-init
    ################################################################
    check_for_disable_cloudinit $*

    ################################################################
    # Check for enabling cloud-init
    ################################################################
    check_for_enable_cloudinit $*

    ################################################################
    # Check for forcing the rebuild of the initrd
    ################################################################
    check_for_force_rebuild_initrd $*

  ########################################################
  # Get/set partition type
  ########################################################
    case ${BOOTLOADER} in
      UEFI|uefi)
        PARTITION_TABLE_TYPE=gpt
      ;;
      BIOS|bios)
        get_partition_table_type $*
      ;;
    esac

  ##############################################################################################
  # Display output of what we are going to do
  ##############################################################################################
    echo 
    echo -e "${LTRED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}"
    echo -e "${LTRED}!!!!             WARNING: ALL DATA ON DISK WILL BE LOST!             !!!!${NC}"
    echo -e "${LTRED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}"
    echo -e "${LTPURPLE}=========================================================================${NC}"
    if ! [ -z ${ORIG_DISK_DEV} ]
    then
      echo -e "${LTPURPLE}Disk Device:       ${GRAY}${ORIG_DISK_DEV} ${LTPURPLE}(using MPIO Disk Device)${NC}"
      echo -e "${LTPURPLE}MPIO Disk Device:  ${GRAY}${DISK_DEV}${NC}"
    else
      echo -e "${LTPURPLE}Disk Device:       ${GRAY}${DISK_DEV}${NC}"
    fi
    if ! [ -z ${ISO_IMAGE} ]
    then
      echo -e "${LTPURPLE}Live Image:        ${GRAY}${ISO_IMAGE}${NC}"
      echo -e "${LTPURPLE}ISO Mounted on:    ${GRAY}${ISO_MOUNT}${NC}"
      echo -e "${LTPURPLE}Squash Mounted on: ${GRAY}${SQUASH_MOUNT}${NC}"
    elif ! [ -z ${ROOTFS_IMAGE} ]
    then
      echo -e "${LTPURPLE}RootFS Image:      ${GRAY}${ROOTFS_IMAGE}${NC}"
      echo -e "${LTPURPLE}RootFS Mounted on: ${GRAY}${ROOTFS_IMAGE_MOUNT}${NC}"
    else
      echo -e "${LTPURPLE}Squash Image:      ${GRAY}${SQUASH_IMAGE}${NC}"
      echo -e "${LTPURPLE}Squash Mounted on: ${GRAY}${SQUASH_MOUNT}${NC}"
    fi
 
    echo -e "${LTPURPLE}Bootloader:        ${GRAY}${BOOTLOADER}${NC}"
    case ${BOOTLOADER} in
      UEFI)
        case ${SECURE_BOOT} in
          Y)
            echo -e "${LTPURPLE}Secure Boot:       ${GRAY}Yes${NC}"
          ;;
          N)
            echo -e "${LTPURPLE}Secure Boot:       ${GRAY}No${NC}"
          ;;
        esac
      ;;
    esac
 
    echo -e "${LTPURPLE}Partition Table:   ${GRAY}${PARTITION_TABLE_TYPE}${NC}"
    case ${CREATE_HOME_PART} in
      Y)
        echo -e "${LTPURPLE}Create /home:      ${GRAY}Yes${NC}"
      ;;
      N)
        echo -e "${LTPURPLE}Create /home:      ${GRAY}No${NC}"
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
        echo -e "${LTPURPLE}             /:         ${GRAY}${ROOT2_SIZE} (${ROOT_FS_TYPE})${NC}"
        echo -e "${LTPURPLE}             /home:     ${GRAY}${HOME_SIZE} (${HOME_FS_TYPE})${NC}"
      ;;
      N)
        echo -e "${LTPURPLE}             /:         ${GRAY}${ROOT_SIZE} (${ROOT_FS_TYPE})${NC}"
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

  #################################################################################################
  # Do the install
  #################################################################################################
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

######################################################################################################
######################################################################################################
####                           Main Code Body
######################################################################################################
######################################################################################################

time main $*

