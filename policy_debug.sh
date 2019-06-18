#!/bin/bash
 
# Russell Seifert
# Technology Leader
# Check Point Software Technologies Ltd.
 
###############################################################################
# HELP SCREEN
###############################################################################
HELP_USAGE="Usage: $0 [OPTIONS]
 
Miscellaneous:
   -h    display this help
   -v    version information
   -d    debug this script. a log file named 'script_debug.txt' will be
           created in the current working directory
   -s    disable minimum disk space check
 
Gateway debugging options:
   -b    define the kernel debug buffer
   -f    enable more kernel debug flags
   -k    kernel debug only
   -l    fetchlocal debug only
 
Management debugging options:
   -a    API debug (R80 and up only)
   -m    install to more than one Gateway
"
 
HELP_VERSION="
Policy Installation Debug Script
Version 3.6.3 June 8, 2018
"
 
while getopts ":hvadbfklms" HELP_OPTION; do
                case "$HELP_OPTION" in
                                h) echo "$HELP_USAGE" ; exit ;;
                                a) API_DEBUG_ON=1 ;;
                                b) DEBUG_BUFFER_ON=1 ;;
                                d) set -vx ; exec &> >(tee script_debug.txt) ;;
                                f) MORE_DEBUG_FLAGS=1 ;;
                                k) KERNEL_DEBUG_ONLY=1 ;;
                                l) FETCHLOCAL_DEBUG_ONLY=1 ;;
                                m) MULTIPLE_INSTALL=1 ;;
                                s) SPACE_CHECK_OFF=1 ;;
                                v) echo "$HELP_VERSION" ; exit ;;
                                \?) echo "Invalid option: -$OPTARG" >&2
                                                echo "$HELP_USAGE" >&2 ; exit 1 ;;
                esac
done
shift $(( OPTIND - 1 ))
 
if (( "$#" > "0" )); then
                echo -e "ERROR: Illegal number of parameters\\n$HELP_USAGE"
                exit 1
fi
 
###############################################################################
# INTRODUCTION
###############################################################################
clear
echo -e "\033[1m************************************************"
echo -e "Welcome to the Policy Installation Debug Script"
echo -e "************************************************\\n\033[0m"
echo -e "This script will debug Policy Installation problems"
echo -e "Please answer the following questions if asked\\n"
unset TMOUT
 
###############################################################################
# VERIFY ENVIRONMENT AND IMPORT CHECKPOINT VARIABLES
###############################################################################
if [[ $(uname -s) != "Linux" ]]; then
                echo -e "\\nERROR: This is not running on Linux"
                echo -e "This script is designed to run on a Linux OS"
                echo -e "Please find an alternate method to debug Policy Installation\\n"
                exit 1
fi
 
if [[ -r /etc/profile.d/CP.sh ]]; then
                source /etc/profile.d/CP.sh
elif [[ -r /opt/CPshared/5.0/tmp/.CPprofile.sh ]]; then
                source /opt/CPshared/5.0/tmp/.CPprofile.sh
elif [[ -r $CPDIR/tmp/.CPprofile.sh ]]; then
                source $CPDIR/tmp/.CPprofile.sh
else
                echo -e "\\nERROR: Unable to find \$CPDIR/tmp/.CPprofile.sh"
                echo -e "Verify this file exists and you can read it\\n"
                exit 1
fi
 
###############################################################################
# BASIC VARIABLES
###############################################################################
IS_MGMT=$($CPDIR/bin/cpprod_util FwIsFirewallMgmt 2> /dev/null | sed 's/ *$//')
IS_MDS=$($CPDIR/bin/cpprod_util CPPROD_GetValue PROVIDER-1 IsConfigured 1 2> /dev/null | sed 's/ *$//')
IS_FW=$($CPDIR/bin/cpprod_util FwIsFirewallModule 2> /dev/null | sed 's/ *$//')
IS_VSX=$($CPDIR/bin/cpprod_util FwIsVSX 2> /dev/null | sed 's/ *$//')
IS_SG80=$($CPDIR/bin/cpprod_util CPPROD_GetValue Products SG80 1 2> /dev/null | sed 's/ *$//')
IS_61K=$($CPDIR/bin/cpprod_util CPPROD_GetValue ASG_CHASSIS ChassisID 1 2> /dev/null | sed 's/ *$//')
MAJOR_VERSION=$($CPDIR/bin/cpprod_util CPPROD_GetValue CPshared VersionText 1 2> /dev/null | sed 's/ *$//')
 
ECHO="/bin/echo -e"
SCRIPT_NAME=($(basename $0))
FILES="$SCRIPT_NAME"_files.$$
IP_ADDR=localhost
 
###############################################################################
# VERIFY OPTIONS AND ENVIRONMENT
###############################################################################
if [[ "$IS_VSX" == "1" ]]; then
                if [[ -r /etc/profile.d/vsenv.sh ]]; then
                                source /etc/profile.d/vsenv.sh
                elif [[ -r $FWDIR/scripts/vsenv.sh ]]; then
                                source $FWDIR/scripts/vsenv.sh
                else
                                if (( $($ECHO "${MAJOR_VERSION:1} < 75.40" | bc -l) )); then
                                                $ECHO "\\nERROR: This is a VSX Gateway on a version lower than R75.40VS"
                                                $ECHO "This script is not supported on this version"
                                                $ECHO "Please follow sk84700 to debug Policy Installation\\n"
                                                exit 1
                                else
                                                $ECHO "\\nERROR: Unable to find /etc/profile.d/vsenv.sh or \$FWDIR/scripts/vsenv.sh"
                                                $ECHO "Verify this file exists in either directory and you can read it\\n"
                                                exit 1
                                fi
                fi
fi
 
if [[ "$IS_FW" == "1" && "$IS_MGMT" == "0" ]]; then
                if [[ "$KERNEL_DEBUG_ONLY" == "1" && "$FETCHLOCAL_DEBUG_ONLY" == "1" ]]; then
                                $ECHO "\\nERROR: Can not have both kernel debug only and fetchlocal debug only enabled\\n"
                                exit 1
                fi
 
                if [[ "$MULTIPLE_INSTALL" == "1" ]]; then
                                $ECHO "\\nERROR: Can not enable multiple install on a Gateway\\n"
                                exit 1
                fi
fi
 
if [[ "$IS_MGMT" == "1" && "$IS_FW" == "0" ]]; then
                if [[ "$DEBUG_BUFFER_ON" == "1" ]]; then
                                $ECHO "\\nERROR: Can not define a kernel debug buffer on a Management\\n"
                                exit 1
                fi
 
                if [[ "$MORE_DEBUG_FLAGS" == "1" ]]; then
                                $ECHO "\\nERROR: Can not enable more debug flags on a Management\\n"
                                exit 1
                fi
 
                if [[ "$KERNEL_DEBUG_ONLY" == "1" ]]; then
                                $ECHO "\\nERROR: Can not enable kernel debug only on a Management\\n"
                                exit 1
                fi
 
                if [[ "$FETCHLOCAL_DEBUG_ONLY" == "1" ]]; then
                                $ECHO "\\nERROR: Can not enable fetchlocal debug only on a Management\\n"
                                exit 1
                fi
fi
 
api_running()
{
                JETTY_PID=$(pgrep -f $CPDIR/jetty/start.jar)
                if [[ "$?" != "0" ]]; then
                                return 1
                fi
 
                API_STATUS=$(tail -n 1 $MDS_FWDIR/api/conf/jetty.state | grep STARTED)
                if [[ "$?" != "0" ]]; then
                                return 1
                fi
 
                if [[ -z "$JETTY_PID" || -z "$API_STATUS" ]]; then
                                return 1
                fi
 
                if ! kill -0 "$JETTY_PID" ; then
                                return 1
                fi
 
                return 0
}
 
if [[ "$API_DEBUG_ON" == "1" ]]; then
                if [[ "$IS_FW" == "1" && "$IS_MGMT" == "0" ]]; then
                                $ECHO "\\nERROR: Can not enable API debug on a Gateway\\n"
                                exit 1
                fi
 
                if (( $($ECHO "${MAJOR_VERSION:1} < 80" | bc -l) )); then
                                $ECHO "\\nERROR: Can not have API debug on for a Management lower than R80\\n"
                                exit 1
                fi
 
                if ! api_running ; then
                                $ECHO "\\nERROR: The API server is not running"
                                $ECHO "Run 'api start' and 'api status' to verify the API is running\\n"
                                exit 1
                fi
fi
 
###############################################################################
# SCRIPT LOCK
###############################################################################
SCRIPT_LOCK=/tmp/policy-debug-lock
 
if [[ "$IS_SG80" == "Failed to find the value" ]]; then
                if ! mkdir "$SCRIPT_LOCK" 2> /dev/null ; then
                                SCRIPT_PID=$(ps -ef | grep "$SCRIPT_NAME" | egrep -v "grep|$PPID" | awk '{ print $2 }')
                                SCRIPT_PPID=$(ps -ef | grep "$SCRIPT_NAME" | egrep -v "grep|$PPID" | awk '{ print $3 }')
                                ORIG_PID=0
 
                                for i in $SCRIPT_PID; do
                                                for j in $SCRIPT_PPID; do
                                                                if [[ "$i" == "$j" ]]; then
                                                                                ORIG_PID="$j"
                                                                fi
                                                done
                                done
 
                                if [[ "$ORIG_PID" != "0" ]]; then
                                                $ECHO "\\nERROR: This script is already running with PID: $ORIG_PID\\n"
                                else
                                                $ECHO "\\nERROR: This script might already be running, but can not find its PID"
                                                $ECHO "1. Verify this script is not already running in \"ps -ef\""
                                                $ECHO "2. Remove this script's lock directory $SCRIPT_LOCK"
                                                $ECHO "3. Run this script again\\n"
                                fi
 
                                exit 1
                fi
fi
 
###############################################################################
# CREATE TEMPORARY DIRECTORIES
###############################################################################
if [[ "$IS_SG80" == "Failed to find the value" ]]; then
                if [[ "$SPACE_CHECK_OFF" == "1" ]]; then
                                DBGDIR=/var/log/policy-debug
                                DBGDIR_FILES=/var/log/policy-debug/"$FILES"
                else
                                if (( $(df -P | grep /$ | awk '{ print $4 }') < "2000000" )); then
                                                if (( $(df -P | egrep "/var$|/var/log$" | awk '{ print $4 }') < "2000000" )); then
                                                                $ECHO "\\nERROR: There is not enough disk space available"
                                                                $ECHO "Please follow sk60080 to clear disk space\\n"
                                                                rm -rf "$SCRIPT_LOCK"
                                                                exit 1
                                                else
                                                                # Not enough space in root. Enough in /var/log
                                                                DBGDIR=/var/log/policy-debug
                                                                DBGDIR_FILES=/var/log/policy-debug/"$FILES"
                                                fi
                                else
                                                # Enough space in root
                                                DBGDIR=/tmp/policy-debug
                                                DBGDIR_FILES=/tmp/policy-debug/"$FILES"
                                fi
                fi
