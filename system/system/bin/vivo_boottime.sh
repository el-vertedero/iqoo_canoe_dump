#!/bin/sh
# LocalBootTimeTest.sh
# Verion : v1.0.0
# Update Data 2024-8-29
#
#


LOG_TAG="bsp_boottime"

DMESG_FILE="/data/boottime/dmesg.txt"

#记录本次开机是否上传
UPLOAD_PROP="sys.vivo.boottime.upload"

# log打印，同时打印到dmseg|logcat|shell
function _LOG()
{
    log  "[$LOG_TAG]:[INFO]: $1"
    echo "[$LOG_TAG]:[INFO]: $1">/dev/kmsg
    echo "$1"
}

function check_need_run()
{
    _LOG "check_need_run..."
    corebspTest=`cat /proc/cmdline | grep 'corebspTest=1'`
    if [ "$corebspTest" == "" ]; then
		cmdline_flag=`cat /proc/cmdline | grep -E 'em_authorized=1|console-at=sendAT|console-at=sendNormal|console-atcmd=vivo_atcmd|console-mode=vivo_em_mode|vivoboot.mode=recovery|vivoboot.mode=survival'`
		if [ "$cmdline_flag" != "" ]; then
			_LOG "Factory Mode or EM mode or Recover, Exit."
			exit
		fi
		
		cmdline_flag2=`cat /proc/cmdline | grep -E 'vivoboot.bootreason=usb|vivoboot.bootreason=USB_CHARGER'`
		if [ "$cmdline_flag2" != "" ]; then
			_LOG "find vivoboot.bootreason=usb|vivoboot.bootreason=USB_CHARGER, check again."
			battary_val=`cat /sys/class/power_supply/battery/capacity`
			_LOG "Battry:[$battary_val]"
			if [ "$battary_val" != "" ]; then
				let battary=$battary_val
				#不统计电量小于5; 存在很多0电量启动，uefi/bl2耗时的问题，需要过滤		
				if [ $battary -le 5 ]; then
					_LOG "Low power, skip."
					exit
				fi
			fi
		fi
		
		charger_mode=`getprop ro.boot.mode`
		if [ "$charger_mode" == "charger" ]; then
			_LOG "Charger Mode, Exit."
			exit
		fi
		
		uploaded=`getprop $UPLOAD_PROP`
		_LOG "$UPLOAD_PROP=[$uploaded]"
		if [ "$uploaded" != "" ]; then
			_LOG "Zygote crashed, $UPLOAD_PROP=[$uploaded], Exit."
			exit
		fi
		
		zygote_reset_val=`getprop persist.sys.zygote.reset`
		if [ "$zygote_reset_val" != "" ]; then
			let zyogte_reset=$zygote_reset_val		
			if [ $zyogte_reset -gt 0 ]; then
				_LOG "Zygote crashed, persist.sys.zygote.reset=[$zyogte_reset], Exit."
				_LOG "Zygote crashed, Exit."
				exit
			fi
		fi   
		

    fi
}

para=$1
_LOG "vivo_boottime.sh parm:$para"
#fun1: post-fs-data create dmesg
if [ "$para" == "dmesg_log" ]; then
#fun2: enable log flag from bbklog	
    rm -rf $DMESG_FILE
    /system/bin/dmesg > $DMESG_FILE
    if [ -f "$DMESG_FILE" ]; then
        _LOG "$DMESG_FILE created."
    else
        _LOG "$DMESG_FILE not created."
    fi
    exit
#disable log flag from bbklog 
elif [ "$para" == "disablelog" ]; then
#fun3: collect boot times
    _LOG "enable log flag"
    exit
elif [ "$para" == "enablelog" ]; then
    _LOG "disable log flag"
    exit
fi

check_need_run

let g_BASE_ADDR=127*0x100000
let g_FLAG_OFFSET=0x10000
let g_BOOT_REC_OFFSET=0
let g_INTVAL=0x1000
let g_time_cnt=5
let g_valid_cnt=0
let g_boot_avg_OFFSET=$g_INTVAL*$g_time_cnt

let g_rec_items=25
let g_times_cnt=19
let g_event_times_cnt=12
let g_max_initlog=3
let g_normal_upload_max=10
let g_abnormal_upload=0
let g_cur_initlog_flag=0

let idx_UTC=0
let idx_RTC=1
let idx_VER=2
let idx_UPLOAD=3
let idx_HASH=4
let idx_INITLOG=5
let idx_time_base=6

let BOOT_TYPE_FIRST=1
let BOOT_TYPE_NORMAL=2
let BOOT_TYPE_UPGRADE=3
let g_partiton_supprt=0 #ANDROID 13.0&VF 14.0的项目logdump只有64M.

let g_cur_ver_upload_time=0
let g_skip_upload=0
let g_boot_type=$BOOT_TYPE_NORMAL

let g_upload_status=0

normal_boot_hash="000000a87c117ebf8064bdaf726a6fc5"
first_hash_prefix="FFFFFF"
abnormal_hash_prefix="AAAAAA"
upgrade_hash_prefix="EEEEEE"
shutdown_hash_prefix="DDDDDD"

                     #boot1 boot2 boots init bsp   fwks  all   fwk1  fwk2 fwk3 fwk4 fwk5 fwk6 fwk7 fwk8 fwk9 fwk10 fwk11 fwk12
    g_time_threshold=(0     0     0     0    14000 16000 32000 0     0    0    0    0    0    0    0    0    0     0     0)
g_time_threshold_chk=(0     0     0     0    0     0     0     0     0    0    0    0    0    0    0    0    0     0     0)

g_boot_rec=()
g_cur_boot_rec=()
g_times_avg=()
g_version=""
g_Tool_Version="v1.0.0"
g_Tool_Update_Data="2024-8-29"

g_work_dir_base="/data/boottime"

let g_max_err_logs=5
function create_err_files()
{    
    let cnt=$g_max_err_logs-1
    for i in `seq 1 $cnt`
    do
        let k=$i
        let j=$cnt-$k
        filename="errlog$j.tar.gz"
        let l=$j+1
        new_filename="errlog$l.tar.gz"
        if [ -f "$filename" ]; then
            mv $filename $new_filename
        fi
    done
    
    mv /data/boottime/errlog* /data/logData/
    tar zcvf /data/logData/errlog0.tar.gz /data/boottime
    mv /data/logData/errlog* /data/boottime
}

