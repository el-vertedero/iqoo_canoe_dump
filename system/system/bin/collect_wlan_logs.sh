#!/system/bin/sh

TAG="cnss_collect_wlan_logs"
# This path should be synced with defination in cnss diag
BASE_DIR="/sdcard/cache/wlan_logs"
BBKLOG_BASE_DIR="/data/bbklog/"
BBKLOG_BUFFER_DIR="/data/logData/modules/2900/circulated_wlan_logs"

CIRCULATE_NETLOG_DIR="/data/syslog/bbklog/circulate_netlog"
NETLOG_DIR="/data/syslog/bbklog/netlog"

# Post fix for zipped files
POST_FIX=".gz"
# Put zipped file to specified location and will be uploaded
MODULE_LOCATION="/data/logData/modules/"
DEST_LOCATION="/data/logData/modules/2900/"

BT_HCILOG_LOCATION="/data/misc/bluetooth/logs/"
BT_HCILOG_BBK_ON_LOCATION="/data/bbklog/bt_log/"

BT_MAX_FOLDER_SIZE=$(( 10 * 1024 ))

fw_autominidump_size=$(( 20 * 1024 * 1024 ))
host_autominidump_size=$(( 3 * 1024 * 1024 ))

# No used yet; place holder
EVENT_SUBTYPE="0"

# Command to trigger log dumping(sending SIGTERM to cnss_diag_system)
TRIGGER_CMD="trigger_dump"

COLLECT_LOGS_CMD="collect_logs"
function cp_bt_log {
    is_bt_offload_sup=`getprop ro.bluetooth.a2dp_offload.supported`
    log -t ${TAG} "is_bt_offload_sup=$is_bt_offload_sup"

    if [ "$is_bt_offload_sup" = "false" ];then
        log -t ${TAG} "is_bt_offload_sup=$is_bt_offload_sup , no need BT Hci logs"
        return
    fi

    bt_total_size=0;
    bt_dest_location="${1}/bt_hci_log"
    if [ ! -d "$bt_dest_location" ]; then
        mkdir $bt_dest_location -m 777
    fi
    is_bbk_on=`getprop persist.sys.log.ctrl`
    log -t ${TAG} "is_bbk_on=$is_bbk_on"

    if [ "$is_bbk_on" = "yes" ];then
        bt_src_floder=$BT_HCILOG_BBK_ON_LOCATION
    else
        bt_src_floder=$BT_HCILOG_LOCATION
    fi

    for bt_file in `ls $bt_src_floder -t`; do
        bt_file_size=`du ${bt_src_floder}$bt_file | awk '{printf $1}'`;
        log -t ${TAG} "bt_total_size: $bt_total_size, bt_file_size: $bt_file_size, BT_MAX_FOLDER_SIZE: $BT_MAX_FOLDER_SIZE"
        # If the size of latest bt_file >= $BT_MAX_FOLDER_SIZE, then we only copy this latest file and return.
        if [[ $bt_file_size -ge $BT_MAX_FOLDER_SIZE ]] && [[ $bt_total_size -eq "0" ]]; then
            log -t ${TAG} "cp -r ${bt_src_floder}$bt_file $bt_dest_location"
            cp -r ${bt_src_floder}$bt_file $bt_dest_location
            break;
        fi;

        # Sort by time, we copy the last few files until the $bt_total_size > $BT_MAX_FOLDER_SIZE.
        bt_total_size=$(( $bt_total_size + $bt_file_size ));
        if [[ $bt_total_size -le $BT_MAX_FOLDER_SIZE ]]; then
            log -t ${TAG} "cp -r ${bt_src_floder}$bt_file $bt_dest_location"
            cp -r ${bt_src_floder}$bt_file $bt_dest_location
        else
            break;
        fi;
    done
}

# Command to enable ppdu logs
PPDU_LOG_CMD="trigger_ppdu_logs"
PPDU_LOG_BIT="0x01"
PHY_DBG_BIT="0x20"

