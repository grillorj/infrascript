#!/bin/sh
LANG=C
export LANG

clean() {
    v=$(printf '%s' "$1" | tr -d '\r' | tr '|\n' '/ ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -z "$v" ] && v="N/A"
    printf '%s' "$v"
}

find_azcmagent() {
    if [ -x /opt/azcmagent/bin/azcmagent ]; then
        echo /opt/azcmagent/bin/azcmagent
        return
    fi
    command -v azcmagent 2>/dev/null
}

run_limited() {
    if command -v timeout >/dev/null 2>&1; then
        timeout 20 "$@" 2>/dev/null
    else
        "$@" 2>/dev/null
    fi
}

json_value() {
    # $1 = JSON text, $2 = key (case-insensitive match on the key name)
    printf '%s\n' "$1" | tr -d '\n' | grep -io "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed 's/^[^:]*:[[:space:]]*"//;s/"$//'
}

text_value() {
    # $1 = text, $2 = label
    printf '%s\n' "$1" | sed -n "s/^[[:space:]]*$2[[:space:]]*:[[:space:]]*//p" | head -1
}

service_state() {
    # $1 = label, $2 = unit name
    if [ "$HAVE_SYSTEMCTL" != "yes" ]; then
        printf '%s=unknown' "$1"
        return
    fi
    load=$(systemctl show -p LoadState "$2.service" 2>/dev/null | sed 's/^LoadState=//')
    if [ "$load" != "loaded" ]; then
        printf '%s=notfound' "$1"
        return
    fi
    st=$(systemctl is-active "$2.service" 2>/dev/null)
    case "$st" in
        active) st=running ;;
        inactive) st=stopped ;;
        "") st=unknown ;;
    esac
    printf '%s=%s' "$1" "$st"
}

HAVE_SYSTEMCTL=no
command -v systemctl >/dev/null 2>&1 && HAVE_SYSTEMCTL=yes

AZ=$(find_azcmagent)
if [ -z "$AZ" ]; then
    echo "No|Not installed|Not installed|||||"
    exit 0
fi

SERVICES="$(service_state himds himdsd);$(service_state arcproxy arcproxyd);$(service_state extensionservice extd);$(service_state gcarcservice gcad)"

JSON=$(run_limited "$AZ" show -j)
version=$(json_value "$JSON" agentVersion)
status=$(json_value "$JSON" status)
rname=$(json_value "$JSON" resourceName)
rgroup=$(json_value "$JSON" resourceGroup)
sub=$(json_value "$JSON" subscriptionId)
tenant=$(json_value "$JSON" tenantId)
beat=$(json_value "$JSON" lastHeartbeat)

if [ -z "$status" ]; then
    TEXT=$(run_limited "$AZ" show)
    if [ -z "$TEXT" ]; then
        ver=$(run_limited "$AZ" version | grep -o '[0-9][0-9]*\(\.[0-9][0-9]*\)\+' | head -1)
        echo "Yes|$(clean "$ver")|Error: azcmagent show failed or timed out|N/A|N/A|N/A|N/A|N/A|$SERVICES"
        exit 0
    fi
    version=$(text_value "$TEXT" "Agent Version")
    status=$(text_value "$TEXT" "Agent Status")
    rname=$(text_value "$TEXT" "Resource Name")
    rgroup=$(text_value "$TEXT" "Resource Group Name")
    [ -z "$rgroup" ] && rgroup=$(text_value "$TEXT" "Resource Group")
    sub=$(text_value "$TEXT" "Subscription ID")
    tenant=$(text_value "$TEXT" "Tenant ID")
    beat=$(text_value "$TEXT" "Agent Last Heartbeat")
    [ -z "$beat" ] && beat=$(text_value "$TEXT" "Last Heartbeat")
fi

if [ -z "$version" ]; then
    version=$(run_limited "$AZ" version | grep -o '[0-9][0-9]*\(\.[0-9][0-9]*\)\+' | head -1)
fi

echo "Yes|$(clean "$version")|$(clean "$status")|$(clean "$rname")|$(clean "$rgroup")|$(clean "$sub")|$(clean "$tenant")|$(clean "$beat")|$SERVICES"
exit 0
