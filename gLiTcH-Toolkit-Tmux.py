#!/usr/bin/env python3

import os
import subprocess
import shutil
import sys
import time
import signal
import tempfile
from pathlib import Path

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

# Tmux session configuration
TMUX_SESSION_NAME = "glitch-toolkit"
TEMP_SCRIPT_DIR = "/tmp/glitch-toolkit-execution"

def print_colored(text, color):
    """Prints text in a specified color."""
    print(f"{color}{text}{NC}")

def check_tmux_available():
    """Check if tmux is installed and available."""
    try:
        subprocess.run(["tmux", "-V"], capture_output=True, check=True)
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False

def setup_repository():
    """Clones or updates the repository. Prints status messages directly."""
    if not os.path.exists(BASE_DIR):
        try:
            os.makedirs(BASE_DIR)
        except OSError as e:
            print(f"{RED}Failed to create base directory {BASE_DIR}: {e}{NC}")
            return False
    
    os.chdir(BASE_DIR)

    if os.path.isdir(os.path.join(LOCAL_DIR_PATH, ".git")):
        print(f"{YELLOW}Updating repository...{NC}")
        sys.stdout.flush()
        try:
            result = subprocess.run(["git", "-C", LOCAL_DIR_PATH, "pull"], 
                                  capture_output=True, text=True, errors='replace')
            if result.returncode != 0:
                print(f"{RED}Failed to update repository. Error: {result.stderr.strip()}{NC}")
                return False
        except Exception as e:
            print(f"{RED}Failed to update repository. Error: {str(e)}{NC}")
            return False
    else:
        print(f"{YELLOW}Cloning repository...{NC}")
        sys.stdout.flush()
        try:
            result = subprocess.run(["git", "clone", REPO_URL, LOCAL_DIR_PATH], 
                                  capture_output=True, text=True, errors='replace')
            if result.returncode != 0:
                print(f"{RED}Failed to clone repository. Error: {result.stderr.strip()}{NC}")
                return False
        except Exception as e:
            print(f"{RED}Failed to clone repository. Error: {str(e)}{NC}")
            return False
    
    print(f"{GREEN}Repository ready!{NC}")
    return True

def get_tools():
    """Gets a sorted list of tools from the repository."""
    tools = []
    if not os.path.isdir(LOCAL_DIR_PATH):
        return tools

    for item in os.listdir(LOCAL_DIR_PATH):
        if item == ".git" or item.startswith('.'):
            continue
        item_path = os.path.join(LOCAL_DIR_PATH, item)
        if os.path.isfile(item_path):
            tools.append(item)
    
    tools.sort(key=str.lower)
    return tools

def kill_tmux_session():
    """Kill existing tmux session if it exists."""
    try:
        subprocess.run(["tmux", "kill-session", "-t", TMUX_SESSION_NAME], 
                      capture_output=True, check=False)
    except Exception:
        pass

def create_execution_wrapper(tool_path, tool_name):
    """Create a wrapper script for tool execution with proper environment."""
    os.makedirs(TEMP_SCRIPT_DIR, exist_ok=True)
    
    wrapper_path = os.path.join(TEMP_SCRIPT_DIR, f"execute_{tool_name}.sh")
    
    wrapper_content = f'''#!/bin/bash

# Set environment variables to suppress interactive prompts
export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none
export APT_LISTBUGS_FRONTEND=none
export NEEDRESTART_MODE=a

# Clear the screen and show header
clear
echo -e "\\033[1;35m╔══════════════════════════════════════════════════════════════════════════════╗\\033[0m"
echo -e "\\033[1;35m║\\033[0m \\033[1;33mExecuting: {tool_name}\\033[0m" + " " * (76 - len(tool_name)) + "\\033[1;35m║\\033[0m"
echo -e "\\033[1;35m╠══════════════════════════════════════════════════════════════════════════════╣\\033[0m"
echo -e "\\033[1;35m║\\033[0m \\033[0;36mPress Ctrl+C to interrupt execution\\033[0m" + " " * (43) + "\\033[1;35m║\\033[0m"
echo -e "\\033[1;35m╚══════════════════════════════════════════════════════════════════════════════╝\\033[0m"
echo ""

# Function to handle cleanup on exit
cleanup() {{
    echo ""
    echo -e "\\033[1;35m╔══════════════════════════════════════════════════════════════════════════════╗\\033[0m"
    echo -e "\\033[1;35m║\\033[0m \\033[1;32mExecution completed for: {tool_name}\\033[0m" + " " * (54 - len(tool_name)) + "\\033[1;35m║\\033[0m"
    echo -e "\\033[1;35m║\\033[0m \\033[0;33mPress any key to return to main menu...\\033[0m" + " " * (40) + "\\033[1;35m║\\033[0m"
    echo -e "\\033[1;35m╚══════════════════════════════════════════════════════════════════════════════╝\\033[0m"
    read -n 1 -s
}}

# Set trap for cleanup
trap cleanup EXIT INT TERM

# Execute the tool
echo -e "\\033[1;36m--- Output ---\\033[0m"
bash "{tool_path}" 2>&1

# Wait for user input before closing
echo ""
echo -e "\\033[1;32m--- Execution finished ---\\033[0m"
'''
    
    with open(wrapper_path, 'w') as f:
        f.write(wrapper_content)
    
    os.chmod(wrapper_path, 0o755)
    return wrapper_path

