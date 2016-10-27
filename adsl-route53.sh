#!/bin/bash
#讀取跟目錄的adsl.txt檔案 並自動撥接ADSL 並更新router53的recordser
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ZONEID="ZVH75PP42YZ8R"
SERIAL=$(cat /proc/cpuinfo | tail -c 5)i
RECORDSET="${SERIAL}.pi.ready-market.com"
DATE=`date +%Y-%m-%d:%H:%M:%S`
# More advanced options below
# The Time-To-Live of this recordset
TTL=300
# Change this if you want
COMMENT="Auto updating @ `date`"
# Change to AAAA if using an IPv6 address
TYPE="A"
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
username=`cat /adsl.txt|head -1`
password=`cat /adsl.txt|sed -n 2p`
echo $username
echo $password
echo 'connecting to adsl...'

count=0
maxcount=10
poff -a > /dev/null
until test -n "`ifconfig | grep ppp`"
do
	if [ "$count" != 0 ]
		then echo "$count th connection failed!"
	fi
	cp /etc/ppp/peers/dsl-config temp
	echo "user \"$username\"" >> temp
	echo "password \"$password\"" >> temp
	mv temp /etc/ppp/peers/dsl-provider
	pon dsl-provider > /dev/null
	count=`expr $count + 1`
	if [ "$count" -eq "$maxcount" ]
	then echo 'Failed too much times.Please check adsl.txt, or retry later'
	exit 0
	fi
	sleep 10
done
echo `plog | grep local`
echo 'connection build!'
IP=`ifconfig | sed -n '/^ppp0/{n;p;}' | sed 's/ *inet addr:\(.*\) P-t-P.*/\1/'`
route -v add default gw $IP
# Get current dir
# (from http://stackoverflow.com/a/246128/920350)
LOGFILE="$DIR/update-route53.log"
IPFILE="$DIR/update-route53.ip"

# Check if the IP has changed
if [ ! -f "$IPFILE" ]
    then
    touch "$IPFILE"
fi

if grep -Fxq "$IP" "$IPFILE"; then
    # code if found
    echo "[${DATE}]$RECORDSET is still $IP. Exiting" >> "$LOGFILE"
    exit 0
else
    echo "[${DATE}]$RECORDSET has changed to $IP" >> "$LOGFILE"
    # Fill a temp file with valid JSON
    TMPFILE=$(mktemp /tmp/temporary-file.XXXXXXXX)
    cat > ${TMPFILE} << EOF
    {
      "Comment":"$COMMENT",
      "Changes":[
        {
          "Action":"UPSERT",
          "ResourceRecordSet":{
            "ResourceRecords":[
              {
                "Value":"$IP"
              }
            ],
            "Name":"$RECORDSET",
            "Type":"$TYPE",
            "TTL":$TTL
          }
        }
      ]
    }
EOF

    # Update the Hosted Zone record
    aws route53 change-resource-record-sets \
        --hosted-zone-id $ZONEID \
        --change-batch file://"$TMPFILE" >> "$LOGFILE"
    echo "$IP" > "$IPFILE"

    # Clean up
    rm $TMPFILE
fi
exit 0
