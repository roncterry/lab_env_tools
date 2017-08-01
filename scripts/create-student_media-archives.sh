#!/bin/bash

usage() {
  echo
  echo "USAGE: $0 <archive_format> <student_media_dir>[,<student_media_dir>,...]"
  echo
  echo "  Archive Formats:"
  echo "    7z        -7zip with LZMA compression split into 2G files"
  echo "    7zma2     -7zip with LZMA2 compression split into 2G files"
  echo "    7zcopy    -7zip with no compression split into 2G files"
  echo "    tar       -tar archive with no compression"
  echo "    tgz       -gzip  compressed tar archive"
  echo "    tbz       -bzip2 compressed tar archive"
  echo "    txz       -xz compressed tar archive"
  echo
}

case ${1}
in
  7z)
    ARCHIVE_CMD="7z a -t7z -m0=LZMA -mmt=on -v2g"
    ARCHIVE_EXT="7z"
  ;;
  7zma2)
    ARCHIVE_CMD="7z a -t7z -m0=LZMA2 -mmt=on -v2g"
    ARCHIVE_EXT="7z"
  ;;
  7zcopy)
    ARCHIVE_CMD="7z a -t7z -mx=0 -v2g"
    ARCHIVE_EXT="7z"
  ;;
  tar)
    ARCHIVE_CMD="tar cvf"
    ARCHIVE_EXT="tar"
  ;;
  tar.gz|tgz)
    ARCHIVE_CMD="tar czvf"
    ARCHIVE_EXT="tgz"
  ;;
  tar.bz2|tbz)
    ARCHIVE_CMD="tar cjvf"
    ARCHIVE_EXT="tbz"
  ;;
  tar.xz|txz)
    ARCHIVE_CMD="tar cJvf"
    ARCHIVE_EXT="txz"
  ;;
  *)
    usage
    exit
  ;;
esac

if [ -z ${2} ]
then
  echo "ERROR: No student media directories were provided."
  exit 1
else
  for SM_DIR in $(echo ${2} | sed 's/,/ /g')
  do
    if ! [ -d ${2} ]
    then
      echo "ERROR: The provided student media directory doesn't appear to exist."
      echo "Skipping ..."
    else
      echo "---------------------------------------------------------------------"
      echo "COMMAND: ${ARCHIVE_CMD} ${SM_DIR}.${ARCHIVE_EXT} ${SM_DIR}"
      echo
      ${ARCHIVE_CMD} ${SM_DIR}.${ARCHIVE_EXT} ${SM_DIR}
      echo
      echo "COMMAND: md5sum ${SM_DIR}.${ARCHIVE_EXT}* > ${SM_DIR}.${ARCHIVE_EXT}.md5sums"
      echo
      md5sum ${SM_DIR}.${ARCHIVE_EXT}* > ${SM_DIR}.${ARCHIVE_EXT}.md5sums
    fi
  done
fi
