#!/bin/bash

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

echo
echo -e "${LTBLUE}###################################################################${NC}"
echo -e "${LTBLUE}                  Sparsifying the VM's Disks${NC}"
echo -e "${LTBLUE}###################################################################${NC}"
echo

for DISK in *.qcow2
do
  echo
  echo -e "${LTCYAN}-----------------------------------------------------------------${NC}"
  echo -e "${LTCYAN}Sparsifying: ${LTPURPLE}${DISK}${NC}"
  echo -e "${LTCYAN}-----------------------------------------------------------------${NC}"
  echo
  echo -e "${LTGREEN}COMMAND:${GRAY} mv ${DISK} ${DISK}.orig${NC}"
  mv ${DISK} ${DISK}.orig

  echo -e "${LTGREEN}COMMAND:${GRAY} virt-sparsify ${DISK}.orig ${DISK}${NC}"
  virt-sparsify ${DISK}.orig ${DISK}

  echo
done

echo
echo -e "${LTRED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}"
echo -e "${LTRED}  Make sure you test the new disk before deleting the old one!${NC}"
echo -e "${LTRED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}"
echo
