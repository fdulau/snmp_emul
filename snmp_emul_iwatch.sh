#!/bin/sh


FROM=$1
FILE_FULL=$2
FILE=$( basename $FILE_FULL )
BASE="/opt/snmp_emul/conf/available"
REAL_FILE="$BASE/$FILE"
EVENT=$3

CMD='/opt/snmp_emul/bin/parse_snmp_emul.pl'

case $EVENT in
  "IN_DELETE") $( $CMD -f $REAL_FILE -D );;  
  *) $( $CMD -f $REAL_FILE );;
  
esac