# 遇到错误时，报错退出
function ERROR()
{    
    log  "[$LOG_TAG]:[ERROR]: $1"
    echo "[$LOG_TAG]:[ERROR]: $1">/dev/kmsg
    echo "$1"
    create_err_files
    exit
}

function _LOG_FILE()
{
    file=$1
    #echo file=$file
    #log  "[$LOG_TAG]:[INFO]: $1"
    #echo "[$LOG_TAG]:[INFO]: $1">/dev/kmsg

    while read line
    do
        log  "[$LOG_TAG]:[INFO]: $line"
        echo "[$LOG_TAG]:[INFO]: $line"> /dev/kmsg
    done <$file

    contents=`cat $file`
    echo "$contents"
}


function wait_boot_bootcompleted()
{
    for i in `seq 1 100000`
    do
        result=`getprop sys.boot_completed`
        
        if [[ "$result" == "1" ]]; then 
            return
        fi
        sleep 1
    done
}

#
#format1:QCOM
#[    1.706564] KPI: Bootloader start count = 88675
#[    1.706567] KPI: Bootloader end count = 141317
#[    1.706568] KPI: Bootloader load kernel count = 314
#[    1.706570] KPI: Kernel MPM timestamp = 207878
#[    1.706571] KPI: Kernel MPM Clock frequency = 32768
#
#format2: qcom 获取1.706570
#[1.706570] KPI: Kernel MPM timestamp = 207878
#filename
FILE_KPI="bootloaderTime_tmp.txt"
FILE_EVENT="event_tmp.txt"

FILE_LAST_VER="last_version.txt"
FILE_LAST_SLOT="last_slot.txt"
FILE_BOOTED="booted.txt"

#bootloader
KEY_KPI_START_CNT="Bootloader_start_count_=_"
KEY_KPI_MPM_timestamp="Kernel_MPM_timestamp_=_"
KEY_KPI_CLOCK_FREQ="KPI:_Kernel_MPM_Clock_frequency_=_"
KEY_KPI_Kernel_MPM_timestamp1="[____"
KEY_KPI_Kernel_MPM_timestamp2="]_KPI:"
#eventlog
KEY_boot_progress_start="boot_progress_start:_"
KEY_boot_progress_enable_screen="boot_progress_enable_screen:_"  #单独处理
KEY_wm_boot_animation_done="wm_boot_animation_done:_"

KEY_FWK1="boot_progress_preload_start:_"                 #init   boot_progress_start: 7389
KEY_FWK2="boot_progress_preload_end:_"                 #fwk1   boot_progress_preload_start: 7731
KEY_FWK3="boot_progress_system_run:_"                     #fwk2   boot_progress_preload_end: 8557
KEY_FWK4="boot_progress_pms_start:_"                     #fwk3   boot_progress_system_run: 8894
KEY_FWK5="boot_progress_pms_system_scan_start:_"         #fwk4   boot_progress_pms_start: 10210
KEY_FWK6="boot_progress_pms_data_scan_start:_"         #fwk5   boot_progress_pms_system_scan_start: 11438
KEY_FWK7="boot_progress_pms_scan_end:_"                 #fwk6   boot_progress_pms_data_scan_start: 12432
KEY_FWK8="boot_progress_pms_ready:_"                     #fwk7   boot_progress_pms_scan_end: 12502
KEY_FWK9="boot_progress_ams_ready:_"                   #fwk8   boot_progress_pms_ready: 12802
KEY_FWK10="sf_stop_bootanim:_"                         		#fwk9  boot_progress_enable_screen: 19000
KEY_FWK11="wm_boot_animation_done:_"                   		#fwk10  sf_stop_bootanim: 25243


KEY_FWKS=($KEY_FWK1 $KEY_FWK2 $KEY_FWK3 $KEY_FWK4 $KEY_FWK5 $KEY_FWK6 $KEY_FWK7 $KEY_FWK8 $KEY_FWK9 $KEY_FWK10 $KEY_FWK11)

