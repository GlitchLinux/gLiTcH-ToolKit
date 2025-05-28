#!/usr/bin/env python3

import os
import subprocess
import shutil
import sys
from time import sleep

# Define ANSI color codes
RED = '\033[0;31m'
GREEN = '\033[0;32m'
YELLOW = '\033[0;33m'
BLUE = '\033[0;34m'
CYAN = '\033[0;36m'
PINK = '\033[1;35m'
NC = '\033[0m'  # No Color

# Repository details
REPO_URL = "https://github.com/GlitchLinux/gLiTcH-ToolKit.git"
BASE_DIR = "/tmp"
LOCAL_DIR_NAME = "gLiTcH-ToolKit"
LOCAL_DIR_PATH = os.path.join(BASE_DIR, LOCAL_DIR_NAME)

def print_colored(text, color):
    """Prints text in a specified color."""
    print(f"{color}{text}{NC}")

def check_tmux():
    """Check if tmux is available."""
    try:
        subprocess.run(["tmux", "-V"], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False

def setup_repository():
    """Clones or updates the repository."""
    if not os.path.exists(BASE_DIR):
        try:
            os.makedirs(BASE_DIR)
        except OSError as e:
            print(f"{RED}Failed to create base directory {BASE_DIR}: {e}{NC}")
            return False
    
    os.chdir(BASE_DIR)

    if os.path.isdir(os.path.join(LOCAL_DIR_PATH, ".git")):
        print(f"{YELLOW}Updating repository...{NC}")
        try:
            subprocess.run(["git", "-C", LOCAL_DIR_PATH, "pull"], check=True)
            subprocess.run(["chmod", "-R", "+x", LOCAL_DIR_PATH], check=True)
        except subprocess.CalledProcessError as e:
            print(f"{RED}Failed to update repository. Error: {e.stderr}{NC}")
            return False
    else:
        print(f"{YELLOW}Cloning repository...{NC}")
        try:
            subprocess.run(["git", "clone", REPO_URL, LOCAL_DIR_PATH], check=True)
            subprocess.run(["chmod", "-R", "+x", LOCAL_DIR_PATH], check=True)
        except subprocess.CalledProcessError as e:
            print(f"{RED}Failed to clone repository. Error: {e.stderr}{NC}")
            return False
    return True

def get_tools():
    """Gets a sorted list of tools (scripts & executables) from the repository."""
    tools = []
    if not os.path.isdir(LOCAL_DIR_PATH):
        return tools

    for item in os.listdir(LOCAL_DIR_PATH):
        if item == ".git" or item.startswith('.'):
            continue
        item_path = os.path.join(LOCAL_DIR_PATH, item)

        if os.path.isfile(item_path) and (
            os.access(item_path, os.X_OK) or item.endswith(('.sh', '.py'))
        ):
            tools.append(item)
    
    tools.sort(key=str.lower)
    return tools

def display_menu(tools):
    """Displays the menu of available tools."""
    os.system('clear')
    print(f"{PINK}╔════════════════════════════════════════════╗{NC}")
    print(f"{PINK}║{NC}{YELLOW}      gLiTcH-ToolKit - Linux System Tools      {NC}{PINK}║{NC}")
    print(f"{PINK}╠════════════════════════════════════════════╣{NC}")
    
    for idx, tool in enumerate(tools, 1):
        print(f"{PINK}║{NC} {GREEN}{idx:2}.{NC} {CYAN}{tool.ljust(38)}{NC} {PINK}║{NC}")
    
    print(f"{PINK}╠════════════════════════════════════════════╣{NC}")
    print(f"{PINK}║{NC} {YELLOW} 0. Quit{' ' * 35}{NC}{PINK}║{NC}")
    print(f"{PINK}╚════════════════════════════════════════════╝{NC}")
    print()

def run_in_tmux(tool_path):
    """Run the selected tool in a new tmux window."""
    session_name = "glitch-toolkit"

    try:
        # Check if session exists
        result = subprocess.run(["tmux", "has-session", "-t", session_name],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if result.returncode != 0:
            # Create detached session if it doesn't exist
            subprocess.run(["tmux", "new-session", "-d", "-s", session_name])

        # Build the shell command string
        command_string = f"bash -c '{tool_path} || echo \"Script failed with exit code $?\"; exec bash'"

        # Open a new window for the tool inside the session
        subprocess.run([
            "tmux", "new-window",
            "-t", f"{session_name}:",
            "-n", os.path.basename(tool_path),
            command_string
        ], check=True)

        # Focus the new window if inside tmux
        if 'TMUX' in os.environ:
            subprocess.run(["tmux", "select-window", "-t", f"{session_name}:" + os.path.basename(tool_path)])

        # Attach to the session if not already inside tmux
        elif 'TMUX' not in os.environ:
            subprocess.run(["tmux", "attach-session", "-t", session_name])

    except subprocess.CalledProcessError as e:
        print(f"{RED}Failed to run in tmux: {e}{NC}")
        return False
    return True

def main():
    """Main function to run the tool kit."""
    if not check_tmux():
        print(f"{RED}Error: tmux is required for this toolkit. Please install tmux first.{NC}")
        sys.exit(1)
    
    print(f"{YELLOW}Initializing gLiTcH-ToolKit...{NC}")
    if not setup_repository():
        print_colored("Initial setup failed. Please check messages above. Exiting.", RED)
        return
    
    tools = get_tools()
    if not tools:
        print(f"{YELLOW}No executable tools found in repository.{NC}")
        return
    
    while True:
        display_menu(tools)
        
        try:
            choice = input(f"{YELLOW}Select a tool (1-{len(tools)}), or 0 to quit: {NC}")
            
            if not choice:
                continue
                
            choice = int(choice)
            
            if choice == 0:
                break
            elif 1 <= choice <= len(tools):
                selected_tool = tools[choice - 1]
                tool_path = os.path.join(LOCAL_DIR_PATH, selected_tool)
                
                print(f"{YELLOW}Launching {selected_tool} in tmux window...{NC}")
                sleep(1)
                
                if not run_in_tmux(tool_path):
                    print(f"{RED}Failed to launch tool.{NC}")
                    input(f"{PINK}Press Enter to continue...{NC}")
                
            else:
                print(f"{RED}Invalid selection. Please choose between 1 and {len(tools)}.{NC}")
                sleep(1)
                
        except ValueError:
            print(f"{RED}Please enter a number.{NC}")
            sleep(1)
        except KeyboardInterrupt:
            print(f"\n{YELLOW}Exiting...{NC}")
            break
    
    # Cleanup
    if os.path.exists(LOCAL_DIR_PATH):
        try:
            shutil.rmtree(LOCAL_DIR_PATH)
            print(f"{GREEN}Cleaned up temporary files.{NC}")
        except OSError as e:
            print(f"{RED}Failed to clean up temporary files: {e}{NC}")
    
    # Kill tmux session if we created it and we're not already inside tmux
    if 'TMUX' not in os.environ:
        subprocess.run(["tmux", "kill-session", "-t", "glitch-toolkit"])

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"{RED}An unexpected error occurred: {e}{NC}")
        sys.exit(1)
