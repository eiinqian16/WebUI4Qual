#! /bin/sh

DEVICE="/dev/ttyUSB2"
max_wait=120
count=0
TEST_TARGET="8.8.8.8"

get_modem() {
    local usb_file="/sys/kernel/debug/usb/devices"

    if [ ! -f "$usb_file" ]; then
        mount -t debugfs none /sys/kernel/debug 2>/dev/null
        [ ! -f "$usb_file" ] && return 1
    fi

    awk '
    /^T:/ {
        is_modem = 0
        current_product = ""
    }

    /^S:[[:space:]]+Product=/ {
        # Strip the label to get just the model name
        p = $0
        sub(/^S:[[:space:]]+Product=/, "", p)
        # Clean up carriage returns
        gsub(/\r/, "", p)
        current_product = p
    }

    /Driver=(option|qmi_wwan|cdc_ether|cdc_mbim|qmi)/ {
        is_modem = 1
    }

    {
        if (is_modem && current_product != "" && current_product !~ /HUB/ && current_product !~ /Controller/) {
            # Trim leading/trailing spaces one last time
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", current_product)
            # Map hardware identification string to model name
            if (current_product == "5G Module") current_product = "SRM810"
            print current_product
            exit 0
        }
    }
    ' "$usb_file"
}

get_sim_det_script() {
    local model="$1"
    case "$model" in
        "RG255AA-CN" | "RG255AA-EU")
            echo "/usr/bin/rg255a_sim_det.sh"
            logger -t "rc.local" "Selected SIM detection script for $model"
            ;;
        "Asrmicro")
            echo "/usr/bin/a7908e_sim_det.sh"
            logger -t "rc.local" "Selected SIM detection script for $model"
            ;;
        "SRM810")
            echo "/usr/bin/srm810_sim_det.sh"
            logger -t "rc.local" "Selected SIM detection script for $model"
            ;;
        "RM500U" | "RM500U-"*)
            echo "/usr/bin/rm500u_sim_det.sh"
            logger -t "rc.local" "Selected SIM detection script for $model"
            ;;
        *)
            echo "Unknown modem model: $model. No SIM detection script available." >&2
            return 1
            ;;
    esac
}

get_script() {
    if [ -c "$DEVICE" ]; then
        logger -t "rc.local" "Modem device $DEVICE is present."
        case "$MODEL" in
        "RG255AA-CN" | "RG255AA-EU")
            logger -t "rc.local" "Using RG255AA auto config script"
            script="/usr/bin/rg255a_auto_config.sh"
            ;;
        "Asrmicro")
            logger -t "rc.local" "Using A7908E auto config script"
            script="/usr/bin/a7908e_auto_config.sh"
            ;;
        "SRM810")
            logger -t "rc.local" "Using SRM810 auto config script"
            script="/usr/bin/srm810_auto_config.sh"
            ;;
        "RM500U" | "RM500U-"*)
            logger -t "rc.local" "Using RM500U auto config script"
            script="/usr/bin/rm500u_auto_config.sh"
            ;;
        *)
            logger -t "rc.local" "Unknown modem model: $MODEL. Skipping auto configuration."
            exit
            ;;
        esac
    else
        logger -t "rc.local" "Error: Modem device $DEVICE not found. Exiting auto configuration."
        exit 1
    fi
}

get_stats_script() {
    case "$MODEL" in
        "RG255AA-CN" | "RG255AA-EU")
            echo "/www/webUI/cgi-bin/rg255a_get_lte_stats.sh"
            ;;
        "Asrmicro")
            echo "/www/webUI/cgi-bin/a7908e_get_lte_stats.sh"
            ;;
        "SRM810")
            echo "/www/webUI/cgi-bin/srm810_get_lte_stats.sh"
            ;;
        "RM500U" | "RM500U-"*)
            echo "/www/webUI/cgi-bin/rm500u_get_lte_stats.sh"
            ;;
        *)
            echo "Unknown modem model: $MODEL. No stats script available." >&2
            return 1
            ;;
    esac
}

check_internet() {
    # Ping once with a 2-second timeout
    if ping -I usb0 -c 1 -W 2 $TEST_TARGET >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

MODEL=$(get_modem)
echo "$MODEL" > /tmp/modem_model
if [ ! -L "/www/webUI/modem_model" ]; then
    ln -s /tmp/modem_model /www/webUI/modem_model
fi

logger "rc.local" "Detecting SIM ICCID ..."

DET_SCRIPT=$(get_sim_det_script "$MODEL" 2>/dev/null)
logger -t "rc.local" "Using SIM detection script: ${DET_SCRIPT:-None}"

if [ -n "$DET_SCRIPT" ] && [ -x "$DET_SCRIPT" ]; then
    $DET_SCRIPT > /tmp/sim_det.log 2>&1
fi

if [ "$MODEL" != "RM500U-"* ]; then
    sleep 60
else
    sleep 5
fi

if check_internet; then
        logger "rc.local" "Detected $MODEL"
        logger "rc.local" "Internet is ALREADY READY. No changes needed."
else
    get_script
    logger -t "rc.local" "Initializing LTE auto configuration ..."
    $script >> /tmp/auto_config.log
    sleep 2

    logger -t "rc.local" "Initializing Internet connection ..."
    /usr/bin/initialize_int.sh 
    sleep 10
fi

stats_script=$(get_stats_script "$MODEL")
logger -t "rc.local" "Using LTE data retrieval script: ${stats_script:-None}"
logger -t "rc.local" "Initializing LTE data retrieval ..."
if [ -n "$stats_script" ] && [ -x "$stats_script" ]; then
    $stats_script > /tmp/stats_retrieve.log 2>&1
fi
sleep 2

logger -t "rc.local" "Populating frequency list ..."
/usr/bin/get_supported_freq_list.sh > /tmp/freq_debug.log 2>&1

/etc/init.d/uhttpd restart

if [ -n "$stats_script" ] && [ -x "$stats_script" ]; then
    stats_file="/tmp/lte_stats"
    retry_count=0
    max_retries=3

    # Check if file exists and contains the failure string
    while [ $retry_count -lt $max_retries ]; do
        if [ -f "$stats_file" ] && grep -q "No operator detected" "$stats_file"; then
            retry_count=$((retry_count + 1))
            logger -t "rc.local" "Warning: 'No operator detected' found in $stats_file. Retrying stats fetch ($retry_count/$max_retries)..."
            
            sleep 5
            $stats_script > /tmp/stats_retrieve.log 2>&1
        else
            # Operator detected cleanly, exit validation loop
            break
        fi
    done
fi

/usr/bin/prodinfo.sh > /tmp/prod_info.log 2>&1