g_val=""
function getkey_from_file()
{
    filename=$1
    findstr=$2
    #echo "getkey_from_file file:$filename,findstr:$findstr"
    result=`cat $filename|grep $findstr`
    
    if [ "$result" == "" ]; then
        ERROR "cat $filename|grep $findstr, result:$result"
    fi
    
    ret=${result#*$findstr}

    if [ "$ret" == "" ]; then
        ERROR "$result#*$findstr, ret:$ret"
    fi
    g_val=$ret
}

function getkey_timestamp_from_file()
{
    filename=$1
    
    result=`cat $filename|grep $findstr`
    if [ "$result" == "" ]; then
        ERROR "cat $filename|grep $findstr,result:$result"
    fi
    
    ret1=${result#*$KEY_KPI_Kernel_MPM_timestamp1}
    if [ "$ret1" == "" ]; then
        ERROR "$result#*$KEY_KPI_Kernel_MPM_timestamp1, ret1:$ret1 "
    fi
    
    ret2=${ret1%%$KEY_KPI_Kernel_MPM_timestamp2*}
    if [ "$ret2" == "" ]; then
        ERROR "$ret1%%$KEY_KPI_Kernel_MPM_timestamp2*, ret2:$ret2 "
    fi
    
    g_val=$ret2    
}


function calc_time_from_file()
{
    RTC=`/system/bin/hwclock`    

    current_date=$(date +"%Y-%m-%d")
    current_time=$(date +"%H_%M_%S")

    current_date="$current_date""_"
    current_time="$current_time"
    UTC=$current_date$current_time
    RTC=${RTC:0:19}
    #echo $RTC
    #echo $UTC
    RTC=`echo "$RTC" | sed 's/ /_/g'`
    #echo $RTC
    _LOG "Curret Time: UTC=$UTC, RTC=$RTC"
    sed -i  's/ /_/g' $FILE_EVENT    

    #echo deal with KPI: keyword from dmesg.
    if [ "$g_vendor" == "QCOM" ]; then
        sed -i  's/ /_/g' $FILE_KPI
        getkey_from_file $FILE_KPI $KEY_KPI_START_CNT
        let v1=$g_val    
        getkey_from_file $FILE_KPI $KEY_KPI_MPM_timestamp
        let v2=$g_val
        getkey_from_file $FILE_KPI $KEY_KPI_CLOCK_FREQ
        let v3=$g_val
        getkey_timestamp_from_file $FILE_KPI
        resust=`echo $g_val|awk '{printf("%.0f", 1000*$1)}'`

        let timestamp_MPM=$resust
        let bootloader1=$v1*1000/$v3
        let total_bootloader=$v2*1000/$v3-$timestamp_MPM
        let bootloader2=$total_bootloader-$bootloader1
    elif [ "$g_vendor" == "MTK" ]; then    
      #format mtk
      #2396        : preloader
      #1018        : bl2_ext (Start->Show logo: 668)
      # 293        : tfa
      #  10        : sec_os
      # 191        : gz
      #2726        : lk      
      let total_bootloader=`awk '{ sum += $1 } END { print sum }' $FILE_KPI`
      let bootloader1=`awk '/preloader/ { print $1 }' $FILE_KPI`
      let bootloader2=$total_bootloader-$bootloader1
    elif [ "$g_vendor" == "SPRD" ]; then
        ERROR "dont support for SPRD platform"
    else
        ERROR "unknow platform."
    fi
    
    getkey_from_file $FILE_EVENT $KEY_boot_progress_start
    let init=$g_val
    getkey_from_file $FILE_EVENT $KEY_wm_boot_animation_done
    let total_all=$g_val+$total_bootloader
    let total_bsp=$init+$total_bootloader
    let framework=$g_val-$init

    _LOG "setprop sys.vivo.time.bloader1 $bootloader1"
    setprop sys.vivo.time.bloader1 $bootloader1
    _LOG "setprop sys.vivo.time.bloader2 $bootloader2"
    setprop sys.vivo.time.bloader2 $bootloader2
    _LOG "setprop sys.vivo.time.bloaders $total_bootloader"
    setprop sys.vivo.time.bloaders $total_bootloader
    _LOG "setprop sys.vivo.time.init $init"
    setprop sys.vivo.time.init $init
    _LOG "setprop sys.vivo.time.bsp $total_bsp"
    setprop sys.vivo.time.bsp $total_bsp
    _LOG "setprop sys.vivo.time.fwks $framework"
    setprop sys.vivo.time.fwks $framework
    _LOG "setprop sys.vivo.time.all $all"
    setprop sys.vivo.time.all $total_all

    st_fwks=(0)
    fwks_times=(0)
    let cnt=$g_event_times_cnt-1
    for i in `seq 1 $cnt`
    do
        let j=$i-1
        getkey_from_file $FILE_EVENT ${KEY_FWKS[$j]}
        let st_fwks[$j]=$g_val
    done
    
    let cnt=$g_event_times_cnt-1
    for i in `seq 1 $cnt`
    do
        let j=$i-1
        if [ $j -eq 0 ]; then
            let tmp=${st_fwks[0]}-$init
        else
            let tmp=${st_fwks[($j)]}-${st_fwks[($j)-1]}
        fi
        fwks_times[$j]=$tmp
    done 
	
    #单独处理 boot_progress_enable_screen
    getkey_from_file $FILE_EVENT $KEY_boot_progress_enable_screen		
    fwks_times[$g_event_times_cnt-1]=$g_val

    #echo "bootloader1:$bootloader1"
    #echo "bootloader2:$bootloader2"
    #echo "init:$init"
    #echo "framework:$framework"
    #echo "total_bootloader:$total_bootloader"
    #echo "total_bsp:$total_bsp"
    #echo "total_all:$total_all"
    #echo "timestamp_MPM:$timestamp_MPM"
#one format:
#RTC=1970-01-28_08:49:34;UTC=2024-04-28_08:49:34;VER=PD2307_A_14.0.0.1_boot.W10;UPLOAD=1;HASH=9c9b4dc01e61991ca61d84445c39431d;INITLOG=0;
#     boot1 boot2 boots init bsp framworks all fwk1 fwk2 fwk3 fwk4 fwk5 fwk6 fwk7 fwk8 fwk9 fwk10 fwk11 fwk12
#time=0     1     1     1    1   1         1   1    1    1    1    1    1    1    1    1    1     1     1
    g_cur_boot_rec[$idx_RTC]=$RTC
    g_cur_boot_rec[$idx_UTC]=$UTC
    g_cur_boot_rec[$idx_VER]=$g_version
    g_cur_boot_rec[$idx_UPLOAD]=0
    g_cur_boot_rec[$idx_HASH]=null
    g_cur_boot_rec[$idx_INITLOG]=0
    g_cur_boot_rec[$idx_time_base]=$bootloader1
    g_cur_boot_rec[($idx_time_base)+1]=$bootloader2    
    g_cur_boot_rec[($idx_time_base)+2]=$total_bootloader
    g_cur_boot_rec[($idx_time_base)+3]=$init
    g_cur_boot_rec[($idx_time_base)+4]=$total_bsp    
    g_cur_boot_rec[($idx_time_base)+5]=$framework
    g_cur_boot_rec[($idx_time_base)+6]=$total_all
    for i in `seq 1 $g_event_times_cnt`
    do
        let j=$i-1
        let offset=$j+$idx_time_base
        let offset=$offset+7
        g_cur_boot_rec[$offset]=${fwks_times[$j]}
    done
    
    rm -rf $FILE_KPI
    rm -rf $FILE_EVENT
}
function generate_event_file()
{
    for i in `seq 1 50`
    do
        rm -rf event.txt
        rm -rf event_org.txt
        
        /system/bin/logcat -d -t 10000 -b events -f event_org.txt
        if [ $? -eq 0 ]; then
            _LOG "/system/bin/logcat -d -t 10000 -b events -f event_org.txt: SUCCSED."
        else
            _LOG "/system/bin/logcat -d -t 10000 -b events -f event_org.txt: FIALED.:ret:$?"
        fi
        cat event_org.txt | grep -E 'boot_progress|sf_stop_bootanim|wm_boot_animation_done' > event.txt
        rm -rf event_org.txt
        if [ $? -eq 0 ]; then
            con=`cat event.txt| grep "boot_progress"`
            echo "###$con###"
            if [ "$con" != "" ]; then
                _LOG_FILE "event.txt"
                _LOG "event.txt generated."
                echo cp -rf event.txt event_tmp.txt
                cp -rf event.txt event_tmp.txt
                return
            fi
            _LOG "wait for event.ext to create, sleep 3s."
            sleep 2
        fi
        _LOG "wait for event.ext to create, sleep 3s."
        sleep 2
    done
    ERROR "event.txt generate failed."
}

function get_cur_boot_time()
{    
    #sleep 1
    let time=0
    if [ "$g_vendor" == "QCOM" ]; then        
        if [ ! -f "$DMESG_FILE" ]; then
            /system/bin/dmesg > $DMESG_FILE
            _LOG "$DMESG_FILE created at 2st stage."
        fi
        cat $DMESG_FILE | grep KPI > bootloaderTime.txt
        cp -rf bootloaderTime.txt bootloaderTime_tmp.txt
    elif [ "$g_vendor" == "MTK" ]; then
        cat /proc/bootprof > bootprof.txt
        cat /proc/bootprof | grep -E ': preloader|: bl2_ext|: tfa|: sec_os|: gz|: lk' > bootloaderTime.txt
        cp -rf bootloaderTime.txt bootloaderTime_tmp.txt
    elif [ "$g_vendor" == "SPRD" ]; then
        ERROR "dont support for SPRD platform"
    fi

    generate_event_file
    cp -rf event.txt event_tmp.txt
    calc_time_from_file
}

function get_device_info()
{
    g_version=`getprop ro.vivo.system.product.version`
    #g_soc=`getprop ro.vivo.product.platform`
    #g_buildtype=`getprop ro.build.type`
    g_android=`getprop ro.vivo.os.version`
    g_vendor=`getprop ro.vivo.product.solution`    
}

function get_boot_type()
{
    CRYPT_LOG_PATH1="/logdata/cryptfs/vold_fbe"
    CRYPT_LOG_PATH2="/cache/cryptfs/vold_fbe"    
    DATA_ENCTRY_KEY_STR="/data encrypt: 1"
    
    cur_slot=`getprop ro.boot.slot_suffix`
    if [ -f "$FILE_LAST_SLOT" ]; then
        last_slot=`cat $FILE_LAST_SLOT`
        if [ -f "$FILE_LAST_VER" ]; then
            last_ver=`cat $FILE_LAST_VER`
        fi
    fi
    
    if [ "$cur_slot" != "" ]; then
        if [ -f "$FILE_LAST_SLOT" ] && [ "$last_slot" != "$cur_slot" ]; then
            if [ -f "$FILE_LAST_VER" ] && [ "$last_ver" != "$g_version" ]; then
                g_boot_type=$BOOT_TYPE_UPGRADE            
                _LOG "VAB,Upgrade boot."
            else
                _LOG "VAB,not Upgrade 2 boot."
            fi
        else
            _LOG "VAB,not Upgrade 2 boot."
        fi
    else
        if [ -f "$FILE_LAST_VER" ] && [ "$last_ver" != "$g_version" ]; then
            g_boot_type=$BOOT_TYPE_UPGRADE
        
            _LOG "non-VAB,nUpgrade boot."
        else
            _LOG "non-VAB,not Upgrade boot."
        fi
    fi

    if [ ! -f "$FILE_BOOTED" ]; then
        g_boot_type=$BOOT_TYPE_FIRST
    fi
    
#    if [ -f "$CRYPT_LOG_PATH1" ]; then
#        path=$CRYPT_LOG_PATH1
#    else
#        path=$CRYPT_LOG_PATH2
#    fi
#    
#    result=`cat $path | grep "$DATA_ENCTRY_KEY_STR"`
#    if [ "$result" != "" ]; then
#        _LOG "get encrypt Key string:[$result]"
#        g_boot_type=$BOOT_TYPE_FIRST
#        
#    else 
#        g_boot_type=$BOOT_TYPE_NORMAL
#    fi
    
    _LOG "BOOT_TYPE:$g_boot_type"
}

function get_cur_initlog_flag()
{
    if [ $g_partiton_supprt -eq 0 ]; then 
        _LOG "get_cur_initlog_flag logdump is not support."
        return
    fi

    let skip=`expr $g_BASE_ADDR + $g_FLAG_OFFSET`
    #echo "skip=$skip"
    #echo "dd if=/dev/block/by-name/logdump of=$g_work_dir_base/red_tmp.txt bs=1 skip=$skip count=1024"
    rm -rf read_tmp.txt
    dd if=/dev/block/by-name/logdump of=$g_work_dir_base/read_tmp.txt bs=1 skip=$skip count=32 > /dev/null 2>&1
    part_flag=`cat read_tmp.txt|grep "INITLOG=enable"`
    cmdline_flag=`cat /proc/cmdline | grep 'initcall_debug' | grep 'printk.devkmsg=on' | grep 'ignore_loglevel'`
    rm -rf read_tmp.txt
    if [ "$cmdline_flag" != "" ]; then
        _LOG "Current boot has enabled init log flag."
        let g_cur_initlog_flag=1
        if [ "$part_flag" != "" ]; then
            _LOG "But logdump flag not enable."
        else
            _LOG "And logdump flag has enabled."
        fi
    else 
        _LOG "Current boot has not enabled init log flag."
    fi
}

function dump_device_info()
{
    echo "#####################设备信息#######################"
    echo "版本:【$g_version】 编译类型:【$g_buildtype】 ALLLOG:$init_all_log"
    echo "Android:【$g_android】 芯片厂商:【$g_vendor】 平台:【$g_soc】"
    echo "#####################设备信息#######################"
}

function clear_logdump_part()
{
    dd if=/dev/zero of=/dev/block/by-name/logdump
}

#one format:
#RTC=1970-01-28_08:49:34;UTC=2024-04-28_08:49:34;VER=PD2307_A_14.0.0.1_boot.W10;UPLOAD=1;HASH=9c9b4dc01e61991ca61d84445c39431d
#     boot1 boot2 boots init bsp framworks all fwk1 fwk2 fwk3 fwk4 fwk5 fwk6 fwk7 fwk8 fwk9 fwk10 fwk11 fwk12
#time=0     1     1     1    1   1         1   1    1    1    1    1    1    1    1    1    1     1     1
#eg
#RTC=1970-01-28_08:49:34;UTC=2024-04-28_08:49:34;VER=PD2307_A_14.0.0.1_boot.W10;UPLOAD=1;HASH=9c9b4dc01e61991ca61d84445c39431d
#TIMES=2711 1942 4653 4912 9565 15776 25341 5337 5942 7608 7835 8304 8310 8471 18040 20687 20688 21934 22535
function parse_one_rec()
{
    idx=$1
    content=$2
    #echo $g_boot_rec
    RTC=`echo ${content}|awk -F ";" '{print $1}'`
    UTC=`echo ${content}|awk -F ";" '{print $2}'`
    VER=`echo ${content}|awk -F ";" '{print $3}'`
    UPLOAD=`echo ${content}|awk -F ";" '{print $4}'`
    HASH=`echo ${content}|awk -F ";" '{print $5}'`
    INITLOG=`echo ${content}|awk -F ";" '{print $6}'`
    TIMES=`echo ${content}|awk -F ";" '{print $7}'`

    ##echo "content:::$content"
    #echo "index:$idx"
    #echo "Before:"
    #echo $RTC
    #echo $UTC
    #echo $VER
    #echo $UPLOAD
    #echo $HASH
    #echo $INITLOG
    #echo $TIMES
    
    RTC=${RTC:4}
    UTC=${UTC:4}
    VER=${VER:4}
    UPLOAD=${UPLOAD:7}
    HASH=${HASH:5}
    TIMES=${TIMES:6}
    INITLOG=${INITLOG:8}

    TIMES=`echo ${TIMES}|awk -F "-" '{print}'`

    #echo "After:"
    #echo $RTC
    #echo $UTC
    #echo $VER
    #echo $UPLOAD
    #echo $HASH
    #echo $INITLOG
    #echo $TIMES    

    let offset_base=$idx*$g_rec_items
    #echo "offset_base=$offset_base"
    let offset=$offset_base+$idx_RTC 
    g_boot_rec[$offset]=$RTC
    let offset=$offset_base+$idx_UTC
    g_boot_rec[$offset]=$UTC
    let offset=$offset_base+$idx_VER
    g_boot_rec[$offset]=$VER
    let offset=$offset_base+$idx_UPLOAD
    g_boot_rec[$offset]=$UPLOAD
    let offset=$offset_base+$idx_HASH
    g_boot_rec[$offset]=$HASH
    let offset=$offset_base+$idx_INITLOG
    g_boot_rec[$offset]=$INITLOG
    #boot_arr=(${TIMES//-/})
    boot_arr=(`echo $TIMES | tr '-' ' '`)
    #echo ${boot_arr[@]}

    arr_len=${#boot_arr[@]}
    #echo "arr_len:$arr_len"
    if [ $arr_len -ne $g_times_cnt ]; then
        echo "$arr_len -ne $g_times_cnt "
        _LOG "clear logdump. Wait next boot."
        clear_logdump_part
        exit
    fi
    
    for i in `seq 1 $g_times_cnt`
    do
        let j=$i-1
        let offset=$offset_base+$idx_time_base+$j
        g_boot_rec[$offset]=${boot_arr[$j]}
    done
}

function read_rec_from_part()
{
    if [ $g_partiton_supprt -eq 0 ]; then 
        _LOG "read_rec_from_part logdump is not support."
        return
    fi
    
    for i in `seq 1 $g_time_cnt`
    do
        let j=$i-1
        let skip=`expr $g_BASE_ADDR + $g_BOOT_REC_OFFSET + $j \* $g_INTVAL`
        #echo "skip=$skip"
        #echo "dd if=/dev/block/by-name/logdump of=$g_work_dir_base/read_tmp.txt bs=1 skip=$skip count=1024"
        rm -rf read_tmp.txt
        
        dd if=/dev/block/by-name/logdump of=$g_work_dir_base/read_tmp.txt bs=1 skip=$skip count=1024 > /dev/null 2>&1
        content=`cat read_tmp.txt`
        is_valid=`echo $content | grep 'RTC=' | grep 'VER=' | grep 'HASH=' | grep 'UTC='`
        if [ "$is_valid" == "" ]; then
            break
        else
            parse_one_rec $j $content
            let g_valid_cnt=$g_valid_cnt+1
        fi
        rm -rf read_tmp.txt
        #echo ${g_boot_rec[@]}
    done
    _LOG "From partition Read valid record Count=$g_valid_cnt."
}

#function calc_cur_boot_time()
#{
#    for i in `seq 1 $g_time_cnt`
#    do
#        #echo $i 
#        let j=$i-1
#        let skip=`expr $g_BASE_ADDR + $g_BOOT_REC_OFFSET + $j \* $g_INTVAL`
#        #echo "skip=$skip"
#        #echo "dd if=/dev/block/by-name/logdump of=$g_work_dir_base/red_tmp.txt bs=1 skip=$seek count=1024"
#        rm -rf red_tmp.txt
#        dd if=/dev/block/by-name/logdump of=$g_work_dir_base/red_tmp.txt bs=1 skip=$seek count=1024 > /dev/null 2>&1
#        content=`cat red_tmp.txt`
#        is_valid=`echo $content | grep 'RTC=' | grep 'VER=' | grep 'LOG_HASH=' | grep 'UTC='`
#        if [ "$is_valid" == "" ]; then
#            break
#        else
#            parse_one_rec $j $content
#        fi
#        #echo ${g_boot_rec[@]}
#    done
#}

function update_local_rec()
{
    #8->9 8->7 ... 1->2 cur->0
    let cnt=$g_valid_cnt-1
    for i in `seq 0 $cnt` 
    do        
        let i1=$cnt-$i
        let i1=$i1

        let idx=$i1
        #echo idx=$idx
        for j in `seq 1 $g_rec_items`
        do
            let j1=$j-1
            let in=$idx
            let in=$idx*$g_rec_items
            let in=$in+$j1
            
            let out=$idx+1
            let out=$out*$g_rec_items
            let out=$out+$j1
            g_boot_rec[$out]=${g_boot_rec[$in]}
        done
    done
    
    #cur->0
    for i in `seq 1 $g_rec_items`
    do            
        let j=$i-1
        g_boot_rec[$j]=${g_cur_boot_rec[$j]}
    done
    let g_valid_cnt++
}

function write_rec_to_part()
{

    if [ $g_partiton_supprt -eq 0 ]; then 
        _LOG "logdump is not support."
        return
    fi
    
    let g_valid_cnt=0
    for i in `seq 1 $g_time_cnt`
    do    
        let j=$i-1
        let off_base=$j*$g_rec_items
        
        val=${g_boot_rec[($off_base)+$idx_UTC]}
        if [ "$val" == "" ]; then
            break;
        fi
 
        let g_valid_cnt++
        rm -rf write_tmp.txt        
        content="UTC=${g_boot_rec[($off_base)+$idx_UTC]};"
        content=$content"RTC=${g_boot_rec[($off_base)+$idx_RTC]};"
        content=$content"VER=${g_boot_rec[($off_base)+$idx_VER]};"
        content=$content"UPLOAD=${g_boot_rec[($off_base)+$idx_UPLOAD]};"
        content=$content"HASH=${g_boot_rec[($off_base)+$idx_HASH]};"
        content=$content"INITLOG=${g_boot_rec[($off_base)+$idx_INITLOG]};"
        content=$content"TIMES="
        
        for k1 in `seq 1 $g_times_cnt`
        do
            let k2=$k1-1
            let off2=$idx_time_base+$k2
            content=$content"${g_boot_rec[($off_base)+$off2]}"
            if [ $k2 -eq $g_times_cnt-1 ]; then
                content=$content";"
            else
                content=$content"-"
            fi
        done
        echo $content > write_tmp.txt
        let seek=`expr $g_BASE_ADDR + $g_BOOT_REC_OFFSET + $j \* $g_INTVAL`
        #echo ""seek=$seek"
        #echo "dd of=/dev/block/by-name/logdump if=$g_work_dir_base/write_tmp.txt bs=1 seek=$seek count=1024"
        dd of=/dev/block/by-name/logdump if=$g_work_dir_base/write_tmp.txt bs=1 seek=$seek count=1024 > /dev/null 2>&1
        
        rm -rf write_tmp.txt
    done
    #echo "exit write_rec_to_part"
}

function clear_log_flags()
{
    if [ $g_partiton_supprt -eq 0 ]; then 
        _LOG "clear_log_flags logdump is not support."
        return
    fi
    
    _LOG "Clear log flags..."
    let seek=`expr $g_BASE_ADDR + $g_FLAG_OFFSET`
    #echo ""seek=$seek"
    dd of=$g_work_dir_base/zero if=/dev/zero bs=1 count=64
    #echo "dd of=/dev/block/by-name/logdump if=$g_work_dir_base/zero bs=1 seek=$seek count=64"
    dd of=/dev/block/by-name/logdump if=$g_work_dir_base/zero bs=1 seek=$seek count=64 > /dev/null 2>&1
    rm -rf zero
}

function open_log_flags()
{
    if [ $g_partiton_supprt -eq 0 ]; then 
        _LOG "open_log_flags logdump is not support."
        return
    fi
    
    let initlog_cnt=0
    for i in `seq 1 $g_valid_cnt`
    do
        let j=$i-1
        let base=$j*$g_rec_items
        let off1=$base+$idx_VER
        let off2=$base+$idx_INITLOG
        if [ [ "$g_boot_rec[$off1]" == "$g_version" ] && [ $g_boot_rec[$off2] -eq 1 ]]; then
            let initlog_cnt++
        fi
    done    
    
    clear_log_flags

    if [ $initlog_cnt -lt $g_max_initlog]; then
        let seek=`expr $g_BASE_ADDR + $g_FLAG_OFFSET`
        #echo ""seek=$seek"
        #echo "dd of=/dev/block/by-name/logdump if=$g_work_dir_base/write_flag.txt bs=1 seek=$seek count=64"
        echo "INITLOG=enable" > write_flag.txt
        dd of=/dev/block/by-name/logdump if=$g_work_dir_base/write_flag.txt bs=1 seek=$seek count=64 > /dev/null 2>&1
    else
        _LOG "Warning###Ver:$g_version init log enable cnt, exceed max [$g_max_initlog]."
    fi
}

function update_cur_boot_rec()
{
    if [ $1 != "" ]; then
        upload=$1
    fi
    
    if [ $2 != "" ]; then
        hash=$2
    fi

    g_cur_boot_rec[$idx_UPLOAD]=$upload
    g_cur_boot_rec[$idx_HASH]=$hash
    g_cur_boot_rec[$idx_INITLOG]=$g_cur_initlog_flag
    
    #echo "info:${g_cur_boot_rec[@]}"
}

function print_check_result()
{
    #print header
    printf "\n%-10s%-7s%-7s%-7s%-7s%-7s%-7s%-7s%-7s%-7s%-7s%-7s%-7s%-7s%-7s%-7s%-7s%-7s%-7s%-7s" "no" "boot1" "boot2" "boots" "init" "bsp" "fwks" "all" "fwk1" "fwk2" "fwk3" "fwk4" "fwk5" "fwk6" "fwk7" "fwk8" "fwk9" "fwk10" "fwk11" "fwk12" >check.txt
    #boot time info
    printf "\n%-10s" "BootTime:" >>check.txt
    for i in `seq 1 $g_times_cnt`
    do
        let j=$i-1
        printf "%-7s" "${g_cur_boot_rec[($idx_time_base)+$j]}" >>check.txt
    done
    
    #threshold info
    printf "\n%-10s" "Thredhold:" >>check.txt
    for i in `seq 1 $g_times_cnt`
    do
        let j=$i-1
        printf "%-7s" "${g_time_threshold[$j]}" >>check.txt
    done
    
    #check result
    printf "\n%-10s" "CheckRlt:" >>check.txt
    for i in `seq 1 $g_times_cnt`
    do
        let j=$i-1
        printf "%-7s" "${g_time_threshold_chk[$j]}" >>check.txt
    done
    printf "       \n       \n" >>check.txt
    
    _LOG_FILE "check.txt"
    #rm -f check.txt
}

function check_times()
{
    for i in `seq 1 $g_times_cnt`
    do
        #sleep 1
        let j=$i-1
        #echo "no:$j"
        #echo "g_time_threshold[$j]:${g_time_threshold[$j]}"
        if [ ${g_time_threshold[$j]} -eq 0 ]; then
            continue
        else
            let max=${g_time_threshold[$j]}
            let off=$idx_time_base+$j
            let cur=${g_cur_boot_rec[$off]}
            #echo "max=$max,cur=$cur"
            if [ $cur -gt $max ]; then
                g_time_threshold_chk[$j]=1
                let g_abnormal_upload=1
            fi
        fi
    done
    
    print_check_result
    
    #sleep 1
    if [ $g_abnormal_upload -eq 1 ]; then
        #echo "${g_time_threshold_chk[@]} $g_version" >hash_tmp.txt
        hash=`md5sum -b dmesg.txt`
        #echo "hash:$hash"
        #rm -rf hash_tmp.txt
        hash="$abnormal_hash_prefix""${hash:6}"
        echo $hash >log_hash.txt
        update_cur_boot_rec $g_abnormal_upload $hash
    else
        if [ $g_cur_ver_upload_time -gt $g_normal_upload_max ]; then
            _LOG "Warning###Ver:$g_version upload times exceed max [$g_normal_upload_max], skip upload."
            let g_skip_upload=1
            return
        fi
        echo $normal_boot_hash >log_hash.txt
    fi
    
    #echo "Curret Boot Time:${g_cur_boot_rec[@]}"
    #echo "Threshold:${g_time_threshold_chk[@]}"
    #echo "Time check result:${g_time_threshold_chk[@]}"
    
    #int excced max.
    if [ $g_time_threshold_chk[3] == 1 ]; then
        open_log_flags
    fi
}

function calc_avg_times()
{
    for i1 in `seq 1 $g_valid_cnt`    
    do
        let i2=$i1-1
        let base=$i2*$g_rec_items
        
        for k1 in `seq 1 $g_times_cnt`
        do
            k2=$k1-1
            let off=$base+$idx_time_base
            let off=$off+$k2
            let tmp=${g_times_avg[$k2]}+${g_boot_rec[off]}
            g_times_avg[$k2]=$tmp
        done
    done
    
    for i in `seq 1 $g_times_cnt`
    do
        let j=$i-1
        g_times_avg[$j]=`expr ${g_times_avg[$j]} / $g_valid_cnt`
    done
    #echo avg:${g_times_avg[@]}
    sleep 1
}

function write_avg_times_to_part()
{
    if [ $g_partiton_supprt -eq 0 ]; then 
        _LOG "write_avg_times_to_part logdump is not support."
        return
    fi
    rm -rf write_avg.txt
    
    printf "Times=$g_valid_cnt;\n" >write_avg.txt
    printf "%-10s%-7s%-7s%-7s%-7s%-7s%-7s%-7s%-7s%-7s%-7s%-7s%-7s%-7s%-7s%-7s%-7s%-7s%-7s%-7s\n" "no:" "boot1" "boot2" "boots" "init" "bsp" "fwks" "all" "fwk1" "fwk2" "fwk3" "fwk4" "fwk5" "fwk6" "fwk7" "fwk8" "fwk9" "fwk10" "fwk11" "fwk12"  >>write_avg.txt
    
    #printf "\n%-10s" "no:">>write_avg.txt
    for i1 in `seq 1 $g_valid_cnt`    
    do
        let i2=$i1-1
        let base=$i2*$g_rec_items
        printf "%-10s" "$i1">>write_avg.txt
        for k1 in `seq 1 $g_times_cnt`
        do
            k2=$k1-1
            let off=$base+$idx_time_base
            let off=$off+$k2
            if [ $k1 -eq $g_times_cnt ]; then
                printf "%-7s\n" "${g_boot_rec[off]}">>write_avg.txt
            else
                printf "%-7s" "${g_boot_rec[off]}">>write_avg.txt
            fi
        done
    done
    #boot time info
    printf "\n%-10s" "avgTime:">>write_avg.txt

    for i in `seq 1 $g_times_cnt`
    do
        let j=$i-1
        if [ $j -eq $g_times_cnt ]; then
            printf "%-7s\n" "${g_times_avg[$j]}">>write_avg.txt
        else
            printf "%-7s" "${g_times_avg[$j]}">>write_avg.txt
        fi
    done
    printf "\n" >>write_avg.txt
    #echo $content > write_avg.txt
    _LOG_FILE "write_avg.txt"
    
    let seek=`expr $g_BASE_ADDR + $g_boot_avg_OFFSET`
    #echo ""seek=$seek"
    #echo "dd of=/dev/block/by-name/logdump if=$g_work_dir_base/write_avg.txt bs=1 seek=$seek count=2048"
    dd of=/dev/block/by-name/logdump if=$g_work_dir_base/write_avg.txt bs=1 seek=$seek count=2048 > /dev/null 2>&1
}

function get_upload_cnt_info()
{
    if [ -f "uploadcount.txt" ] && [ -f "last_version.txt" ]; then
        last_ver=`cat last_version.txt`
        if [ "$g_version" == "$last_ver" ]; then
            let g_cur_ver_upload_time=`cat uploadcount.txt`
        else
            let g_cur_ver_upload_time=0
        fi
    else
        let g_cur_ver_upload_time=0
    fi
}

function update_upload_cnt_info()
{    
    if [ $g_cur_ver_upload_time -gt $g_normal_upload_max ]; then
        _LOG "Warning###Ver:$g_version upload times exceed max [$g_normal_upload_max]."
    else
        let g_cur_ver_upload_time++
    fi
    
    echo $g_cur_ver_upload_time > uploadcount.txt
    _LOG upload_time:$g_cur_ver_upload_time
}

function generate_log_files()
{
    echo  "run generate_log_files"
    rm -rf logs
    rm boottime_log.tar.gz -rf
    mkdir logs
    cd logs
    
    cp ../errlog0.tar.gz ./
    rm ../errlog0.tar.gz -rf
    
    mv /data/boottime/errlog* /data/logData/    
    cp ../* ./ -rf
    mv /data/logData/errlog* /data/boottime/
    
    if [ "$g_vendor" == "QCOM" ]; then
        if [ -f "/proc/blog/0" ]; then
            cat /proc/blog/0 > blog.txt
            cat blog.txt | grep -E 'UEFI Start|UEFI Total|Shutting Down|Start EBS' > blog_summary.txt
        fi        
    elif [ "$g_vendor" == "MTK" ]; then
        cat /proc/bootprof > bootprof.txt
        cat /proc/bootprof | grep -E ': preloader|: bl2_ext|: tfa|: sec_os|: gz|: lk' > bootloaderTime.txt
    fi
    
    /system/bin/dmesg > dmesg.txt

    getprop > prop.txt
    #cat prop.txt | grep ro.boottime.init > prop_initboot.txt    
    /system/bin/logcat -t 10000 -d -f logcat.txt
    cd ..
    #mv /data/boottime/errlog* /data/logData/
    tar zcvf boottime_log.tar.gz logs >/dev/null
    #mv /data/logData/errlog* /data/boottime
    sleep 1
    show_file_list=`ls -l boottime_log.tar.gz`
    _LOG "$show_file_list"
    
    show_file_list=`ls -l logs`
    _LOG "$show_file_list"
}

function generate_upload_file()
{
    time_prefix=""
    filename_prefix=""
    
    generate_log_files
    
    hash=`md5sum -b boottime_log.tar.gz`
    if [ "$g_boot_type" == "$BOOT_TYPE_FIRST" ]; then
        prefix="F"
        filename_prefix="0first"
        mv boottime_log.tar.gz first_boottime_log.tar.gz

        hash="$first_hash_prefix""${hash:6}"
        echo $hash>first_log_hash.txt
        _LOG "BOOT_TYPE_FIRST"
    elif [ "$g_boot_type" == "$BOOT_TYPE_NORMAL" ]; then
        prefix="B"
        filename_prefix="normal"
        _LOG "g_abnormal_upload:$g_abnormal_upload"
        if [ $g_abnormal_upload -eq 1 ]; then            
            hash="$normal_hash_prefix""${hash:6}"
            _LOG "normal_boot_hash=1, HASH:$hash"
        else
            hash=$normal_boot_hash
            _LOG "normal_boot_hash!=1, HASH:$hash"
        fi
        
        if [ ! -f "log_hash.txt" ]; then
            echo $hash >log_hash.txt
        fi
        
        _LOG "FIANL HASH, HASH:$hash"
        _LOG "BOOT_TYPE_NORMAL"
    elif [ "$g_boot_type" == "$BOOT_TYPE_UPGRADE" ]; then
        prefix="U"
        filename_prefix="upgrade"
        hash="$upgrade_hash_prefix""${hash:6}"
        echo $hash >log_hash.txt
        _LOG "BOOT_TYPE_UPGRADE"
    fi
    
    file_name="${filename_prefix}_time_upload.txt"
    _LOG "HASH:$hash,file_name:$file_name"
    rm -rf $file_name
    printf "%s" "#">$file_name
    for i in `seq 1 $g_times_cnt`
    do
        let j=$i-1
        let off=$j+$idx_time_base
        printf "%s#" "${g_cur_boot_rec[off]}">>$file_name
    done
    printf "%s\n" "">>$file_name
    _LOG_FILE $file_name
}

function trigger_upload()
{
    usr_guide=`settings get global device_provisioned`
    if [ "$usr_guide" != "1" ]; then
        _LOG "User Guide = [$usr_guide], no Finish, will upload next boot!"
    else
        _LOG "User Guide = [$usr_guide], Finish"
        _LOG "vivo_boottime_upload.... start"
        ls -l
        /system/bin/vivo_boottime_upload
        _LOG "upload status:$?"
        if [ $? -eq 0 ]; then
            
            let g_upload_status=1
        fi
        ls -l
        _LOG "vivo_boottime_upload.... end"
    fi
}

function clear_log_files()
{
    #rm -rf $g_work_dir_base/*
    mkdir -p $g_work_dir_base
    cd $g_work_dir_base
    ls -l
    rm logs -rf
    #/data/boottime/booted.txt last_slot.txt last_ver.txt   #记录上次开机记录，用于是否为升级开机
    # dmesg.txt post-data 生成的不删除
    # first_time_upload.txt | grep -v first_log_hash.txt #记录上次开机记录，用于判断是否为首次开机。
    find . -type f | grep -v booted | grep -v last | grep -v uploadcount.txt | grep -v errlog | grep -v dmesg.txt | grep -v first_time_upload.txt | grep -v first_log_hash.txt | grep -v first_boottime_log.tar.gz | xargs rm -rf
    ls -l
    let logsize=`du -sb /data/boottime |awk '{print $1}'`
    _LOG "/data/boottime dir size:$logsize bytes"
    #如果log目录超过100M，删除超过10M的文件。
    if [ $logsize -gt 100 ]; then
        find -type f -size +10M | xargs rm -rf
    fi
}

function Init()
{
    _LOG "Start boottime.sh"
    
    _LOG "Tool Version:$g_Tool_Version"
    _LOG "Tool Update Date:$g_Tool_Update_Data"
    
    if [ -f "$FILE_BOOTED" ]; then
        _LOG_FILE $FILE_BOOTED
    fi    
}

function generate_maker_file()
{
    if [ ! -f "$FILE_BOOTED" ]; then
        RTC=`/system/bin/hwclock`    

        current_date=$(date +"%Y-%m-%d")
        current_time=$(date +"%H_%M_%S")

        current_date="$current_date""_"
        current_time="$current_time"
        UTC=$current_date$current_time
        RTC=${RTC:0:19}
        #echo $RTC
        #echo $UTC
        RTC=`echo "$RTC" | sed 's/ /:/g'`
        echo "First Boot Time:RTC=$RTC,UTC=$UTC" >$FILE_BOOTED
        if [ -f "$FILE_BOOTED" ]; then
            _LOG "$FILE_BOOTED generated."
            _LOG_FILE $FILE_BOOTED
        fi
    fi
    
    rm $FILE_LAST_SLOT -rf
    getprop ro.boot.slot_suffix > $FILE_LAST_SLOT
    if [ -f "$FILE_LAST_SLOT" ]; then
        _LOG "$FILE_LAST_SLOT generated."
        _LOG_FILE $FILE_LAST_SLOT
    fi
    
    rm $FILE_LAST_VER -rf
    echo $g_version > $FILE_LAST_VER
    if [ -f "$FILE_LAST_VER" ]; then
        _LOG "$FILE_LAST_VER generated."
        _LOG_FILE $FILE_LAST_VER
    fi
}

function check_part()
{
    #let g_partiton_supprt=0
    #filename="/data/boottime/part_test.img"
    #dd if=/dev/block/by-name/logdump of=$filename bs=1 count=16 skip=104857600 # 100M 读16字节    
    #filesize=$(ls -l "$filename" | awk '{print $5}')
    #if [ -f "$filename" ] && [ "$filesize" != "0" ]; then
    #    _LOG "logdump parttion = 128M."
    #    g_partiton_supprt=1
    #else
    #    _LOG "logdump parttion < 128M."
    #    g_partiton_supprt=0
    #fi
    ##rm -rf $g_partiton_supprt
    g_partiton_supprt=0
}

function Finish()
{
    setprop $UPLOAD_PROP 1
    uploaded=`getprop $UPLOAD_PROP`
    _LOG "$UPLOAD_PROP=[$uploaded]"
    chmod -R 777 /data/boottime
    chmod -R 777 /data/logData/modules/902
    _LOG "Exit boottime.sh"
}

Init
#wait_boot_bootcompleted
check_part
clear_log_files
get_device_info
get_boot_type
get_cur_initlog_flag
clear_log_flags
get_cur_boot_time

if [ "$g_boot_type" == "$BOOT_TYPE_NORMAL" ]; then
    get_upload_cnt_info
    read_rec_from_part
    check_times
    update_local_rec
    write_rec_to_part
    calc_avg_times
    write_avg_times_to_part
fi

if [ $g_skip_upload != 1 ]; then
    generate_upload_file
    trigger_upload
    if [ "$g_boot_type" == "$BOOT_TYPE_NORMAL" ] &&  [ "$g_boot_type" != "$g_abnormal_upload" ]  && [ $g_upload_status -eq 1 ]; then
        update_upload_cnt_info
    fi
fi
    
generate_maker_file

Finish
