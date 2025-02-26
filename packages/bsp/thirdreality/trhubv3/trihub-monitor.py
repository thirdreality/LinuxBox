#!/usr/bin/env python3

import os
import sys
import time
import threading
import subprocess
import signal
import argparse
from enum import Enum
import logging

# Configure logging
logging.basicConfig(level=logging.DEBUG, format='%(asctime)s - %(levelname)s - %(message)s')

class LedState(Enum):
    REBOOT = "reboot"
    FACTORY_RESET = "factory-reset"
    NORMAL = "normal"
    NETWORK_ERROR = "network_error"
    NETWORK_LOST = "network_lost"
    STARTUP = "startup"

class SysFSGPIO:
    BASE_PATH = "/sys/class/gpio"

    @staticmethod
    def export_pin(pin):
        try:
            if not os.path.exists(f"{SysFSGPIO.BASE_PATH}/gpio{pin}"):
                with open(f"{SysFSGPIO.BASE_PATH}/export", "w") as f:
                    f.write(str(pin))
                time.sleep(0.1)
        except IOError as e:
            logging.error(f"Exporting GPIO pin {pin} failed: {e}")

    @staticmethod
    def write_value(pin, value):
        try:
            with open(f"{SysFSGPIO.BASE_PATH}/gpio{pin}/value", "w") as f:
                f.write(str(value))
        except IOError as e:
            logging.error(f"Writing to GPIO pin {pin} failed: {e}")

    @staticmethod
    def read_value(pin):
        try:
            with open(f"{SysFSGPIO.BASE_PATH}/gpio{pin}/value", "r") as f:
                return f.read().strip()
        except IOError as e:
            logging.error(f"Reading from GPIO pin {pin} failed: {e}")
            return None

    @staticmethod
    def set_direction(pin, direction):
        try:
            with open(f"{SysFSGPIO.BASE_PATH}/gpio{pin}/direction", "w") as f:
                f.write(direction)
        except IOError as e:
            logging.error(f"Setting direction for GPIO pin {pin} failed: {e}")

class GpioLed:
    def __init__(self):
        self.RED_PIN = 414
        self.GREEN_PIN = 430
        self.BLUE_PIN = 431
        self._initialize_pins()
    
    def _initialize_pins(self):
        for pin in [self.RED_PIN, self.GREEN_PIN, self.BLUE_PIN]:
            SysFSGPIO.export_pin(pin)
            SysFSGPIO.set_direction(pin, "out")
    
    def set_color(self, red, green, blue):
        pin_states = {self.RED_PIN: red, self.GREEN_PIN: green, self.BLUE_PIN: blue}
        for pin, state in pin_states.items():
            SysFSGPIO.write_value(pin, 1 if state else 0)
    
    def off(self):
        self.set_color(True, True, True)
    
    def red(self):
        self.set_color(False, True, True)
    
    def green(self):
        self.set_color(True, False, True)
    
    def blue(self):
        self.set_color(True, True, False)
    
    def yellow(self):
        self.set_color(False, False, True)
    
    def purple(self):
        self.set_color(False, True, False)
    
    def cyan(self):
        self.set_color(True, False, False)
    
    def white(self):
        self.set_color(False, False, False)

class GpioButton:
    def __init__(self):
        self.BUTTON_PIN = 422
        self._initialize_pin()
    
    def _initialize_pin(self):
        SysFSGPIO.export_pin(self.BUTTON_PIN)
        SysFSGPIO.set_direction(self.BUTTON_PIN, "in")
    
    def is_pressed(self):
        value = SysFSGPIO.read_value(self.BUTTON_PIN)
        return value == "0"

