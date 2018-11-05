#!/bin/bash

#====================================================================================================
#  Function list
#====================================================================================================


#====================================================================================================
#  Main Script Menu
#====================================================================================================

x=0
while [ $x == 0 ]
do
	clear
	echo "Please choose Blade you would like to Debug (1-4):"
	echo "1. Security (App Control || URL Filtering || DLP || TE)"
	echo "2. VPN (Site to Site || Remote Access || Mobile Access)"
	echo "3. High End (Operating System || ClusterXL || SecureXL)"
	echo "4. Management (Policy Installation)"
	echo "5. Quit"
	read answer

	case "$answer" in
			1)
			echo "You chose Security (App Control || URL Filtering || DLP || TE)."
			x=1
			;;
			2)
			echo "You chose VPN (Site to Site || Remote Access || Mobile Access)."
			x=2
			;;
			3)
			echo "You chose High End (Operating System || ClusterXL || SecureXL)."
			x=3
			;;
			4)
			echo "You chose Management (Policy Installation)."
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
	./Security_Script.sh
elif [[ "$x" == "2" ]]; then
	./VPN_Script.sh
elif [[ "$x" == "3" ]]; then
	./HE_Script.sh
elif [[ "$x" == "4" ]]; then
	./Management_Script.sh
elif [[ "$x" == "5" ]]; then
	clear
	exit 1
fi

	