# cut log for expected size
# 1:file name 2:expected size 3:new file name
function log_cut {
    log_size=`stat -c %s ${1}`
    if [[ $? -eq 0 && $log_size -gt ${2} ]]; then
        tail -c ${2} ${1} > ${3}
        if [ $? -eq 0 ]; then
            rm -rf ${1}
            if [ $? -ne 0 ]; then
                # remove split file if delete original host log failed
                rm -rf ${3}
            fi
            sed -i '1d' ${3}
        else
            # remove split file if tail log file failed
            rm -rf ${3}
        fi
    fi
}

function dump_circulated_wlan_log_service {
    echo "dump of circulated wlan log service" > ${1}/circulated_wlan_log_service.dump
    vivo_wlan_flag=`getprop persist.sys.vivo.wlan.log.trigger.flag`
    echo  "persist.sys.vivo.wlan.log.trigger.flag=$vivo_wlan_flag" >> ${1}/circulated_wlan_log_service.dump
    vivo_ppdu_log_flag=`getprop sys.vivo.ppdu.log.enabled`
    echo  "sys.vivo.ppdu.log.enabled=$vivo_ppdu_log_flag" >> ${1}/circulated_wlan_log_service.dump
}

function dump_sys_service {
    log -t ${TAG} "dumpsys start ${1}"
    dumpsys wifi > "${1}/wifi.dump"
    dumpsys connectivity > "${1}/connectivity.dump"
    #dumpsys netd > "${1}/netd.dump"
    dumpsys wificond > "${1}/wificond.dump"
    dumpsys network_management > "${1}/network_management.dump"
    dumpsys network_stack > "${1}/network_stack.dump"
    logcat -d -t 80000 > "${1}/logcat.log"
    dmesg > "${1}/dmesg.log"
    dump_circulated_wlan_log_service ${1}
    cp_bt_log  ${1}
}

if [ "$1" == "$PPDU_LOG_CMD" ]; then
    vivo_wlan_flag=`getprop persist.sys.vivo.wlan.log.trigger.flag`
    if [ $((vivo_wlan_flag&PPDU_LOG_BIT)) == 1 ]; then
        setprop sys.vivo.ppdu.log.enabled 1
    fi
    if [ $((vivo_wlan_flag&PHY_DBG_BIT)) == 32 ]; then
        setprop sys.vivo.ppdu.log.enabled 2
    fi
    return
fi

