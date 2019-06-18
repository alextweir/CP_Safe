#!/bin/bash

#====================================================================================================
#  Debug Vairables
#====================================================================================================
debug_directory=/var/log/tmp/debug
logfile=$debug_directory/logs.txt

#====================================================================================================
#  Function list
#====================================================================================================

#################################
## OS Check & Debug Buffer Set ##
#################################
function check_OS_for_buffer {
    whatami=$(cpstat os | grep 'OS Name' | awk '{print $3, $4}' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
	if [[ $whatami == "Gaia" ]]; then
	    debug_buffer=32000
	    debug_directory=/var/log/tmp/debug
	    logfile=$debug_directory/logs.txt
	elif [[ $whatami == "Gaia Embedded" ]]; then
	    debug_buffer=15000
	    printf "Please enter a directory: "
	    read debug_directory
	    logfile=$debug_directory/logs.txt
	fi
}

####################
## SecureXL Check ##
####################
function check_securexl {
    yesno_securexl=$(fwaccel stat | grep -E "Accelerator Status")
    if [[ -z $yesno_securexl ]]; then
        yesno_securexl=$(echo "$fwaccel_stat" | sed 's/|//g' | grep ^0 | grep -Eo 'enabled|disabled')
    fi

    printf "===============================================\n" >> $logfile
    printf "| SecureXL Initial Status\n" >> $logfile
    printf "===============================================\n" >> $logfile

    if [[ $yesno_securexl == *"on"* || $yesno_securexl == *"enabled"* ]]; then
        printf "[ $(date) ] " >> $logfile
        printf "SecureXL is on\n" | tee -a $logfile
        yesno_securexl=1
        printf "[ $(date) ] " >> $logfile
        printf "yesno_securexl = $yesno_securexl \n" >> $logfile
    else
        printf "[ $(date) ] " >> $logfile
        printf "SecureXL is off\n" | tee -a $logfile
        yesno_securexl=0
        printf "[ $(date) ] " >> $logfile
        printf "yesno_securexl = $yesno_securexl \n" >> $logfile
    fi
}

##############
## IP Query ##
##############
function ask_for_ips {
    # Create log file
    mkdir -p $debug_directory
    echo "" > $logfile

    printf "===============================================\n" >> $logfile
    printf "| User Input\n" >> $logfile
    printf "===============================================\n" >> $logfile

    read -e -p "Enter Source IP address: " srcIP
    printf "[ $(date) ] " >> $logfile
    printf "Enter Source IP address: $srcIP\n" >> $logfile

    read -e -p "Enter Destination IP address: " dstIP
    printf "[ $(date) ] " >> $logfile
    printf "Enter Destination IP address: $dstIP\n" >> $logfile

   sleep 1
}

#####################
## Interface Query ##
#####################
function get_interface_names {
    findInterfacesCounter=0
    for line in $(ifconfig -a | grep HW | awk '{print $1}'); do
        array[$findInterfacesCounter]=$line
        ((findInterfacesCounter++))
    done

    for i in ${array[*]}; do
        if [[ $(ip route get $srcIP) == *$i* ]]; then
            ingress=$i
            if [[ $ingress == "" ]]; then
                printf "Script unable to find correct interface for IP $srcIP\n"
                printf "Please enter the name of the interface that $srcIP should enter\n"
                printf "the firewall on as it appears in the output of ifconfig\n"
                read -e -p "Interface Name: " ingress
            fi
        fi
        if [[ $(ip route get $dstIP) == *$i* ]]; then
            egress=$i
            if [[ $egress == "" ]]; then
                printf "Script unable to find correct interface for IP $dstIP\n"
                printf "Please enter the name of the interface that $dstIP should enter\n"
                printf "the firewall on as it appears in the output of ifconfig\n"
                read -e -p "Interface Name: " egress
            fi
        fi
    done

    printf "===============================================\n" >> $logfile
    printf "| Interfaces\n" >> $logfile
    printf "===============================================\n" >> $logfile
    printf "[ $(date) ] " >> $logfile
    printf "Ingress interface is: $ingress\n" | tee -a $logfile
    printf "[ $(date) ] " >> $logfile
    printf "Egress interface is: $egress\n" | tee -a $logfile
    printf "If the interfaces above are incorrect the tcpdumps taken will be inaccurate\n"
    sleep 1
}

#########################################
## Ifconfig & Routing Table Collection ##
#########################################
function bg_info_gathering {
    printf "===============================================\n" >> $logfile
    printf "| ifconfig -a\n" >> $logfile
    printf "===============================================\n" >> $logfile
    ifconfig -a >> $logfile

    clish -c "lock database override" >/dev/null 2>&1
    printf "===============================================\n" >> $logfile
    printf "| clish -c \"show route\"\n" >> $logfile
    printf "===============================================\n" >> $logfile
    clish -c "show route" >> $logfile

    printf "===============================================\n" >> $logfile
    printf "| ls -lrt /var/log/dump/usermode/\n" >> $logfile
    printf "===============================================\n" >> $logfile
    ls -lrt /var/log/dump/usermode/ >> $logfile

    printf "===============================================\n" >> $logfile
    printf "| ls -lrt /var/crash/\n" >> $logfile
    printf "===============================================\n" >> $logfile
    ls -lrt /var/crash/ >> $logfile
}

#################
##  TCP Dumps  ##
#################
function fw_pcaps {
    printf "===============================================\n" >> $logfile
    printf "| Capture Information\n" >> $logfile
    printf "===============================================\n" >> $logfile   
    printf "Starting Packet Captures...\n"
    printf "Starting Ingress TCPdump on interface ${ingress}\n"
    nohup tcpdump -s 0 -nnei ${ingress} -C 100 -W 10 -w $debug_directory/tcpdump-ingress.pcap -Z ${USER} >/dev/null 2>&1 &
    printf "[ $(date) ] " >> $logfile
    echo "nohup tcpdump -s 0 -nnei ${ingress} -C 100 -W 10 -w ~/tcpdump-ingress.pcap -Z ${USER} >/dev/null 2>&1 &" >> $logfile

    printf "Starting Egress TCPdump on interface ${egress}\n"
    nohup tcpdump -s 0 -nnei ${egress} -C 100 -W 10 -w $debug_directory/tcpdump-egress.pcap -Z ${USER} >/dev/null 2>&1 &
    printf "[ $(date) ] " >> $logfile
    echo "nohup tcpdump -s 0 -nnei ${egress} -C 100 -W 10 -w ~/tcpdump-egress.pcap -Z ${USER} >/dev/null 2>&1 &" >> $logfile

    printf "Starting FW Monitor\n"
    printf "[ $(date) ] " >> $logfile
    printf "Starting FW Monitor\n" >> $logfile

    nohup fw monitor -i -e "accept;" -o $debug_directory/fw_mon.pcap >/dev/null 2>&1 &
    printf "[ $(date) ] " >> $logfile
    echo "nohup fw monitor -i -e \"accept;\" -o ~/fw_mon.pcap >/dev/null 2>&1 &" >> $logfile
}

##################
## ZDebug Start ##
##################
function zdebug_start {
    printf "Starting Zdebug\n"
    printf "[ $(date) ] " >> $debug_directory/zdebug.txt
    printf "Starting Zdebug\n" >> $debug_directory/zdebug.txt

    nohup fw ctl zdebug + drop >> $debug_directory/zdebug.txt & >/dev/null 2>&1 &
    printf "[ $(date) ] " >> $logfile
    echo "nohup fw ctl zdebug + drop > $debug_directory/zdebug.txt & >/dev/null 2>&1 &" >> $logfile
    fw ctl zdebug + drop >> $debug_directory/zdebug.txt &
}

##########################
## SecureXL Debug Start ##
##########################
function secureXL_start {
	printf "===============================================\n" >> $logfile
    printf "| SecureXL Status\n" >> $logfile
    printf "===============================================\n" >> $logfile
	fwaccel stat >> $logfile
	printf "===============================================\n" >> $logfile
    printf "| SecureXL Existing Connections\n" >> $logfile
    printf "===============================================\n" >> $logfile
	fwaccel conns >> $logfile
	printf "===============================================\n" >> $logfile
    printf "| SecureXL Number of Connections Handled\n" >> $logfile
    printf "===============================================\n" >> $logfile
	fwaccel conns -s >> $logfile
	printf "===============================================\n" >> $logfile
    printf "| SecureXL Statistics\n" >> $logfile
    printf "===============================================\n" >> $logfile
	fwaccel stats >> $logfile
	printf "===============================================\n" >> $logfile
    printf "| SecureXL Statistics Summary\n" >> $logfile
    printf "===============================================\n" >> $logfile
	fwaccel stats -s >> $logfile
	printf "===============================================\n" >> $logfile
    printf "| SecureXL Templates Statistics\n" >> $logfile
    printf "===============================================\n" >> $logfile
	fwaccel templates >> $logfile
	printf "===============================================\n" >> $logfile
    printf "| SecureXL Connections Detected\n" >> $logfile
    printf "===============================================\n" >> $logfile
	fw tab -t cphwd_db -s >> $logfile

	fw ctl debug 0 
	fw ctl debug -buf 32000
	fw ctl debug -m fw + conn drop 
	fw ctl debug -m all
	sim dbg -m pkt all
	sim dbg -m vpn all
	sim dbg -m drv all
	fwaccel dbg -m db all
	fwaccel dbg -m api all
	fw ctl kdebug -T -f > $debug_directory/kern.ctl &

    echo "Debug Ready"

	vpn_log_number=$(/bin/log_start list | grep vpnd.elg | awk 'BEGIN { FS = ")" } ; { print $1 }')
	echo > $debug_directory/unlimit
	/bin/log_start list | grep vpn | awk -v y="$vpn_log_number" '{ print "/bin/log_start limit " y " " $3 " " $4 }' > $debug_directory/unlimit
    chmod 777 $debug_directory/unlimit
    /bin/log_start log unlimit $vpn_log_number

	vpn debug trunc
	vpn debug on TDERROR_ALL_ALL=5

	echo "Debug environment is ready, please reproduce the problem."
}

#######################################
## FW Monitor || Packet Captures End ##
#######################################
function fw_pcaps_stop {
    read -p "Press any key to stop debugs and captures" -n1 anykey

    for LINE in $(jobs -p); do
        RIPid="$(ps aux | grep $LINE | grep -v grep | awk '{for(i=11; i<=NF; ++i) printf "%s ", $i; print ""}')"
        kill ${LINE} >/dev/null 2>&1
        printf "[ $(date) ] " >> $logfile
        echo "kill ${LINE} - $RIPid" >> $logfile
    done
}

#########################
## SecureXL Debug Stop ##
#########################
function secureXL_stop {
    read -p "Press any key to stop debugs and captures" -n1 anykey

	vpn debug off
	vpn debug ikeoff

	fw ctl debug 0

	cp $FWDIR/log/vpnd.elg $debug_directory
	cp $FWDIR/log/ike.elg $debug_directory
	cp $FWDIR/log/ikev2.xmll $debug_directory

	fwaccel dbg resetall
	sim dbg resetall
	$debug_directory/unlimit
}

#######################
## Archive & Cleanup ##
#######################
function zip_and_clean_Basic {
    date="%Y-%m-%d"
    cd $debug_directory/
    echo "Zipping up files:"
    tar zcvf "$(date '+%F'_'%H-%M-%S')_Basic_archive.tgz" *
    rm fw_mon.pcap tcpdump-* logs.txt zdebug.txt
    echo "Please upload $debug_directory/"$(date '+%F'_'%H-%M-%S')_Basic_archive.tgz" to Check Point support for review."
}

##########################
## SFTP Upload & Delete ##
##########################
function SFTP_Upload {
	sftp=""
	printf "Would you like to upload to SFTP (y/n): "
	read sftp

	if [[ "$sftp" == "y" ]]; then
                srnumber=""
                printf "Please enter the SR#: "
                read srnumber
                host="216.228.148.22"
                cd $debug_directory

                sftp $srnumber@$host <<EOF
                                cd incoming/
                                put *_archive.tgz
                                bye
EOF
	elif [[ "$sftp" == "n" ]]; then
                exit 1
	fi
}

#====================================================================================================
#  Main Script Menu
#====================================================================================================
x=0
while [ $x == 0 ]
do
	clear
	echo "Please choose the debug you would like to run (1-6):"
	echo "1. FW Monitor || Packet Captures"
	echo "2. SecureXL Debug"
	echo "3. Exit"
		read answer

	case "$answer" in
		1)
		echo "You chose FW Monitor || Packet Captures."
		x=1
		;;
		2)
		echo "You chose SecureXL Debug."
		x=2
		;;
		3)
        echo "Exiting"
        x=3
        ;;
		*)
		clear
		echo "That is not an option."
		sleep 1
		;;
	esac
done

if [[ "$x" == "1" ]]; then
	check_OS_for_buffer
                if [[ $whatami == *"Gaia"* ]]; then
                echo "OS Name: $whatami"
                fi
    ask_for_ips
    get_interface_names
    check_securexl
               if [[ $yesno_securexl == 1 ]]; then
               echo "SecureXL is enabled. Please manually disable SecureXL and then restart script."
               exit 1
               fi
    bg_info_gathering
    fw_pcaps
    zdebug_start
    fw_pcaps_stop
    zip_and_clean_Basic
    SFTP_Upload

elif [[ "$x" == "2" ]]; then
	clear
    check_OS_for_buffer
	    if [[ $whatami == *"Gaia"* ]]; then
    	    echo "OS Name: $whatami"
    	fi
    ask_for_ips
    get_interface_names
    bg_info_gathering
    fw_pcaps
    secureXL_start
    secureXL_stop
    fw_pcaps_stop
    zip_and_clean_Basic
    SFTP_Upload

elif [[ "$x" == "3" ]]; then
	clear
    exit 1
fi