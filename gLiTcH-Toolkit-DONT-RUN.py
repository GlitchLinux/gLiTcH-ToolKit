import os
import subprocess
import shutil
import math
import sys
from threading import Thread
from queue import Queue, Empty
import time

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

# Global state for the main window's layout details
MAIN_WINDOW_LAYOUT = {
    "screen_draw_start_row": 1,  # UI always drawn from line 1
    "content_start_line_abs": 0, # Absolute screen line where content (tools/output) begins
    "content_height": 0,         # Number of lines available for content
    "total_width": 0,            # Full width of the bordered window
    "prompt_line_abs": 0,        # Absolute screen line for the input prompt text
    "prompt_text_start_col_abs": 0, # Absolute screen column where prompt text (after "║ > ") starts
    "is_drawn_once": False,      # Flag for initial draw
    "num_columns_for_tools": 3   # Default number of columns for tools
}

# Constants for layout calculations
FIXED_HEADER_LINES = 3  # Top border, Title, Content Separator
FIXED_FOOTER_LINES_INCL_PROMPT = 3 # Prompt Separator, Prompt Line, Bottom Border
MIN_CONTENT_HEIGHT = 3         # Minimum rows for tool list / execution output
MIN_TOOLKIT_WIDTH = 40         # Minimum reasonable width for the toolkit UI
MIN_COLUMN_TEXT_WIDTH = 10     # Minimum text area width for a single column of tools (excluding number)

def clear_screen_area(start_row, num_rows, term_width):
    """Clears a specific number of lines from a start row."""
    for i in range(num_rows):
        sys.stdout.write(f"\033[{start_row + i};1H") # Move to start of line
        sys.stdout.write(" " * term_width)        # Fill with spaces
    sys.stdout.write(f"\033[{start_row};1H")       # Reset cursor to start of cleared area
    sys.stdout.flush()

def print_colored(text, color):
    """Prints text in a specified color."""
    # This function is simple; complex printing is handled by drawing functions
    print(f"{color}{text}{NC}")

def setup_repository():
    """Clones or updates the repository. Prints status messages directly."""
    if not os.path.exists(BASE_DIR):
        try:
            os.makedirs(BASE_DIR)
        except OSError as e:
            print(f"{RED}Failed to create base directory {BASE_DIR}: {e}{NC}")
            return False
    
    os.chdir(BASE_DIR) # Change current directory

    if os.path.isdir(os.path.join(LOCAL_DIR_PATH, ".git")):
        print(f"{YELLOW}Updating repository...{NC}")
        sys.stdout.flush()
        try:
            subprocess.run(["git", "-C", LOCAL_DIR_PATH, "pull"], check=True, capture_output=True, text=True, errors='replace')
        except subprocess.CalledProcessError as e:
            print(f"{RED}Failed to update repository. Error: {e.stderr.strip()}{NC}")
            return False
    else:
        print(f"{YELLOW}Cloning repository...{NC}")
        sys.stdout.flush()
        try:
            subprocess.run(["git", "clone", REPO_URL, LOCAL_DIR_PATH], check=True, capture_output=True, text=True, errors='replace')
        except subprocess.CalledProcessError as e:
            print(f"{RED}Failed to clone repository. Error: {e.stderr.strip()}{NC}")
            return False
    return True

def get_tools():
    """Gets a sorted list of tools from the repository."""
    tools = []
    if not os.path.isdir(LOCAL_DIR_PATH):
        return tools

    for item in os.listdir(LOCAL_DIR_PATH):
        if item == ".git" or item.startswith('.'): # Exclude .git and hidden files
            continue
        item_path = os.path.join(LOCAL_DIR_PATH, item)
        if os.path.isfile(item_path): # Consider only files as tools
            tools.append(item)
    
    tools.sort(key=str.lower) # Case-insensitive sort
    return tools

def count_visible_chars(text_with_ansi):
    """Counts visible characters in a string, ignoring ANSI escape codes."""
    plain_text_len = 0
    in_escape_sequence = False
    for char in text_with_ansi:
        if char == '\033':
            in_escape_sequence = True
        elif in_escape_sequence and char == 'm':
            in_escape_sequence = False
        elif not in_escape_sequence:
            plain_text_len += 1
    return plain_text_len

