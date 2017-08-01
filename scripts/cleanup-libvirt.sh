#!/bin/bash
#
# version: 20161112.001

###############################################################################
#                global vars
###############################################################################


###############################################################################
#                functions
###############################################################################

remove_all_vms() {
  for VM in $(virsh list --all | grep -v Id | grep -v "^-" | awk '{ print $2 }')
  do 
    virsh destroy ${VM}
    virsh undefine --remove-all-storage --snapshots-metadata --wipe-storage ${VM}
  done
}

remove_all_vnets() {
  for VNET in $(virsh net-list --all | grep -v " *Name" | grep -v "^-" | awk '{ print $1 }')
  do 
    virsh net-destroy ${VNET}
    virsh net-undefine ${VNET}
  done
}


main() {
  echo
  echo "----------------------------------------------------------------------"
  echo "Removing all Libvirt VMs ..."
  echo
  remove_all_vms
  echo
  echo "----------------------------------------------------------------------"
  echo "Removing all Libvirt vritual networks ..."
  echo
  remove_all_vnets
}


###############################################################################
#                main code body
###############################################################################

main