if [ "$1" == "$COLLECT_LOGS_CMD" ]; then
    log -t $TAG "Start dumping wlan logs"
    is_wlan_logs=`getprop persist.sys.is_wlan_log`
    if [[ $is_wlan_logs -eq 0 ]]; then
        pid_str=`getprop sys.circulated_wlan_logs.pid`
        kill -15 $pid_str
        sleep 5
        log -t $TAG "Restart circulated wlan logs"
        start circulated_wlan_logs
        cd $BASE_DIR
        latest_logs=`ls -t .| head -n1`
        tail -c $fw_autominidump_size ${latest_logs}/buffered_cnss_fw_logs.txt > cnss_fw_logs_current_split.txt
        tail -c $host_autominidump_size ${latest_logs}/buffered_host_driver_logs.txt > host_driver_logs_current_split.txt
        chmod 777 cnss_fw_logs_current_split.txt
        chmod 777 host_driver_logs_current_split.txt
        rm -rf *wlan_logs*
        #rm -rf ${BASE_DIR}/*
        return
    fi
    if [[ $is_wlan_logs -eq 2 ]]; then
        files=`ls ${BBKLOG_BASE_DIR}/wlan_logs`
        mkdir $BASE_DIR
        cd ${BBKLOG_BASE_DIR}
        if [ $? -eq 0 ]; then
            fw_max_time=0
            fw_file=""
            host_max_time=0
            host_file=""
            for file in $files; do
                # search fw logs for need
                if [[ $file == *"cnss_fw_logs"* && $file != "cnss_fw_logs_current.txt" ]]; then
                    cur_time=`stat -c %Y wlan_logs/$file`
                    if [ $cur_time -gt $fw_max_time ]; then
                        fw_max_time=$cur_time
                        fw_file=$file
                    fi
                fi
                # search host logs for need
                if [[ $file == *"host_driver_logs"* && $file != "host_driver_logs_current.txt" ]]; then
                    cur_time=`stat -c %Y wlan_logs/$file`
                    if [ $cur_time -gt $host_max_time ]; then
                        host_max_time=$cur_time
                        host_file=$file
                    fi
                fi
            done
            if [ $fw_file ]; then
                cp "${BBKLOG_BASE_DIR}/wlan_logs/$fw_file" "$BASE_DIR/cnss_fw_logs_current.txt"
                cat "${BBKLOG_BASE_DIR}/wlan_logs/cnss_fw_logs_current.txt" >> "/$BASE_DIR/cnss_fw_logs_current.txt"
            else
                cp "${BBKLOG_BASE_DIR}/wlan_logs/cnss_fw_logs_current.txt" "$BASE_DIR/cnss_fw_logs_current.txt"
            fi
            if [ $host_file ]; then
                cp "${BBKLOG_BASE_DIR}/wlan_logs/$host_file" "$BASE_DIR/host_driver_logs_current.txt"
                cat "${BBKLOG_BASE_DIR}/wlan_logs/host_driver_logs_current.txt" >> "$BASE_DIR/host_driver_logs_current.txt"
            else
                cp "${BBKLOG_BASE_DIR}/wlan_logs/host_driver_logs_current.txt" "$BASE_DIR/host_driver_logs_current.txt"
            fi
            # cut fw and host log if the total size of fw log and host log is larger than 12.5M
            log_cut $BASE_DIR/cnss_fw_logs_current.txt $fw_autominidump_size $BASE_DIR/cnss_fw_logs_current_split.txt
            log_cut $BASE_DIR/host_driver_logs_current.txt $host_autominidump_size $BASE_DIR/host_driver_logs_current_split.txt
            chmod 777 $BASE_DIR/cnss_fw_logs_current_split.txt
            chmod 777 $BASE_DIR/host_driver_logs_current_split.txt
        fi
        return
    fi
fi

