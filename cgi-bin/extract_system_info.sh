#!/bin/sh

# Set content type to json
echo "Content-Type: application/json"
echo ""  # Separate header from body

extract_sys_info() {
    json_data=$(cat /etc/board.json)
    openwrt_release=$(cat /etc/openwrt_release)
    memory=$(cat /proc/meminfo)
    
    json_output="{"
    model=$(echo "$json_data" | sed -n 's/.*"name": "\(.*\)"/\1/p')
    host=$(echo "$openwrt_release" | awk -F"='" '/DISTRIB_ID/ {gsub(/'\''/, "", $2); print $2}')
    arch=$(echo "$openwrt_release" | awk -F"='" '/DISTRIB_ARCH/ {gsub(/'\''/, "", $2); print $2}')
    target=$(echo "$openwrt_release" | awk -F"='" '/DISTRIB_TARGET/ {gsub(/'\''/, "", $2); print $2}')
    kerVer=$(uname -a | grep "OpenWrt" | awk '{print $3}')
    date=$(date)
    memAvail=$(echo "$memory" | grep "MemAvailable:" | awk '{print $2}')
    memTotal=$(echo "$memory" | grep "MemTotal:" | awk '{print $2}')
    memUsed=$(free -m | awk 'NR==2 {print $3}')
    cache=$(echo "$memory" | awk 'NR==5 {print $2}')
    totStorage=$(df | awk 'NR==5 {print $2}')
    usedStorage=$(df | awk 'NR==5 {print $3}')
    perStorage=$(df | awk 'NR==5 {gsub("%", "", $5); print $5}')
    totTmp=$(df | awk 'NR==3 {print $2}')
    usedTmp=$(df | awk 'NR==3 {print $3}')
    perTmp=$(df | awk 'NR==3 {gsub("%", "", $5); print $5}')
    fwBlk=$(df | awk 'NR==7 {print $1}')
    fwDir=$(df | awk 'NR==7 {print $6}')
    fwTotMem=$(df | awk 'NR==7 {print $2}')
    fwUsedMem=$(df | awk 'NR==7 {print $3}')
    perFwMem=$(df | awk 'NR==7 {gsub("%", "", $5); print $5}')

    json_output="${json_output}\"model\":\"${model}\""
    [ -n "$host" ] && json_output="${json_output},\"host\":\"${host}\""
    [ -n "$arch" ] && json_output="${json_output},\"arch\":\"${arch}\""
    [ -n "$target" ] && json_output="${json_output},\"target\":\"${target}\""
    [ -n "$kerVer" ] && json_output="${json_output},\"kernel\":\"${kerVer}\""
    [ -n "$date" ] && json_output="${json_output},\"date\":\"${date}\""
    [ -n "$memAvail" ] && json_output="${json_output},\"memAvail\":\"${memAvail}\""
    [ -n "$memTotal" ] && json_output="${json_output},\"memTotal\":\"${memTotal}\""
    [ -n "$memUsed" ] && json_output="${json_output},\"memUsed\":\"${memUsed}\""
    [ -n "$cache" ] && json_output="${json_output},\"cache\":\"${cache}\""
    [ -n "$totStorage" ] && json_output="${json_output},\"totStorage\":\"${totStorage}\""
    [ -n "$usedStorage" ] && json_output="${json_output},\"usedStorage\":\"${usedStorage}\""
    [ -n "$perStorage" ] && json_output="${json_output},\"perStorage\":\"${perStorage}\""
    [ -n "$totTmp" ] && json_output="${json_output},\"totTmp\":\"${totTmp}\""
    [ -n "$usedTmp" ] && json_output="${json_output},\"usedTmp\":\"${usedTmp}\""
    [ -n "$perTmp" ] && json_output="${json_output},\"perTmp\":\"${perTmp}\""
    [ -n "$fwBlk" ] && json_output="${json_output},\"fwBlk\":\"${fwBlk}\""
    [ -n "$fwDir" ] && json_output="${json_output},\"fwDir\":\"${fwDir}\""
    [ -n "$fwTotMem" ] && json_output="${json_output},\"fwTotMem\":\"${fwTotMem}\""
    [ -n "$fwUsedMem" ] && json_output="${json_output},\"fwUsedMem\":\"${fwUsedMem}\""
    [ -n "$perFwMem" ] && json_output="${json_output},\"perFwMem\":\"${perFwMem}\""
    
    json_output="${json_output}}"

    echo "$json_output"
}

extract_sys_info