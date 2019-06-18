#!/bin/bash

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

#################
## Shell Check ##
#################
function check_shell {
    SHELL=$(cat /etc/passwd | grep $USER)

    if [[ $SHELL == *"/bin/bash"* ]]; then
        echo "Default shell is /bin/bash"
        defaultSHELL="bash"
    elif [[ $SHELL == *"/etc/cli.sh"* ]]; then
        echo "Default shell is /etc/cli.sh"
        defaultSHELL="clish"
    else
        echo "Default shell is neither /bin/bash or /etc/cli.sh"
        defaultSHELL="unknown"
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

######################
## VPN Light Kernel ##
######################
function fw_kern_start {
    echo "Debug is initializing, please wait ...."

    fw ctl debug 0 
    fw ctl debug -buf $debug_buffer
    fw ctl debug -m fw + conn drop
    fw ctl debug -m VPN + all
    fw ctl kdebug -T -f > $debug_directory/kern.ctl &

    vpn debug trunc
    vpn debug on TDERROR_ALL_ALL=5

    echo "Debug environment is ready, please reproduce the problem."
}

##########################################
## VPN Light Kernel with Unified Policy ##
##########################################
function fw_kern_UP_start {
    echo "Debug is initializing, please wait ...."

    fw ctl debug 0 
    fw ctl debug -buf $debug_buffer
    fw ctl debug -m fw + vm conn drop
    fw ctl debug -m UP + all
    fw ctl debug -m VPN + all
    fw ctl kdebug -T -f > $debug_directory/kern.ctl &

    vpn debug trunc
    vpn debug on TDERROR_ALL_ALL=5

    echo "Debug environment is ready, please reproduce the problem."
}

######################
## Mobile Trace Log ##
######################
function Mobile_Trace_Log {
	echo "Debug is initializing, please wait ...."

	cp $CVPNDIR/conf/httpd.conf $debug_directory/httpd.conf_old

	version=$(cat /etc/cp-release | sed -r "s/.*R([0-9]*).*/\1/")
	sub_version=$(cat /etc/cp-release | sed -r "s/.*\.([0-9]*).*/\1/")

	if [ "$version" -ge 77 -a "$sub_version" -ge 10 ]; then
	    sed -e "s/ERROR/DEBUG/" $CVPNDIR/phpincs/conf/log4php.properties -s > $debug_directory/log4php.properties_new
	    echo > $CVPNDIR/log/trace_log/SSLVPNPortalLog.log
	    cp $CVPNDIR/phpincs/conf/log4php.properties $debug_directory/log4php.properties_old
	    cp $debug_directory/log4php.properties_new $CVPNDIR/phpincs/conf/log4php.properties

	elif [ "$version" -ge 77 ]; then
	    sed -e 's/^ *LogLevel .*/LogLevel debug/' -e 's/^ *CvpnTraceApache .*/CvpnTraceApache On/'  $CVPNDIR/conf/httpd.conf -s > $debug_directory/httpd.conf_new
    	if [ "$1" = "all" ] || [ "$1" = "any" ]; then
    	    cvpnd_admin debug trace on
    	else
        	cvpnd_admin debug trace users=$1
    	fi

	elif [ "$version" -ge 76 ]; then
	    sed -e 's/^ *LogLevel .*/LogLevel debug/'  $CVPNDIR/conf/httpd.conf -s > $debug_directory/httpd.conf_new
	    if [ "$1" = "all" ] || [ "$1" = "any" ]; then
	        cvpnd_admin debug trace on
	    else
	        cvpnd_admin debug trace users=$1
	    fi

	elif [ "$version" -ge 75 -a "$sub_version" -ge 40 ]; then
    	    sed -e 's/^ *LogLevel .*/LogLevel debug/'  $CVPNDIR/conf/httpd.conf -s > $debug_directory/httpd.conf_new
        	if [ "$1" = "all" ] || [ "$1" = "any" ]; then
            	cvpnd_admin debug trace on
        	else
        	    cvpnd_admin debug trace users=$1
        	fi
	elif [ "$version" -ge 71 ]; then
	        sed -e 's/^ *LogLevel .*/LogLevel debug/' -e 's/^ *# *LoadModule trace_logger /LoadModule trace_logger /'  $CVPNDIR/conf/httpd.conf -s > $debug_directory/httpd.conf_new
	    else
	        sed -e 's/^ *LogLevel .*/LogLevel debug/' -e 's/^ *# *LoadModule trace_logger /LoadModule trace_logger /' -e 's/^ *# *CvpnTraceLogDir /CvpnTraceLogDir/' -e 's/^ *# *CvpnTraceLogMaxByte .*/CvpnTraceLogMaxByte 10000000/' $CVPNDIR/conf/httpd.conf -s > $DBGDIR/httpd.conf_new
	fi

	userID=""
	printf "Please enter the User ID we will be testing with: "
	read userID
	echo $userID > $logfile

	find $CVPNDIR/log/trace_log -type f -name '*' -exec rm {} \;
	cp $debug_directory/httpd.conf_new $CVPNDIR/conf/httpd.conf
	rm $CVPNDIR/log/httpd.log*
	echo > $CVPNDIR/log/httpd.log

	trunc_succ_msg="Log file was trunctuated"
	trunc_res=$(cvpnd_admin debug trunc)

	#======================================================#
	# fallback for versions that don't support trunc       #
	#======================================================#
	if [ "$trunc_res" != "$trunc_succ_msg" ]; then
    echo > $CVPNDIR/log/cvpnd.elg
	fi

	rm $CVPNDIR/log/cvpnd.elg*
	echo > $CVPNDIR/log/cvpnd.elg
	cvpnd_admin debug set TDERROR_ALL_ALL=5
	cvpnd_admin policy
	echo "Debug environment is ready, please reproduce the problem."
}

#####################
## SNX Debug Start ##
#####################
function SNX_start {
	echo "Debug is initializing, please wait ...."

	userID=""
	printf "Please enter the User ID we will be testing with: "
	read userID
	echo $userID > $logfile

	echo > $debug_directory/kernel_debug.log
	fw ctl debug 0 
	fw ctl debug -buf 32000
	fw ctl debug -m fw + conn drop nat xlate xltrc
	fw ctl debug -m fw + cptls crypt
	fw ctl debug -m VPN all
	fw ctl kdebug -T -f > $debug_directory/kernel_debug.log &

	vpn_log_number=$(/bin/log_start list | grep vpnd.elg | awk 'BEGIN { FS = ")" }; { print $1 }')
	echo > $debug_directory/unlimit
	/bin/log_start list | grep vpn | awk -v y="$vpn_log_number" '{ print "/bin/log_start limit " y " " $3 " " $4 }' > $debug_directory/unlimit
	chmod 777 $debug_directory/unlimit
	/bin/log_start log unlimit $vpn_log_number

	vpn debug trunc
	rm $FWDIR/log/vpnd.elg*
	vpn debug on TDERROR_ALL_ALL=5

	rm $CVPNDIR/log/cvpnd.elg*
	echo > $CVPNDIR/log/cvpnd.elg
	cvpnd_admin debug set TDERROR_ALL_ALL=5

	cp $CVPNDIR/conf/httpd.conf $debug_directory/httpd.conf_old
	sed -e 's/^ *LogLevel .*/LogLevel debug/' $CVPNDIR/conf/httpd.conf -s > $debug_directory/httpd.conf_new
	cp $debug_directory/httpd.conf_new $CVPNDIR/conf/httpd.conf
	rm $CVPNDIR/log/httpd.log*
	echo > $CVPNDIR/log/httpd.log
	cvpnd_admin policy
	echo "Debug environment is ready, please reproduce the problem."
}

#################
##  TCP Dumps  ##
#################
function fw_pcaps {
	vpn debug trunc
    vpn debug on TDERROR_ALL_ALL=5
    
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

    nohup fw ctl zdebug + drop > $debug_directory/zdebug.txt & >/dev/null 2>&1 &
    printf "[ $(date) ] " >> $logfile
    echo "nohup fw ctl zdebug + drop > $debug_directory/zdebug.txt & >/dev/null 2>&1 &" >> $logfile
    fw ctl zdebug + drop > $debug_directory/zdebug.txt &
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

#################################
## Kernel Debug Extended Start ##
#################################
function Kernel_Extended_Start {
    print "PLEASE NOTE: This debug is VERY resource intensive and needs to be run during a maintenance window as well as having someone on site with access to the device in the event that it becomes non-responsive and must be unplugged in order to cause a proper Fail-Over or recover the device."
    print "Please enter password to continue: "


    echo "Debug is initializing, please wait ...." >&4

	accel_status=$(fwaccel stat | grep "Accelerator Status" | awk 'BEGIN { FS = ":" } ; { print $2 }')

	if [ $accel_status == "on" ]; then echo -e "\\nWARNING - We have detected that Secure XL is currently enabled on the system.\\nThis script was designed to run when SXL is disabled.\\nRunning this script with enabled SXL can result in gathering partial data only,\\nplease consider stopping the script and running it again when SXL is disabled.\\nTo stop SXL run \"fwaccel off\".\\nOtherwise please explain why do you need to have it enabled to TAC person you\\nare working with.\\n\\n" >&4; fwaccel stat > $DBGDIR/fwaccel_stat.txt; fi

	fw monitor -e "accept;" -o $DBGDIR/mon.pcap &

	fw ctl debug 0 
	fw ctl debug -buf 32000
	fw ctl debug -m fw + ld conn drop packet route xlate xltrc nat
	fw ctl debug -m fw + cptls crypt
	fw ctl debug -m VPN all
	fw ctl kdebug -T -f > $DBGDIR/kern.ctl & 

	vpn_log_number=$(/bin/log_start list | grep vpnd.elg | awk 'BEGIN { FS = ")" } ; { print $1 }')
	echo > $DBGDIR/unlimit
	/bin/log_start list | grep vpn | awk -v y="$vpn_log_number" '{ print "/bin/log_start limit " y " " $3 " " $4 }' > $DBGDIR/unlimit
	chmod 777 $DBGDIR/unlimit
	/bin/log_start unlimit $vpn_log_number

	rm $FWDIR/log/vpnd.elg.*
	vpn debug trunc
	vpn debug on TDERROR_ALL_ALL=5

	echo "Debug environment is ready, please reproduce the problem." >&4
}

######################################################
## FW Monitor || Ike || VPND || Packet Captures End ##
######################################################
function fw_pcaps_stop {
    read -p "Press any key to stop debugs and captures" -n1 anykey

    vpn debug off
    vpn debug truncoff

    for LINE in $(jobs -p); do
        RIPid="$(ps aux | grep $LINE | grep -v grep | awk '{for(i=11; i<=NF; ++i) printf "%s ", $i; print ""}')"
        kill ${LINE} >/dev/null 2>&1
        printf "[ $(date) ] " >> $logfile
        echo "kill ${LINE} - $RIPid" >> $logfile
    done

    if [[ -f $FWDIR/log/sfwd.elg ]]; then
        # Fake Gaia
        cp $FWDIR/log/sfwd.elg* $debug_directory/
    else 
        # Real Gaia
        cp $FWDIR/log/vpnd.elg* $debug_directory/
    fi

    cp $FWDIR/log/ike.elg* $debug_directory/
    cp $FWDIR/log/ikev2.xmll* $debug_directory/

}

#############################################################
## VPN Light Kernel & Light Kernel with Unified Policy End ##
#############################################################
function fw_kern_stop {
    read -p "Press any key to stop debugs and captures" -n1 anykey

    fw ctl debug 0 
    vpn debug off
    vpn debug truncoff

    for LINE in $(jobs -p); do
        RIPid="$(ps aux | grep $LINE | grep -v grep | awk '{for(i=11; i<=NF; ++i) printf "%s ", $i; print ""}')"
        kill ${LINE} >/dev/null 2>&1
        printf "[ $(date) ] " >> $logfile
        echo "kill ${LINE} - $RIPid" >> $logfile
    done

    if [[ -f $FWDIR/log/sfwd.elg ]]; then
        # Fake Gaia
        cp $FWDIR/log/sfwd.elg* $debug_directory/
    else 
        # Real Gaia
        cp $FWDIR/log/vpnd.elg* $debug_directory/
    fi

    cp $FWDIR/log/ike.elg* $debug_directory/
    cp $FWDIR/log/ikev2.xmll* $debug_directory/

}

##########################
## End Mobile Trace Log ##
##########################
function Mobile_Trace_End {
	read -p "Press any key to stop debugs and captures" -n1 anykey

	cp $debug_directory/httpd.conf_old $CVPNDIR/conf/httpd.conf
	cvpnd_admin policy
	cvpnd_admin debug off
	cp $debug_directory/log4php.properties_old $CVPNDIR/phpincs/conf/log4php.properties
	cp $CVPNDIR/log/cvpnd.elg* $debug_directory/
	cp $CVPNDIR/log/httpd.log $debug_directory/
	cp $CVPNDIR/log/httpd.starlog $debug_directory/
	cp -r $CVPNDIR/log/trace_log $debug_directory/
	echo > $CVPNDIR/log/cvpnd.elg
	echo > $CVPNDIR/log/httpd.log
	rm $CVPNDIR/log/cvpnd.elg*
	find $CVPNDIR/log/trace_log -type f -name '*' -exec rm {} \;
}

####################
## SNX Debug Stop ##
####################
function SNX_stop {
	read -p "Press any key to stop debugs and captures" -n1 anykey

	fw ctl debug 0
	vpn debug off
	vpn debug ikeoff
	cvpnd_admin debug off
	
	cp $debug_directory/httpd.conf_old $CVPNDIR/conf/httpd.conf
	
	cvpnd_admin policy
	
	cp $CVPNDIR/log/cvpnd.elg* $debug_directory/
	cp $FWDIR/log/vpnd.elg* $debug_directory/
	cp $CVPNDIR/log/httpd.log* $debug_directory/

	rm $CVPNDIR/log/cvpnd.elg*
	rm $FWDIR/log/vpnd.elg*
	rm $CVPNDIR/log/httpd.log*

	echo > $CVPNDIR/log/cvpnd.elg
	echo > $FWDIR/log/vpnd.elg
	echo > $CVPNDIR/log/httpd.log
	$debug_directory/unlimit
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

#############################
## Archive & Cleanup Basic ##
#############################
function zip_and_clean_Basic {
    date="%Y-%m-%d"
    cd $debug_directory/
    echo "Zipping up files:"
    tar zcvf "$(date '+%F'_'%H-%M-%S')_Basic_archive.tgz" *
    if [[ -f $FWDIR/log/sfwd.elg ]]; then
        # Fake Gaia
        rm fw_mon.pcap tcpdump-* logs.txt ike.elg* ikev2.xmll* sfwd.elg* zdebug.txt
    else 
        # Real Gaia
        rm fw_mon.pcap tcpdump-* logs.txt ike.elg* ikev2.xmll* vpnd.elg* zdebug.txt
    fi
    echo "Please upload $debug_directory/"$(date '+%F'_'%H-%M-%S')_Basic_archive.tgz" to Check Point support for review."
}

#######################################################################
## Archive & Cleanup Light Kernel & Light Kernel with Unified Policy ##
#######################################################################
function zip_and_clean_Kernel {
    cd $debug_directory/
    echo "Zipping up files:"
    tar zcvf "$(date '+%F'_'%H-%M-%S')_Kernel_archive.tgz" *
    if [[ -f $FWDIR/log/sfwd.elg ]]; then
        # Fake Gaia
        rm fw_mon.pcap tcpdump-* logs.txt ike.elg* ikev2.xmll* sfwd.elg* kern.ctl
    else 
        # Real Gaia
        rm fw_mon.pcap tcpdump-* logs.txt ike.elg* ikev2.xmll* vpnd.elg* kern.ctl
    fi
    echo "Please upload $debug_directory/"$(date '+%F'_'%H-%M-%S')_Kernel_archive.tgz" to Check Point support for review."
}

########################################
## Archive & Cleanup Mobile Trace Log ##
########################################
function zip_and_clean_Mobile_Trace {
    cd $debug_directory/
    echo "Zipping up files:"
    tar zcvf "$(date '+%F'_'%H-%M-%S')_Mobile_archive.tgz" *
    rm fw_mon.pcap tcpdump-* logs.txt cvpnd.elg* httpd.starlog* httpd.log log4php.properties_old httpd.conf_old log4php.properties_new httpd.conf_new zdebug.txt
    echo "Please upload $debug_directory/"$(date '+%F'_'%H-%M-%S')_Mobile_archive.tgz" to Check Point support for review."
}

###############################
## Archive & Cleanup SNX Log ##
###############################
function zip_and_clean_SNX {
    cd $debug_directory/
    echo "Zipping up files:"
    tar zcvf "$(date '+%F'_'%H-%M-%S')_SNX_archive.tgz" *
    rm fw_mon.pcap tcpdump-* logs.txt cvpnd.elg* httpd.log httpd.conf_old httpd.conf_new zdebug.txt
    echo "Please upload $debug_directory/"$(date '+%F'_'%H-%M-%S')_SNX_archive.tgz" to Check Point support for review."
}

######################################
## Archive & Cleanup SecureXL Debug ##
######################################
function zip_and_clean_SecureXL {
	cd $debug_directory/
    echo "Zipping up files:"
    tar zcvf "$(date '+%F'_'%H-%M-%S')_SXL_archive.tgz" *
    rm fw_mon.pcap tcpdump-* logs.txt ike.elg* ikev2.xmll* vpnd.elg* kern.ctl
    echo "Please upload $debug_directory/"$(date '+%F'_'%H-%M-%S')_SXL_archive.tgz" to Check Point support for review."
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
	echo "Please choose the debug you would like to run (1-6):"
	echo "1. FW Monitor || IKE || VPND || Packet Captures"
	echo "2. VPN Light Kernel Debug"
	echo "3. VPN Light Kernel Debug with Unified Policy (R80.10+)"
	echo "4. Mobile Access Debug (CVPND Debug)"
	echo "5. SNX Debug (CVPND & VPND Debug)"
	echo "6. SecureXL VPN Debug"
	echo "7. Extended Kernel Debug"
    echo "8. Exit"
	read answer

	case "$answer" in
		1)
		echo "You chose FW Monitor || IKE || VPND || Packet Captures."
		x=1
		;;
		2)
		echo "You chose VPN Light Kernel Debug."
		x=2
		;;
		3)
		echo "You chose VPN Light Kernel with Unified Policy."
		x=3
		;;
		4)
		echo "You chose Mobile Access Debug (CVPND Debug)."
		x=4
		;;
		5)
		echo "You chose SNX Debug (CVPND & VPND Debug)."
		x=5
		;;
		6)
		echo "You chose SecureXL VPN Debug."
		x=6
		;;
		7)
		echo "You chose Extended Kernel Debug"
		x=7
		;;
        8)
        echo "Exiting"
        x=8
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
    Mobile_Trace_Log
    fw_pcaps
    Mobile_Trace_End
    zip_and_clean_Mobile_Trace
    SFTP_Upload

elif [[ "$x" == "5" ]]; then
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
    SNX_start
    fw_pcaps
    SNX_stop
    zip_and_clean_SNX
    SFTP_Upload

elif [[ "$x" == "6" ]]; then
	clear
    check_OS_for_buffer
	    if [[ $whatami == *"Gaia"* ]]; then
    	    echo "OS Name: $whatami"
    	fi
    ask_for_ips
    get_interface_names
    bg_info_gathering
    secureXL_start
    fw_pcaps
    secureXL_stop
    zip_and_clean_SecureXL
    SFTP_Upload
elif [[ "$x" == "7" ]]; then
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
    Kernel_Extended_Start
    fw_pcaps
    fw_kern_stop
    zip_and_clean_Kernel
    SFTP_Upload

elif [[ "$x" == "8" ]]; then
	clear
    exit 1
fi