else
                if [[ "$SPACE_CHECK_OFF" == "1" ]]; then
                                DBGDIR=/logs/policy-debug
                                DBGDIR_FILES=/logs/policy-debug/"$FILES"
                else
                                if (( $(df | grep "/logs" | awk '{ print $4 }') < "10000" )); then
                                                if (( $(df | grep "/storage" | awk '{ print $4 }') < "10000" )); then
                                                                $ECHO "\\nERROR: There is not enough disk space available"
                                                                $ECHO "Please follow sk60080 to clear disk space\\n"
                                                                rm -rf "$SCRIPT_LOCK"
                                                                exit 1
                                                else
                                                                # Not enough space in /logs. Enough in /storage
                                                                DBGDIR=/storage/tmp/policy-debug
                                                                DBGDIR_FILES=/storage/tmp/policy-debug/"$FILES"
                                                fi
                                else
                                                # Enough space in /logs
                                                DBGDIR=/logs/policy-debug
                                                DBGDIR_FILES=/logs/policy-debug/"$FILES"
                                fi
                fi
fi
 
if [[ ! -d "$DBGDIR_FILES" ]]; then
                mkdir -p "$DBGDIR_FILES"
else
                $ECHO "\\nERROR: $DBGDIR_FILES directory already exists"
                $ECHO "Move or rename this directory then run this script again\\n"
                rm -rf "$SCRIPT_LOCK"
                exit 1
fi
 
OTHER_FILES="$DBGDIR_FILES"/other_files
mkdir -p "$OTHER_FILES"
 
###############################################################################
# PROCESS CLEANUP AND TERMINATION SIGNALS
###############################################################################
if [[ "$IS_SG80" == "Failed to find the value" ]]; then
                interrupted()
                {
                                $ECHO "\\n\\nERROR: Script interrupted, cleaning temporary files..."
 
                                if [[ "$IS_FW" == "1" ]]; then
                                                fw ctl debug 0 - 1> /dev/null
                                fi
 
                                if [[ "$IS_MGMT" == "1" && "$MAJOR_VERSION" == "R80"* ]]; then
                                                if [[ "$QUESTION" == "5" ]]; then
                                                                $MDS_FWDIR/scripts/cpm_debug.sh -t Assign_Global_Policy -s INFO > /dev/null
                                                                $MDS_FWDIR/scripts/cpm_debug.sh -r > /dev/null
                                                fi
                                                unset INTERNAL_POLICY_LOADING
                                                logLevelInstalPolicy_line_info
                                fi
 
                                pkill -P $$
                                rm -rf "$DBGDIR_FILES"
                                rm -rf "$SCRIPT_LOCK"
 
                                $ECHO "Completed\\n"
                                exit 1
                }
                trap interrupted SIGHUP SIGINT SIGTERM # 1 2 15
 
                clean_up()
                {
                                pkill -P $$
                                rm -rf "$DBGDIR_FILES"
                                rm -rf "$SCRIPT_LOCK"
                }
                trap clean_up EXIT # 0
fi
 
###############################################################################
# MONITOR DISK SPACE USAGE
###############################################################################
if [[ "$IS_SG80" == "Failed to find the value" ]]; then
                disk_space_check()
                {
                                while true; do
                                                DISKCHECK=$(df -P $DBGDIR | grep / | awk '{ print $4 }')
                                                if (( "$DISKCHECK" < "500000" )); then
                                                                $ECHO "\\n\\nERROR: Disk space is now less than 500MB. Stopping debug...\\n"
                                                                df -h "$DBGDIR"
                                                                kill -15 $$
                                                fi
                                sleep 10
                                done
                }
                disk_space_check &
fi
 
###############################################################################
# START SCRIPT SESSION LOG
###############################################################################
SESSION_LOG="$DBGDIR_FILES"/session.log
START_DATE=$(/bin/date "+%d %b %Y %H:%M:%S %z")
 
echo_log()
{
                $ECHO "$1" >> "$SESSION_LOG"
}
 
echo_shell_log()
{
                $ECHO "$1" | tee -a "$SESSION_LOG"
}
 
echo_log "$HELP_VERSION"
echo_log "Script Started at $START_DATE\\n"
 
###############################################################################
# LOG DEBUG OPTIONS
###############################################################################
if [[ "$MORE_DEBUG_FLAGS" == "1" ]]; then
                echo_shell_log "\\nINFO: More debug flags is enabled"
fi
 
if [[ "$KERNEL_DEBUG_ONLY" == "1" ]]; then
                echo_shell_log "\\nINFO: Running Gateway kernel debug only"
fi
 
if [[ "$FETCHLOCAL_DEBUG_ONLY" == "1" ]]; then
                echo_shell_log "\\nINFO: Running Gateway fetchlocal debug only"
fi
 
if [[ "$MULTIPLE_INSTALL" == "1" ]]; then
                echo_shell_log "\\nINFO: Install to multiple Gateways is enabled"
fi
 
if [[ "$SPACE_CHECK_OFF" == "1" ]]; then
                echo_shell_log "\\nWARNING: Minimum disk space check is disabled"
fi
 
if [[ "$API_DEBUG_ON" == "1" ]]; then
                echo_shell_log "\\nINFO: API debug is enabled"
fi
 
###############################################################################
# CHANGE TO CMA CONTEXT IF MDS
###############################################################################
change_to_cma()
{
                echo_shell_log "\\nThis is a Multi-Domain Management Server"
                echo_shell_log "\\n--------DOMAINS DETECTED--------\\n"
 
                OBJECT_ARRAY=($($MDSVERUTIL AllCMAs | sort | tee -a "$SESSION_LOG"))
                display_objects "Domains"
 
                while true; do
                                $ECHO "\\nWhat is the number of the Domain you want to debug?"
                                $ECHO -n "(1-${OBJECT_ARRAY_NUMBER_OPTION}): "
                                read CMA_NUMBER
 
                                case "$CMA_NUMBER" in
                                                [1-9]|[1-9][0-9]|[1-9][0-9][0-9])
                                                                CMA_NAME="${OBJECT_ARRAY[$((CMA_NUMBER-1))]}"
                                                                CMA_NAME_EXIST=$($MDSVERUTIL AllCMAs | grep ^"$CMA_NAME"$)
                                                                ;;
                                                *)
                                                                not_valid
                                                                continue ;;
                                esac
 
                                case "$CMA_NAME" in
                                                "")
                                                                not_valid
                                                                continue ;;
 
                                                "$CMA_NAME_EXIST")
                                                                IP_ADDR=$($MDSVERUTIL CMAIp -n $CMA_NAME)
                                                                if [[ "$?" != "0" ]]; then
                                                                                $ECHO "\\nERROR: Could not get the IP address for $CMA_NAME"
                                                                                $ECHO "Verify \$FWDIR/conf/CustomerIP file is not corrupted\\n"
                                                                                clean_up
                                                                                exit 1
                                                                fi
 
                                                                mdsenv "$CMA_NAME"
                                                                DOMAIN_NAME=$($CPDIR/bin/cpprod_util CPPROD_GetValue FW1 CustomerName 1)
                                                                if [[ -z "$DOMAIN_NAME" ]]; then
                                                                                $ECHO "\\nERROR: Could not get the Domain name for $CMA_NAME"
                                                                                $ECHO "Verify $CPDIR/registry/HKLM_registry.data file is not corrupted\\n"
                                                                                clean_up
                                                                                exit 1
                                                                fi
 
                                                                echo_log "\\nSelected CMA: $CMA_NAME"
                                                                echo_log "Domain: $DOMAIN_NAME"
                                                                echo_shell_log ""
                                                                break ;;
                                esac
                done
}
 
###############################################################################
# CHECK FWM STATUS
###############################################################################
smc_fwm_running()
{
                FWM_PID=$(cpwd_admin getpid -name FWM 2> /dev/null)
                if [[ "$?" != "0" ]]; then
                                return 1
                fi
 
                if [[ -z "$FWM_PID" || "$FWM_PID" == "0" ]]; then
                                return 1
                fi
 
                if ! kill -0 "$FWM_PID" ; then
                                return 1
                fi
 
                return 0
}
 
mds_fwm_running()
{
                FWM_WD_PID=$(cpwd_admin getpid -name FWM.$CMA_NAME 2> /dev/null)
                if [[ "$?" != "0" ]]; then
                                $ECHO "\\nERROR: Can not get the PID of FWM for $CMA_NAME"
                                return 1
                fi
 
                if [[ -z "$FWM_WD_PID" || "$FWM_WD_PID" == "0" ]]; then
                                $ECHO "\\nERROR: FWM for $CMA_NAME is not up in cpwd_admin list"
                                return 1
                fi
 
                if ! kill -0 "$FWM_WD_PID" ; then
                                $ECHO "\\nERROR: Can not check that FWM for $CMA_NAME with PID $FWM_WD_PID exists"
                                return 1
                fi
 
                FWM_PS=$(ps aux | grep fwm | grep /$CMA_NAME/ | egrep -v "cma_with_wd|grep")
                if [[ "$?" != "0" ]]; then
                                $ECHO "\\nERROR: FWM is not up for $CMA_NAME in mdsstat"
                                return 1
                fi
 
                FWM_PID=$($ECHO $FWM_PS | awk '{ print $2 }')
 
                if [[ -z "$FWM_PID" || "$FWM_PID" == "0" ]]; then
                                $ECHO "\\nERROR: FWM is not up for $CMA_NAME"
                                $ECHO "Run ps aux and verify there are two FWM processes for $CMA_NAME"
                                return 1
                fi
 
                if ! kill -0 "$FWM_PID" ; then
                                $ECHO "\\nERROR: Can not check that FWM for $CMA_NAME with PID $FWM_PID exists"
                                return 1
                fi
 
                return 0
}
 
check_fwm()
{
                if [[ "$IS_MDS" == "1" ]]; then
                                if ! mds_fwm_running ; then
                                                $ECHO "Verify FWM is up and running\\n"
                                                clean_up
                                                exit 1
                                fi
                else
                                if ! smc_fwm_running ; then
                                                $ECHO "\\nERROR: FWM is not up"
                                                $ECHO "Verify FWM is up and running\\n"
                                                clean_up
                                                exit 1
                                fi
                fi
}
 
