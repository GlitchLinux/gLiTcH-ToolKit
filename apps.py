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
    "screen_draw_start_row": 1,
    "content_start_line_abs": 0,
    "content_height": 0,
    "total_width": 0,
    "prompt_line_abs": 0,        # Absolute screen line for the input prompt text
    "prompt_input_col_abs": 0,   # Absolute screen column for input()
    "is_drawn_once": False,
    "num_columns_for_tools": 3   # Default number of columns for tools
}

# Constants for layout
FIXED_HEADER_LINES = 3  # Top border, Title, Content Separator
FIXED_FOOTER_LINES_INCL_PROMPT = 3 # Prompt Separator, Prompt Line, Bottom Border
MIN_CONTENT_HEIGHT = 3
MIN_TOOLKIT_WIDTH = 40 # Minimum reasonable width for the toolkit
MIN_COLUMN_WIDTH = 15 # Minimum width for a single column of tools

def clear_screen():
    os.system('cls' if os.name == 'nt' else 'clear')

def print_colored(text, color):
    print(f"{color}{text}{NC}")

def setup_repository():
    if not os.path.exists(BASE_DIR):
        try:
            os.makedirs(BASE_DIR)
        except OSError as e:
            print_colored(f"Failed to create base directory {BASE_DIR}: {e}", RED)
            return False
    os.chdir(BASE_DIR)
    if os.path.isdir(os.path.join(LOCAL_DIR_PATH, ".git")):
        print_colored("Updating repository...", YELLOW)
        sys.stdout.flush()
        try:
            subprocess.run(["git", "-C", LOCAL_DIR_PATH, "pull"], check=True, capture_output=True, text=True)
        except subprocess.CalledProcessError as e:
            print_colored(f"Failed to update repository. Error: {e.stderr}", RED)
            return False
    else:
        print_colored("Cloning repository...", YELLOW)
        sys.stdout.flush()
        try:
            subprocess.run(["git", "clone", REPO_URL, LOCAL_DIR_PATH], check=True, capture_output=True, text=True)
        except subprocess.CalledProcessError as e:
            print_colored(f"Failed to clone repository. Error: {e.stderr}", RED)
            return False
    return True

def get_tools():
    tools = []
    if not os.path.isdir(LOCAL_DIR_PATH): return tools
    for item in os.listdir(LOCAL_DIR_PATH):
        if item == ".git" or item.startswith('.'): continue
        item_path = os.path.join(LOCAL_DIR_PATH, item)
        if os.path.isfile(item_path): tools.append(item)
    tools.sort(key=str.lower)
    return tools

