#!/bin/sh
# refer to pinctrl-meson-axg.c

reset_module()
{
    if [ "$1" = "zigbee" ]; then
        # Zigbee reset: DB_RSTN1/GPIOZ_1
        gpioset 0 1=0
        sleep 0.1
        gpioset 0 1=1
    elif [ "$1" = "thread" ]; then
        # Thread reset: DB_RSTN2/GPIOA_1
        gpioset 0 27=0
        sleep 0.1
        gpioset 0 27=1
    else
        echo "Invalid mode: $1. Use 'zigbee' or 'thread'."
        exit 1
    fi
    sleep 0.1
}

enter_isp_mode()
{
    if [ "$1" = "zigbee" ]; then
        # Zigbee boot: DB_BOOT1/GPIOZ_3
        gpioset 0 3=1
        sleep 0.1

        reset_module "zigbee"

        gpioset 0 3=0
    elif [ "$1" = "thread" ]; then
        # Thread boot: DB_BOOT2/GPIOA_3
        gpioset 0 29=1
        sleep 0.1

        reset_module "thread"

        gpioset 0 29=0
    else
        echo "Invalid mode: $1. Use 'zigbee' or 'thread'."
        exit 1
    fi

    sleep 0.1
}

disable_isp()
{
    if [ "$1" = "zigbee" ]; then
        # Zigbee boot: DB_BOOT1/GPIOZ_3
        gpioset 0 3=0
    elif [ "$1" = "thread" ]; then
        # Thread boot: DB_BOOT2/GPIOA_3
        gpioset 0 29=0
    fi
    sleep 0.1
}

bflb_pip_install_dependence()
{
    #apt-get install python3-dev -y
    pip install pylink-square==0.5.0 --break-system-packages
    pip install pyserial==3.5 --break-system-packages
    pip install ecdsa==0.15 --break-system-packages
    pip install portalocker==2.0.0 --break-system-packages
    pip install pycryptodome==3.9.8 --break-system-packages
    pip install bflb-crypto-plus==1.0 --break-system-packages
    pip install pycklink==0.1.1 --break-system-packages
}

flash_firmware()
{
    mode=$1
    image_size=$2
    image_size_dir=""

    if [ "$image_size" = "1m" ]; then
        image_size_dir="partition_1m_images"
    elif [ "$image_size" = "2m" ]; then
        image_size_dir="partition_2m_images"
    else
        echo "Invalid image size: $image_size. Use '1m' or '2m'."
        exit 1    
    fi

    if [ "$mode" = "zigbee" ]; then
        port="/dev/ttyAML3"
        firmware="/usr/lib/firmware/bl706/${image_size_dir}/zigbee_whole_img.bin"

        # define GPIOX_17	64
        # gpioget 0 64
    elif [ "$mode" = "thread" ]; then
        port="/dev/ttyAML6"
        firmware="/usr/lib/firmware/bl706/${image_size_dir}/thread_whole_img.bin"
    else
        echo "Invalid mode: $mode. Use 'zigbee' or 'thread'."
        exit 1
    fi

    if [ ! -d "/usr/lib/firmware/bl706/bflb_iot" ]; then
        bflb_pip_install_dependence
        tar -zxvf /lib/firmware/bl706/bflb_iot.tar.gz -C /lib/firmware/bl706/
    fi

    enter_isp_mode $mode

    echo "Burning Image, mode: $mode. port: $port . firmware: $firmware"
    python3 /usr/lib/firmware/bl706/bflb_iot/core/bflb_iot_tool.py --chipname=bl702 --port=$port --baudrate=2000000 --addr=0x0 --firmware="$firmware" --single

    if [ $? -eq 0 ]; then
        echo "Burn successfully"
    else
        echo "Burning failed, try again"
        bflb_pip_install_dependence
        python3 /usr/lib/firmware/bl706/bflb_iot/core/bflb_iot_tool.py --chipname=bl702 --port=$port --baudrate=2000000 --addr=0x0 --firmware="$firmware" --single
    fi

    disable_isp $mode
}

case "$1" in
    start)
    mode=${2:-zigbee}  # default to zigbee if no second argument
    echo "BL706: start $mode ..."
    disable_isp $mode # Default to zigbee if mode not specified
    reset_module $mode
    ;;

    restart)
    mode=${2:-zigbee}  # default to zigbee if no second argument
    echo "BL706: restart $mode ..."
    disable_isp $mode # Default to zigbee if mode not specified
    reset_module $mode
    ;;

    flash)
    mode=${2:-zigbee}  # [zigbee|thread]: default to zigbee if no second argument
    image_size=${3:-1m}  # [1m|2m]: default to 1m
    echo "BL706: flash $mode with images size: $image_size ..."
    flash_firmware $mode $image_size
    disable_isp $mode
    reset_module $mode
    ;;

    install)
    echo "BL706: bflb_pip_install_dependence..."
    bflb_pip_install_dependence
    ;;

    *)
    echo "Usage: $0 {start [zigbee|thread]|restart [zigbee|thread]|flash [zigbee|thread] [1m|2m]|install}"
    exit 1
    ;;
esac