###############################################################################
# VERIFY 61K/41K CHASSIS AND BLADE
###############################################################################
verify_61k()
{
                BLADEID=$($CPDIR/bin/cpprod_util CPPROD_GetValue ASG_CHASSIS BladeID 1)
                echo_shell_log "\\nThis is a 61k/41k Gateway"
                read -p "Do you want to run the debug on Chassis $IS_61K Blade $BLADEID? (y/n) [n]? " CORRECT_61K
 
                                case "$CORRECT_61K" in
                                                [yY][eE][sS]|[yY])
                                                                echo_log "Selected: Chassis $IS_61K Blade $BLADEID"
                                                                ;;
                                                *)
                                                                $ECHO "Please change to the correct Chassis and Blade\\n"
                                                                clean_up
                                                                exit 1
                                                                ;;
                                esac
}
 
###############################################################################
# VERIFY VSX CONTEXT
###############################################################################
verify_vsx()
{
                VSID_SCRIPT=$(cat /proc/self/vrf)
                echo_shell_log "\\nThis is a VSX Gateway"
                read -p "Do you want to run the debug on VS $VSID_SCRIPT? (y/n) [n]? " CORRECT_VS
 
                                case "$CORRECT_VS" in
                                                [yY][eE][sS]|[yY])
                                                                echo_log "Selected: VS $VSID_SCRIPT"
                                                                ;;
                                                *)
                                                                $ECHO "Please change to the correct Virtual System\\n"
                                                                clean_up
                                                                exit 1
                                                                ;;
                                esac
 
                vsenv "$VSID_SCRIPT" > /dev/null
}
 
###############################################################################
# VERIFY KERNEL DEBUG BUFFER
###############################################################################
verify_buffer()
{
                if [[ "$DEBUG_BUFFER_ON" == "1" ]]; then
                                while true; do
                                                $ECHO "\\nWhat size in kilobytes do you want the kernel debug buffer? [4000-32768]"
                                                read DEBUG_BUFFER
 
                                                case "$DEBUG_BUFFER" in
                                                                [4-9][0-9][0-9][0-9]|[1-9][0-9][0-9][0-9][0-9])
                                                                                if (( "$DEBUG_BUFFER" < 16384 )); then
                                                                                                $ECHO "\\nINFO: The kernel debug buffer is defined less than 16384"
                                                                                                $ECHO "The debug may not show the error with a buffer of $DEBUG_BUFFER"
                                                                                                read -p "Do you want to continue running the debug? (y/n) [n]? " LOW_BUFFER
 
                                                                                                case "$LOW_BUFFER" in
                                                                                                                [yY][eE][sS]|[yY])
                                                                                                                                ;;
                                                                                                                *)
                                                                                                                                $ECHO "\\nPlease define a larger buffer"
                                                                                                                                exit_if_needed
                                                                                                                                continue
                                                                                                                                ;;
                                                                                                esac
                                                                                fi
 
                                                                                if (( "$DEBUG_BUFFER" > 32768 )); then
                                                                                                $ECHO "\\nERROR: Kernel debug buffer can only be up to 32768"
                                                                                                $ECHO "Please define a valid buffer between 4000-32768"
                                                                                                exit_if_needed
                                                                                                continue
                                                                                fi
 
                                                                                VMALLOC_TOTAL=$(cat /proc/meminfo | grep "VmallocTotal" | awk '{ print $2 }')
                                                                                VMALLOC_USED=$(cat /proc/meminfo | grep "VmallocUsed" | awk '{ print $2 }')
                                                                                VMALLOC_CHUNK=$(cat /proc/meminfo | grep "VmallocChunk" | awk '{ print $2 }')
                                                                                VMALLOC_FREE=$(( $VMALLOC_TOTAL - $VMALLOC_USED ))
 
                                                                                if (( "$VMALLOC_FREE" < "$DEBUG_BUFFER" )) || (( "$VMALLOC_CHUNK" < "$DEBUG_BUFFER" )); then
                                                                                                $ECHO "\\nERROR: Not enough kernel debug buffer free to allocate $DEBUG_BUFFER"
                                                                                                $ECHO "Available buffer: $VMALLOC_FREE kB"
                                                                                                $ECHO "Please define a smaller kernel debug buffer"
                                                                                                $ECHO "Or follow sk84700 to increase the Vmalloc"
                                                                                                exit_if_needed
                                                                                                continue
                                                                                fi
 
                                                                                echo_shell_log "\\nKernel debug buffer set to $DEBUG_BUFFER\\n"
                                                                                break
                                                                                ;;
                                                                *)
                                                                                $ECHO "\\nERROR: Kernel debug buffer defined is not valid"
                                                                                $ECHO "Use only numbers and must be between 4000-32768"
                                                                                exit_if_needed
                                                                                continue
                                                                                ;;
                                                esac
                                done
                else
                                DEBUG_BUFFER=32000
                                VMALLOC_TOTAL=$(cat /proc/meminfo | grep "VmallocTotal" | awk '{ print $2 }')
                                VMALLOC_USED=$(cat /proc/meminfo | grep "VmallocUsed" | awk '{ print $2 }')
                                VMALLOC_CHUNK=$(cat /proc/meminfo | grep "VmallocChunk" | awk '{ print $2 }')
                                VMALLOC_FREE=$(( $VMALLOC_TOTAL - $VMALLOC_USED ))
 
                                if (( "$VMALLOC_FREE" < "$DEBUG_BUFFER" )) || (( "$VMALLOC_CHUNK" < "$DEBUG_BUFFER" )); then
                                                $ECHO "\\nERROR: Not enough kernel debug buffer free to allocate $DEBUG_BUFFER"
                                                $ECHO "Available buffer: $VMALLOC_CHUNK kB"
                                                $ECHO "Follow sk84700 to increase the Vmalloc"
                                                $ECHO "Or run this script again and define a smaller buffer"
                                                $ECHO "./$SCRIPT_NAME -b\\n"
                                                clean_up
                                                exit 1
                                fi
                fi
}
 
kernel_memory_used()
{
                $ECHO "\\nERROR: Failed to allocate kernel debug buffer of $DEBUG_BUFFER"
                $ECHO "Follow sk101875 Scenario 2 or sk84700 to increase the Vmalloc\\n"
}
 
###############################################################################
# ASK USER WHAT TO DEBUG
###############################################################################
debug_mgmt_or_fw()
{
                echo_shell_log "\\nThis is a Standalone Server"
                echo_shell_log "\\n--------DEBUGS AVAILABLE--------\\n"
 
                echo_shell_log "1. Management"
                echo_shell_log "2. Gateway (load on module failed / installation failed on gateway)\\n"
 
                while true; do
                                $ECHO "Which option do you want to debug?"
                                $ECHO -n "(1-2): "
                                read STAND_DEBUG
 
                                case "$STAND_DEBUG" in
                                                [1-2])
                                                                $ECHO ""
                                                                echo_log "Selected: $STAND_DEBUG"
                                                                break ;;
                                                *)
                                                                not_valid
                                                                continue ;;
                                esac
                done
}
 
what_to_debug()
{
                echo_shell_log "\\n--------DEBUGS AVAILABLE--------\\n"
 
                echo_shell_log "1. Database Installation"
                echo_shell_log "2. Policy Verification"
                echo_shell_log "3. Policy Installation"
                echo_shell_log "4. Slow Policy Install"
 
                if [[ "$IS_MDS" == "1" ]]; then
                                echo_shell_log "5. Assign Global Policy"
                fi
 
                while true; do
                                $ECHO "\\nWhich option do you want to debug?"
 
                                if [[ "$IS_MDS" == "1" ]]; then
                                                $ECHO -n "(1-5): "
                                else
                                                $ECHO -n "(1-4): "
                                fi
 
                                read QUESTION
 
                                if [[ "$IS_MDS" == "1" ]]; then
                                                case "$QUESTION" in
                                                                [1-5])
                                                                                echo_log "\\nSelected: $QUESTION"
                                                                                break ;;
                                                                *)
                                                                                not_valid
                                                                                continue ;;
                                                esac
                                else
                                                case "$QUESTION" in
                                                                [1-4])
                                                                                echo_log "\\nSelected: $QUESTION"
                                                                                break ;;
                                                                *)
                                                                                not_valid
                                                                                continue ;;
                                                esac
                                fi
                done
}
 
which_fw_policy()
{
                echo_shell_log "\\n\\n--------POLICY DEBUGS AVAILABLE--------\\n"
                echo_shell_log "1. Network Security / Access Control"
                echo_shell_log "2. Threat Prevention"
 
                if [[ "$IS_FW" == "0" && "$API_DEBUG_ON" != "1" ]]; then
                                echo_shell_log "3. QoS"
                                echo_shell_log "4. Desktop Security"
                fi
 
                while true; do
                                $ECHO "\\nWhich policy do you want to debug?"
 
                                if [[ "$IS_FW" == "0" && "$API_DEBUG_ON" != "1" ]]; then
                                                $ECHO -n "(1-4): "
                                else
                                                $ECHO -n "(1-2): "
                                fi
 
                                read WHICH_POLICY
 
                                if [[ "$IS_FW" == "0" && "$API_DEBUG_ON" != "1" ]]; then
                                                case "$WHICH_POLICY" in
                                                                [1-4])
                                                                                echo_log "\\nSelected: $WHICH_POLICY"
                                                                                break ;;
                                                                *)
                                                                                not_valid
                                                                                continue ;;
                                                esac
                                else
                                                case "$WHICH_POLICY" in
                                                                [1-2])
                                                                                echo_log "\\nSelected: $WHICH_POLICY"
                                                                                break ;;
                                                                *)
                                                                                not_valid
                                                                                continue ;;
                                                esac
                                fi
                done
}
 
exit_if_needed()
{
                $ECHO "Press CTRL-C to exit the script if needed"
}
 
not_valid()
{
                $ECHO "\\nERROR: Selection is not valid"
                exit_if_needed
}
 
###############################################################################
# MULTIPLE INSTALL
###############################################################################
MI_ARRAY=""
MI_ARRAY_CHECK=()
MI_COUNT=1
 
mi_options()
{
                # Show selected Gateways
                if [[ "$OBJECT_NUMBER" == "$OBJECT_ARRAY_LIST" ]]; then
                                if [[ -z "$MI_ARRAY" ]]; then
                                                $ECHO "No $1 selected"
                                else
                                                MI_CURRENT=$($ECHO ${MI_ARRAY[@]} | sed 's/targets.[0-9]*//g')
                                fi
 
                                return 1
                fi
 
                # Done adding Gateways
                if [[ "$OBJECT_NUMBER" == "$((OBJECT_ARRAY_LIST + 1))" ]]; then
                                if [[ -z "$MI_ARRAY" ]]; then
                                                $ECHO "No $1 selected. Can not install to nothing"
                                                return 1
                                else
                                                MI_DONE=$($ECHO ${MI_ARRAY[@]} | sed 's/targets.[0-9]*//g')
                                                return 2
                                fi
                fi
 
                return 0
}
 