if [ "$1" == "$TRIGGER_CMD" ]; then
    log -t $TAG "Start dumping wlan logs"
    is_wlan_logs=`getprop persist.sys.is_wlan_log`
    if [[ $is_wlan_logs -eq 0 ]]; then
        pid_str=`getprop sys.circulated_wlan_logs.pid`
        kill -15 $pid_str
        sleep 5
        log -t $TAG "Restart circulated wlan logs"
        start circulated_wlan_logs
    fi
    if [[ $is_wlan_logs -eq 2 ]]; then
        cd $BBKLOG_BASE_DIR
        if [ $? -ne 0 ]; then
            return
        fi
        if [ ! -d "$MODULE_LOCATION" ]; then
            mkdir $MODULE_LOCATION -m 777
        fi
        if [ ! -d "$DEST_LOCATION" ]; then
            mkdir $DEST_LOCATION -m 777
        fi
        if [ ! -d "$BBKLOG_BUFFER_DIR" ]; then
            mkdir $BBKLOG_BUFFER_DIR -m 777
            if [ $? -ne 0 ]; then
                return
            fi
        fi

        netlog_file=""
        netlog_max_time=0
        files=`ls ${CIRCULATE_NETLOG_DIR}`
        if [ $? -eq 0 ]; then
            for file in $files; do
                if [[  $file == *"tcp_dump"* ]]; then
                    cur_time=`stat -c %Y ${CIRCULATE_NETLOG_DIR}/${file}`
                    if [ $cur_time -gt $netlog_max_time ]; then
                        netlog_max_time=$cur_time
                        netlog_file="${CIRCULATE_NETLOG_DIR}/${file}"
                    fi
                fi
            done
        fi
        files=`ls ${NETLOG_DIR}`
        if [ $? -eq 0 ]; then
            for file in $files; do
                if [[ $file == "tcp_dump"* ]]; then
                    cur_time=`stat -c %Y ${NETLOG_DIR}/${file}`
                    if [ $cur_time -gt $netlog_max_time ]; then
                        netlog_max_time=$cur_time
                        netlog_file="${NETLOG_DIR}/${file}"
                    fi
                fi
            done
        fi
        if [ $netlog_file ]; then
            cp $netlog_file "${BBKLOG_BUFFER_DIR}/netlog.pcap"
            if [ $? == 0 ]; then
                tcpdump -r "${BBKLOG_BUFFER_DIR}/netlog.pcap" -C 3 -w ${BBKLOG_BUFFER_DIR}/netlog_temp.pcap -W 14
                net_file_cnt=`ls ${BBKLOG_BUFFER_DIR} | grep netlog_temp.pcap | wc -l`
                log -t $TAG "check nfiles cnt: $net_file_cnt"
                if [[ $net_file_cnt -eq 1 ]]; then
                    mv "${BBKLOG_BUFFER_DIR}/netlog_temp.pcap00" "${BBKLOG_BUFFER_DIR}/tcpdump.pcap0"
                elif [[ $net_file_cnt -lt 10 && $net_file_cnt -gt 1 ]]; then
                    mv "${BBKLOG_BUFFER_DIR}/netlog_temp.pcap0`expr $net_file_cnt - 2`" "${BBKLOG_BUFFER_DIR}/tcpdump.pcap0"
                    mv "${BBKLOG_BUFFER_DIR}/netlog_temp.pcap0`expr $net_file_cnt - 1`" "${BBKLOG_BUFFER_DIR}/tcpdump.pcap1"
                elif [[ $net_file_cnt -eq 10 ]]; then
                    mv "${BBKLOG_BUFFER_DIR}/netlog_temp.pcap09" "${BBKLOG_BUFFER_DIR}/tcpdump.pcap0"
                    mv "${BBKLOG_BUFFER_DIR}/netlog_temp.pcap10" "${BBKLOG_BUFFER_DIR}/tcpdump.pcap1"
                elif [[ $net_file_cnt -lt 15 && $net_file_cnt -gt 10 ]]; then
                    mv "${BBKLOG_BUFFER_DIR}/netlog_temp.pcap`expr $net_file_cnt - 2`" "${BBKLOG_BUFFER_DIR}/tcpdump.pcap0"
                    mv "${BBKLOG_BUFFER_DIR}/netlog_temp.pcap`expr $net_file_cnt - 1`" "${BBKLOG_BUFFER_DIR}/tcpdump.pcap1"
                fi
                rm ${BBKLOG_BUFFER_DIR}/netlog.pcap
                rm ${BBKLOG_BUFFER_DIR}/netlog_temp.pca*
            fi
        fi

        files=`ls wlan_logs`
        if [ $? -eq 0 ]; then
            fw_max_time=0
            fw_file=""
            host_max_time=0
            host_file=""
            for file in $files; do
                # search fw logs for need
                if [[ $file == *"cnss_fw_logs"* && $file != "cnss_fw_logs_current.txt" ]]; then
                    cur_time=`stat -c %Y wlan_logs/$file`
                    if [ $cur_time -gt $fw_max_time ]; then
                        fw_max_time=$cur_time
                        fw_file=$file
                    fi
                fi
                # search host logs for need
                if [[ $file == *"host_driver_logs"* && $file != "host_driver_logs_current.txt" ]]; then
                    cur_time=`stat -c %Y wlan_logs/$file`
                    if [ $cur_time -gt $host_max_time ]; then
                        host_max_time=$cur_time
                        host_file=$file
                    fi
                fi
            done
            if [ $fw_file ]; then
                cp "wlan_logs/$fw_file" "$BBKLOG_BUFFER_DIR/cnss_fw_logs_current.txt"
                cat "wlan_logs/cnss_fw_logs_current.txt" >> "$BBKLOG_BUFFER_DIR/cnss_fw_logs_current.txt"
            else
                cp "wlan_logs/cnss_fw_logs_current.txt" "$BBKLOG_BUFFER_DIR/cnss_fw_logs_current.txt"
            fi
            if [ $host_file ]; then
                cp "wlan_logs/$host_file" "$BBKLOG_BUFFER_DIR/host_driver_logs_current.txt"
                cat "wlan_logs/host_driver_logs_current.txt" >> "$BBKLOG_BUFFER_DIR/host_driver_logs_current.txt"
            else
                cp "wlan_logs/host_driver_logs_current.txt" "$BBKLOG_BUFFER_DIR/host_driver_logs_current.txt"
            fi

            # cut fw and host log if the total size of fw log and host log is larger than 40M
            log_cut $BBKLOG_BUFFER_DIR/cnss_fw_logs_current.txt 31457280 $BBKLOG_BUFFER_DIR/cnss_fw_logs_current_split.txt
            log_cut $BBKLOG_BUFFER_DIR/host_driver_logs_current.txt 10485760 $BBKLOG_BUFFER_DIR/host_driver_logs_current_split.txt
            dump_sys_service $BBKLOG_BUFFER_DIR

            cd $DEST_LOCATION
            tar_file="circulated_wlan_logs$POST_FIX"
            tar -czf $tar_file "circulated_wlan_logs"
            if [ $? -eq 0 ]; then
                # Remove unzipped log files
                rm -rf $BBKLOG_BUFFER_DIR
                if [ $? -eq 0 ]; then
                    log -t ${TAG} "rm -rf $BBKLOG_BUFFER_DIR successful"
                else
                    log -t ${TAG} "rm -rf $BBKLOG_BUFFER_DIR Failed!"
                    exit -1
                fi
            else
                log -t ${TAG} " Failed to tar and zip log files"
                exit -1
            fi

            # Rename log file as cloud diag required:
            # extype_subtype_filecontenthash@TIME.info
            reason=`getprop sys.vivo.wlan_log_trigger_reason`
            log -t ${TAG} "Last trigger reason is ${reason}"

            # Hash with seed (imei + time in millisec)
            timestamp=`date +%s%3N`
            imei=`getprop persist.sys.vtouch.imei`
            hash=`echo "$imei$timestamp" | md5sum -b`
            full_name="${reason}_${EVENT_SUBTYPE}_${hash}@${timestamp}.info"
            mv "$tar_file" "$full_name"
            if [ $? -eq 0 ]; then
                log -t ${TAG} "Formated log files: ${full_name}"
                # remove old tar_file
                rm -rf $tar_file
            fi

            full_name=$DEST_LOCATION$full_name
            chmod 777 $full_name
            if [ $? != 0 ]; then
                log -t ${TAG} "Failed to make log $full_name accessible"
                exit -1
            fi

            #Notify cloud app to upload logs
            os_version=`getprop ro.build.version.bbk`
            cur_date=`date +%s%N`
            am broadcast -a "com.vivo.intent.action.CLOUD_DIAGNOSIS" --ei "attr" 1 --ei "module" 2900 --es "data" "{\"moduleid\":\"2900\",\"eventId\":\"00055|012\",\"dt\":{\"exptype\":${reason},\"osysversion\":\"${os_version}\",\"otime\":\"${cur_date}\",\"oapp_version_code\":\"1.0\",\"caller_shell\":\"\",\"caller_pid\":\"\",\"caller_name\":\"\"},\"fullhash\":\"${hash}\",\"logpath\":\"${full_name}\"}" com.bbk.iqoo.logsystem
            if [ $? -eq 0 ]; then
                log -t ${TAG} "Send broadcast to cloud diag successfully!!"
            fi
        fi
    fi
    return
