#!/bin/bash

#====================================================================================================
#  Debug Vairables
#====================================================================================================
debug_directory=/var/log/tmp/debug
logfile=$debug_directory/logs.txt

#====================================================================================================
#  Function list
#====================================================================================================

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

##########################
##  WSTLSD Debug Start  ##
##########################
function WSTLSD_Start {
	for PROC in $(pidof wstlsd) ; do fw debug $PROC on TDERROR_ALL_ALL=6 ; done
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

#######################
## PEPD Debug Start  ##
#######################
function PEPD_Start {
	pep d on
	pep d set all all
}

##########################
## IA Full Debug Start  ##
##########################
function IA_Start {
	adlog a d on 
	pep debug on 
	pdp debug on 
	pdp d s all all 
	pep d s all all 
}

#########################
##  WSTLSD Debug Stop  ##
#########################
function WSTLSD_Stop {
	for PROC in $(pidof wstlsd) ; do fw debug $PROC off TDERROR_ALL_ALL=0 ; done

	cp $FWDIR/log/wstlsd.elg*
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

######################
## PEPD Debug Stop  ##
######################
function PEPD_Stop {
	pep d unset all all
	pep d off

	cp $FWDIR/log/pepd.elg* $debug_directory
}

#########################
## IA Full Debug Stop  ##
#########################
function IA_Stop {
	pdp d unset all all 
	pep d unset all all 
	pdp d off 
	pep d off

	cp $FWDIR/log/pdpd.elg* $debug_directory
	cp $FWDIR/log/pepd.elg* $debug_directory
}

#####################################################
## Archive & Cleanup FW Monitor || Packet Captures ##
#####################################################
function zip_and_clean_Basic {
    cd $debug_directory/
    echo "Zipping up files:"
    tar zcvf "$(date '+%F'_'%H-%M-%S')_archive.tgz" *
    rm fw_mon.pcap tcpdump-* logs.txt
    echo "Please upload $debug_directory/"$(date '+%F'_'%H-%M-%S')_archive.tgz" to Check Point support for review"
}

##############################
## Archive & Cleanup WSTLSD ##
##############################
function zip_and_clean_WSTLSD {
    cd $debug_directory/
    echo "Zipping up files:"
    tar zcvf "$(date '+%F'_'%H-%M-%S')_archive.tgz" *
    rm logs.txt wstlsd.elg*
    echo "Please upload $debug_directory/"$(date '+%F'_'%H-%M-%S')_archive.tgz" to Check Point support for review"

############################
## Archive & Cleanup PEPD ##
############################
function zip_and_clean_PEPD {
    cd $debug_directory/
    echo "Zipping up files:"
    tar zcvf "$(date '+%F'_'%H-%M-%S')_archive.tgz" *
    rm logs.txt pepd.elg*
    echo "Please upload $debug_directory/"$(date '+%F'_'%H-%M-%S')_archive.tgz" to Check Point support for review"
}

###############################
## Archive & Cleanup IA Full ##
###############################
function zip_and_clean_IA {
    cd $debug_directory/
    echo "Zipping up files:"
    tar zcvf "$(date '+%F'_'%H-%M-%S')_archive.tgz" *
    rm logs.txt pepd.elg* pdpd.elg* fw_mon.pcap tcpdump-*
    echo "Please upload $debug_directory/"$(date '+%F'_'%H-%M-%S')_archive.tgz" to Check Point support for review"
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
		put archive.tgz
		bye
EOF
elif [[ "$sftp" == "n" ]]; then
	exit 1
rm $debug_directory/*_archive.tgz
fi
}

#####################
## Final Clean-Up  ##
#####################
function Final_Cleanup {
    directory=""
    printf "Please enter the directory the Debug Script was installed in:"
    read directory
    rm -rf $directory
}

#====================================================================================================
#  Main Script Menu
#====================================================================================================

x=0
while [ $x == 0 ]
do
	clear
	echo "Please choose the debug you would like to run (1-5):"
	echo "1. FW Monitor || Packet Captures"
	echo "2. PEPD"
	echo "3. PEPD & PDPD"
	echo "4. WSTLSD"
	echo "5. Quit"
	read answer

	case "$answer" in
			1)
			echo "You chose FW Monitor || Packet Captures."
			x=1
			;;
			2)
			echo "You chose PEPD."
			x=2
			;;
			3)
			echo "You chose PEPD & PDPD."
			x=3
			;;
			4)
			echo "You chose WSTLSD."
			x=4
			;;
			5)
			echo "Exiting"
			x=5
			;;
			*)
			clear
			echo "That is not an option."
			sleep 1
			;;
	esac
done

if [[ "$x" == "1" ]]; then
	clear
    ask_for_ips
    get_interface_names
    check_securexl

    if [[ $yesno_securexl == 1 ]]; then
        echo "SecureXL is enabled. Please manually disable SecureXL and then restart script."
        exit 1
    fi
    
    bg_info_gathering
    fw_pcaps
    fw_pcaps_stop
    zip_and_clean_Basic
    SFTP_Upload

elif [[ "$x" == "2" ]]; then
	clear
    ask_for_ips
    get_interface_names
    check_securexl

    if [[ $yesno_securexl == 1 ]]; then
        echo "SecureXL is enabled. Please manually disable SecureXL and then restart script."
        exit 1
    fi

    bg_info_gathering
    fw_kern_start
    fw_pcaps
    fw_kern_stop
    zip_and_clean_Kernel
    SFTP_Upload

elif [[ "$x" == "3" ]]; then
	clear
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
    fw_kern_UP_start
    fw_pcaps
    fw_kern_stop
    zip_and_clean_Kernel
    SFTP_Upload

elif [[ "$x" == "4" ]]; then
	clear
    ask_for_ips
    get_interface_names
    check_securexl

    if [[ $yesno_securexl == 1 ]]; then
        echo "SecureXL is enabled. Please manually disable SecureXL and then restart script."
        exit 1
    fi
    
    bg_info_gathering
    Mobile_Trace_Log
    fw_pcaps
    Mobile_Trace_End
    zip_and_clean_Mobile_Trace
    SFTP_Upload

elif [[ "$x" == "5" ]]; then
	clear
    exit 1
fi
