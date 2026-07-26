#!/usr/bin/env bash
# Self-extracting base64 rebuild script for: dd.png
# Original size: 7271 bytes
set -euo pipefail

OUT_FILE="dd.png"
EXPECTED_SIZE=7271

if [[ -e "$OUT_FILE" ]]; then
    printf "> '%s' already exists. Overwrite? [y/N] " "$OUT_FILE"
    read -r ANS
    case "$ANS" in
        [Yy]*) ;;
        *) echo "> aborted"; exit 1 ;;
    esac
fi

echo "> rebuilding '$OUT_FILE'..."
base64 -d <<'B64_DATA' > "$OUT_FILE"
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
B64_DATA

if ACTUAL=$(stat -c%s "$OUT_FILE" 2>/dev/null); then :; else ACTUAL=$(stat -f%z "$OUT_FILE"); fi

if [[ "$ACTUAL" -eq "$EXPECTED_SIZE" ]]; then
    echo "> rebuild complete: '$OUT_FILE' ($ACTUAL bytes) - byte count matches"
else
    echo "> WARNING: byte count mismatch!"
    echo ">   expected: $EXPECTED_SIZE bytes"
    echo ">   actual:   $ACTUAL bytes"
    echo ">   file rebuild may be corrupt."
    exit 2
fi

cat > "/tmp/mini-dd-gui.py" << 'EOF'

#!/usr/bin/python3

import tkinter as tk
from tkinter import filedialog, messagebox, ttk
import subprocess
import threading
import re
import os
import signal

ICON_PATH = "/usr/share/pixmaps/dd.png"

