#!/bin/sh

reset_zigbee_module()
{
    # pin zigbee reset: GPIOZ_1
    gpioset 0 1=0
    sleep 0.1
    gpioset 0 1=1
    sleep 0.1
}

zigbee_enter_isp_mode()
{
    # pin zigbee boot: GPIOZ_3
    gpioset 0 3=1
    sleep 0.1

    reset_zigbee_module

    gpioset 0 3=0
    sleep 0.1
}

disable_zigbee_isp()
{
    gpioset 0 3=0
    sleep 0.1
}

bflb_pip_install_dependence()
{
    apt-get install python3-dev -y
    pip install pylink-square==0.5.0
    pip install pyserial==3.5
    pip install ecdsa==0.15
    pip install portalocker==2.0.0
    pip install pycryptodome==3.9.8
    pip install bflb-crypto-plus==1.0
    pip install pycklink==0.1.1
}

flash_zigbee()
{
    if [ ! -d "/usr/lib/firmware/bl706/bflb_iot" ]; then
        bflb_pip_install_dependence
        tar -zxvf /lib/firmware/bl706/bflb_iot.tar.gz -C /lib/firmware/bl706/
    fi
    zigbee_enter_isp_mode
    python3 /usr/lib/firmware/bl706/bflb_iot/core/bflb_iot_tool.py --chipname=bl702 --port=/dev/ttyAML3 --baudrate=2000000 --addr=0x0 --firmware="/usr/lib/firmware/bl706/bl706_whole_flash_data.bin" --single

    if [ $? -eq 0 ]; then
        echo "Burn successfully"
    else
        echo "Burning failed, try again"
        bflb_pip_install_dependence
        python3 /usr/lib/firmware/bl706/bflb_iot/core/bflb_iot_tool.py --chipname=bl702 --port=/dev/ttyAML3 --baudrate=2000000 --addr=0x0 --firmware="/usr/lib/firmware/bl706/bl706_whole_flash_data.bin" --single
    fi

    disable_zigbee_isp
}


case "$1" in
    start)
    echo "BL706: start..."
    disable_zigbee_isp
    reset_zigbee_module
    ;;

    restart)
    echo "BL706: restart..."
    disable_zigbee_isp
    reset_zigbee_module
    ;;

    flash)
    echo "BL706: restart..."
    flash_zigbee
    disable_zigbee_isp
    reset_zigbee_module
    ;;

    install)
    echo "BL706: bflb_pip_install_dependence..."
    bflb_pip_install_dependence
    ;;

    *)
    echo "Usage: $0 {start|restart|flash}"
    exit 1
    ;;
esac
