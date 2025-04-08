#!/usr/bin/env python3
import os
import sys
import configparser
from pathlib import Path
import subprocess
import shutil
import getpass
from typing import Optional, Dict, List

# Configuration handling - updated paths
CONFIG_DIR = Path.home() / ".LUKS-VAULT"
CONFIG_FILE = CONFIG_DIR / "config"
MOUNT_DIR = CONFIG_DIR / "mnt"

class RemoteLUKSVault:
    def __init__(self):
        self.ssh_config: Optional[Dict] = None
        self.luks_config: Optional[Dict] = None
        self.connected: bool = False
        self.mounted: bool = False
        # Setup directories
        CONFIG_DIR.mkdir(exist_ok=True, parents=True)
        MOUNT_DIR.mkdir(exist_ok=True, parents=True)

    def check_dependencies(self):
        """Check if required programs are installed"""
        missing = []
        for cmd in ['sshpass', 'sshfs', 'fusermount', 'umount']:
            if not shutil.which(cmd):
                missing.append(cmd)
        if missing:
            print("Error: Missing required dependencies:")
            for cmd in missing:
                print(f" - {cmd}")
            if 'sshfs' in missing:
                print("To install on Debian/Ubuntu: sudo apt install sshfs sshpass")
                print("To install on Arch: sudo pacman -S sshfs sshpass")
                print("To install on Fedora: sudo dnf install fuse-sshfs sshpass")
            sys.exit(1)

    def load_configs(self) -> List[Dict]:
        """Load all saved configurations"""
        configs = []
        if CONFIG_FILE.exists():
            config = configparser.ConfigParser()
            config.read(CONFIG_FILE)
            for section in config.sections():
                cfg = dict(config[section])
                cfg['name'] = section
                configs.append(cfg)
        return configs

    def save_config(self, name: str, config: Dict):
        """Save a new configuration"""
        parser = configparser.ConfigParser()
        if CONFIG_FILE.exists():
            parser.read(CONFIG_FILE)
        parser[name] = config
        with open(CONFIG_FILE, 'w') as f:
            parser.write(f)

    def select_config(self) -> Optional[Dict]:
        """Prompt user to select a saved configuration"""
        configs = self.load_configs()
        if not configs:
            return None
        print("\nSaved configurations:")
        for i, cfg in enumerate(configs, 1):
            print(f"{i}. {cfg['name']} ({cfg.get('hostname', '')})")
        print("\n0. Create new configuration")
        try:
            choice = int(input("\nSelect configuration (number): "))
            if 1 <= choice <= len(configs):
                return configs[choice-1]
            return None
        except ValueError:
            return None

    def get_ssh_credentials(self) -> Dict:
        """Prompt for SSH credentials"""
        print("\nEnter SSH connection details:")
        hostname = input("Hostname: ").strip()
        port = input("Port [22]: ").strip() or "22"
        username = input("Username: ").strip()
        password = getpass.getpass("Password: ")
        return {
            'hostname': hostname,
            'port': port,
            'username': username,
            'password': password
        }

    def get_luks_details(self) -> Dict:
        """Prompt for LUKS details"""
        print("\nEnter LUKS volume details:")
        device = input("Device (e.g. /dev/sdb1): ").strip()
        mapper = input("Mapper name [encrypted_vault]: ").strip() or "encrypted_vault"
        mount_point = input("Mount point [/mnt/encrypted]: ").strip() or "/mnt/encrypted"
        return {
            'device': device,
            'mapper': mapper,
            'mount_point': mount_point
        }

    def connect_ssh(self, config: Dict) -> bool:
        """Establish SSH connection"""
        try:
            # Test SSH connection
            cmd = [
                'sshpass', '-p', config['password'],
                'ssh', '-p', config['port'],
                f"{config['username']}@{config['hostname']}",
                'echo "Connection successful"'
            ]
            result = subprocess.run(cmd, capture_output=True, text=True)
            if "Connection successful" not in result.stdout:
                print(f"SSH connection failed: {result.stderr}")
                return False
            self.ssh_config = config
            self.connected = True
            return True
        except Exception as e:
            print(f"SSH connection error: {str(e)}")
            return False

    def mount_luks(self, config: Dict) -> bool:
        """Mount the LUKS volume"""
        if not self.connected:
            print("Not connected to SSH server")
            return False
        passphrase = getpass.getpass("Enter LUKS passphrase: ")
        try:
            print("\n[1/3] Unlocking LUKS container...")
            ssh_cmd = f"echo {passphrase} | sudo -S cryptsetup luksOpen {config['device']} {config['mapper']}"
            cmd = [
                'sshpass', '-p', self.ssh_config['password'],
                'ssh', '-p', self.ssh_config['port'],
                f"{self.ssh_config['username']}@{self.ssh_config['hostname']}",
                ssh_cmd
            ]
            result = subprocess.run(cmd, capture_output=True, text=True)
            if result.returncode != 0:
                print(f"Failed to unlock LUKS: {result.stderr}")
                return False

            print("[2/3] Mounting LUKS volume on remote...")
            # Added chmod to ensure permissions are correct
            ssh_cmd = (
                f"echo {passphrase} | sudo -S mount /dev/mapper/{config['mapper']} {config['mount_point']} && "
                f"sudo chmod -R 777 {config['mount_point']}"
            )
            cmd = [
                'sshpass', '-p', self.ssh_config['password'],
                'ssh', '-p', self.ssh_config['port'],
                f"{self.ssh_config['username']}@{self.ssh_config['hostname']}",
                ssh_cmd
            ]
            result = subprocess.run(cmd, capture_output=True, text=True)
            if result.returncode != 0:
                print(f"Failed to mount: {result.stderr}")
                # Clean up if mount failed
                ssh_cmd = f"echo {passphrase} | sudo -S cryptsetup luksClose {config['mapper']}"
                subprocess.run([
                    'sshpass', '-p', self.ssh_config['password'],
                    'ssh', '-p', self.ssh_config['port'],
                    f"{self.ssh_config['username']}@{self.ssh_config['hostname']}",
                    ssh_cmd
                ], capture_output=True)
                return False

            print("[3/3] Mounting via SSHFS locally...")
            MOUNT_DIR.mkdir(exist_ok=True)
            cmd = [
                'sshfs',
                '-p', self.ssh_config['port'],
                f"{self.ssh_config['username']}@{self.ssh_config['hostname']}:{config['mount_point']}",
                str(MOUNT_DIR),
                '-o', 'password_stdin',
                '-o', 'uid=' + str(os.getuid()),
                '-o', 'gid=' + str(os.getgid()),
                '-o', 'allow_other',  # Added to allow access to all users
                '-o', 'default_permissions',
                '-o', 'reconnect',
                '-o', 'ServerAliveInterval=15',
                '-o', 'ServerAliveCountMax=3'
            ]
            result = subprocess.run(
                cmd, 
                input=self.ssh_config['password'],
                text=True,
                capture_output=True
            )
            if result.returncode != 0:
                print(f"Failed to mount via SSHFS: {result.stderr}")
                return False
            self.luks_config = config
            self.mounted = True
            print("Successfully mounted!")
            print(f"Files should be accessible at: {MOUNT_DIR}")
            return True
        except Exception as e:
            print(f"Mount error: {str(e)}")
            return False

    def unmount(self):
        """Unmount and lock the LUKS volume"""
        if not self.mounted:
            return
        try:
            print("\nUnmounting SSHFS...")
            # Try multiple unmount methods
            unmounted = False
            for cmd in [['fusermount', '-u', str(MOUNT_DIR)], 
                       ['umount', '-l', str(MOUNT_DIR)],  # Lazy unmount
                       ['umount', str(MOUNT_DIR)]]:
                try:
                    subprocess.run(cmd, check=True)
                    unmounted = True
                    break
                except subprocess.CalledProcessError:
                    continue
            if not unmounted:
                print(f"Warning: Could not unmount {MOUNT_DIR}. You may need to unmount manually.")
                print("Try: sudo umount -f " + str(MOUNT_DIR))
                return False

            # Remote unmount and lock
            passphrase = getpass.getpass("Enter LUKS passphrase to unlock: ")
            print("Unmounting remote volume...")
            ssh_cmd = f"echo {passphrase} | sudo -S umount {self.luks_config['mount_point']}"
            cmd = [
                'sshpass', '-p', self.ssh_config['password'],
                'ssh', '-p', self.ssh_config['port'],
                f"{self.ssh_config['username']}@{self.ssh_config['hostname']}",
                ssh_cmd
            ]
            subprocess.run(cmd, check=True)
            print("Locking LUKS container...")
            ssh_cmd = f"echo {passphrase} | sudo -S cryptsetup luksClose {self.luks_config['mapper']}"
            cmd = [
                'sshpass', '-p', self.ssh_config['password'],
                'ssh', '-p', self.ssh_config['port'],
                f"{self.ssh_config['username']}@{self.ssh_config['hostname']}",
                ssh_cmd
            ]
            subprocess.run(cmd, check=True)
            self.mounted = False
            print("Volume unmounted and locked")
            return True
        except subprocess.CalledProcessError as e:
            print(f"Unmount failed: {str(e)}")
            return False

    def disconnect(self):
        """Disconnect from SSH"""
        if self.mounted:
            self.unmount()
        self.connected = False
        print("Disconnected")

    def open_gui_file_manager(self):
        """Open the mounted directory in a GUI file manager"""
        try:
            gui_managers = ['thunar', 'nautilus', 'pcmanfm', 'dolphin']
            for manager in gui_managers:
                if shutil.which(manager):
                    subprocess.Popen([manager, str(MOUNT_DIR)])
                    print(f"Opened {MOUNT_DIR} in {manager}")
                    return
            print("No supported GUI file manager found. Please install Thunar, Nautilus, PCManFM, or Dolphin.")
        except Exception as e:
            print(f"Failed to open GUI file manager: {str(e)}")

    def run(self):
        """Main application loop"""
        print("=== Remote LUKS Vault Manager ===")
        # Check dependencies first
        self.check_dependencies()
        # Load or create configuration
        config = self.select_config()
        if config:
            print(f"\nUsing configuration: {config['name']}")
            use_this = input("Use this configuration? [Y/n]: ").lower() != 'n'
            if not use_this:
                config = None
        if not config:
            name = input("\nEnter a name for this configuration: ").strip()
            ssh_config = self.get_ssh_credentials()
            luks_config = self.get_luks_details()
            config = {
                'name': name,
                **ssh_config,
                **luks_config
            }
            self.save_config(name, config)
        # Connect and mount
        if not self.connect_ssh(config):
            return
        if not self.mount_luks(config):
            self.disconnect()
            return
        # Open GUI file manager
        self.open_gui_file_manager()
        # Disconnect when done
        input("\nPress Enter to unmount and disconnect...")
        self.disconnect()

if __name__ == "__main__":
    vault = RemoteLUKSVault()
    vault.run()
