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
    "prompt_line_abs": 0,
    "prompt_input_col_abs": 0,
    "is_drawn_once": False,
    "num_columns_for_tools": 3
}

# Constants for layout
FIXED_HEADER_LINES = 3
FIXED_FOOTER_LINES_INCL_PROMPT = 3
MIN_CONTENT_HEIGHT = 3
MIN_TOOLKIT_WIDTH = 30  # Absolute minimum width for the UI to be somewhat coherent
MIN_COLUMN_TEXT_WIDTH = 10 # Minimum text area width for a single column of tools

def clear_screen():
    os.system('cls' if os.name == 'nt' else 'clear')

def print_colored(text, color):
    print(f"{color}{text}{NC}")

def setup_repository():
    # (Setup repository logic remains the same)
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
    # (Get tools logic remains the same)
    tools = []
    if not os.path.isdir(LOCAL_DIR_PATH): return tools
    for item in os.listdir(LOCAL_DIR_PATH):
        if item == ".git" or item.startswith('.'): continue
        item_path = os.path.join(LOCAL_DIR_PATH, item)
        if os.path.isfile(item_path): tools.append(item)
    tools.sort(key=str.lower)
    return tools

def display_tools_with_border(tools, screen_draw_start_row, term_width, term_height):
    available_height = term_height - screen_draw_start_row + 1
    calculated_content_height = available_height - FIXED_HEADER_LINES - FIXED_FOOTER_LINES_INCL_PROMPT
    content_height = max(MIN_CONTENT_HEIGHT, calculated_content_height)
    MAIN_WINDOW_LAYOUT["content_height"] = content_height
    num_rows_for_tools = content_height

    # --- Width Calculations ---
    actual_total_width = term_width
    if actual_total_width < MIN_TOOLKIT_WIDTH:
        actual_total_width = MIN_TOOLKIT_WIDTH # Enforce minimum if terminal is too small

    MAIN_WINDOW_LAYOUT["total_width"] = actual_total_width
    
    # Determine number of columns
    # Max 3 columns, min 1. Available width for columns area: actual_total_width - borders - inter-column spacing
    # Borders (║ ║) take 4 chars.
    inner_drawable_width = actual_total_width - 4
    
    if inner_drawable_width >= (MIN_COLUMN_TEXT_WIDTH * 3 + 2 * 3): # 3 cols + 2 separators (3 chars each)
        num_columns = 3
    elif inner_drawable_width >= (MIN_COLUMN_TEXT_WIDTH * 2 + 1 * 3): # 2 cols + 1 separator
        num_columns = 2
    else:
        num_columns = 1
    MAIN_WINDOW_LAYOUT["num_columns_for_tools"] = num_columns

    # Calculate symmetrical column text widths
    col_text_widths = [0] * num_columns
    if num_columns > 0:
        total_separator_width = (num_columns - 1) * 3
        space_for_all_cols_text_area = inner_drawable_width - total_separator_width
        if space_for_all_cols_text_area < num_columns * 1: # Ensure at least 1 char per col text area
            space_for_all_cols_text_area = num_columns * 1 
            # This scenario means terminal is extremely small, overriding MIN_COLUMN_TEXT_WIDTH logic just for positive width

        base_col_text_width = space_for_all_cols_text_area // num_columns
        remainder_width = space_for_all_cols_text_area % num_columns
        
        for i in range(num_columns):
            col_text_widths[i] = base_col_text_width + (1 if i < remainder_width else 0)
            if col_text_widths[i] <=0: col_text_widths[i] = 1 # Absolute fallback

    num_tools = len(tools)
    MAIN_WINDOW_LAYOUT["content_start_line_abs"] = screen_draw_start_row + (FIXED_HEADER_LINES -1)

    # --- Drawing ---
    print(PINK + "╔" + "═" * (actual_total_width - 2) + "╗" + NC + "\033[K")
    header_text = "gLiTcH-ToolKit - Linux System Tools"
    header_padding_total = actual_total_width - len(header_text) - 2
    header_pad_left = max(0, header_padding_total // 2)
    header_pad_right = max(0, header_padding_total - header_pad_left)
    print(PINK + "║" + NC + " " * header_pad_left + YELLOW + header_text + NC +
          " " * header_pad_right + PINK + "║" + NC + "\033[K")
    print(PINK + "╠" + "═" * (actual_total_width - 2) + "╣" + NC + "\033[K")

    for r in range(num_rows_for_tools):
        line_str = PINK + "║ " + NC
        for c in range(num_columns):
            tool_idx = r + c * num_rows_for_tools
            col_alloc_for_text = col_text_widths[c]

            if tool_idx < num_tools:
                tool_name_orig = tools[tool_idx]
                tool_num_prefix = f"{tool_idx + 1}. "
                display_text_no_color = tool_num_prefix + tool_name_orig

                if len(display_text_no_color) > col_alloc_for_text:
                    available_for_name = col_alloc_for_text - len(tool_num_prefix) - 1 # For "…"
                    if available_for_name < 0:
                        truncated_prefix = tool_num_prefix[:max(0, col_alloc_for_text - 1)]
                        display_text_colored = f"{GREEN}{truncated_prefix}…{NC}"
                        # Pad with spaces if truncated prefix and ellipsis is less than allocated
                        len_after_color_approx = len(truncated_prefix) + 1
                        padding = ' ' * max(0, col_alloc_for_text - len_after_color_approx)
                        line_str += display_text_colored + padding

                    else:
                        truncated_name = tool_name_orig[:available_for_name]
                        display_text_colored = f"{GREEN}{tool_num_prefix}{PINK}{truncated_name}…{NC}"
                        line_str += display_text_colored # Assumes it fills due to ellipsis
                else:
                    display_text_colored = f"{GREEN}{tool_num_prefix}{PINK}{tool_name_orig}{NC}"
                    padding_needed = col_alloc_for_text - len(display_text_no_color)
                    line_str += display_text_colored + (' ' * padding_needed)
            else:
                line_str += " " * col_alloc_for_text # Empty slot

            if c < num_columns - 1:
                line_str += "   "  # Separator
        
        line_str += PINK + " ║" + NC
        print(line_str + "\033[K")

    print(PINK + "╟" + "─" * (actual_total_width - 2) + "╢" + NC + "\033[K")
    MAIN_WINDOW_LAYOUT["prompt_line_abs"] = MAIN_WINDOW_LAYOUT["content_start_line_abs"] + content_height + 1
    prompt_prefix = " > "
    MAIN_WINDOW_LAYOUT["prompt_input_col_abs"] = 1 + 2 + len(prompt_prefix) # screen_col is 1-indexed, "║ ", " > "
    empty_prompt_space = actual_total_width - 2 - len(prompt_prefix) - 2 # "║", "prompt", "║", space for cursor
    print(PINK + "║" + NC + YELLOW + prompt_prefix + NC + " " * max(0, empty_prompt_space) + PINK + "║" + NC + "\033[K")
    print(PINK + "╚" + "═" * (actual_total_width - 2) + "╝" + NC + "\033[K")
    MAIN_WINDOW_LAYOUT["is_drawn_once"] = True


def execute_tool(tool_path, output_queue):
    # (Execute tool logic remains the same)
    try:
        process = subprocess.Popen(["bash", tool_path],
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                     text=True, bufsize=1, universal_newlines=True, errors='replace')
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


def count_visible_chars(text_with_ansi):
    """Counts visible characters in a string with ANSI codes."""
    plain_text = ""
    in_escape = False
    for char in text_with_ansi:
        if char == '\033':
            in_escape = True
        elif in_escape and char == 'm':
            in_escape = False
        elif not in_escape:
            plain_text += char
    return len(plain_text)

def smart_truncate(text_with_ansi, max_visible_chars):
    """Truncates a string with ANSI codes to a max number of visible characters."""
    if count_visible_chars(text_with_ansi) <= max_visible_chars:
        return text_with_ansi

    truncated_text = ""
    visible_count = 0
    in_escape = False
    ellipsis_len = 1 # for "…"

    for char in text_with_ansi:
        if char == '\033':
            in_escape = True
            truncated_text += char
        elif in_escape:
            truncated_text += char
            if char == 'm':
                in_escape = False
        else: # Visible character
            if visible_count < max_visible_chars - ellipsis_len:
                truncated_text += char
                visible_count += 1
            elif visible_count == max_visible_chars - ellipsis_len: # Add ellipsis and stop
                truncated_text += "…" + NC # Add NC to reset color before ellipsis
                visible_count += ellipsis_len
                break
            else: # Should have stopped before
                break
    
    # If loop finished and string is still too short (e.g. max_visible_chars was 0 or 1)
    if visible_count < max_visible_chars and not truncated_text.endswith("…"+NC):
         if max_visible_chars > 0:
            return ("…" + NC)[:max_visible_chars] # Return ellipsis if possible
         else:
            return ""


    return truncated_text


def format_output_line_for_window(line_text, max_content_width):
    # (Format output line logic, using smart_truncate)
    truncated_line = smart_truncate(line_text, max_content_width)
    visible_len_of_truncated = count_visible_chars(truncated_line)
    padding = " " * max(0, max_content_width - visible_len_of_truncated)
    return PINK + "║ " + NC + truncated_line + padding + PINK + " ║" + NC


def display_execution_output_within_main_window(tool_name, output_queue):
    # (Display execution output logic remains largely the same, uses updated layout info)
    if not MAIN_WINDOW_LAYOUT["is_drawn_once"]:
        print_colored("Error: Main window layout not established.", RED)
        return

    content_start_abs = MAIN_WINDOW_LAYOUT["content_start_line_abs"]
    content_height = MAIN_WINDOW_LAYOUT["content_height"]
    content_text_width = MAIN_WINDOW_LAYOUT["total_width"] - 4 # For text between "║ " and " ║"

    output_lines_buffer = []

    sys.stdout.write(f"\033[{content_start_abs};1H") # Move to start of content area
    
    exec_header_plain = f"Executing: {tool_name}"
    exec_header_display_text = smart_truncate(f"Executing: {YELLOW}{tool_name}{NC}", content_text_width)
    
    header_visible_len = count_visible_chars(exec_header_display_text)
    header_padding = " " * max(0, content_text_width - header_visible_len)
    
    print(PINK + "║ " + NC + exec_header_display_text + header_padding + PINK + " ║" + NC + "\033[K")

    scrollable_output_height = content_height - 1 # 1 line for "Executing..." header
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
                    # Print a blank content line
                    print(PINK + "║ " + NC + " " * content_text_width + PINK + " ║" + NC + "\033[K")
            sys.stdout.flush()

        except Empty: continue 
        except Exception as e:
            error_line_abs = content_start_abs + content_height -1 # Last line of content area
            sys.stdout.write(f"\033[{error_line_abs};1H")
            error_msg_text = smart_truncate(f"{RED}Display Error: {str(e)}{NC}", content_text_width)
            print(format_output_line_for_window(error_msg_text, content_text_width) + "\033[K")
            sys.stdout.flush()
            break 


def main():
    # (Main function logic remains largely the same structure, uses term_cols/rows)
    clear_screen()
    if not setup_repository():
        print_colored("Initial setup failed. Exiting.", RED)
        return

    screen_draw_start_row = 1
    MAIN_WINDOW_LAYOUT["screen_draw_start_row"] = screen_draw_start_row

    while True:
        term_cols, term_rows = shutil.get_terminal_size()
        
        sys.stdout.write(f"\033[{screen_draw_start_row};1H")
        sys.stdout.write("\033[J") # Clear from cursor to end of screen

        tools = get_tools()

        if not tools:
            display_tools_with_border(tools, screen_draw_start_row, term_cols, term_rows)
            prompt_abs = MAIN_WINDOW_LAYOUT["prompt_line_abs"]
            prompt_col_start_text = MAIN_WINDOW_LAYOUT["prompt_input_col_abs"] - len(" > ") # Start of prompt text area
            
            sys.stdout.write(f"\033[{prompt_abs};{prompt_col_start_text}H\033[K")
            no_tools_msg = f"{YELLOW}No tools found. Repo empty or inaccessible."
            prompt_text_area_width = MAIN_WINDOW_LAYOUT["total_width"] - (prompt_col_start_text -1) - 2 # For "║" and "║"
            print(no_tools_msg.ljust(max(0,prompt_text_area_width)) + NC, end="")
            sys.stdout.flush()

            # Add an input prompt below the main window for this specific case, as the internal one is for messages.
            sys.stdout.write(f"\033[{MAIN_WINDOW_LAYOUT['prompt_line_abs'] + 2};1H\033[K") # Two lines below border
            try:
                choice_str = input(f"{PINK}Press Enter to refresh, or 'q' to quit: {NC}").lower()
                if choice_str == 'q': break
                clear_screen() # Full clear before trying setup again
                if not setup_repository():
                    print_colored("Refresh failed. Exiting.", RED)
                    time.sleep(2) # Give time to read message
                    break
                continue # Retry the loop to redraw
            except KeyboardInterrupt: break
            continue
            
        display_tools_with_border(tools, screen_draw_start_row, term_cols, term_rows)

        prompt_line_abs = MAIN_WINDOW_LAYOUT["prompt_line_abs"]
        prompt_input_col_abs = MAIN_WINDOW_LAYOUT["prompt_input_col_abs"]
        prompt_text_area_width = MAIN_WINDOW_LAYOUT["total_width"] - (prompt_input_col_abs -1) - 2 # space for text input
        
        sys.stdout.write(f"\033[{prompt_line_abs};{prompt_input_col_abs}H")
        sys.stdout.write(" " * max(0, prompt_text_area_width) + f"\033[{max(0, prompt_text_area_width)}D") # Clear and reposition
        sys.stdout.flush()

        try:
            choice_str = input(f"{YELLOW}Choice (1-{len(tools)}), 0 quit: {NC}")

            sys.stdout.write(f"\033[{prompt_line_abs};{prompt_input_col_abs}H") # Go to start of input area
            sys.stdout.write(" " * max(0, prompt_text_area_width) + f"\033[{max(0, prompt_text_area_width)}D") # Clear it for next message/input
            sys.stdout.flush()


            if not choice_str:
                print(RED + "Invalid selection! ".ljust(max(0,prompt_text_area_width)) + NC, end="")
                sys.stdout.flush()
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

                sys.stdout.write(f"\033[{prompt_line_abs};{prompt_input_col_abs}H")
                sys.stdout.write(" " * max(0,prompt_text_area_width) + f"\033[{max(0,prompt_text_area_width)}D") # Clear input area
                input(PINK + "Execution completed. Press Enter...".ljust(max(0,prompt_text_area_width)) + NC)
            else:
                print(RED + f"Invalid selection! ".ljust(max(0,prompt_text_area_width)) + NC, end="")
                sys.stdout.flush()
                time.sleep(1.5)
        except ValueError:
            print(RED + "Invalid input. Enter a number.".ljust(max(0,prompt_text_area_width)) + NC, end="")
            sys.stdout.flush()
            time.sleep(1.5)
        except KeyboardInterrupt:
            # Clean up prompt line before exiting message
            sys.stdout.write(f"\033[{prompt_line_abs};1H\033[K") # Clear entire prompt line
            print_colored("\nExiting due to user interruption.", YELLOW)
            break
        sys.stdout.flush()


    # Cleanup
    if os.path.exists(LOCAL_DIR_PATH):
        try:
            # Try to move cursor to bottom of terminal for cleanup messages
            _, term_rows_at_exit = shutil.get_terminal_size()
            sys.stdout.write(f"\033[{term_rows_at_exit};1H\n\033[K") 
            shutil.rmtree(LOCAL_DIR_PATH)
            print_colored(f"Cleaned up: {LOCAL_DIR_PATH}.", GREEN)
        except OSError as e:
            print_colored(f"Cleanup failed: {e}", RED)
        except Exception: # Catch potential shutil.get_terminal_size() error on some systems/exits
             print_colored(f"Cleanup (faced minor issue displaying status): {LOCAL_DIR_PATH} removal attempted.", YELLOW if os.path.exists(LOCAL_DIR_PATH) else GREEN)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(NC) 
        print(f"{RED}An unexpected error occurred globally: {e}{NC}")
        import traceback
        traceback.print_exc()
    finally:
        print(NC, end='')
        print()