class HwMonitor:
    def __init__(self):
        self.led = GpioLed()
        self.button = GpioButton()
        self.current_state = LedState.STARTUP
        self.state_lock = threading.Lock()
        self.running = threading.Event()
        self.running.set()
        self.threads = []
    
    def set_state(self, state):
        with self.state_lock:
            if state in [LedState.REBOOT, LedState.FACTORY_RESET]:
                self.current_state = state
            elif self.current_state not in [LedState.REBOOT, LedState.FACTORY_RESET]:
                self.current_state = state
    
    def get_state(self):
        with self.state_lock:
            return self.current_state
    
    def led_control_thread(self):
        blink_counter = 0
        while self.running.is_set():
            state = self.get_state()
            blink_counter = (blink_counter + 1) % 2

            if state == LedState.REBOOT:
                self.led.yellow()
            elif state == LedState.FACTORY_RESET:
                self.led.red()
            elif state == LedState.NORMAL:
                self.led.blue()
            elif state == LedState.NETWORK_ERROR:
                if blink_counter == 0:
                    self.led.blue()
                else:
                    self.led.off()
            elif state == LedState.NETWORK_LOST:
                if blink_counter == 0:
                    self.led.yellow()
                else:
                    self.led.off()
            elif state == LedState.STARTUP:
                if blink_counter == 0:
                    self.led.white()
                else:
                    self.led.off()
            
            time.sleep(0.5)
    
    def button_thread(self):
        press_start = None
        reboot_triggered = False
        factory_reset_triggered = False
        
        while self.running.is_set():
            if self.button.is_pressed():
                if press_start is None:
                    press_start = time.time()
                
                press_duration = time.time() - press_start
                
                if press_duration >= 15 and not factory_reset_triggered:
                    self.set_state(LedState.FACTORY_RESET)
                    factory_reset_triggered = True
                    reboot_triggered = False
                elif press_duration >= 5 and not reboot_triggered and not factory_reset_triggered:
                    self.set_state(LedState.REBOOT)
                    reboot_triggered = True
            
            else:
                if press_start is not None:
                    press_duration = time.time() - press_start
                    
                    if factory_reset_triggered:
                        self._perform_factory_reset()
                    elif reboot_triggered:
                        self._perform_reboot()
                    
                    press_start = None
                    reboot_triggered = False
                    factory_reset_triggered = False
            
            time.sleep(0.1)
    
    def network_thread(self):
        self.set_state(LedState.STARTUP)
        
        while self.running.is_set():
            wlan0_up = self._is_interface_up("wlan0")
            
            if not wlan0_up:
                self.set_state(LedState.NETWORK_LOST)
                time.sleep(5)
                continue
            
            if self._is_network_connected():
                self.set_state(LedState.NORMAL)
            else:
                self.set_state(LedState.NETWORK_LOST)
            
            time.sleep(5)
    
    def _is_interface_up(self, interface):
        try:
            with open(f"/sys/class/net/{interface}/operstate", "r") as f:
                state = f.read().strip()
                return state == "up"
        except (FileNotFoundError, IOError):
            return False
    
    def _is_network_connected(self):
        try:
            result = subprocess.run(
                ["iw", "dev", "wlan0", "link"],
                capture_output=True, 
                text=True
            )
            return "Connected" in result.stdout
        except subprocess.SubprocessError:
            return False

    def _perform_reboot(self):
        logging.info("Performing reboot...")
        self.set_state(LedState.REBOOT)
        try:
            subprocess.run(["systemctl", "stop", "docker"])
            subprocess.run(["reboot"])
        except subprocess.SubprocessError as e:
            logging.error(f"Error during reboot: {e}")
    
    def _perform_factory_reset(self):
        logging.info("Performing factory reset...")
        self.set_state(LedState.FACTORY_RESET)
        try:
            subprocess.run(["systemctl", "stop", "docker"])
            if os.path.exists("/etc/NetworkManager/system-connections"):
                for file in os.listdir("/etc/NetworkManager/system-connections"):
                    os.remove(os.path.join("/etc/NetworkManager/system-connections", file))
            subprocess.run(["reboot"])
        except Exception as e:
            logging.error(f"Error during factory reset: {e}")
    
    def start(self):
        logging.info("Starting hardware monitor...")
        
        self.threads = [
            threading.Thread(target=self.led_control_thread, daemon=True),
            threading.Thread(target=self.button_thread, daemon=True),
            threading.Thread(target=self.network_thread, daemon=True)
        ]
        
        for thread in self.threads:
            thread.start()
        
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)
        
        self.running.wait()
    
    def stop(self):
        logging.info("Stopping hardware monitor...")
        self.running.clear()
        self.led.off()
        for thread in self.threads:
            thread.join()
    
    def _signal_handler(self, sig, frame):
        self.stop()
        sys.exit(0)

def main():
    parser = argparse.ArgumentParser(description='Hardware Monitor for LED and button control')
    subparsers = parser.add_subparsers(dest='command', help='Commands')
    
    daemon_parser = subparsers.add_parser('daemon', help='Start hardware monitor daemon')
    
    set_parser = subparsers.add_parser('set', help='Set LED state')
    set_parser.add_argument('state', choices=[s.value for s in LedState], help='LED state to set')
    
    args = parser.parse_args()
    
    if args.command == 'daemon':
        monitor = HwMonitor()
        monitor.start()
    elif args.command == 'set':
        state = args.state
        led = GpioLed()
        
        if state == LedState.REBOOT.value:
            led.yellow()
        elif state == LedState.FACTORY_RESET.value:
            led.red()
        elif state == LedState.NORMAL.value:
            led.blue()
        elif state == LedState.NETWORK_ERROR.value:
            led.blue()
            time.sleep(0.5)
            led.off()
        elif state == LedState.NETWORK_LOST.value:
            led.yellow()
            time.sleep(0.5)
            led.off()
        elif state == LedState.STARTUP.value:
            led.white()
            time.sleep(0.5)
            led.off()
        
        logging.info(f"LED state set to: {state}")
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