in_mi_array_check()
{
                MI_CHECK_COUNT=0
 
                for MI_GW in ${MI_ARRAY_CHECK[@]}; do
                                if [[ "$MI_GW" == "$OBJECT_NAME" ]]; then
                                                let "MI_CHECK_COUNT += 1"
                                fi
                done
 
                if (( $MI_CHECK_COUNT > 1 )); then
                                return 0
                fi
 
                return 1
}
 
multiple_install()
{
                MI_ARRAY_CHECK+=($OBJECT_NAME)
 
                if in_mi_array_check ; then
                                $ECHO "Already selected $OBJECT_NAME"
                                return 1
                fi
 
                if [[ "$API_DEBUG_ON" == "1" ]]; then
                                MI_ARRAY="$MI_ARRAY targets.${MI_COUNT} $OBJECT_NAME"
                                let "MI_COUNT += 1"
                else
                                MI_ARRAY="$MI_ARRAY $OBJECT_NAME"
                fi
 
                $ECHO "Added: $OBJECT_NAME"
}
 
###############################################################################
# API INSTALL
###############################################################################
API_JSON_FILE="$DBGDIR_FILES"/api_run_results
API_ID_FILE="$DBGDIR_FILES"/api_id
API_TASK_RESULTS="$DBGDIR_FILES"/api_task_results.txt
 
api_debug_sess_desc()
{
                case "$QUESTION" in
                                2)
                                                SESSION_DESC="Verifying Policy $POLICY_NAME"
                                                ;;
                                3)
                                                if [[ "$WHICH_POLICY" == "1" ]]; then
                                                                if [[ "$MULTIPLE_INSTALL" == "1" ]]; then
                                                                                SESSION_DESC="Installing Access Control Policy $POLICY_NAME to $MI_DONE"
                                                                else
                                                                                SESSION_DESC="Installing Access Control Policy $POLICY_NAME to $GATEWAY_NAME"
                                                                fi
                                                elif [[ "$WHICH_POLICY" == "2" ]]; then
                                                                if [[ "$MULTIPLE_INSTALL" == "1" ]]; then
                                                                                SESSION_DESC="Installing Threat Prevention Policy $POLICY_NAME to $MI_DONE"
                                                                else
                                                                                SESSION_DESC="Installing Threat Prevention Policy $POLICY_NAME to $GATEWAY_NAME"
                                                                fi
                                                fi
                                                ;;
                                5)
                                                SESSION_DESC="Reassigning Global Policy to $DOMAIN_NAME"
                                                ;;
                esac
}
 
api_debug_login()
{
                api_debug_sess_desc
 
                if [[ "$IS_MDS" == "1" && "$QUESTION" != "5" ]]; then
                                MGMT_CLI_LOGIN=$(mgmt_cli login domain "$DOMAIN_NAME" session-name "Policy Installation Debug Script" session-description "$SESSION_DESC" -r true -f json > "$API_ID_FILE" 2> /dev/null)
                else
                                MGMT_CLI_LOGIN=$(mgmt_cli login session-name "Policy Installation Debug Script" session-description "$SESSION_DESC" -r true -f json > "$API_ID_FILE" 2> /dev/null)
                fi
 
                if [[ "$?" != "0" ]]; then
                                $ECHO "\\nERROR: Can not login to the API\\n"
                                clean_up
                                exit 1
                fi
}
 
api_debug_logout()
{
                mgmt_cli logout -s "$API_ID_FILE" &> /dev/null
 
                if [[ "$?" != "0" ]]; then
                                $ECHO "\\nERROR: Failed to logout of the API\\n"
                fi
}
 
api_debug_starting()
{
                for UNSET_MGMTCLI in $(env | grep MGMT_CLI_ | cut -f1 -d"="); do
                                unset "$UNSET_MGMTCLI"
                done

                $ECHO "Logging into the API..."
 
                api_debug_login
}
 
api_debug_valid()
{
                if [[ "$MGMT_CLI_RUN_RET" != "0" ]]; then
                                $ECHO -n "\\nERROR: "
                                jq -r '."message"' "$API_JSON_FILE"
                                $ECHO ""
                                clean_up
                                exit 1
                fi
}
 
api_debug_setup()
{
                api_debug_valid
 
                if [[ "$QUESTION" == "5" ]]; then
                                TASK_ID=$(jq -r '.tasks[]."task-id"' $API_JSON_FILE)
                else
                                TASK_ID=$(jq -r '."task-id"' $API_JSON_FILE)
                fi
 
                echo_shell_log "\\nAPI Task ID is $TASK_ID\\n"
 
                MI_INSTALL_TO=$($ECHO ${GATEWAY_NAME[@]} | sed 's/targets.[0-9]*//g')
 
                if [[ "$API_POLICY_TYPE" == "access" ]]; then
                                echo_shell_log "Installing Access Control Policy $POLICY_NAME to $MI_INSTALL_TO\\n"
                elif [[ "$API_POLICY_TYPE" == "threat-prevention" ]]; then
                                echo_shell_log "Installing Threat Prevention Policy $POLICY_NAME to $MI_INSTALL_TO\\n"
                fi
}
 
api_debug()
{
                api_debug_setup
 
                while true; do
                                TASK_INFO=$(mgmt_cli show task task-id "$TASK_ID" -s "$API_ID_FILE" -f json | jq -r '.tasks[] | [."task-name" , .status , ."progress-percentage"] | @csv')
                                TASK_NAME=$($ECHO $TASK_INFO | awk -F "," '{ print $1 }' | sed 's/"//g')
                                TASK_STATUS=$($ECHO $TASK_INFO | awk -F "," '{ print $2 }' | sed 's/"//g')
                                TASK_PERCENT=$($ECHO $TASK_INFO | awk -F "," '{ print $3 }')
 
                                if [[ "$TASK_PERCENT" == "100" ]]; then
                                                break
                                else
                                                $ECHO "$TASK_NAME  $TASK_STATUS  (${TASK_PERCENT}%)"
                                                sleep 10
                                                continue
                                fi
                done
 
                echo_shell_log "$TASK_NAME  $TASK_STATUS  (${TASK_PERCENT}%)"
                TASK_MESSAGE=$(mgmt_cli show task task-id "$TASK_ID" details-level full -s $API_ID_FILE &> "$API_TASK_RESULTS")
}
 
###############################################################################
# SELECTION OF POLICY/MGMT/GW
###############################################################################
display_objects()
{
                if [[ -f "$QDB_ERR" ]]; then
                                if [[ $(cat "$QDB_ERR" | sed 's/^ *//' | sed 's/ *$//') == "Failed to bind to local server" ]]; then
                                                $ECHO "\\nERROR: Failed to find any $1"
                                                $ECHO "The license may not be valid\\n"
                                                clean_up
                                                exit 1
                                else
                                                rm -rf "$QDB_ERR"
                                fi
                fi
 
                if [[ -z "$OBJECT_ARRAY" ]]; then
                                $ECHO "\\nERROR: There are no $1 detected"
                                $ECHO "Verify there are $1 in the SmartConsole\\n"
                                clean_up
                                exit 1
                fi
 
                OBJECT_ARRAY_NUMBER=$(printf '%s\n' "${OBJECT_ARRAY[@]}" | wc -l | awk '{ print $1 }')
                OBJECT_ARRAY_NUMBER_OPTION="$OBJECT_ARRAY_NUMBER"
 
                for (( OBJECT_ARRAY_LIST = 1; "$OBJECT_ARRAY_NUMBER" > 0; OBJECT_ARRAY_LIST++ )); do
                                $ECHO "${OBJECT_ARRAY_LIST}. ${OBJECT_ARRAY[$((OBJECT_ARRAY_LIST - 1))]}"
                                let "OBJECT_ARRAY_NUMBER -= 1"
                done
 
                if [[ "$MULTIPLE_INSTALL" == "1" && "$1" == "Gateways" ]]; then
                                $ECHO "\\n${OBJECT_ARRAY_LIST}. Show selected $1"
                                $ECHO "$((OBJECT_ARRAY_LIST + 1)). Done adding $1"
                fi
}
 
select_object()
{
                while true; do
                                $ECHO "\\nWhat is the number of the $1 to debug?"
 
                                if [[ "$MULTIPLE_INSTALL" == "1" && "$1" == "Gateway/Cluster" ]]; then
                                                $ECHO -n "(1-$((OBJECT_ARRAY_LIST + 1))): "
                                else
                                                $ECHO -n "(1-${OBJECT_ARRAY_NUMBER_OPTION}): "
                                fi
 
                                read OBJECT_NUMBER
 
                                if [[ "$MULTIPLE_INSTALL" == "1" ]]; then
                                                mi_options $1
                                                MI_OPTIONS_RET="$?"
 
                                                if [[ "$MI_OPTIONS_RET" == "1" ]]; then
                                                                $ECHO "Currently selected: $MI_CURRENT"
                                                                continue
                                                elif [[ "$MI_OPTIONS_RET" == "2" ]]; then
                                                                $ECHO "Selected: $MI_DONE"
                                                                echo_log "\\nSelected: $MI_DONE"
                                                                break
                                                fi
                                fi
 
                                case "$OBJECT_NUMBER" in
                                                [1-9]|[1-9][0-9]|[1-9][0-9][0-9])
                                                                OBJECT_NAME="${OBJECT_ARRAY[$((OBJECT_NUMBER - 1))]}"
 
                                                                if [[ "$1" == "Policy" ]]; then
                                                                                OBJECT_NAME_EXIST=$($ECHO "$IP_ADDR\n-t policies_collections -a\n-q\n" | queryDB_util | awk '/Object Name:/ { print $3 }' | grep ^"$OBJECT_NAME"$)
 
                                                                elif [[ "$1" == "Global Policy" ]]; then
                                                                                OBJECT_NAME_EXIST=$(cpmiquerybin attr "" policies_collections "" -a __name__ | grep -v "No Global Policy" | sed 's/[[:blank:]]*$//' | grep ^"$OBJECT_NAME"$)
 
                                                                elif [[ "$1" == "Management" ]]; then
                                                                                OBJECT_NAME_EXIST=$($ECHO "$IP_ADDR\n-t network_objects -s management='true' -s log_server='true'\n-q\n" | queryDB_util | awk '/Object Name:/ { print $3 }' | grep ^"$OBJECT_NAME"$)
 
                                                                elif [[ "$1" == "Gateway/Cluster" ]]; then
                                                                                OBJECT_NAME_EXIST=$($ECHO "$IP_ADDR\n-t network_objects -s firewall='installed'\n-q\n" | queryDB_util | awk '/Object Name:/ { print $3 }' | grep ^"$OBJECT_NAME"$)
                                                                fi
                                                                ;;
                                                *)
                                                                not_valid
                                                                continue ;;
                                esac
 
                                case "$OBJECT_NAME" in
                                                "")
                                                                not_valid
                                                                continue ;;

                                                "$OBJECT_NAME_EXIST")
                                                                if [[ "$MULTIPLE_INSTALL" == "1" && "$1" == "Gateway/Cluster" ]]; then
                                                                                multiple_install
                                                                                continue
                                                                else
                                                                                $ECHO "Selected: $OBJECT_NAME"
                                                                                echo_log "\\nSelected: $OBJECT_NAME"
                                                                                break
                                                                fi
                                esac
                done
}
 