fi

is_wlan_logs=`getprop persist.sys.is_wlan_log`
if [[ $is_wlan_logs -eq 2 ]]; then
    log -t $TAG "Wlan logs is enabled, no need to collect circulated wlan logs again"
    return
fi
log -t $TAG "Start collecting wlan logs"
# main starts here
cd $BASE_DIR
# It is not really the correct case to have multiple wlan logs
# But it is safe to take actions in a loop
for file in `ls .`; do
    src_file="$file"
    if [[ $file == *"wlan_logs"* && -d $src_file ]]
    then
        # split file name and get the first token as trigger reason
        arrIN=(${file//_/ })
        reason=${arrIN[0]}

        trigger_reason=`getprop sys.vivo.wlan_log_trigger_reason`
        if [ ${reason} -ne ${trigger_reason} ]; then
            log -t ${TAG} "mismatch reason of $file, try to delete it"
            rm -rf $file
            if [ $? -eq 0 ]; then
                log -t ${TAG} "rm -rf $file successful"
            else
                log -t ${TAG} "rm -rf $file Failed!"
            fi
            continue
        fi

        log -t ${TAG} "Handling log files ${src_file}"
        # cut host log if the total size of fw log and host log is larger than 40M
        fw_size=`stat -c %s $file/buffered_cnss_fw_logs.txt`
        if [ $? -eq 0 ]; then
            expect_size=`expr 41943040 - $fw_size`
            log_cut $file/buffered_host_driver_logs.txt $expect_size $file/buffered_host_driver_logs_split.txt
        fi

        dump_sys_service $file

        netlog_file=""
        netlog_max_time=0
        nfiles=`ls ${CIRCULATE_NETLOG_DIR}`
        if [ $? -eq 0 ]; then
            for nfile in $nfiles; do
                if [[  $nfile == *"tcp_dump"* ]]; then
                    cur_time=`stat -c %Y ${CIRCULATE_NETLOG_DIR}/${nfile}`
                    if [ $cur_time -gt $netlog_max_time ]; then
                        netlog_max_time=$cur_time
                        netlog_file="${CIRCULATE_NETLOG_DIR}/${nfile}"
                    fi
                fi
            done
        fi
        nfiles=`ls ${NETLOG_DIR}`
        if [ $? -eq 0 ]; then
            for nfile in $nfiles; do
                if [[ $nfile == "tcp_dump"* ]]; then
                    cur_time=`stat -c %Y ${NETLOG_DIR}/${nfile}`
                    if [ $cur_time -gt $netlog_max_time ]; then
                        netlog_max_time=$cur_time
                        netlog_file="${NETLOG_DIR}/${nfile}"
                    fi
                fi
            done
        fi
        if [ $netlog_file ]; then
            cp $netlog_file "${file}/netlog.pcap"
            if [ $? == 0 ]; then
                tcpdump -r "${file}/netlog.pcap" -C 3 -w ${file}/netlog_temp.pcap -W 14
                net_file_cnt=`ls ${file} | grep netlog_temp.pcap | wc -l`
                log -t $TAG "check nfiles cnt: $net_file_cnt"
                if [[ $net_file_cnt -eq 1 ]]; then
                    mv "${file}/netlog_temp.pcap00" "${file}/tcpdump.pcap0"
                elif [[ $net_file_cnt -lt 10 && $net_file_cnt -gt 1 ]]; then
                    mv "${file}/netlog_temp.pcap0`expr $net_file_cnt - 2`" "${file}/tcpdump.pcap0"
                    mv "${file}/netlog_temp.pcap0`expr $net_file_cnt - 1`" "${file}/tcpdump.pcap1"
                elif [[ $net_file_cnt -eq 10 ]]; then
                    mv "${file}/netlog_temp.pcap09" "${file}/tcpdump.pcap0"
                    mv "${file}/netlog_temp.pcap10" "${file}/tcpdump.pcap1"
                elif [[ $net_file_cnt -lt 15 && $net_file_cnt -gt 10 ]]; then
                    mv "${file}/netlog_temp.pcap`expr $net_file_cnt - 2`" "${file}/tcpdump.pcap0"
                    mv "${file}/netlog_temp.pcap`expr $net_file_cnt - 1`" "${file}/tcpdump.pcap1"
                fi
                rm ${file}/netlog.pcap
                rm ${file}/netlog_temp.pca*
            fi
        fi

        tar_file="$file$POST_FIX"
        tar -czf $tar_file $file
        if [ $? -eq 0 ]; then
            # Remove unzipped log files
            rm -rf $file
            if [ $? -eq 0 ]; then
                log -t ${TAG} "rm -rf $file successful"
            else
                log -t ${TAG} "rm -rf $file Failed!"
                exit -1
            fi
        else
            log -t ${TAG} " Failed to tar and zip log files"
            exit -1
        fi

        # Rename log file as cloud diag required:
        # extype_subtype_filecontenthash@TIME.info
        log -t ${TAG} "Last trigger reason is ${reason}"

        # Hash with seed (imei + time in millisec)
        timestamp=`date +%s%3N`
        imei=`getprop persist.sys.vtouch.imei`
        hash=`echo "$imei$timestamp" | md5sum -b`
        #log -t ${TAG} "imei+time:${imei}${timestamp}"
        #log -t ${TAG} "hash: ${hash}"
        full_name="${reason}_${EVENT_SUBTYPE}_${hash}@${timestamp}.info"
        mv "$tar_file" "$full_name"
        if [ $? -eq 0 ]; then
            log -t ${TAG} "Formated log files: ${full_name}"
        fi

        # TODO: move to cloud and notify
        # Always make sure dest dir exists
        if [ ! -d "$MODULE_LOCATION" ]; then
            mkdir $MODULE_LOCATION -m 777
        fi
        if [ ! -d "$DEST_LOCATION" ]; then
            mkdir $DEST_LOCATION -m 777
        fi
        #mkdir -p $DEST_LOCATION -m 777
        mv $full_name $DEST_LOCATION
        if [ $? != 0 ]; then
            log -t ${TAG} "Failed to move logs to cloud diag modules"
            exit -1
        fi
        full_name=$DEST_LOCATION$full_name
        chmod 777 $full_name
        if [ $? != 0 ]; then
            log -t ${TAG} "Failed to make log $full_name accessible"
            exit -1
        fi

        #Notify cloud app to upload logs
        os_version=`getprop ro.build.version.bbk`
        #cur_date=`date "+%Y-%m-%d %H:%M:%S"`
        cur_date=`date +%s%N`
        #log -t ${TAG} $os_version
        #log -t ${TAG} $cur_date
        #log -t ${TAG} $full_name
        #log -t ${TAG} "data" "{\"moduleid\":\"2900\",\"eventId\":\"00055|012\",\"dt\":{\"exptype\":${reason},\"osysversion\":\"${os_version}\",\"otime\":\"${cur_date}\",\"oapp_version_code\":\"1.0\",\"caller_shell\":\"\",\"caller_pid\":\"\",\"caller_name\":\"\"},\"fullhash\":\"${hash}\",\"logpath\":\"${full_name}\"}"
        am broadcast -a "com.vivo.intent.action.CLOUD_DIAGNOSIS" --ei "attr" 1 --ei "module" 2900 --es "data" "{\"moduleid\":\"2900\",\"eventId\":\"00055|012\",\"dt\":{\"exptype\":${reason},\"osysversion\":\"${os_version}\",\"otime\":\"${cur_date}\",\"oapp_version_code\":\"1.0\",\"caller_shell\":\"\",\"caller_pid\":\"\",\"caller_name\":\"\"},\"fullhash\":\"${hash}\",\"logpath\":\"${full_name}\"}" com.bbk.iqoo.logsystem
        if [ $? -eq 0 ]; then
            log -t ${TAG} "Send broadcast to cloud diag successfully!!"
        fi
    fi
done