def smart_truncate(text_with_ansi, max_visible_length):
    """Truncates a string containing ANSI codes to a maximum visible length, adding '…'."""
    if count_visible_chars(text_with_ansi) <= max_visible_length:
        return text_with_ansi

    truncated_string = ""
    current_visible_length = 0
    in_escape_sequence = False
    ellipsis = "…"
    ellipsis_len = len(ellipsis) # This is 1 for the single char ellipsis

    # Iterate through the original string character by character
    for char_index, char_value in enumerate(text_with_ansi):
        if char_value == '\033': # Start of an ANSI escape sequence
            in_escape_sequence = True
            truncated_string += char_value
        elif in_escape_sequence: # Inside an ANSI escape sequence
            truncated_string += char_value
            if char_value == 'm': # End of an ANSI escape sequence
                in_escape_sequence = False
        else:  # Visible character
            # Check if there's space for this character AND the ellipsis
            if current_visible_length < max_visible_length - ellipsis_len:
                truncated_string += char_value
                current_visible_length += 1
            elif current_visible_length == max_visible_length - ellipsis_len : # Space for ellipsis only
                truncated_string += ellipsis + NC # Add NoColor to reset before ellipsis
                current_visible_length += ellipsis_len
                break # Stop processing, string is now at max_visible_length
            else: # Not enough space even for ellipsis, so break earlier
                # This case implies max_visible_length was too small for char + ellipsis
                # The string might already be too long if ellipsis_len is > 1 and max_visible_length is small.
                # If ellipsis is "…", its length is 1.
                if current_visible_length < max_visible_length : # if there is space for at least one char of ellipsis
                     truncated_string += ellipsis + NC
                     current_visible_length += ellipsis_len
                break
    
    # Fallback if max_visible_length is very small (e.g., 0 or 1)
    if max_visible_length > 0 and count_visible_chars(truncated_string) == 0 and not text_with_ansi.startswith(ellipsis):
        # If string is empty but should have content, return ellipsis if possible
        return (ellipsis + NC) if max_visible_length >= ellipsis_len else ""
    
    # Safety check: if somehow the string is still longer than allowed (complex ANSI might trick simple counter)
    # This is a fallback, the primary logic should handle it.
    if count_visible_chars(truncated_string) > max_visible_length:
        # Re-truncate based on a simpler plain text version if the above failed.
        # This is a very rough fallback.
        plain_fallback = ""
        in_esc_fallback = False
        for char_fb in truncated_string:
            if char_fb == '\033': in_esc_fallback = True
            elif in_esc_fallback and char_fb == 'm': in_esc_fallback = False
            elif not in_esc_fallback: plain_fallback += char_fb
        
        if len(plain_fallback) > max_visible_length:
            return plain_fallback[:max(0, max_visible_length - ellipsis_len)] + ellipsis + NC

    return truncated_string