###############################################################################
# DETECTION OF POLICY/MGMT/GW
###############################################################################
QDB_ERR="$DBGDIR_FILES"/qdb_err
 
policy_detect()
{
                echo_shell_log "\\n\\n--------POLICIES DETECTED--------\\n"
 
                OBJECT_ARRAY=($($ECHO "$IP_ADDR\n-t policies_collections -a\n-q\n" | queryDB_util 2> "$QDB_ERR" | awk '/Object Name:/ { print $3 }' | tee -a "$SESSION_LOG"))
 
                display_objects "Policies"
                select_object "Policy"
 
                POLICY_NAME="$OBJECT_NAME"
}
 
global_policy_detect()
{
                echo_shell_log "\\n\\n--------GLOBAL POLICIES DETECTED--------\\n"
 
                mdsenv
                OBJECT_ARRAY=($(cpmiquerybin attr "" policies_collections "" -a __name__ | grep -v "No Global Policy" | sort | tee -a "$SESSION_LOG"))
 
                display_objects "Global Policies"
                select_object "Global Policy"
 
                GLOBAL_POLICY_NAME="$OBJECT_NAME"
}
 
mgmt_detect()
{
                echo_shell_log "\\n\\n--------MANAGEMENTS DETECTED--------\\n"
 
                OBJECT_ARRAY=($($ECHO "$IP_ADDR\n-t network_objects -s management='true' -s log_server='true'\n-q\n" | queryDB_util 2> "$QDB_ERR" | awk '/Object Name:/ { print $3 }' | tee -a "$SESSION_LOG"))
 
                display_objects "Management servers"
                select_object "Management"
 
                MGMT_NAME="$OBJECT_NAME"
}
 
gateway_detect()
{
                echo_shell_log "\\n\\n--------GATEWAYS DETECTED--------\\n"
 
                # NETWORK SECURITY
                if [[ "$1" == "1" ]]; then
                                OBJECT_ARRAY=($($ECHO "$IP_ADDR\n-t network_objects -s firewall='installed'\n-q\n" | queryDB_util | awk '/Object Name:/ { print $3 }' | tee -a "$SESSION_LOG"))
 
                # THREAT PREVENTION
                elif [[ "$1" == "2" ]]; then
                                $ECHO -n "Detecting..."
                                THREAT_GATEWAY_FILE="$DBGDIR_FILES"/tp.txt
 
                                THREAT_AMW=($($ECHO "$IP_ADDR\n-t network_objects -s firewall='installed' -s anti_malware_blade='installed'\n-q\n" | queryDB_util | awk '/Object Name:/ { print $3 }' >> "$THREAT_GATEWAY_FILE"))
                                THREAT_AV=($($ECHO "$IP_ADDR\n-t network_objects -s firewall='installed' -s anti_virus_blade='installed'\n-q\n" | queryDB_util | awk '/Object Name:/ { print $3 }' >> "$THREAT_GATEWAY_FILE"))
                                THREAT_EX=($($ECHO "$IP_ADDR\n-t network_objects -s firewall='installed' -s scrubbing_blade='installed'\n-q\n" | queryDB_util | awk '/Object Name:/ { print $3 }' >> "$THREAT_GATEWAY_FILE"))
                                THREAT_EM=($($ECHO "$IP_ADDR\n-t network_objects -s firewall='installed' -s threat_emulation_blade='installed'\n-q\n" | queryDB_util | awk '/Object Name:/ { print $3 }' >> "$THREAT_GATEWAY_FILE"))
                                THREAT_IPS=($($ECHO "$IP_ADDR\n-t network_objects -s firewall='installed' -s ips_blade='installed'\n-q\n" | queryDB_util | awk '/Object Name:/ { print $3 }' >> "$THREAT_GATEWAY_FILE"))
                                OBJECT_ARRAY=($(cat "$THREAT_GATEWAY_FILE" | sort -u | tee -a "$SESSION_LOG"))
 
                                rm "$THREAT_GATEWAY_FILE"
                                $ECHO -n "\b\b\b\b\b\b\b\b\b\b\b\b"
 
                # QoS
                elif [[ "$1" == "3" ]]; then
                                OBJECT_ARRAY=($($ECHO "$IP_ADDR\n-t network_objects -s floodgate='installed'\n-q\n" | queryDB_util | awk '/Object Name:/ { print $3 }' | tee -a "$SESSION_LOG"))
 
                # DESKTOP SECURITY
                elif [[ "$1" == "4" ]]; then
                                OBJECT_ARRAY=($($ECHO "$IP_ADDR\n-t network_objects -s policy_server='installed'\n-q\n" | queryDB_util | awk '/Object Name:/ { print $3 }' | tee -a "$SESSION_LOG"))
                fi
 
                display_objects "Gateways"
                select_object "Gateway/Cluster"
 
                if [[ "$MULTIPLE_INSTALL" == "1" ]]; then
                                GATEWAY_NAME="$MI_ARRAY"
                                if [[ "$API_DEBUG_ON" == "1" ]]; then
                                                GATEWAY_NAME=$($ECHO $GATEWAY_NAME | sed 's/^targets.1//')
                                fi
                else
                                GATEWAY_NAME="$OBJECT_NAME"
                fi
}
 
###############################################################################
# FUNCTIONS FOR MAIN DEBUG
###############################################################################
starting_mgmt_debug()
{
                echo_shell_log "\\n\\n--------STARTING DEBUG--------\\n"
                DEBUG_DATE=$(/bin/date "+%d %b %Y %H:%M:%S %z")
                echo_log "Debug Started at $DEBUG_DATE"
}
 
starting_fw_debug()
{
                if [[ "$IS_61K" != "Failed to find the value" ]]; then
                                if [[ "$IS_VSX" == "1" ]]; then
                                                echo_shell_log "\\n\\n----STARTING DEBUG ON CHASSIS $IS_61K BLADE $BLADEID VS ${VSID_SCRIPT}----\\n"
                                else
                                                echo_shell_log "\\n\\n----STARTING DEBUG ON CHASSIS $IS_61K BLADE $BLADEID----\\n"
                                fi
 
                elif [[ "$IS_VSX" == "1" ]]; then
                                echo_shell_log "\\n\\n----STARTING DEBUG ON VS ${VSID_SCRIPT}----\\n"
                else
                                echo_shell_log "\\n----STARTING DEBUG----\\n"
                fi
 
                $ECHO "Turning debug on..."
 
                DEBUG_DATE=$(/bin/date "+%d %b %Y %H:%M:%S %z")
                echo_log "Debug Started at $DEBUG_DATE"
                echo_log "\\nRunning:"
}
 
progress_bar()
{
                PB_CHARS=( "-" "\\" "|" "/" )
                PB_COUNT=0
                PB_PID=$!
 
                while [ -d /proc/"$PB_PID" ]; do
                                PB_POS=$(( $PB_COUNT % 4 ))
                                $ECHO -n "\b${PB_CHARS[$PB_POS]}"
                                PB_COUNT=$(( $PB_COUNT + 1 ))
                                sleep 1
                done
}
 
logLevelInstalPolicy_line_debug()
{
                cp -p $MDS_FWDIR/conf/tdlog.cpm $MDS_FWDIR/conf/tdlog.cpm_ORIGINAL
                sed -i 's/{basicConversionPattern}/{extendedConversionPattern}/g' $MDS_FWDIR/conf/tdlog.cpm
                sed -i 's/logLevelInstalPolicy=info/logLevelInstalPolicy=debug/g' $MDS_FWDIR/conf/tdlog.cpm
}
 
logLevelInstalPolicy_line_info()
{
                if [[ -f "$MDS_FWDIR/conf/tdlog.cpm_ORIGINAL" ]]; then
                                mv $MDS_FWDIR/conf/tdlog.cpm_ORIGINAL $MDS_FWDIR/conf/tdlog.cpm
                else
                                sed -i 's/{extendedConversionPattern}/{basicConversionPattern}/g' $MDS_FWDIR/conf/tdlog.cpm
                                sed -i 's/logLevelInstalPolicy=debug/logLevelInstalPolicy=info/g' $MDS_FWDIR/conf/tdlog.cpm
                fi
}
 
export_internal_policy_r80()
{
                if [[ "$API_DEBUG_ON" != "1" ]]; then
                                echo_log "export INTERNAL_POLICY_LOADING=1"
                                export INTERNAL_POLICY_LOADING=1
                fi
 
                logLevelInstalPolicy_line_debug
}
 
export_tderror_debug()
{
                echo_log "\\nRunning:"
 
                if [[ "$MAJOR_VERSION" == "R80"* ]]; then
                                export_internal_policy_r80
                fi
}
 
###############################################################################
# MAIN DEBUG MGMT
###############################################################################
mgmt_database()
{
                mgmt_detect
                starting_mgmt_debug
 
                export_tderror_debug
                echo_log "TDERROR_ALL_ALL=5 fwm dbload $MGMT_NAME &> install_database_debug.txt"
 
                $ECHO -n "Installing Database to $MGMT_NAME   "
                TDERROR_ALL_ALL=5 fwm dbload "$MGMT_NAME" &> "$DBGDIR_FILES"/install_database_debug.txt &
                progress_bar
}
 
