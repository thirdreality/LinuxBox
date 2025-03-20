#!/bin/bash



# Check if /usr/bin/ha exists
if [ ! -f /usr/bin/ha ]; then
    echo "/usr/bin/ha does not exist. Exiting."
    exit 0
fi

# Function: Check if the output contains cpu_percent
check_cpu_percent() {
    echo "$1" | grep -q "cpu_percent"
}


check_observer() {
    # Step 2: Execute ha observer status and check for cpu_percent
    while true; do
        observer_status=$(/usr/bin/ha observer status 2>/dev/null)
        if check_cpu_percent "$observer_status"; then
            break
        else
            echo "Checking ha observer status, retrying in 2 seconds..."
            sleep 2
        fi
    done
}

check_core()
{
    while true; do
        # Step 3: Execute ha core status and check for cpu_percent
        core_status=$(/usr/bin/ha core status 2>/dev/null)
        if ! check_cpu_percent "$core_status"; then
            echo "Checking ha core status, attempting to start core..."
            /usr/bin/ha core start
            sleep 2  # Allow time for core to start
        fi

        # Recheck ha core status
        new_core_status=$(/usr/bin/ha core status 2>/dev/null)
        if check_cpu_percent "$new_core_status"; then
            echo "Success bringup ha core, watchdog exiting."
            break
        else
            echo "Check failed ha core status. Retrying later ..."
            sleep 5  # Allow time for core to start
        fi
    done
}

post_check_core() {
    sleep 15 
    curl -sL ${URL_APPARMOR_PROFILE} > "${DATA_SHARE}/apparmor/hassio-supervisor"
    while true; do
        # Recheck ha core status
        post_core_status=$(/usr/bin/ha core status 2>/dev/null)
        if check_cpu_percent "$post_core_status"; then
            echo "ha core running, watchdog hibernating."
            sleep 15 
        else
            echo "ha core failed, watchdog wakeup."
            break
        fi
    done
}

# main loop
while true; do
    check_observer

    check_core

    post_check_core
done






