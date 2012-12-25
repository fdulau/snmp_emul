#!/bin/sh


FROM=$1
FILE_FULL=$2
FILE=$( basename $FILE_FULL )
BASE="/home/GIT/snmp_emul/conf/available"
REAL_FILE="$BASE/$FILE"
EVENT=$3

CMD='/home/GIT/snmp_emul/parse_snmp_emul.pl'

case $EVENT in
  "IN_DELETE") $( $CMD -f $REAL_FILE -D );;  
  *) $( $CMD -f $REAL_FILE );;
  
esac