class DDUtilityApp:
    def __init__(self, root):
        self.root = root
        self.root.title("DD Utility")
        self.root.configure(bg='gray20')

        # Embed the dd.png icon in the window/taskbar
        if os.path.exists(ICON_PATH):
            self.icon_image = tk.PhotoImage(file=ICON_PATH)
            self.root.iconphoto(True, self.icon_image)

        # Create main frame
        self.main_frame = tk.Frame(self.root, bg='gray20')
        self.main_frame.pack(padx=10, pady=10, fill='both', expand=True)

        self.selected_file = None
        self.selected_source_disk = None
        self.selected_destination_disk = None
        self.total_size = 0  # Total size of source
        self.task_message = ""  # Message to display during operation
        self.process = None  # Reference to the dd process

        self.font = ("Sans", 11)  # Font for most of the UI
        self.disk_selection_font = ("Sans", 13)  # Larger font for disk selection window

        self.initialize_ui()

    def initialize_ui(self):
        self.clear_ui()

        self.label = tk.Label(self.main_frame, text="Choose DD Task", bg='gray20', fg='white', font=("Sans", 14))
        self.label.pack(pady=10)

        self.file_to_disk_button = tk.Button(self.main_frame, text="File to Disk", command=self.file_to_disk, width=25, font=self.font)
        self.file_to_disk_button.pack(pady=10)

        self.disk_to_disk_button = tk.Button(self.main_frame, text="Disk to Disk", command=self.disk_to_disk, width=25, font=self.font)
        self.disk_to_disk_button.pack(pady=10)

        # Do not explicitly set window size to use system default
        self.root.geometry("")

    def clear_ui(self):
        for widget in self.main_frame.winfo_children():
            widget.destroy()

    def choose_file(self):
        return filedialog.askopenfilename(title="Select File", filetypes=[("Disk Images", "*.img *.iso"), ("All Files", "*.*")])

    def choose_disk(self, prompt, preselect=None, on_done=None):
        try:
            # Get all disk devices (no partitions) - works with any drive type
            disk_details = subprocess.check_output(["lsblk", "-d", "-n", "-o", "NAME,SIZE"]).decode().strip().split("\n")
            disk_choices = [
                f"/dev/{line.split()[0]} ({line.split()[1]})" for line in disk_details
                if line.strip()
            ]

            def on_select():
                selection = disk_listbox.curselection()
                if selection:
                    selected = disk_listbox.get(selection[0]).split()[0]  # Extract the device name only
                    if on_done:
                        on_done(selected)

            self.clear_ui()
            tk.Label(self.main_frame, text=prompt, bg='gray20', fg='white', font=self.disk_selection_font).pack(pady=10)

            disk_listbox = tk.Listbox(self.main_frame, selectmode=tk.SINGLE, bg='white', font=self.disk_selection_font)
            disk_listbox.pack(fill='both', expand=True)

            for disk in disk_choices:
                disk_listbox.insert(tk.END, disk)

            if preselect:
                try:
                    index = disk_choices.index(f"{preselect} (SIZE)")
                    disk_listbox.select_set(index)
                    disk_listbox.see(index)
                except ValueError:
                    pass

            ok_button = tk.Button(self.main_frame, text="OK", command=on_select, font=self.font)
            ok_button.pack(pady=10)

        except subprocess.CalledProcessError as e:
            messagebox.showerror("Error", f"Failed to list disks: {e}")

    def file_to_disk(self):
        self.selected_file = self.choose_file()
        if not self.selected_file:
            self.initialize_ui()
            return

        self.total_size = os.path.getsize(self.selected_file)
        self.choose_disk("Choose disk to write to:", on_done=self.set_destination_disk)

    def disk_to_disk(self):
        self.choose_disk("Choose disk to read from (source):", on_done=self.set_source_disk)

    def set_source_disk(self, source):
        if source:
            self.selected_source_disk = source
            # Determine total size of source disk
            try:
                self.total_size = int(subprocess.check_output(["sudo", "blockdev", "--getsize64", source]).strip())
            except subprocess.CalledProcessError as e:
                messagebox.showerror("Error", f"Failed to get size of source disk: {e}")
                self.initialize_ui()
                return
            self.choose_disk("Choose disk to write to (destination):", on_done=self.set_destination_disk)

    def set_destination_disk(self, destination):
        if destination:
            self.selected_destination_disk = destination
            self.show_confirmation()

    def show_confirmation(self):
        self.clear_ui()

        if self.selected_file:  # File to Disk
            confirmation_message = (
                f"Source File: {os.path.basename(self.selected_file)}\n"
                f"Destination Disk: {self.selected_destination_disk}\n"
                "Do you want to proceed with this operation?"
            )
        else:  # Disk to Disk
            confirmation_message = (
                f"Source Disk: {self.selected_source_disk}\n"
                f"Destination Disk: {self.selected_destination_disk}\n"
                "Do you want to proceed with this operation?"
            )

        tk.Label(self.main_frame, text=confirmation_message, bg='gray20', fg='white', font=("Sans", 14)).pack(pady=10)

        # "Cancel" and "Continue" buttons with positions switched
        cancel_button = tk.Button(self.main_frame, text="Cancel", command=self.initialize_ui, font=self.font, bg='gray80', fg='black')
        cancel_button.pack(side='left', padx=10, pady=10)

        continue_button = tk.Button(self.main_frame, text="Continue", command=self.show_progress, font=self.font)
        continue_button.pack(side='right', padx=10, pady=10)

    def show_progress(self):
        self.clear_ui()

        # Update the task message based on the operation type
        if self.selected_file:
            self.task_message = f"Flashing {os.path.basename(self.selected_file)} to {self.selected_destination_disk}"
        else:
            self.task_message = f"Cloning {self.selected_source_disk} to {self.selected_destination_disk}"

        # Display the current DD task message
        self.task_label = tk.Label(self.main_frame, text=self.task_message, bg='gray20', fg='white', font=("Sans", 14))
        self.task_label.pack(pady=10)

        # Progress bar and info
        style = ttk.Style()
        style.configure('fancy.Horizontal.TProgressbar',
                        troughcolor='gray20',
                        background='#afff59',  # grey
                        thickness=10)  # Thinner progress bar

        self.progress_bar = ttk.Progressbar(self.main_frame, length=280, mode='determinate', style='fancy.Horizontal.TProgressbar')
        self.progress_bar.pack(pady=10, fill='x')  # Fill the width of the container

        self.progress_info = tk.Label(self.main_frame, text="Copied: 0 MB, 0% Done", bg='gray20', fg='white', font=("Sans", 14))
        self.progress_info.pack(pady=10)

        # Frame for centering the cancel button
        button_frame = tk.Frame(self.main_frame, bg='gray20')
        button_frame.pack(pady=10)

        # Cancel button with standardized color, spanning the width of the progress bar
        self.cancel_button = tk.Button(button_frame, text="Cancel", command=self.cancel_dd, font=self.font, bg='gray80', fg='black')
        self.cancel_button.pack(fill='x', padx=10)

        # Start the dd process in a separate thread
        threading.Thread(target=self.execute_dd).start()

    def update_progress(self, line):
        # Extracting data from dd output
        match = re.search(r'(\d+) bytes', line)
        if match:
            copied_bytes = int(match.group(1))
            copied_mb = copied_bytes / (1024 * 1024)
            if self.total_size > 0:
                progress_percentage = min((copied_bytes / self.total_size) * 100, 100)
                # Format copied MB to an integer with leading zeros
                copied_mb_formatted = f"{int(copied_mb):04d}"
                self.root.after(0, self.progress_bar.config, {'value': progress_percentage})
                self.root.after(0, self.progress_info.config, {'text': f"Copied: {copied_mb_formatted} MB, {progress_percentage:.0f}% Done"})

    def execute_dd(self):
        if self.selected_file and self.selected_destination_disk:
            src = self.selected_file
            dest = self.selected_destination_disk
        elif self.selected_source_disk and self.selected_destination_disk:
            src = self.selected_source_disk
            dest = self.selected_destination_disk
        else:
            return

        try:
            self.process = subprocess.Popen(
                ["sudo", "dd", f"if={src}", f"of={dest}", "bs=4M", "conv=fdatasync", "status=progress"],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            while True:
                line = self.process.stderr.readline()
                if not line:
                    break
                self.root.after(0, self.update_progress, line.strip())
            self.process.wait()
            self.root.after(0, self.show_completion_message)
        except subprocess.CalledProcessError as e:
            self.root.after(0, messagebox.showerror, "Error", f"DD operation failed: {e}")
        finally:
            self.process = None

    def cancel_dd(self):
        if self.process:
            self.process.send_signal(signal.SIGINT)  # Send SIGINT to stop the process
            self.process = None
        self.root.after(0, self.initialize_ui)

    def show_completion_message(self):
        self.clear_ui()
        self.completion_label = tk.Label(self.main_frame, text="DD operation completed successfully.", bg='gray20', fg='white', font=("Sans", 14))
        self.completion_label.pack(pady=10)

        # "Exit" and "New DD" buttons
        self.exit_button = tk.Button(self.main_frame, text="Exit", command=self.root.quit, font=self.font)
        self.exit_button.pack(side='left', padx=10, pady=10)

        self.new_dd_button = tk.Button(self.main_frame, text="New DD", command=self.initialize_ui, font=self.font)
        self.new_dd_button.pack(side='left', padx=10, pady=10)

def main():
    root = tk.Tk()
    app = DDUtilityApp(root)
    root.mainloop()

if __name__ == "__main__":
    main()

EOF

sudo mv dd.png /usr/share/pixmaps/dd.png
sudo cp /tmp/mini-dd-gui.py /bin/.dd-gui.py
echo '#!/bin/bash' > /tmp/dd-gui
echo "sudo python3 /bin/.dd-gui.py" >> /tmp/dd-gui
sudo mv /tmp/dd-gui /bin/dd-gui
sudo chmod +x /bin/dd-gui /bin/.dd-gui.py

# Desktop launcher entry
cat > /tmp/dd-gui.desktop << 'DESKTOP_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=DD GUI
GenericName=Disk Imaging Utility
Comment=DD Gui for flashing images and cloning disks
Exec=/bin/dd-gui
Icon=/usr/share/pixmaps/dd.png
Terminal=false
Categories=System;Utility;
StartupNotify=true
DESKTOP_EOF

sudo mv /tmp/dd-gui.desktop /usr/share/applications/dd-gui.desktop
sudo chmod 644 /usr/share/applications/dd-gui.desktop

if command -v update-desktop-database >/dev/null 2>&1; then
    sudo update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
fi

echo "> installed: /bin/dd-gui, /bin/.dd-gui.py, /usr/share/pixmaps/dd.png, /usr/share/applications/dd-gui.desktop"