def execute_tool_with_tmux(tool_path, tool_name):
    """Execute a tool using tmux split-pane layout."""
    try:
        # Create execution wrapper
        wrapper_path = create_execution_wrapper(tool_path, tool_name)
        
        # Kill any existing session
        kill_tmux_session()
        
        # Create new tmux session with the main menu in the left pane
        subprocess.run([
            "tmux", "new-session", "-d", "-s", TMUX_SESSION_NAME,
            "-x", "120", "-y", "30"  # Set initial size
        ], check=True)
        
        # Split the window vertically (left: menu, right: execution)
        subprocess.run([
            "tmux", "split-window", "-h", "-t", TMUX_SESSION_NAME
        ], check=True)
        
        # Resize panes (left: 40%, right: 60%)
        subprocess.run([
            "tmux", "resize-pane", "-t", f"{TMUX_SESSION_NAME}:0.0", "-p", "40"
        ], check=True)
        
        # Set up the left pane with a monitoring script
        monitor_script_content = f'''#!/bin/bash
clear
echo -e "\\033[1;35m╔══════════════════════════════════════════════════════════════════════════════╗\\033[0m"
echo -e "\\033[1;35m║\\033[0m \\033[1;33mgLiTcH-ToolKit - Execution Monitor\\033[0m" + " " * (47) + "\\033[1;35m║\\033[0m"
echo -e "\\033[1;35m╠══════════════════════════════════════════════════════════════════════════════╣\\033[0m"
echo -e "\\033[1;35m║\\033[0m \\033[0;32mCurrently running: {tool_name}\\033[0m" + " " * (58 - len(tool_name)) + "\\033[1;35m║\\033[0m"
echo -e "\\033[1;35m║\\033[0m" + " " * (78) + "\\033[1;35m║\\033[0m"
echo -e "\\033[1;35m║\\033[0m \\033[0;36mControls:\\033[0m" + " " * (69) + "\\033[1;35m║\\033[0m"
echo -e "\\033[1;35m║\\033[0m \\033[0;33m  • Ctrl+C in right pane: Stop execution\\033[0m" + " " * (41) + "\\033[1;35m║\\033[0m"
echo -e "\\033[1;35m║\\033[0m \\033[0;33m  • Any key after completion: Return to menu\\033[0m" + " " * (36) + "\\033[1;35m║\\033[0m"
echo -e "\\033[1;35m║\\033[0m" + " " * (78) + "\\033[1;35m║\\033[0m"
echo -e "\\033[1;35m║\\033[0m \\033[0;36mExecution Status:\\033[0m" + " " * (61) + "\\033[1;35m║\\033[0m"
echo -e "\\033[1;35m╚══════════════════════════════════════════════════════════════════════════════╝\\033[0m"
echo ""

# Monitor the execution pane
while tmux list-sessions 2>/dev/null | grep -q "{TMUX_SESSION_NAME}"; do
    pane_content=$(tmux capture-pane -t "{TMUX_SESSION_NAME}:0.1" -p | tail -1)
    if [[ "$pane_content" == *"Press any key to return"* ]]; then
        echo -e "\\033[1;32m✓ Execution completed successfully\\033[0m"
        break
    elif [[ "$pane_content" == *"error"* ]] || [[ "$pane_content" == *"Error"* ]]; then
        echo -e "\\033[1;31m⚠ Execution encountered errors\\033[0m"
    else
        echo -e "\\033[1;33m⟳ Script is running...\\033[0m"
    fi
    sleep 2
    # Move cursor up and clear line for status update
    echo -e "\\033[1A\\033[K\\c"
done

echo ""
echo -e "\\033[1;36mExecution session ended. You can now close this window.\\033[0m"
read -n 1 -s
'''
        
        monitor_script_path = os.path.join(TEMP_SCRIPT_DIR, "monitor.sh")
        with open(monitor_script_path, 'w') as f:
            f.write(monitor_script_content)
        os.chmod(monitor_script_path, 0o755)
        
        # Run monitor script in left pane
        subprocess.run([
            "tmux", "send-keys", "-t", f"{TMUX_SESSION_NAME}:0.0",
            f"bash {monitor_script_path}", "Enter"
        ], check=True)
        
        # Run the tool in the right pane
        subprocess.run([
            "tmux", "send-keys", "-t", f"{TMUX_SESSION_NAME}:0.1",
            f"bash {wrapper_path}", "Enter"
        ], check=True)
        
        # Attach to the session
        subprocess.run([
            "tmux", "attach-session", "-t", TMUX_SESSION_NAME
        ], check=True)
        
    except subprocess.CalledProcessError as e:
        print(f"{RED}Failed to execute tool with tmux: {e}{NC}")
        return False
    except Exception as e:
        print(f"{RED}Unexpected error during execution: {e}{NC}")
        return False
    finally:
        # Clean up
        kill_tmux_session()
    
    return True