def display_tools_with_border(tools, screen_draw_start_row, term_width, term_height):
    """
    Displays the main toolkit UI including borders, headers, tool list, and prompt area.
    Calculates layout based on terminal size and updates MAIN_WINDOW_LAYOUT.
    Assumes cursor is at screen_draw_start_row, column 1.
    """
    # --- Layout Calculations ---
    available_height_for_ui = term_height - screen_draw_start_row + 1
    calculated_content_height = available_height_for_ui - FIXED_HEADER_LINES - FIXED_FOOTER_LINES_INCL_PROMPT
    content_height = max(MIN_CONTENT_HEIGHT, calculated_content_height)
    MAIN_WINDOW_LAYOUT["content_height"] = content_height
    num_rows_for_tools = content_height

    actual_total_width = term_width # Use full terminal width
    if actual_total_width < MIN_TOOLKIT_WIDTH:
        actual_total_width = MIN_TOOLKIT_WIDTH
    MAIN_WINDOW_LAYOUT["total_width"] = actual_total_width
    
    inner_drawable_width = actual_total_width - 4 # Space between "║ " and " ║"
    
    # Determine number of columns based on available inner width
    if inner_drawable_width >= (MIN_COLUMN_TEXT_WIDTH * 3 + 2 * 3): # 3 cols + 2 separators (3 chars each)
        num_columns = 3
    elif inner_drawable_width >= (MIN_COLUMN_TEXT_WIDTH * 2 + 1 * 3): # 2 cols + 1 separator
        num_columns = 2
    else:
        num_columns = 1
    MAIN_WINDOW_LAYOUT["num_columns_for_tools"] = num_columns

    col_text_widths = [0] * num_columns
    if num_columns > 0:
        total_separator_width = (num_columns - 1) * 3 # Each separator is "   "
        space_for_all_cols_text_area = inner_drawable_width - total_separator_width
        if space_for_all_cols_text_area < num_columns: # Ensure at least 1 char per col
             space_for_all_cols_text_area = num_columns
        
        base_col_text_width = space_for_all_cols_text_area // num_columns
        remainder_width = space_for_all_cols_text_area % num_columns
        for i in range(num_columns):
            col_text_widths[i] = base_col_text_width + (1 if i < remainder_width else 0)

    num_tools = len(tools)
    MAIN_WINDOW_LAYOUT["content_start_line_abs"] = screen_draw_start_row + FIXED_HEADER_LINES -1 

    # --- Drawing ---
    # Each print ends with "\033[K" to clear rest of the line, preventing artifacts on resize
    sys.stdout.write(f"\033[{screen_draw_start_row};1H") # Ensure cursor is at the start for drawing
    
    print(PINK + "╔" + "═" * (actual_total_width - 2) + "╗" + NC + "\033[K")

    header_text = "gLiTcH-ToolKit - Linux System Tools"
    header_padding_total = actual_total_width - len(header_text) - 2
    header_pad_left = max(0, header_padding_total // 2)
    header_pad_right = max(0, header_padding_total - header_pad_left)
    print(PINK + "║" + NC + " " * header_pad_left + YELLOW + header_text + NC +
          " " * header_pad_right + PINK + "║" + NC + "\033[K")

    print(PINK + "╠" + "═" * (actual_total_width - 2) + "╣" + NC + "\033[K")

    # Print Tools Content Area
    for r in range(num_rows_for_tools):
        line_str = PINK + "║ " + NC
        for c in range(num_columns):
            tool_idx = r + c * num_rows_for_tools # Tools listed top-to-bottom, then left-to-right
            col_alloc_for_text = col_text_widths[c]

            if tool_idx < num_tools:
                tool_name_orig = tools[tool_idx]
                tool_num_prefix = f"{tool_idx + 1}. "
                
                full_tool_display_colored = f"{GREEN}{tool_num_prefix}{PINK}{tool_name_orig}{NC}"
                truncated_tool_display = smart_truncate(full_tool_display_colored, col_alloc_for_text)
                
                line_str += truncated_tool_display
                visible_len = count_visible_chars(truncated_tool_display)
                line_str += ' ' * max(0, col_alloc_for_text - visible_len)
            else:
                line_str += " " * col_alloc_for_text # Empty slot

            if c < num_columns - 1:
                line_str += "   "  # Separator between columns
        
        line_str += PINK + " ║" + NC
        print(line_str + "\033[K")

    # Print Prompt Separator
    print(PINK + "╟" + "─" * (actual_total_width - 2) + "╢" + NC + "\033[K")
    
    MAIN_WINDOW_LAYOUT["prompt_line_abs"] = MAIN_WINDOW_LAYOUT["content_start_line_abs"] + content_height + 1
    prompt_prefix_text = " > "
    MAIN_WINDOW_LAYOUT["prompt_text_start_col_abs"] = 1 + 2 + len(prompt_prefix_text) 

    prompt_text_area_width = actual_total_width - MAIN_WINDOW_LAYOUT["prompt_text_start_col_abs"] - 1 
    print(PINK + "║" + NC + YELLOW + prompt_prefix_text + NC + 
          " " * max(0, prompt_text_area_width) + PINK + "║" + NC + "\033[K")
    
    print(PINK + "╚" + "═" * (actual_total_width - 2) + "╝" + NC + "\033[K")
    
    MAIN_WINDOW_LAYOUT["is_drawn_once"] = True
    sys.stdout.flush() 


def execute_tool(tool_path, output_queue):
    """Executes a tool in a subprocess, passing DEBIAN_FRONTEND=noninteractive."""
    try:
        env = os.environ.copy()
        env['DEBIAN_FRONTEND'] = 'noninteractive'
        env['APT_LISTCHANGES_FRONTEND'] = 'none' 

        process = subprocess.Popen(
            ["bash", tool_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1, 
            universal_newlines=True, 
            env=env,
            errors='replace' 
        )

        for stdout_line in iter(process.stdout.readline, ""):
            output_queue.put(stdout_line.strip())
        process.stdout.close() 

        stderr_output = process.stderr.read()
        process.stderr.close() 
        
        process.wait() 

        apt_warning = "WARNING: apt does not have a stable CLI interface. Use with caution in scripts."
        stderr_content_stripped = stderr_output.strip()

        if stderr_content_stripped == apt_warning:
            output_queue.put(f"{YELLOW}{stderr_content_stripped}{NC}") 
        elif stderr_content_stripped: 
            output_queue.put(f"{RED}Error:{NC} {stderr_content_stripped}")
        
        output_queue.put(None)

    except Exception as e:
        output_queue.put(f"{RED}Execution failed: {str(e)}{NC}")
        output_queue.put(None)


def format_output_line_for_window(line_text, max_content_width):
    """Formats a single line of script output for display within the execution window area."""
    truncated_line = smart_truncate(line_text, max_content_width)
    visible_len_of_truncated = count_visible_chars(truncated_line)
    padding = " " * max(0, max_content_width - visible_len_of_truncated)
    return PINK + "║ " + NC + truncated_line + padding + PINK + " ║" + NC


def display_execution_output_within_main_window(tool_name, output_queue):
    """Displays scrolling execution output within the main toolkit's content area."""
    if not MAIN_WINDOW_LAYOUT["is_drawn_once"]:
        print_colored("Error: Main window layout not established.", RED)
        return

    content_start_abs = MAIN_WINDOW_LAYOUT["content_start_line_abs"]
    content_height = MAIN_WINDOW_LAYOUT["content_height"]
    content_text_width = MAIN_WINDOW_LAYOUT["total_width"] - 4 

    output_lines_buffer = [] 

    # --- Update Prompt Line to "Now executing..." ---
    prompt_line_abs = MAIN_WINDOW_LAYOUT["prompt_line_abs"]
    prompt_text_start_col = MAIN_WINDOW_LAYOUT["prompt_text_start_col_abs"]
    prompt_text_area_width = MAIN_WINDOW_LAYOUT["total_width"] - prompt_text_start_col -1 
    
    exec_msg = f"Now executing: {YELLOW}{tool_name}{NC}..."
    truncated_exec_msg = smart_truncate(exec_msg, prompt_text_area_width)
    visible_len_exec_msg = count_visible_chars(truncated_exec_msg)
    padding_exec_msg = " " * max(0, prompt_text_area_width - visible_len_exec_msg)

    sys.stdout.write(f"\033[{prompt_line_abs};{prompt_text_start_col}H") 
    sys.stdout.write(truncated_exec_msg + padding_exec_msg + "\033[K") # Clear rest of line too
    sys.stdout.flush()
    # --- End Prompt Line Update ---

    sys.stdout.write(f"\033[{content_start_abs};1H") 
    
    exec_output_header_colored = f"Output for: {CYAN}{tool_name}{NC}"
    truncated_output_header = smart_truncate(exec_output_header_colored, content_text_width)
    header_visible_len = count_visible_chars(truncated_output_header)
    header_padding = " " * max(0, content_text_width - header_visible_len)
    
    print(PINK + "║ " + NC + truncated_output_header + header_padding + PINK + " ║" + NC + "\033[K")

    scrollable_output_height = content_height - 1 
    if scrollable_output_height <= 0: scrollable_output_height = 1

    while True:
        try:
            output = output_queue.get(timeout=0.05) 
            if output is None:  
                break 

            output_lines_buffer.append(output)
            if len(output_lines_buffer) > scrollable_output_height:
                output_lines_buffer.pop(0) 

            for i in range(scrollable_output_height):
                current_screen_line_for_output = content_start_abs + 1 + i
                sys.stdout.write(f"\033[{current_screen_line_for_output};1H") 
                
                if i < len(output_lines_buffer):
                    formatted_line = format_output_line_for_window(output_lines_buffer[i], content_text_width)
                    print(formatted_line + "\033[K") 
                else:
                    print(PINK + "║ " + NC + " " * content_text_width + PINK + " ║" + NC + "\033[K")
            sys.stdout.flush()

        except Empty:
            continue 
        except Exception as e:
            error_display_line = content_start_abs + content_height -1 
            sys.stdout.write(f"\033[{error_display_line};1H")
            error_msg_text = smart_truncate(f"{RED}Display Error: {str(e)}{NC}", content_text_width)
            print(format_output_line_for_window(error_msg_text, content_text_width) + "\033[K")
            sys.stdout.flush()
            break 


def main():
    """Main function to run the tool kit."""
    os.system('cls' if os.name == 'nt' else 'clear') # Initial clear for setup messages
    
    print(f"{YELLOW}Initializing gLiTcH-ToolKit...{NC}")
    if not setup_repository():
        print_colored("Initial setup failed. Please check messages above. Exiting.", RED)
        return
    time.sleep(0.5) 

    # === Force clear and cursor reset AFTER initial setup messages ===
    os.system('cls' if os.name == 'nt' else 'clear')
    sys.stdout.write("\033[1;1H") # Explicitly move cursor to top-left
    sys.stdout.flush()
    # === End force clear ===

    screen_draw_start_row = 1 
    MAIN_WINDOW_LAYOUT["screen_draw_start_row"] = screen_draw_start_row

    while True:
        term_cols, term_rows = shutil.get_terminal_size()
        
        sys.stdout.write(f"\033[{screen_draw_start_row};1H") # Ensure cursor is at 1;1
        sys.stdout.write("\033[J") # Clear from cursor (1;1) to end of screen
        sys.stdout.flush()

        tools = get_tools()

        if not tools:
            display_tools_with_border(tools, screen_draw_start_row, term_cols, term_rows)
            
            prompt_line_abs = MAIN_WINDOW_LAYOUT["prompt_line_abs"]
            prompt_text_start_col = MAIN_WINDOW_LAYOUT["prompt_text_start_col_abs"]
            prompt_text_area_width = MAIN_WINDOW_LAYOUT["total_width"] - prompt_text_start_col -1 

            no_tools_msg_colored = f"{YELLOW}No tools found. Repository might be empty or inaccessible."
            truncated_no_tools_msg = smart_truncate(no_tools_msg_colored, prompt_text_area_width)
            visible_len_no_tools = count_visible_chars(truncated_no_tools_msg)
            padding_no_tools = " " * max(0, prompt_text_area_width - visible_len_no_tools)
            
            sys.stdout.write(f"\033[{prompt_line_abs};{prompt_text_start_col}H")
            sys.stdout.write(truncated_no_tools_msg + padding_no_tools + "\033[K") # Clear rest of line
            sys.stdout.flush()

            sys.stdout.write(f"\033[{MAIN_WINDOW_LAYOUT['prompt_line_abs'] + 2};1H\033[K") 
            try:
                choice_str = input(f"{PINK}Press Enter to refresh, or 'q' to quit: {NC}").lower()
                if choice_str == 'q': break
                os.system('cls' if os.name == 'nt' else 'clear') 
                print(f"{YELLOW}Refreshing repository information...{NC}")
                if not setup_repository():
                    print_colored("Refresh failed. Exiting.", RED)
                    time.sleep(2)
                    break
                time.sleep(0.5)
                # === Force clear and cursor reset AFTER setup messages before loop continues ===
                os.system('cls' if os.name == 'nt' else 'clear')
                sys.stdout.write("\033[1;1H")
                sys.stdout.flush()
                # === End force clear ===
                continue 
            except KeyboardInterrupt:
                break 
            continue 
            
        display_tools_with_border(tools, screen_draw_start_row, term_cols, term_rows)

        prompt_line_abs = MAIN_WINDOW_LAYOUT["prompt_line_abs"]
        prompt_text_start_col = MAIN_WINDOW_LAYOUT["prompt_text_start_col_abs"]
        prompt_text_area_width = MAIN_WINDOW_LAYOUT["total_width"] - prompt_text_start_col -1 
        
        input_prompt_msg_colored = f"{YELLOW}Choice (1-{len(tools)}), 0 quit: {NC}"
        
        sys.stdout.write(f"\033[{prompt_line_abs};{prompt_text_start_col}H") 
        sys.stdout.write(" " * max(0, prompt_text_area_width) + "\033[K") # Clear area
        sys.stdout.write(f"\033[{prompt_line_abs};{prompt_text_start_col}H") 
        sys.stdout.flush()

        try:
            choice_str = input(input_prompt_msg_colored) 

            sys.stdout.write(f"\033[{prompt_line_abs};{prompt_text_start_col}H")
            sys.stdout.write(" " * max(0, prompt_text_area_width) + "\033[K") 
            sys.stdout.flush()

            if not choice_str: 
                sys.stdout.write(f"\033[{prompt_line_abs};{prompt_text_start_col}H")
                error_msg = smart_truncate(f"{RED}Invalid selection! Please enter a number.", prompt_text_area_width)
                sys.stdout.write(error_msg + " " * max(0, prompt_text_area_width - count_visible_chars(error_msg)) + "\033[K")
                sys.stdout.flush()
                time.sleep(1.5)
                continue

            choice = int(choice_str)

            if choice == 0: 
                break
            elif 1 <= choice <= len(tools): 
                selected_tool_name = tools[choice - 1]
                selected_tool_path = os.path.join(LOCAL_DIR_PATH, selected_tool_name)
                
                output_queue = Queue()
                exec_thread = Thread(target=execute_tool, args=(selected_tool_path, output_queue))
                exec_thread.start()
                
                display_execution_output_within_main_window(selected_tool_name, output_queue)
                
                exec_thread.join() 

                sys.stdout.write(f"\033[{prompt_line_abs};{prompt_text_start_col}H")
                completed_msg = smart_truncate(f"{PINK}Execution completed. Press Enter...", prompt_text_area_width)
                sys.stdout.write(completed_msg + " " * max(0, prompt_text_area_width - count_visible_chars(completed_msg)) + "\033[K")
                sys.stdout.flush()
                input() 
            else: 
                sys.stdout.write(f"\033[{prompt_line_abs};{prompt_text_start_col}H")
                error_msg = smart_truncate(f"{RED}Invalid selection! Choose 0-{len(tools)}.", prompt_text_area_width)
                sys.stdout.write(error_msg + " " * max(0, prompt_text_area_width - count_visible_chars(error_msg)) + "\033[K")
                sys.stdout.flush()
                time.sleep(1.5)
        except ValueError: 
            sys.stdout.write(f"\033[{prompt_line_abs};{prompt_text_start_col}H")
            error_msg = smart_truncate(f"{RED}Invalid input. Please enter a number.", prompt_text_area_width)
            sys.stdout.write(error_msg + " " * max(0, prompt_text_area_width - count_visible_chars(error_msg)) + "\033[K")
            sys.stdout.flush()
            time.sleep(1.5)
        except KeyboardInterrupt:
            sys.stdout.write(f"\033[{prompt_line_abs};1H\033[K") 
            sys.stdout.write(f"\033[{MAIN_WINDOW_LAYOUT.get('prompt_line_abs', term_rows -1) + 2};1H\n") # Use .get for safety
            print_colored("Exiting due to user interruption.", YELLOW)
            break 
        sys.stdout.flush() 

    # --- Cleanup ---
    try:
        _, term_rows_at_exit = shutil.get_terminal_size()
        final_cursor_line = MAIN_WINDOW_LAYOUT.get("prompt_line_abs", term_rows_at_exit -3) + 2 # Use .get for safety
        final_cursor_line = min(final_cursor_line, term_rows_at_exit) 
        sys.stdout.write(f"\033[{final_cursor_line};1H\n\033[K") 
    except Exception: 
        print("\n\n")

    if os.path.exists(LOCAL_DIR_PATH):
        try:
            shutil.rmtree(LOCAL_DIR_PATH)
            print_colored(f"Cleaned up temporary files: {LOCAL_DIR_PATH}", GREEN)
        except OSError as e:
            print_colored(f"Failed to clean up temporary files: {e}", RED)
    
    print(NC) 
    sys.stdout.flush()


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(NC) 
        try:
            _, term_rows_final = shutil.get_terminal_size()
            sys.stdout.write(f"\033[{term_rows_final};1H\n")
        except:
            print("\n\n")
        print(f"{RED}An critical unexpected error occurred: {e}{NC}")
        import traceback
        traceback.print_exc()
    finally:
        print(NC, end='')
        sys.stdout.write("\n") 
        sys.stdout.flush()