def display_tools_with_border(tools, screen_draw_start_row, term_width, term_height):
    # Calculate available height for content
    available_height = term_height - screen_draw_start_row + 1
    calculated_content_height = available_height - FIXED_HEADER_LINES - FIXED_FOOTER_LINES_INCL_PROMPT
    content_height = max(MIN_CONTENT_HEIGHT, calculated_content_height)
    
    MAIN_WINDOW_LAYOUT["content_height"] = content_height
    num_rows_for_tools = content_height # This is how many tools per column can be shown

    # Determine number of columns based on terminal width
    # Max 3 columns, min 1 column.
    if term_width > MIN_COLUMN_WIDTH * 3 + 10: # Ample space for 3 columns
        num_columns = 3
    elif term_width > MIN_COLUMN_WIDTH * 2 + 8: # Space for 2
        num_columns = 2
    else: # Default to 1 if very narrow
        num_columns = 1
    MAIN_WINDOW_LAYOUT["num_columns_for_tools"] = num_columns


    num_tools = len(tools)
    
    # Determine column widths
    col_widths = [0] * num_columns
    # Calculate base width required by borders and inter-column spacing
    base_width_for_border_spacing = 4 + (num_columns - 1) * 3 # "║ ", " ║", and "   " separators

    # Max available width for all columns content (not including their own padding yet)
    max_total_cols_content_width = term_width - base_width_for_border_spacing -2 # -2 for safety margin
    
    # Distribute available width among columns or calculate ideal if enough space
    ideal_col_widths = [0] * num_columns
    for i in range(num_columns):
        max_len = 0
        for j in range(num_rows_for_tools): # Use num_rows_for_tools
            idx = j + i * num_rows_for_tools
            if idx < num_tools:
                tool_display_name = f"{idx + 1}. {tools[idx]}"
                # Truncate tool name if it's excessively long for a column
                # Max visible length for tool name in a column:
                # (max_total_cols_content_width / num_columns) - len("NN. ")
                # This is a simplification; true truncation is harder with dynamic col widths.
                # For now, just get its length.
                if len(tool_display_name) > max_len:
                    max_len = len(tool_display_name)
            elif j == 0 :
                max_len = max(max_len, 5) # Min width for an empty column slot
        ideal_col_widths[i] = max_len + 2 # Add padding

    ideal_total_width = sum(ideal_col_widths) + base_width_for_border_spacing
    
    # Actual total width for the toolkit window
    # Use ideal if it fits, otherwise cap at terminal width or a minimum
    actual_total_width = min(ideal_total_width, term_width -1) # -1 to avoid issues at edge
    actual_total_width = max(MIN_TOOLKIT_WIDTH, actual_total_width)
    
    # Recalculate individual column widths if total width was capped or needs to expand
    # This part ensures columns fill the actual_total_width proportionally or equally
    current_sum_ideal_no_padding = sum(w - 2 for w in ideal_col_widths)
    available_for_cols_content = actual_total_width - base_width_for_border_spacing
    
    for i in range(num_columns):
        if current_sum_ideal_no_padding > 0: # Proportional
            col_widths[i] = 2 + int((ideal_col_widths[i] - 2) / current_sum_ideal_no_padding * available_for_cols_content)
        else: # Equal distribution if no ideal basis (e.g., no tools)
            col_widths[i] = 2 + int(available_for_cols_content / num_columns)
    
    # Adjust last column width to ensure sum matches actual_total_width - base_width_for_border_spacing
    current_cols_content_sum = sum(w - 2 for w in col_widths)
    diff = available_for_cols_content - current_cols_content_sum
    if num_columns > 0:
      col_widths[num_columns - 1] += diff


    MAIN_WINDOW_LAYOUT["total_width"] = actual_total_width
    MAIN_WINDOW_LAYOUT["content_start_line_abs"] = screen_draw_start_row + FIXED_HEADER_LINES -1 # Adjusted: -1 because screen_draw_start_row is 1-indexed
    
    # Prompt line calculation
    # content_start_line_abs is 0-indexed relative to screen_draw_start_row, if screen_draw_start_row =1, then it's actual screen line + headers
    # Corrected: content_start_line_abs will be the actual screen line.
    MAIN_WINDOW_LAYOUT["content_start_line_abs"] = screen_draw_start_row + (FIXED_HEADER_LINES -1)


    # Print top border
    print(PINK + "╔" + "═" * (actual_total_width - 2) + "╗" + NC + "\033[K")

    # Print header
    header_text = "gLiTcH-ToolKit - Linux System Tools"
    header_padding_total = actual_total_width - len(header_text) - 2
    header_pad_left = header_padding_total // 2
    header_pad_right = header_padding_total - header_pad_left
    print(PINK + "║" + NC + " " * header_pad_left + YELLOW + header_text + NC +
          " " * header_pad_right + PINK + "║" + NC + "\033[K")

    # Print content separator
    print(PINK + "╠" + "═" * (actual_total_width - 2) + "╣" + NC + "\033[K")

    # Print Tools Content Area
    for r in range(num_rows_for_tools):
        line_str = PINK + "║ " + NC
        inner_content_width = actual_total_width - 4 # Space for "║ " and " ║"
        current_line_tool_text = ""
        for c in range(num_columns):
            tool_idx = r + c * num_rows_for_tools
            col_content_alloc = col_widths[c] - 2 # available for text in this col
            if tool_idx < num_tools:
                tool_name = tools[tool_idx]
                display_text_no_color = f"{tool_idx + 1}. {tool_name}"
                
                # Truncate if necessary
                if len(display_text_no_color) > col_content_alloc:
                    display_text_no_color = display_text_no_color[:col_content_alloc-3] + "..."
                
                display_text_colored = f"{GREEN}{tool_idx + 1}. {PINK}{tool_name}{NC}" # Re-color original name
                # This coloring after truncation needs care. Simplified: truncate plain, color original.
                # A better way would be to find where to truncate in colored string.
                if len(f"{tool_idx + 1}. {tool_name}") > col_content_alloc : # if original was too long
                     # Rough estimate for colored truncation.
                    plain_num = f"{tool_idx + 1}. "
                    name_alloc = col_content_alloc - len(plain_num) -3 # for "..."
                    if name_alloc > 0 :
                        display_text_colored = f"{GREEN}{plain_num}{PINK}{tool_name[:name_alloc]}...{NC}"
                    else: # Not enough space even for number and "..."
                         display_text_colored = f"{GREEN}{(plain_num[:col_content_alloc-1])[:col_content_alloc-1]}…{NC}"


                current_line_tool_text += display_text_colored.ljust(col_widths[c] - 2 + len(display_text_colored) - len(display_text_no_color)) # Pad with colors considered
            else:
                current_line_tool_text += " " * (col_widths[c] - 2)
            if c < num_columns - 1:
                current_line_tool_text += "   " # Separator between columns
        
        line_str += current_line_tool_text.ljust(inner_content_width) # ensure full width
        line_str += PINK + " ║" + NC
        print(line_str + "\033[K")

    # Print Prompt Separator
    print(PINK + "╟" + "─" * (actual_total_width - 2) + "╢" + NC + "\033[K")
    MAIN_WINDOW_LAYOUT["prompt_line_abs"] = MAIN_WINDOW_LAYOUT["content_start_line_abs"] + content_height + 1

    # Print Empty Prompt Line
    prompt_prefix = " > "
    MAIN_WINDOW_LAYOUT["prompt_input_col_abs"] = 1 + 2 + len(prompt_prefix) # screen_col + "║ " + "> "
    empty_prompt_space = actual_total_width - 2 - len(prompt_prefix) -1 # -1 for cursor
    print(PINK + "║" + NC + YELLOW + prompt_prefix + NC + " " * empty_prompt_space + PINK + "║" + NC + "\033[K")
    
    # Print Bottom Border
    print(PINK + "╚" + "═" * (actual_total_width - 2) + "╝" + NC + "\033[K")
    
    MAIN_WINDOW_LAYOUT["is_drawn_once"] = True