def display_main_menu(tools):
    """Display the main toolkit menu."""
    os.system('clear')
    
    print(f"{PINK}╔══════════════════════════════════════════════════════════════════════════════╗{NC}")
    print(f"{PINK}║{NC} {YELLOW}gLiTcH-ToolKit - Linux System Tools{NC}                                     {PINK}║{NC}")
    print(f"{PINK}╠══════════════════════════════════════════════════════════════════════════════╣{NC}")
    
    if not tools:
        print(f"{PINK}║{NC} {RED}No tools found in repository{NC}                                           {PINK}║{NC}")
        print(f"{PINK}║{NC}                                                                              {PINK}║{NC}")
        print(f"{PINK}║{NC} {YELLOW}Please check your internet connection and try refreshing{NC}                {PINK}║{NC}")
    else:
        print(f"{PINK}║{NC} {CYAN}Available Tools:{NC}                                                        {PINK}║{NC}")
        print(f"{PINK}║{NC}                                                                              {PINK}║{NC}")
        
        # Display tools in columns
        max_tools_per_page = 20
        displayed_tools = tools[:max_tools_per_page]
        
        for i, tool in enumerate(displayed_tools, 1):
            tool_display = f"{i:2d}. {tool}"
            if len(tool_display) > 76:
                tool_display = tool_display[:73] + "..."
            padding = " " * (76 - len(tool_display))
            print(f"{PINK}║{NC} {GREEN}{tool_display}{NC}{padding} {PINK}║{NC}")
        
        if len(tools) > max_tools_per_page:
            remaining = len(tools) - max_tools_per_page
            print(f"{PINK}║{NC} {YELLOW}... and {remaining} more tools{NC}                                                {PINK}║{NC}")
    
    print(f"{PINK}║{NC}                                                                              {PINK}║{NC}")
    print(f"{PINK}╠══════════════════════════════════════════════════════════════════════════════╣{NC}")
    print(f"{PINK}║{NC} {CYAN}Commands:{NC}                                                                  {PINK}║{NC}")
    print(f"{PINK}║{NC} {YELLOW}  • Enter tool number to execute{NC}                                          {PINK}║{NC}")
    print(f"{PINK}║{NC} {YELLOW}  • 'r' or 'refresh' to update repository{NC}                                {PINK}║{NC}")
    print(f"{PINK}║{NC} {YELLOW}  • 'q' or 'quit' to exit{NC}                                                {PINK}║{NC}")
    print(f"{PINK}╚══════════════════════════════════════════════════════════════════════════════╝{NC}")
    print()