mgmt_verify()
{
                policy_detect
                starting_mgmt_debug
 
                export_tderror_debug
 
                if [[ "$API_DEBUG_ON" == "1" ]]; then
                                api_debug_starting
                                echo_log "mgmt_cli verify-policy policy-package $POLICY_NAME"
 
                                MGMT_CLI_RUN=$(mgmt_cli verify-policy policy-package "$POLICY_NAME" -s $API_ID_FILE --sync false -f json > $API_JSON_FILE)
                                MGMT_CLI_RUN_RET="$?"
                                api_debug
                else
                                echo_log "TDERROR_ALL_ALL=5 fwm verify $POLICY_NAME &> policy_verify_debug.txt"
 
                                $ECHO -n "Verifying $POLICY_NAME Policy   "
                                TDERROR_ALL_ALL=5 fwm verify "$POLICY_NAME" &> "$DBGDIR_FILES"/policy_verify_debug.txt &
                                progress_bar
                fi
}
 
mgmt_install()
{
                which_fw_policy
                policy_detect
 
                if [[ "$WHICH_POLICY" == "1" ]]; then
                                gateway_detect "1"
                                starting_mgmt_debug
 
                                export_tderror_debug
 
                                if [[ "$API_DEBUG_ON" == "1" ]]; then
                                                api_debug_starting
                                                echo_log "mgmt_cli install-policy policy-package $POLICY_NAME access true threat-prevention false targets.1 $GATEWAY_NAME"
 
                                                MGMT_CLI_RUN=$(mgmt_cli install-policy policy-package "$POLICY_NAME" access true threat-prevention false targets.1 $GATEWAY_NAME -s $API_ID_FILE --sync false -f json > $API_JSON_FILE)
                                                MGMT_CLI_RUN_RET="$?"
                                                api_debug
                                else
                                                echo_log "TDERROR_ALL_ALL=5 fwm load $POLICY_NAME $GATEWAY_NAME &> security_policy_install_debug.txt"

                                                $ECHO -n "Installing Security Policy $POLICY_NAME to $GATEWAY_NAME   "
                                                TDERROR_ALL_ALL=5 fwm load "$POLICY_NAME" $GATEWAY_NAME &> "$DBGDIR_FILES"/security_policy_install_debug.txt &
                                                progress_bar
                                fi
 
                elif [[ "$WHICH_POLICY" == "2" ]]; then
                                gateway_detect "2"
                                starting_mgmt_debug
 
                                export_tderror_debug
 
                                if [[ "$API_DEBUG_ON" == "1" ]]; then
                                                api_debug_starting
                                                echo_log "mgmt_cli install-policy policy-package $POLICY_NAME access false threat-prevention true targets.1 $GATEWAY_NAME"
 
                                                MGMT_CLI_RUN=$(mgmt_cli install-policy policy-package "$POLICY_NAME" access false threat-prevention true targets.1 $GATEWAY_NAME -s $API_ID_FILE --sync false -f json > $API_JSON_FILE)
                                                MGMT_CLI_RUN_RET="$?"
                                                api_debug
                                else
                                                echo_log "TDERROR_ALL_ALL=5 fwm load -p threatprevention $POLICY_NAME $GATEWAY_NAME &> threat_prevention_policy_install_debug.txt"
 
                                                $ECHO -n "Installing Threat Prevention Policy $POLICY_NAME to $GATEWAY_NAME   "
                                                TDERROR_ALL_ALL=5 fwm load -p threatprevention "$POLICY_NAME" $GATEWAY_NAME &> "$DBGDIR_FILES"/threat_prevention_policy_install_debug.txt &
                                                progress_bar
                                fi
 
                elif [[ "$WHICH_POLICY" == "3" ]]; then
                                gateway_detect "3"
                                starting_mgmt_debug
 
                                export_tderror_debug
                                echo_log "TDERROR_ALL_ALL=5 fgate load ${POLICY_NAME}.F $GATEWAY_NAME &> qos_policy_install_debug.txt"
 
                                $ECHO -n "Installing QoS Policy $POLICY_NAME to $GATEWAY_NAME   "
                                TDERROR_ALL_ALL=5 fgate load "${POLICY_NAME}.F" $GATEWAY_NAME &> "$DBGDIR_FILES"/qos_policy_install_debug.txt &
                                progress_bar
 
                elif [[ "$WHICH_POLICY" == "4" ]]; then
                                gateway_detect "4"
                                starting_mgmt_debug
 
                                export_tderror_debug
                                echo_log "TDERROR_ALL_ALL=5 fwm psload $FWDIR/conf/${POLICY_NAME}.S $GATEWAY_NAME &> desktop_policy_install_debug.txt"
 
                                $ECHO -n "Installing Desktop Security Policy $POLICY_NAME to $GATEWAY_NAME   "
                                TDERROR_ALL_ALL=5 fwm psload "$FWDIR/conf/${POLICY_NAME}.S" $GATEWAY_NAME &> "$DBGDIR_FILES"/desktop_policy_install_debug.txt &
                                progress_bar
                fi
}
 
mgmt_slow()
{
                policy_detect
                gateway_detect "1"
                starting_mgmt_debug
 
                export_tderror_debug
                echo_log "TDERROR_ALL_PLCY_INST_TIMING=5 fwm load $POLICY_NAME $GATEWAY_NAME &> policy_install_timing_debug.txt"
 
                $ECHO -n "Installing Security Policy $POLICY_NAME to $GATEWAY_NAME   "
                TDERROR_ALL_PLCY_INST_TIMING=5 fwm load "$POLICY_NAME" $GATEWAY_NAME &> "$DBGDIR_FILES"/policy_install_timing_debug.txt &
                progress_bar
}
 
mgmt_global()
{
                if [[ "$MAJOR_VERSION" == "R80"* ]]; then
                                starting_mgmt_debug
                                api_debug_starting
 
                                $ECHO "Verifying Global Assignment for $DOMAIN_NAME..."
                                MGMT_CLI_RUN=$(mgmt_cli show global-assignment global-domain "Global" dependent-domain "$DOMAIN_NAME" -s $API_ID_FILE -f json > $API_JSON_FILE)
                                MGMT_CLI_RUN_RET="$?"
                                api_debug_valid
 
                                $ECHO "Starting Global Assignment for $DOMAIN_NAME..."
 
                                export_tderror_debug
                                echo_log "\$MDS_FWDIR/scripts/cpm_debug.sh -t Assign_Global_Policy -s DEBUG"
                                echo_log "mgmt_cli assign-global-assignment global-domains Global dependent-domains $DOMAIN_NAME"


                                $MDS_FWDIR/scripts/cpm_debug.sh -t Assign_Global_Policy -s DEBUG > /dev/null
                                MGMT_CLI_RUN=$(mgmt_cli assign-global-assignment global-domains "Global" dependent-domains "$DOMAIN_NAME" -s $API_ID_FILE --sync false -f json > $API_JSON_FILE)
                                api_debug
                else
                                global_policy_detect
                                starting_mgmt_debug
 
                                mdsenv "$CMA_NAME"
                                rm $FWDIR/log/fwm.elg.* 2> /dev/null
                                $ECHO "=debug_start=" > $FWDIR/log/fwm.elg
                                fw debug fwm on TDERROR_ALL_ALL=5
 
                                mdsenv
                                export_tderror_debug
                                echo_log "TDERROR_ALL_ALL=5 fwm mds fwmconnect -assign -n 10 -g ##$GLOBAL_POLICY_NAME -l ${CMA_NAME}_._._${DOMAIN_NAME} &> global_policy_assign_debug.txt"
 
                                $ECHO -n "Assigning Global Policy $GLOBAL_POLICY_NAME to $DOMAIN_NAME   "
                                TDERROR_ALL_ALL=5 fwm mds fwmconnect -assign -n 10 -g "##$GLOBAL_POLICY_NAME" -l "${CMA_NAME}_._._${DOMAIN_NAME}" &> "$DBGDIR_FILES"/global_policy_assign_debug.txt &
                                progress_bar
                fi
}
 
debug_mgmt()
{
                # DATABASE
                if [[ "$QUESTION" == "1" ]]; then
                                mgmt_database
 
                # VERIFY
                elif [[ "$QUESTION" == "2" ]]; then
                                mgmt_verify
 
                # INSTALL
                elif [[ "$QUESTION" == "3" ]]; then
                                mgmt_install
 
                # SLOW INSTALL
                elif [[ "$QUESTION" == "4" ]]; then
                                mgmt_slow
 
                # GLOBAL ASSIGN
                elif [[ "$QUESTION" == "5" ]]; then
                                mgmt_global
                fi
}
 
###############################################################################
# MAIN DEBUG FW
###############################################################################
kernel_debug_flags()
{
                fw ctl debug $1 -m fw + filter ioctl > /dev/null
 
                if [[ "$IS_SG80" == "Failed to find the value" ]]; then
                                fw ctl debug $1 -m kiss + salloc > /dev/null
                fi
 
                echo_log "fw ctl debug 0 -"
                echo_log "fw ctl debug -buf $DEBUG_BUFFER $1"
                echo_log "fw ctl debug $1 -m fw + filter ioctl"
 
                if [[ "$IS_SG80" == "Failed to find the value" ]]; then
                                echo_log "fw ctl debug $1 -m kiss + salloc"
                fi
}
 
kernel_debug_more_flags()
{
                if [[ "$WHICH_POLICY" == "2" ]]; then
                                fw ctl debug $1 -m fw + filter ioctl cmi malware > /dev/null
                else
                                fw ctl debug $1 -m fw + filter ioctl cmi > /dev/null
                fi
 
                if [[ "$MAJOR_VERSION" == "R80"* ]]; then
                                fw ctl debug $1 -m UP + error warning > /dev/null
                fi
 
                fw ctl debug $1 -m WS + error warning > /dev/null
                fw ctl debug $1 -m cmi_loader + error warning policy info > /dev/null
                fw ctl debug $1 -m kiss + error warning htab ghtab mtctx salloc pm > /dev/null
 
                echo_log "fw ctl debug 0 -"
                echo_log "fw ctl debug -buf $DEBUG_BUFFER $1"
 
                if [[ "$WHICH_POLICY" == "2" ]]; then
                                echo_log "fw ctl debug $1 -m fw + filter ioctl cmi malware"
                else
                                echo_log "fw ctl debug $1 -m fw + filter ioctl cmi"
                fi
 
                if [[ "$MAJOR_VERSION" == "R80"* ]]; then
                                echo_log "fw ctl debug $1 -m UP + error warning"
                fi
 
                echo_log "fw ctl debug $1 -m WS + error warning"
                echo_log "fw ctl debug $1 -m cmi_loader + error warning policy info"
                echo_log "fw ctl debug $1 -m kiss + error warning htab ghtab mtctx salloc pm"
}
 