def execute_tool(tool_path, output_queue):
    try:
        process = subprocess.Popen(["bash", tool_path],
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                     text=True, bufsize=1, universal_newlines=True)
        for stdout_line in iter(process.stdout.readline, ""):
            output_queue.put(stdout_line.strip())
        process.stdout.close()
        stderr_output = process.stderr.read()
        if stderr_output: output_queue.put(f"{RED}Error:{NC} {stderr_output.strip()}")
        process.wait()
        output_queue.put(None)
    except Exception as e:
        output_queue.put(f"{RED}Execution failed: {str(e)}{NC}")
        output_queue.put(None)

def format_output_line_for_window(line_text, max_content_width):
    plain_text = line_text
    # Simplified ANSI stripping for length check
    temp_plain_text = ""
    in_escape = False
    for char in line_text:
        if char == '\033': in_escape = True
        if not in_escape: temp_plain_text += char
        if in_escape and char == 'm': in_escape = False
    plain_text = temp_plain_text

    if len(plain_text) > max_content_width:
        # Estimate truncation point in original string (very approximate)
        chars_to_keep_plain = max_content_width - 3
        original_idx_count = 0
        plain_idx_count = 0
        trunc_at_original_idx = len(line_text)
        
        in_esc_trunc = False
        for i_orig, char_orig in enumerate(line_text):
            if char_orig == '\033': in_esc_trunc = True
            if not in_esc_trunc:
                plain_idx_count += 1
                if plain_idx_count > chars_to_keep_plain:
                    trunc_at_original_idx = i_orig
                    break
            if in_esc_trunc and char_orig == 'm': in_esc_trunc = False
        
        line_text = line_text[:trunc_at_original_idx] + NC + "..." # Add NC to reset color before "..."


    padding = " " * (max_content_width - len(plain_text)) if len(plain_text) < max_content_width else ""
    return PINK + "║ " + NC + line_text + padding + PINK + " ║" + NC