def main():
    """Main function to run the tool kit."""
    # Check for tmux availability
    if not check_tmux_available():
        print_colored("Error: tmux is not installed or not available in PATH.", RED)
        print_colored("Please install tmux using:", YELLOW)
        print_colored("  Ubuntu/Debian: sudo apt install tmux", CYAN)
        print_colored("  CentOS/RHEL:   sudo yum install tmux", CYAN)
        print_colored("  Fedora:        sudo dnf install tmux", CYAN)
        print_colored("  Arch:          sudo pacman -S tmux", CYAN)
        return
    
    # Initial setup
    print(f"{YELLOW}Initializing gLiTcH-ToolKit...{NC}")
    if not setup_repository():
        print_colored("Initial setup failed. Please check messages above. Exiting.", RED)
        return
    
    # Set up signal handler for clean exit
    def signal_handler(sig, frame):
        print(f"\n{YELLOW}Cleaning up...{NC}")
        kill_tmux_session()
        if os.path.exists(TEMP_SCRIPT_DIR):
            shutil.rmtree(TEMP_SCRIPT_DIR, ignore_errors=True)
        if os.path.exists(LOCAL_DIR_PATH):
            shutil.rmtree(LOCAL_DIR_PATH, ignore_errors=True)
        print_colored("Goodbye!", GREEN)
        sys.exit(0)
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # Main loop
    while True:
        tools = get_tools()
        display_main_menu(tools)
        
        try:
            choice = input(f"{PINK}Enter your choice: {NC}").strip().lower()
            
            if choice in ['q', 'quit']:
                break
            elif choice in ['r', 'refresh']:
                print(f"{YELLOW}Refreshing repository...{NC}")
                if not setup_repository():
                    print_colored("Refresh failed.", RED)
                    time.sleep(2)
                continue
            elif choice.isdigit():
                choice_num = int(choice)
                if 1 <= choice_num <= len(tools):
                    selected_tool = tools[choice_num - 1]
                    selected_tool_path = os.path.join(LOCAL_DIR_PATH, selected_tool)
                    
                    if os.path.isfile(selected_tool_path):
                        print(f"{YELLOW}Preparing to execute: {selected_tool}{NC}")
                        time.sleep(1)
                        execute_tool_with_tmux(selected_tool_path, selected_tool)
                    else:
                        print(f"{RED}Tool file not found: {selected_tool}{NC}")
                        time.sleep(2)
                else:
                    print(f"{RED}Invalid selection. Please choose 1-{len(tools)}.{NC}")
                    time.sleep(2)
            else:
                print(f"{RED}Invalid input. Please try again.{NC}")
                time.sleep(2)
                
        except KeyboardInterrupt:
            break
        except EOFError:
            break
    
    # Cleanup
    print(f"\n{YELLOW}Cleaning up...{NC}")
    kill_tmux_session()
    
    if os.path.exists(TEMP_SCRIPT_DIR):
        try:
            shutil.rmtree(TEMP_SCRIPT_DIR)
            print_colored(f"Cleaned up execution scripts: {TEMP_SCRIPT_DIR}", GREEN)
        except OSError as e:
            print_colored(f"Failed to clean up execution scripts: {e}", RED)
    
    if os.path.exists(LOCAL_DIR_PATH):
        try:
            shutil.rmtree(LOCAL_DIR_PATH)
            print_colored(f"Cleaned up temporary files: {LOCAL_DIR_PATH}", GREEN)
        except OSError as e:
            print_colored(f"Failed to clean up temporary files: {e}", RED)
    
    print_colored("Thanks for using gLiTcH-ToolKit!", GREEN)

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"\n{RED}An unexpected error occurred: {e}{NC}")
        kill_tmux_session()
        if os.path.exists(TEMP_SCRIPT_DIR):
            shutil.rmtree(TEMP_SCRIPT_DIR, ignore_errors=True)
        import traceback
        traceback.print_exc()
    finally:
        print(NC, end='')