kernel_debug()
{
                fw ctl debug 0 - > /dev/null
                fw ctl debug -buf "$DEBUG_BUFFER" $1 > /dev/null
                if [[ "$?" != "0" ]]; then
                                kernel_memory_used
                                clean_up
                                exit 1
                fi
 
                VSID_KERNEL=$1
 
                if [[ "$MORE_DEBUG_FLAGS" == "1" ]]; then
                                kernel_debug_more_flags "$VSID_KERNEL"
                else
                                kernel_debug_flags "$VSID_KERNEL"
                fi
 
                fw ctl kdebug $1 -T -f &> "$DBGDIR_FILES"/kernel_atomic_debug.txt &
                echo_log "fw ctl kdebug $1 -T -f &> kernel_atomic_debug.txt"
}
 
fw_network()
{
                if [[ "$KERNEL_DEBUG_ONLY" != "1" ]]; then
                                echo_log "\\nTDERROR_ALL_ALL=5 fw -d fetchlocal -d $FWDIR/state/__tmp/FW1 &> fetch_local_debug.txt"
 
                                $ECHO -n "Fetching local Network Security policy   "
 
                                TDERROR_ALL_ALL=5 fw -d fetchlocal -d $FWDIR/state/__tmp/FW1 &> "$DBGDIR_FILES"/fetch_local_debug.txt &
                                progress_bar
                else
                                echo_log "\\nfw fetchlocal -d $FWDIR/state/__tmp/FW1"
                                $ECHO -n "Fetching local Network Security policy   "
 
                                fw fetchlocal -d $FWDIR/state/__tmp/FW1 &> /dev/null &
                                progress_bar
                fi
}
 
fw_threat()
{
                if [[ "$KERNEL_DEBUG_ONLY" != "1" ]]; then
                                echo_log "\\nTDERROR_ALL_ALL=5 fw -d amw fetchlocal -d $FWDIR/state/__tmp/AMW &> fetch_local_debug.txt"
 
                                $ECHO -n "Fetching local Threat Prevention policy   "
 
                                TDERROR_ALL_ALL=5 fw -d amw fetchlocal -d $FWDIR/state/__tmp/AMW &> "$DBGDIR_FILES"/fetch_local_debug.txt &
                                progress_bar
                else
                                echo_log "\\nfw amw fetchlocal -d $FWDIR/state/__tmp/AMW"
                                $ECHO -n "Fetching local Threat Prevention policy   "
 
                                fw amw fetchlocal -d $FWDIR/state/__tmp/AMW &> /dev/null &
                                progress_bar
                fi
}
 
debug_fw()
{
                starting_fw_debug
 
                $ECHO "Vmalloc before enabling kernel debug flags:\\n" >> "$OTHER_FILES"/vmalloc.txt
                cat /proc/meminfo | grep Vmalloc >> "$OTHER_FILES"/vmalloc.txt
 
                if [[ "$FETCHLOCAL_DEBUG_ONLY" != "1" ]]; then
                                if [[ "$1" == "VS" ]]; then
                                                kernel_debug "-v $VSID_SCRIPT"
                                else
                                                kernel_debug
                                fi
                fi
 
                $ECHO "\\n\\nVmalloc after enabling kernel debug flags and before policy install:\\n" >> "$OTHER_FILES"/vmalloc.txt
                cat /proc/meminfo | grep Vmalloc >> "$OTHER_FILES"/vmalloc.txt
 
                if [[ "$WHICH_POLICY" == "1" ]]; then
                                fw_network
 
                elif [[ "$WHICH_POLICY" == "2" ]]; then
                                fw_threat
                fi
 
                $ECHO "\\n\\nVmalloc after policy install:\\n" >> "$OTHER_FILES"/vmalloc.txt
                cat /proc/meminfo | grep Vmalloc >> "$OTHER_FILES"/vmalloc.txt
}
 
###############################################################################
# STOP DEBUG
###############################################################################
stop_debug()
{
                STOP_DATE=$(/bin/date "+%d %b %Y %H:%M:%S %z")
                echo_log "\\nDebug Completed at $STOP_DATE"
                $ECHO "\\nDebug Completed\\n"
                $ECHO "Turning debug off..."
 
                if [[ "$IS_MGMT" == "1" && "$MAJOR_VERSION" == "R80"* ]]; then
                                unset INTERNAL_POLICY_LOADING
                                logLevelInstalPolicy_line_info
                fi
 
                if [[ "$IS_FW" == "1" ]]; then
                                fw ctl debug 0 - > /dev/null
 
                                $ECHO "\\n\\nVmalloc after disabling kernel debug flags:\\n" >> "$OTHER_FILES"/vmalloc.txt
                                cat /proc/meminfo | grep Vmalloc >> "$OTHER_FILES"/vmalloc.txt
 
                                $ECHO "\\n\\nVmalloc in /boot/grub/grub.conf:\\n" >> "$OTHER_FILES"/vmalloc.txt
                                grep 'vmalloc' /boot/grub/grub.conf >> "$OTHER_FILES"/vmalloc.txt
                fi
 
                if [[ "$QUESTION" == "5" ]]; then
                                if [[ "$MAJOR_VERSION" == "R80"* ]]; then
                                                $MDS_FWDIR/scripts/cpm_debug.sh -t Assign_Global_Policy -s INFO > /dev/null
                                                $MDS_FWDIR/scripts/cpm_debug.sh -r > /dev/null
                                else
                                                mdsenv "$CMA_NAME"
                                                fw debug fwm off TDERROR_ALL_ALL=0
                                fi
                fi
 
                if [[ "$API_DEBUG_ON" == "1" ]]; then
                                api_debug_logout
                                rm "$API_JSON_FILE"
                                rm "$API_ID_FILE"
                fi
}
 
###############################################################################
# COLLECT GENERAL INFO AND FILES
###############################################################################
MINI_CPINFO="$DBGDIR_FILES"/mini_cpinfo.txt
 
section_mini_cpinfo()
{
                SEP="***********************"
                $ECHO "\\n" >> "$MINI_CPINFO"
                $ECHO "$SEP $1 $SEP" >> "$MINI_CPINFO"
}
 
section_mini_cpinfo_break()
{
                SEP="======================================================================"
                $ECHO "\\n\\n" >> "$MINI_CPINFO"
                $ECHO "$SEP" >> "$MINI_CPINFO"
                $ECHO "$1" >> "$MINI_CPINFO"
                $ECHO "$SEP" >> "$MINI_CPINFO"
}
 