def display_execution_output_within_main_window(tool_name, output_queue):
    if not MAIN_WINDOW_LAYOUT["is_drawn_once"]:
        print_colored("Error: Main window layout not established.", RED)
        return

    content_start_abs = MAIN_WINDOW_LAYOUT["content_start_line_abs"]
    content_height = MAIN_WINDOW_LAYOUT["content_height"]
    content_text_width = MAIN_WINDOW_LAYOUT["total_width"] - 4

    output_lines_buffer = []

    sys.stdout.write(f"\033[{content_start_abs};1H")
    exec_header_display_text = f"Executing: {YELLOW}{tool_name}{NC}"
    plain_header_len = len(f"Executing: {tool_name}")
    header_padding = " " * (content_text_width - plain_header_len) if plain_header_len < content_text_width else ""
    print(PINK + "║ " + NC + exec_header_display_text + header_padding + PINK + " ║" + NC + "\033[K")

    scrollable_output_height = content_height - 1
    if scrollable_output_height <= 0: scrollable_output_height = 1

    while True:
        try:
            output = output_queue.get(timeout=0.05)
            if output is None: break
            output_lines_buffer.append(output)
            if len(output_lines_buffer) > scrollable_output_height:
                output_lines_buffer.pop(0)

            for i in range(scrollable_output_height):
                current_screen_line = content_start_abs + 1 + i
                sys.stdout.write(f"\033[{current_screen_line};1H")
                if i < len(output_lines_buffer):
                    formatted_line = format_output_line_for_window(output_lines_buffer[i], content_text_width)
                    print(formatted_line + "\033[K")
                else:
                    print(PINK + "║ " + NC + " " * content_text_width + PINK + " ║" + NC + "\033[K")
            sys.stdout.flush()
        except Empty: continue
        except Exception as e:
            error_line_abs = content_start_abs + content_height - 1
            sys.stdout.write(f"\033[{error_line_abs};1H")
            error_msg_text = f"{RED}Display Error: {str(e)[:content_text_width-15]}{NC}"
            print(format_output_line_for_window(error_msg_text, content_text_width) + "\033[K")
            sys.stdout.flush()
            break

