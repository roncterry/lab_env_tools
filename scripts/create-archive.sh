#!/bin/bash
#
# version: 1.1.5
# date: 20220222

usage() {
  echo
  echo "USAGE: $0 <directory>[,<directory>,...] [<archive_format>]"
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

case ${2}
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
  -h|-H|help|HELP)
    usage
    exit
  ;;
  *)
    ARCHIVE_CMD="7z a -t7z -m0=LZMA2 -mmt=on -v2g"
    ARCHIVE_EXT="7z"
  ;;
esac

for DIR in $(echo ${1} | tr , \ )
do
  echo "---------------------------------------------------------------------"
  DIR=$(echo ${DIR} | sed 's+/$++')
  if [ -e ${DIR} ]
  then
    echo "COMMAND: ${ARCHIVE_CMD} ${DIR}.${ARCHIVE_EXT} ${DIR}"
    echo
    ${ARCHIVE_CMD} ${DIR}.${ARCHIVE_EXT} ${DIR}
    case ${ARCHIVE_EXT}
    in
      7z)
        md5sum ${DIR}.${ARCHIVE_EXT}.[0-9][0-9][0-9] > ${DIR}.${ARCHIVE_EXT}.md5sums
      ;;
      *)
        md5sum ${DIR}.${ARCHIVE_EXT} > ${DIR}.${ARCHIVE_EXT}.md5sums
      ;;
    esac
  else
    echo "ERROR: The directory \"${DIR}\" does not exist. Skipping ..."
    echo
  fi
done
