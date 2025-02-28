#!/usr/bin/env python3

# maintainer: guoping.liu@thirdreality.com

import os
import sys
import time
import threading
import subprocess
import signal
import argparse
import socket
import logging
from enum import Enum

# Configure logging
logging.basicConfig(level=logging.DEBUG, format='%(asctime)s - %(levelname)s - %(message)s')

class LedState(Enum):
    REBOOT = "reboot"
    FACTORY_RESET = "factory-reset"
    NORMAL = "normal"
    NETWORK_ERROR = "network_error"
    NETWORK_LOST = "network_lost"
    STARTUP = "startup"
    PARING = "paring"
    PARED = "pared"

class SysFSGPIO:
    BASE_PATH = "/sys/class/gpio"

    @staticmethod
    def export_pin(pin):
        if not os.path.exists(f"{SysFSGPIO.BASE_PATH}/gpio{pin}"):
            try:
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
        self.pins = {
            'RED': 414,
            'GREEN': 430,
            'BLUE': 431
        }
        self._initialize_pins()

    def _initialize_pins(self):
        for pin in self.pins.values():
            SysFSGPIO.export_pin(pin)
            SysFSGPIO.set_direction(pin, "out")

    def set_color(self, red, green, blue):
        pin_states = {
            self.pins['RED']: red,
            self.pins['GREEN']: green,
            self.pins['BLUE']: blue
        }
        for pin, state in pin_states.items():
            SysFSGPIO.write_value(pin, 1 if state else 0)

    def off(self): self.set_color(False, False, False)
    def red(self): self.set_color(True, False, False)
    def green(self): self.set_color(False, True, False)
    def blue(self): self.set_color(False, False, True)
    def yellow(self): self.set_color(True, True, False)
    def purple(self): self.set_color(True, False, True)
    def cyan(self): self.set_color(False, True, True)
    def white(self): self.set_color(True, True, True)

class GpioButton:
    BUTTON_PIN = 422

    def __init__(self):
        self._initialize_pin()

    def _initialize_pin(self):
        SysFSGPIO.export_pin(self.BUTTON_PIN)
        SysFSGPIO.set_direction(self.BUTTON_PIN, "in")

    def is_pressed(self):
        return SysFSGPIO.read_value(self.BUTTON_PIN) == "1"

