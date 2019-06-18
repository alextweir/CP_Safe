#!/bin/bash

#====================================================================================================
#  Debug Vairables
#====================================================================================================
debug_directory=/var/log/tmp/debug
logfile=$debug_directory/logs.txt

#====================================================================================================
#  Function list
#====================================================================================================

################################
## SmartEvent Debug R80.x ON  ##
################################
function SmartEvent_On {
	SmartEventSetDebugLevel all trace
	echo "Debug environment is ready, please reproduce the problem."
}

#################################
## SmartEvent Debug R80.x OFF  ##
#################################
function SmartEvent_Off {
	read -p "Press any key to stop debugs and captures" -n1 anykey

	SmartEventSetDebugLevel all info
	SmartEventSetDebugLevel solr warn
	fw debug cpsead off
	fw debug cpsemd off

	SmartEventCollectLogs --full --system_stats

	if [[ -f /var/log/CollectSmartEventLogsOut/AllSmartEvent.out.tar ]]; then
        # file location 1
        cp /var/log/CollectSmartEventLogsOut/AllSmartEvent.out.tar $debug_directory/
    else 
        # file location 2
        cp /var/log/re/AllSmartEvent.out.tar $debug_directory/
    fi
}

#################################
## Archive & Cleanup SmartEvent##
#################################
function zip_and_clean_SE {
    cd $debug_directory/
    echo "Zipping up files:"
    tar zcvf "$(date '+%F'_'%H-%M-%S')_SmartEvent_archive.tgz" *
    rm AllSmartEvent.out.tar
    echo "Please upload $debug_directory/"$(date '+%F'_'%H-%M-%S')_SmartEvent_archive.tgz" to Check Point support for review."
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
#  Main Script
#====================================================================================================

x=0
while [ $x == 0 ]
do
	clear
	echo "Please choose the debug you would like to run (1-6):"
	echo "1. SmartEvent R80.x"
	echo "2. Policy Installation"
	echo "3. CPM Doctor"
	echo "4. Quit"
	read answer

	case "$answer" in
			1)
			echo "You chose SmartEvent R80.x"
			x=1
			;;
			2)
			echo "You chose Policy Installation"
			x=2
			;;
			3)
			echo "You chose CPM Doctor"
			x=3
			;;
			4)
			echo "Exiting"
			x=4
			;;
			*)
			clear
			echo "That is not an option."
			sleep 1
			;;
	esac
done

if [[ "$x" == "1" ]];  then
	clear
	SmartEvent_On
	SmartEvent_Off
	zip_and_clean_SE
	SFTP_Upload
	Final_Cleanup

elif [[ "$x" == "2" ]]; then
	./policy_debug.sh

elif [[ "$x" == "2" ]]; then
	./cpm_doctor.sh

elif [[ "$x" == "6" ]]; then
	clear
    exit 1
fi
