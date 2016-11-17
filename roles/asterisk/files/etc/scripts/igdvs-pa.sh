#!/bin/bash

TMPDIR=`mktemp -d`

#EXTENS="5000 5006 5009 5001 5003 5002 5007 5004 5008 5005 5012 5013 5014 5011 5010 5500 5501 5502"
#EXTENS="6999 4999"
EXTENS="4999"

for EXTEN in $EXTENS
do
cat <<CALLFILE > /${TMPDIR}/${EXTEN}.call
Channel: SIP/${EXTEN}
MaxRetries: 2
RetryTime: 60
WaitTime: 30
Context: from-internal-cttb
Extension: 69999
CALLFILE
done

mv /${TMPDIR}/*.call /var/spool/asterisk/outgoing/