collect_files()
{
                $ECHO "Copying files..."

                # MINI CPINFO

                section_mini_cpinfo_break "VERSION INFORMATION"

                if [[ "$IS_SG80" == "Failed to find the value" ]]; then
                                section_mini_cpinfo "MACHINE DETAILS (clish -c \"show asset all\")"
                                if [[ -f "/bin/clish" ]]; then
                                                clish -c "lock database override" &> /dev/null
                                                clish -c "show asset all" >> "$MINI_CPINFO" 2>&1
                                else
                                                $ECHO "/bin/clish does not exist" >> "$MINI_CPINFO"
                                                $ECHO "This Operating System is not Gaia" >> "$MINI_CPINFO"
                                fi

                                section_mini_cpinfo "VERSION (clish -c \"show version all\")"
                                if [[ -f "/bin/clish" ]]; then
                                                clish -c "lock database override" &> /dev/null
                                                clish -c "show version all" >> "$MINI_CPINFO" 2>&1
                                else
                                                $ECHO "/bin/clish does not exist" >> "$MINI_CPINFO"
                                                $ECHO "This Operating System is not Gaia" >> "$MINI_CPINFO"
                                fi
                else
                                section_mini_cpinfo "VERSION (ver)"
                                ver >> "$MINI_CPINFO"
                fi

                section_mini_cpinfo "SYSTEM INFO (uname -a)"
                uname -a >> "$MINI_CPINFO"

                section_mini_cpinfo_break "SYSTEM INFORMATION"

                section_mini_cpinfo "CPU (cat /proc/cpuinfo | egrep \"^processor|^Processor\" | wc -l)"
                $ECHO -n "Total CPU: " >> "$MINI_CPINFO"
                cat /proc/cpuinfo | egrep "^processor|^Processor" | wc -l >> "$MINI_CPINFO"

                if [[ "$IS_SG80" == "Failed to find the value" ]]; then
                                section_mini_cpinfo "MEMORY (free -m -t)"
                                free -m -t >> "$MINI_CPINFO" 2>&1

                                section_mini_cpinfo "DISK SPACE (df -haT)"
                                df -haT >> "$MINI_CPINFO" 2>&1

                                section_mini_cpinfo "TOP (top -bn1 -p 0 | head -5)"
                                top -bn1 -p 0 2>&1 | head -5 >> "$MINI_CPINFO"
                else
                                section_mini_cpinfo "MEMORY (free)"
                                free >> "$MINI_CPINFO" 2>&1

                                section_mini_cpinfo "DISK SPACE (df -h)"
                                df -h >> "$MINI_CPINFO" 2>&1

                                section_mini_cpinfo "TOP (top -n1 | head -5)"
                                top -n1 2>&1 | head -5 >> "$MINI_CPINFO"
                fi

                section_mini_cpinfo "UPTIME (uptime)"
                uptime >> "$MINI_CPINFO"

                section_mini_cpinfo "TIME (hwclock and ntpstat)"
                hwclock >> "$MINI_CPINFO"
                ntpstat >> "$MINI_CPINFO" 2>&1
 
                section_mini_cpinfo "(cpstat os -f all)"
                cpstat os -f all >> "$MINI_CPINFO"

                if [[ "$IS_FW" == "1" ]]; then
                                if [[ "$IS_SG80" == "Failed to find the value" ]]; then
                                                section_mini_cpinfo "ENABLED BLADES (enabled_blades)"
                                                enabled_blades >> "$MINI_CPINFO" 2>&1
                                fi

                                section_mini_cpinfo "IPS STATUS (ips stat)"
                                ips stat >> "$MINI_CPINFO" 2>&1

                                section_mini_cpinfo "(fw ctl pstat)"
                                fw ctl pstat >> "$MINI_CPINFO"

                                section_mini_cpinfo "(cpstat ha -f all)"
                                cpstat ha -f all >> "$MINI_CPINFO" 2>&1
                fi

                section_mini_cpinfo_break "PROCESSES"

                section_mini_cpinfo "WATCHDOG (cpwd_admin list)"
                cpwd_admin list >> "$MINI_CPINFO"

                section_mini_cpinfo "(ps auxww)"
                ps auxww >> "$MINI_CPINFO"
 
                section_mini_cpinfo_break "INTERFACES AND ROUTING"
 
                section_mini_cpinfo "(ifconfig -a)"
                ifconfig -a >> "$MINI_CPINFO"
 
                section_mini_cpinfo "(arp -nv)"
                arp -nv >> "$MINI_CPINFO"
 
                if [[ "$IS_SG80" == "Failed to find the value" ]]; then
                                section_mini_cpinfo "(netstat -i)"
                                netstat -i >> "$MINI_CPINFO"
                fi
 
                section_mini_cpinfo "(netstat -rn)"
                netstat -rn >> "$MINI_CPINFO"
 
                if [[ "$IS_SG80" == "Failed to find the value" ]]; then
                                netstat -anp >> "$OTHER_FILES"/netstat_anp.txt
                else
                                netstat -an >> "$OTHER_FILES"/netstat_an.txt 2>&1
                fi
 
                section_mini_cpinfo_break "OTHER INFORMATIONIN"
 
                if [[ "$IS_SG80" == "Failed to find the value" ]]; then
                                section_mini_cpinfo "CORE DUMPS"
                                $ECHO "/var/crash" >> "$MINI_CPINFO"
                                ls -lhA /var/crash >> "$MINI_CPINFO" 2>&1
                                $ECHO "/var/log/crash" >> "$MINI_CPINFO"
                                ls -lhA /var/log/crash >> "$MINI_CPINFO" 2>&1
                                $ECHO "/var/log/dump/usermode" >> "$MINI_CPINFO"
                                ls -lhA /var/log/dump/usermode >> "$MINI_CPINFO" 2>&1
                else
                                section_mini_cpinfo "CORE DUMPS (ls -lhA /logs/core)"
                                ls -lhA /logs/core >> "$MINI_CPINFO" 2>&1
                fi
 
                section_mini_cpinfo "LICENSES (cplic print -x)"
                cplic print -x >> "$MINI_CPINFO" 2>&1

                if [[ "$IS_SG80" == "Failed to find the value" ]]; then
                                section_mini_cpinfo_break "HOTFIXES INSTALLED"
                                section_mini_cpinfo "HOTFIXES (cpinfo -y all)"
                                if [[ "$IS_MDS" == "1" ]]; then
                                                mdsenv
                                                script -q -c 'cpinfo -y all' /dev/null >> "$MINI_CPINFO" 2>&1
                                elif [[ "$IS_VSX" == "1" ]]; then
                                                vsenv > /dev/null
                                                script -q -c 'cpinfo -y all' /dev/null >> "$MINI_CPINFO" 2>&1
                                                vsenv "$VSID_SCRIPT" > /dev/null
                                else
                                                script -q -c 'cpinfo -y all' /dev/null >> "$MINI_CPINFO" 2>&1
                                fi
 
                                section_mini_cpinfo "JUMBO HOTFIX TAKE (installed_jumbo_take)"
                                if [[ "$IS_MDS" == "1" ]]; then
                                                if [[ -e $MDS_TEMPLATE/bin/installed_jumbo_take ]]; then
                                                                installed_jumbo_take >> "$MINI_CPINFO"
                                                else
                                                                $ECHO "\$MDS_TEMPLATE/bin/installed_jumbo_take does not exist" >> "$MINI_CPINFO"
                                                fi
                                else
                                                if [[ -e $FWDIR/bin/installed_jumbo_take ]]; then
                                                                installed_jumbo_take >> "$MINI_CPINFO"
                                                else
                                                                $ECHO "\$FWDIR/bin/installed_jumbo_take does not exist" >> "$MINI_CPINFO"
                                                fi
                                fi
                fi
 
                if [[ "$MAJOR_VERSION" == "R80"* ]]; then
                                section_mini_cpinfo "dleserver.jar BUILD NUMBER (cpvinfo $MDS_FWDIR/cpm-server/dleserver.jar)"
                                cpvinfo $MDS_FWDIR/cpm-server/dleserver.jar >> "$MINI_CPINFO" 2>&1
                fi
 
                # OTHER FILES
 
                if [[ "$IS_FW" == "1" ]]; then
                                if [[ -f "$FWDIR/boot/modules/fwkern.conf" ]]; then
                                                cp -p $FWDIR/boot/modules/fwkern.conf* "$OTHER_FILES"
                                fi
 
                                cp -p $CPDIR/registry/HKLM_registry.data* "$OTHER_FILES"
                fi
 
                cp -p /var/log/messages* "$OTHER_FILES"
 
                if [[ "$MAJOR_VERSION" == "R80"* ]]; then
                                cp -p $FWDIR/state/__tmp/FW1/install_policy_report* "$DBGDIR_FILES" 2> /dev/null
 
                                if [[ "$IS_MDS" == "1" ]]; then
                                                if [[ "$QUESTION" == "5" ]]; then
                                                                cp -p $MDS_TEMPLATE/log/cpm.elg* "$DBGDIR_FILES"
                                                else
                                                                cp -p $MDS_TEMPLATE/log/cpm.elg* "$OTHER_FILES"
                                                fi
 
                                                if [[ "$API_DEBUG_ON" == "1" ]]; then
                                                                cp -p $MDS_TEMPLATE/log/install_policy.elg* "$DBGDIR_FILES"
                                                else
                                                                cp -p $MDS_TEMPLATE/log/install_policy.elg* "$OTHER_FILES"
                                                fi
 
                                                mdsenv "$CMA_NAME"
                                                cp -p $CPDIR/registry/HKLM_registry.data* "$OTHER_FILES"
                                                cp -p $FWDIR/conf/objects_5_0.C* "$OTHER_FILES"
                                                cp -p $FWDIR/tmp/fwm_load.state* "$OTHER_FILES" 2> /dev/null
                                elif [[ "$IS_MGMT" == "1" ]]; then
                                                cp -p $CPDIR/registry/HKLM_registry.data* "$OTHER_FILES"
                                                cp -p $FWDIR/conf/objects_5_0.C* "$OTHER_FILES"
                                                cp -p $FWDIR/log/cpm.elg* "$OTHER_FILES"
 
                                                if [[ "$API_DEBUG_ON" == "1" ]]; then
                                                                cp -p $FWDIR/log/install_policy.elg* "$DBGDIR_FILES"
                                                else
                                                                cp -p $FWDIR/log/install_policy.elg* "$OTHER_FILES"
                                                fi
 
                                                cp -p $FWDIR/tmp/fwm_load.state* "$OTHER_FILES" 2> /dev/null
                                fi
                else
                                if [[ "$IS_MDS" == "1" ]]; then

                                                cp -p $MDSDIR/conf/mdsdb/customers.C* "$OTHER_FILES"

                                                mdsenv "$CMA_NAME"

                                                cp -p $CPDIR/registry/HKLM_registry.data* "$OTHER_FILES"

                                                cp -p $FWDIR/conf/objects_5_0.C* "$OTHER_FILES"

                                                cp -p $FWDIR/conf/rulebases_5_0.fws* "$OTHER_FILES"

                                elif [[ "$IS_MGMT" == "1" ]]; then
                                                cp -p $CPDIR/registry/HKLM_registry.data* "$OTHER_FILES"
                                                cp -p $FWDIR/conf/objects_5_0.C* "$OTHER_FILES"
                                                cp -p $FWDIR/conf/rulebases_5_0.fws* "$OTHER_FILES"
                                fi
                fi
 
                if [[ "$QUESTION" == "5" ]]; then
                                if (( $($ECHO "${MAJOR_VERSION:1} < 80" | bc -l) )); then
                                                mdsenv
                                                fwm dumptabletoset -f ips_tables.sqlite -b . -o "$OTHER_FILES"/mds_ips_tables.txt
                                                mdsenv "$CMA_NAME"
                                                fwm dumptabletoset -f ips_tables.sqlite -b . -o "$OTHER_FILES"/cma_ips_tables.txt
                                                cp -p $FWDIR/log/fwm.elg* "$OTHER_FILES"
                                                cp -p $FWDIR/log/gpolicy.log* "$OTHER_FILES"
                                fi
                fi
}
 
###############################################################################
# COMPRESS FILES FOR FINAL ARCHIVE
###############################################################################
compress_files()
{
                HOST_DTS=($(hostname)_at_$(date +%Y-%m-%d_%Hh%Mm%Ss))
                FINAL_ARCHIVE="$DBGDIR"/policy_debug_of_"$HOST_DTS".tgz

                $ECHO "Compressing files..."
                tar czf "$DBGDIR"/policy_debug_of_"$HOST_DTS".tgz -C "$DBGDIR" "$FILES"

                if [[ "$?" == "0" ]]; then
                                $ECHO "Please send back file: $FINAL_ARCHIVE\\n"

                                if [[ "$IS_SG80" != "Failed to find the value" ]]; then
                                                rm -rf "$DBGDIR_FILES"
                                fi
                else
                                $ECHO "\\nERROR: Failed to create tgz archive\\n"

                                if [[ "$IS_SG80" != "Failed to find the value" ]]; then
                                                rm -rf "$DBGDIR_FILES"
                                fi

                                exit 1
                fi
}

 

###############################################################################
# MAIN
###############################################################################
debug_mgmt_all()
{
                check_fwm
                what_to_debug
                debug_mgmt
}

debug_fw_all()
{
                verify_buffer
                which_fw_policy

                if [[ "$1" == "VS" ]]; then
                                debug_fw "VS"
                else
                                debug_fw
                fi
}

main()
{

                # Standalone
                if [[ "$IS_MGMT" == "1" && "$IS_FW" == "1" ]]; then
                                debug_mgmt_or_fw

                            if [[ "$STAND_DEBUG" == "1" ]]; then
                                            debug_mgmt_all
                            else
                                            debug_fw_all
                            fi

                # MGMT
                elif [[ "$IS_MGMT" == "1" && "$IS_FW" == "0" ]]; then

                            # MDS
                            if [[ "$IS_MDS" == "1" ]]; then
                                            change_to_cma
                            else
                                            echo_shell_log "\\nThis is a Management Server"
                            fi
                                debug_mgmt_all

                # 61k/41k and VSX
                elif [[ "$IS_61K" != "Failed to find the value" && "$IS_VSX" == "1" ]]; then
                                verify_61k
                                verify_vsx
                                debug_fw_all "VS"

                # 61k/41k and not VSX
                elif [[ "$IS_61K" != "Failed to find the value" ]]; then
                            verify_61k
                            debug_fw_all

                # VSX
                elif [[ "$IS_VSX" == "1" ]]; then
                            verify_vsx
                            debug_fw_all "VS"

                # FW
                elif [[ "$IS_FW" == "1" ]]; then
                            echo_shell_log "\\nThis is a Security Gateway"
                            debug_fw_all

                else
                            $ECHO "\\nCould not detect if this is a Management or Gateway"
                            $ECHO "Verify \$CPDIR/registry/HKLM_registry.data file is not corrupted\\n"
                            clean_up
                            exit 1
                fi

                stop_debug
                collect_files
                compress_files
}

main
exit 0