def main():
    clear_screen()
    if not setup_repository():
        print_colored("Initial setup failed. Exiting.", RED)
        return

    screen_draw_start_row = 1
    MAIN_WINDOW_LAYOUT["screen_draw_start_row"] = screen_draw_start_row

    while True:
        term_cols, term_rows = shutil.get_terminal_size()
        
        sys.stdout.write(f"\033[{screen_draw_start_row};1H") # Move to top-left of our drawing area
        sys.stdout.write("\033[J") # Clear from cursor to end of screen

        tools = get_tools()

        if not tools:
            # Draw a minimal frame with error message if no tools
            display_tools_with_border(tools, screen_draw_start_row, term_cols, term_rows) # Will draw empty frame
            
            prompt_abs = MAIN_WINDOW_LAYOUT["prompt_line_abs"]
            prompt_col = MAIN_WINDOW_LAYOUT["prompt_input_col_abs"] - len(" > ") # start of the line for message

            sys.stdout.write(f"\033[{prompt_abs};{prompt_col + 2}H\033[K") # Clear prompt space
            no_tools_msg = "No tools found. Repo empty or inaccessible."
            print(YELLOW + no_tools_msg.ljust(MAIN_WINDOW_LAYOUT["total_width"] - 4 - len(" > "))+NC, end="")

            sys.stdout.write(f"\033[{prompt_abs +1};1H\033[K") # Line below prompt area
            try:
                choice_str = input(f"{PINK}Press Enter to refresh, or 'q' to quit: {NC}").lower()
                if choice_str == 'q': break
                clear_screen()
                if not setup_repository():
                    print_colored("Refresh failed. Exiting.", RED)
                    break
                continue
            except KeyboardInterrupt: break
            continue
            
        display_tools_with_border(tools, screen_draw_start_row, term_cols, term_rows)

        prompt_line_abs = MAIN_WINDOW_LAYOUT["prompt_line_abs"]
        prompt_input_col_abs = MAIN_WINDOW_LAYOUT["prompt_input_col_abs"]
        
        # Clear the input part of the prompt line before asking for input
        prompt_text_area_width = MAIN_WINDOW_LAYOUT["total_width"] - (prompt_input_col_abs -1) -2 # -1 for col index, -2 for right border " ║"
        sys.stdout.write(f"\033[{prompt_line_abs};{prompt_input_col_abs}H")
        sys.stdout.write(" " * prompt_text_area_width + "\033[K") # Clear input area
        sys.stdout.write(f"\033[{prompt_line_abs};{prompt_input_col_abs}H") # Reposition for input

        try:
            choice_str = input(f"{YELLOW}Enter choice (1-{len(tools)}), 0 to quit: {NC}")

            if not choice_str:
                sys.stdout.write(f"\033[{prompt_line_abs};{prompt_input_col_abs}H\033[K") # Clear input area
                print(RED + "Invalid selection! ".ljust(prompt_text_area_width) + NC, end="")
                time.sleep(1.5)
                continue

            choice = int(choice_str)

            if choice == 0: break
            elif 1 <= choice <= len(tools):
                selected_tool_name = tools[choice - 1]
                selected_tool_path = os.path.join(LOCAL_DIR_PATH, selected_tool_name)
                
                output_queue = Queue()
                exec_thread = Thread(target=execute_tool, args=(selected_tool_path, output_queue))
                exec_thread.start()
                
                display_execution_output_within_main_window(selected_tool_name, output_queue)
                exec_thread.join()

                sys.stdout.write(f"\033[{prompt_line_abs};{prompt_input_col_abs}H\033[K")
                input(PINK + "Execution completed. Press Enter...".ljust(prompt_text_area_width) + NC)
            else:
                sys.stdout.write(f"\033[{prompt_line_abs};{prompt_input_col_abs}H\033[K")
                print(RED + f"Invalid selection! Choose 0-{len(tools)}.".ljust(prompt_text_area_width) + NC, end="")
                time.sleep(1.5)
        except ValueError:
            sys.stdout.write(f"\033[{prompt_line_abs};{prompt_input_col_abs}H\033[K")
            print(RED + "Invalid input. Enter a number.".ljust(prompt_text_area_width) + NC, end="")
            time.sleep(1.5)
        except KeyboardInterrupt:
            print_colored("\nExiting due to user interruption.", YELLOW)
            break
        sys.stdout.flush()

    # Cleanup
    if os.path.exists(LOCAL_DIR_PATH):
        try:
            sys.stdout.write(f"\033[{term_rows};1H\n\033[K") # Move to bottom and clear line
            shutil.rmtree(LOCAL_DIR_PATH)
            print_colored(f"Cleaned up: {LOCAL_DIR_PATH}.", GREEN)
        except OSError as e:
            print_colored(f"Cleanup failed: {e}", RED)

if __name__ == "__main__":
    original_terminal_settings = None
    # Add advanced terminal settings handling if interactive input becomes an issue
    # For now, this is not strictly needed for the requested features.
    try:
        main()
    except Exception as e:
        print(NC)
        print(f"{RED}Unexpected error: {e}{NC}")
        import traceback
        traceback.print_exc()
    finally:
        print(NC, end='')
        print() # Ensure prompt is on a new line after exit