class HwMonitor:
    SOCKET_PATH = "/tmp/led_socket"

    def __init__(self):
        self.led = GpioLed()
        self.button = GpioButton()
        self.current_state = LedState.STARTUP
        self.state_lock = threading.Lock()
        self.running = threading.Event()
        self.running.set()
        self.stop_event = threading.Event()

        self._setup_socket()
        self.threads = [
            threading.Thread(target=self.led_control_thread, daemon=True),
            threading.Thread(target=self.button_thread, daemon=True),
            threading.Thread(target=self.network_thread, daemon=True)
        ]

    def _setup_socket(self):
        if os.path.exists(self.SOCKET_PATH):
            os.remove(self.SOCKET_PATH)
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server.bind(self.SOCKET_PATH)
        self.server.listen(1)
        self.server.settimeout(1.0)

    # 请按照实际使用情况进行挑战
    def set_state(self, state):
        with self.state_lock:
            # 最高优先级：如果新状态是 REBOOT 或 FACTORY_RESET，则无条件地设置状态
            if state in [LedState.REBOOT, LedState.FACTORY_RESET]:
                self.current_state = state
            else:
                # 如果当前状态是 PARING 且新状态是 PARED 或 NORMAL，则转换为 NORMAL
                if self.current_state == LedState.PARING and state == LedState.PARED:
                    self.current_state = LedState.NORMAL
                # 否则，如果当前状态不是 REBOOT, FACTORY_RESET, 或 PARING，则更新状态
                elif self.current_state not in [LedState.REBOOT, LedState.FACTORY_RESET, LedState.PARING]:
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
            elif state == LedState.PARING:
                if blink_counter == 0:
                    self.led.green()
                else:
                    self.led.off()

            time.sleep(0.5)

    def button_thread(self):
        press_start, reboot_triggered, factory_reset_triggered = None, False, False

        while self.running.is_set():
            if self.button.is_pressed():
                if press_start is None: press_start = time.time()
                press_duration = time.time() - press_start

                if press_duration >= 15:
                    self.set_state(LedState.FACTORY_RESET)
                    factory_reset_triggered, reboot_triggered = True, False
                elif press_duration >= 5:
                    self.set_state(LedState.REBOOT)
                    reboot_triggered = True

            else:
                if press_start:
                    if factory_reset_triggered:
                        self._perform_factory_reset()
                    elif reboot_triggered:
                        self._perform_reboot()
                    press_start, reboot_triggered, factory_reset_triggered = None, False, False

            time.sleep(0.5)

    def network_thread(self):
        # 初始状态设为 STARTUP
        self.set_state(LedState.STARTUP)

        check_interval = 2
        time.sleep(check_interval)

        check_interval = 1

        while self.running.is_set():
            if self._is_interface_existing("wlan0"):
                if self._is_network_connected():
                    self.set_state(LedState.NORMAL)
                    check_interval = 3 
                else:
                    if self._has_nmcli_connection():
                        self.set_state(LedState.NETWORK_ERROR)
                    else:
                        self.set_state(LedState.NETWORK_LOST)
            else:
                self.set_state(LedState.STARTUP)

            time.sleep(check_interval)

    def _is_interface_existing(self, interface="wlan0"):
        try:
            with open(f"/sys/class/net/{interface}/operstate", "r"):
                return True
        except FileNotFoundError:
            return False

    def _is_network_connected(self):
        try:
            result = subprocess.run(["iw", "dev", "wlan0", "link"], capture_output=True, text=True)
            return "Connected" in result.stdout
        except subprocess.SubprocessError:
            return False

    def _has_nmcli_connection(self):
        try:
            result = subprocess.run(
                ['nmcli', '-t', '-f', 'TYPE,STATE,NAME', 'connection', 'show', '--active'],
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            return bool(result.stdout.strip())

        except subprocess.CalledProcessError as e:
            print(f"Command 'nmcli' failed with exit code {e.returncode}")
            print(e.stderr)
            return False
        except Exception as e:
            print(f"An unexpected error occurred: {e}")
            return False

    def _perform_reboot(self):
        logging.info("Performing reboot...")
        self.set_state(LedState.REBOOT)
        self._execute_system_command(["systemctl", "stop", "docker"])
        self._execute_system_command(["reboot"])

    def _perform_factory_reset(self):
        logging.info("Performing factory reset...")
        self.set_state(LedState.FACTORY_RESET)
        # 这里可以启动一个脚本
        self._execute_system_command(["systemctl", "stop", "docker"])
        self._clear_wifi_settings()
        self._execute_system_command(["reboot"])

    def _execute_system_command(self, command):
        try:
            subprocess.run(command, check=True)
        except subprocess.SubprocessError as e:
            logging.error(f"Error executing {' '.join(command)}: {e}")

    def _clear_wifi_settings(self):
        try:
            network_path = "/etc/NetworkManager/system-connections"
            if os.path.exists(network_path):
                for file in os.listdir(network_path):
                    path = os.path.join(network_path, file)
                    os.remove(path)
        except Exception as e:
            logging.error(f"Error clearing WiFi settings: {e}")

    def start(self):
        logging.info("Starting HwMonitor...")
        
        for thread in self.threads:
            thread.start()

        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)

        logging.info("Starting local socket monitor...")

        while not self.stop_event.is_set():
            try:
                conn, _ = self.server.accept()
                with conn:
                    data = conn.recv(1024).decode('utf-8')
                    self.handle_request(data)
                    conn.sendall(b"State set successfully")
            except socket.timeout:
                continue

    def handle_request(self, data):
        state_str = data.strip().lower()
        try:
            state = LedState(state_str)
            self.set_state(state)
        except ValueError:
            logging.error(f"Invalid state: {state_str}")

    def stop(self):
        logging.info("Stopping HwMonitor...")
        self.running.clear()
        self.led.off()
        for thread in self.threads:
            thread.join()
        self.stop_event.set()
        self.server.close()
        if os.path.exists(self.SOCKET_PATH):
            os.remove(self.SOCKET_PATH)

    def _signal_handler(self, sig, frame):
        logging.info("Signal received, stopping...")
        self.stop()
        sys.exit(0)

class HubV3Client:
    SOCKET_PATH = "/tmp/led_socket"
    TIMEOUT = 0.5

    def set_led_state(self, state):
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
                client.settimeout(self.TIMEOUT)
                client.connect(self.SOCKET_PATH)
                client.sendall(state.encode('utf-8'))
                response = client.recv(1024).decode('utf-8')
                logging.info(f"Server response: {response}")
        except (socket.timeout, FileNotFoundError, ConnectionRefusedError) as e:
            logging.error(f"Error in setting LED state: {e}")
        except Exception as e:
            logging.error(f"Unexpected error: {e}")

def main():
    parser = argparse.ArgumentParser(description='Hardware Monitor for LED and button control')
    subparsers = parser.add_subparsers(dest='command', help='Commands')

    subparsers.add_parser('daemon', help='Start hardware monitor daemon')

    set_parser = subparsers.add_parser('set', help='Set LED state')
    set_parser.add_argument('state', choices=[s.value for s in LedState], help='LED state to set')

    args = parser.parse_args()

    if args.command == 'daemon':
        monitor = HwMonitor()
        monitor.start()
    elif args.command == 'set':
        client = HubV3Client()
        client.set_led_state(args.state)
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
