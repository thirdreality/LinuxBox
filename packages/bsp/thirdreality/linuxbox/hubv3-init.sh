#!/bin/bash

GPIO_DIRECTION_OUTPUT=0
GPIO_DIRECTION_INPUT=1

GPIO_ACTIVE_LOW=0
GPIO_ACTIVE_HIGH=1

GPIOS=(
  # Zigbee module: RESET, BOOT
  "427 ${GPIO_DIRECTION_OUTPUT} ${GPIO_ACTIVE_HIGH}"
  "429 ${GPIO_DIRECTION_OUTPUT} ${GPIO_ACTIVE_HIGH}"
)


configure_gpio() {
  echo "${0}: Configure: gpio=${1}, direction=${2}, active_level=${3}"

  if [ ! -d /sys/class/gpio/gpio${1} ]; then
    echo ${1} > /sys/class/gpio/export
    if [ ! -d /sys/class/gpio/gpio${1} ]; then
      echo "${0}: *** Error: Failed to configure GPIO ${1}"
      exit 1
    fi
  fi

  if [ "${2}" == "${GPIO_DIRECTION_OUTPUT}" ]; then
    echo "out" > /sys/class/gpio/gpio${1}/direction
  else
    echo "in" > /sys/class/gpio/gpio${1}/direction
  fi

#   if [ "${3}" == "${GPIO_ACTIVE_LOW}" ]; then
#     echo 1 > /sys/class/gpio/gpio${1}/active_low
#   fi 
}

echo "${0}: Configure Linuxbox GPIOs ..."

# for gpio_parameters in "${GPIOS[@]}"
# do
#  configure_gpio ${gpio_parameters}
# done

# echo "${0}: Reset Zigbee module ..."
# echo 1 > /sys/class/gpio/gpio462/value
# echo 1 > /sys/class/gpio/gpio467/value
# sleep 1
# echo 0 > /sys/class/gpio/gpio467/value

echo "${0}: Reset Linuxbox Zigbee module ..."
gpioset 0 3=0
sleep 0.5
gpioset 0 1=1
sleep 0.5
gpioset 0 1=0
sleep 0.5
gpioset 0 1=1

exit 0
