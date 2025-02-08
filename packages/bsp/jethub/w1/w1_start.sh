#!/bin/sh

insmod /usr/lib/modules/$(uname -r)/kernel/drivers/net/wireless/w1/vmac/aml_sdio.ko
insmod /usr/lib/modules/$(uname -r)/kernel/drivers/net/wireless/w1/vmac/vlsicomm.ko

