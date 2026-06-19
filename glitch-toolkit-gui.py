#!/usr/bin/env python3
"""
gLiTcH-ToolKit GUI - PyQt5 launcher for the gLiTcH-ToolKit repo.
Browse, search, run, copy, and export scripts with a compact dark UI.
"""

import sys
import os
import subprocess
import threading
from pathlib import Path

from PyQt5.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QLineEdit, QListWidget, QListWidgetItem, QLabel, QPushButton,
    QFileDialog, QMessageBox, QStatusBar, QCheckBox, QMenu, QAction,
    QAbstractItemView, QSizePolicy
)
from PyQt5.QtCore import Qt, QSize, pyqtSignal, QObject, QTimer
from PyQt5.QtGui import QIcon, QPixmap, QFont, QPalette, QColor, QKeySequence

# ---------------------------------------------------------------------------
#  Config
# ---------------------------------------------------------------------------
REPO_URL = "https://github.com/GlitchLinux/gLiTcH-ToolKit.git"
REPO_DIR = Path("/tmp/gLiTcH-ToolKit")
ICON_DIR = Path("/tmp/toolkit-icons")
ICON_BASE_URL = "https://glitchlinux.wtf/FILES/toolkit-icons"
ICON_FILES = [
    "txt.png", "terminal-w.png", "sh.png", "py.png", "pf2.png",
    "iso_file.png", "file.png", "exe.png", "cfg.png", "c.png", "bin.png",
]
TERMINAL = None  # auto-detected

# Extension -> icon filename mapping
EXT_ICON_MAP = {
    ".sh":       "sh.png",
    ".py":       "py.png",
    ".txt":      "txt.png",
    ".c":        "c.png",
    ".cfg":      "cfg.png",
    ".conf":     "cfg.png",
    ".bin":      "bin.png",
    ".exe":      "exe.png",
    ".iso":      "iso_file.png",
    ".pf2":      "pf2.png",
    ".deb":      "file.png",
    ".desktop":  "file.png",
}
DEFAULT_ICON = "terminal-w.png"

# Colors
C_BG        = "#0e0e18"
C_BG_ALT    = "#141424"
C_FG        = "#c8c8d4"
C_GREEN     = "#00ff0b"
C_MAGENTA   = "#db00b9"
C_CYAN      = "#00b4d8"
C_BORDER    = "#2a2a3a"
C_SEARCH_BG = "#16162a"
C_SELECT    = "#1e3a1e"
C_SELECT_SUDO = "#3a1e36"
C_HOVER     = "#1a1a30"


# ---------------------------------------------------------------------------
#  Helpers
# ---------------------------------------------------------------------------
def detect_terminal():
    """Find the best available terminal emulator."""
    for term in ["xfce4-terminal", "gnome-terminal", "konsole",
                 "mate-terminal", "lxterminal", "alacritty",
                 "kitty", "xterm"]:
        if subprocess.run(["which", term], capture_output=True).returncode == 0:
            return term
    return "xterm"


def icon_for_file(filename):
    """Return the icon path for a given filename."""
    ext = Path(filename).suffix.lower()
    icon_name = EXT_ICON_MAP.get(ext, DEFAULT_ICON)
    icon_path = ICON_DIR / icon_name
    if icon_path.exists():
        return str(icon_path)
    return None


def ext_label(filename):
    """Short extension tag for display."""
    ext = Path(filename).suffix.lower()
    if ext:
        return ext.lstrip(".")
    return "bin"


# ---------------------------------------------------------------------------
#  Background worker signals
# ---------------------------------------------------------------------------
class WorkerSignals(QObject):
    finished = pyqtSignal(bool, str)  # success, message
    progress = pyqtSignal(str)


# ---------------------------------------------------------------------------
#  Main Window
# ---------------------------------------------------------------------------
class ToolKitWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        global TERMINAL
        TERMINAL = detect_terminal()

        self.tools = []           # list of filenames
        self.sudo_mode = False

        self.setWindowTitle("gLiTcH-ToolKit")
        self.resize(520, 420)
        self.setMinimumSize(340, 260)

        self._build_ui()
        self._apply_theme()
        self._setup_shortcuts()

        # Ensure icons exist, then sync repo
        self._ensure_icons()
        self._sync_repo_bg()

    # ----- UI Build --------------------------------------------------------
    def _build_ui(self):
        central = QWidget()
        self.setCentralWidget(central)
        layout = QVBoxLayout(central)
        layout.setContentsMargins(6, 6, 6, 0)
        layout.setSpacing(4)

        # -- Top bar: search + buttons
        top = QHBoxLayout()
        top.setSpacing(4)

        self.search = QLineEdit()
        self.search.setPlaceholderText("Search or enter number...")
        self.search.setClearButtonEnabled(True)
        self.search.textChanged.connect(self._filter)
        self.search.returnPressed.connect(self._on_enter)
        top.addWidget(self.search, 1)

        self.sudo_btn = QPushButton("USER")
        self.sudo_btn.setFixedWidth(52)
        self.sudo_btn.setCheckable(True)
        self.sudo_btn.setToolTip("Toggle sudo mode  [Ctrl+S]")
        self.sudo_btn.clicked.connect(self._toggle_sudo)
        top.addWidget(self.sudo_btn)

        self.refresh_btn = QPushButton("\u21bb")
        self.refresh_btn.setFixedWidth(28)
        self.refresh_btn.setToolTip("Refresh repo  [Ctrl+R]")
        self.refresh_btn.clicked.connect(self._sync_repo_bg)
        top.addWidget(self.refresh_btn)

        layout.addLayout(top)

        # -- Tool list
        self.tool_list = QListWidget()
        self.tool_list.setIconSize(QSize(20, 20))
        self.tool_list.setSpacing(1)
        self.tool_list.setSelectionMode(QAbstractItemView.SingleSelection)
        self.tool_list.itemDoubleClicked.connect(self._run_selected)
        self.tool_list.setContextMenuPolicy(Qt.CustomContextMenu)
        self.tool_list.customContextMenuRequested.connect(self._context_menu)
        self.tool_list.setVerticalScrollBarPolicy(Qt.ScrollBarAsNeeded)
        self.tool_list.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        layout.addWidget(self.tool_list, 1)

        # -- Status bar
        self.status = QStatusBar()
        self.status.setFixedHeight(20)
        self.setStatusBar(self.status)
        self.status_label = QLabel("Starting...")
        self.status.addWidget(self.status_label, 1)
        self.count_label = QLabel("")
        self.status.addPermanentWidget(self.count_label)

    # ----- Theme -----------------------------------------------------------
    def _apply_theme(self):
        accent = C_GREEN
        sel_bg = C_SELECT
        self._current_accent = accent

        self.setStyleSheet(f"""
            QMainWindow {{
                background: {C_BG};
            }}
            QWidget {{
                background: {C_BG};
                color: {C_FG};
                font-family: "Monospace", "Noto Sans Mono", "DejaVu Sans Mono", monospace;
                font-size: 11px;
            }}
            QLineEdit {{
                background: {C_SEARCH_BG};
                color: {C_FG};
                border: 1px solid {C_BORDER};
                border-radius: 3px;
                padding: 4px 6px;
                font-size: 12px;
                selection-background-color: {accent};
            }}
            QLineEdit:focus {{
                border-color: {accent};
            }}
            QListWidget {{
                background: {C_BG_ALT};
                border: 1px solid {C_BORDER};
                border-radius: 3px;
                outline: none;
            }}
            QListWidget::item {{
                padding: 2px 4px;
                border-radius: 2px;
            }}
            QListWidget::item:selected {{
                background: {sel_bg};
                color: {accent};
            }}
            QListWidget::item:hover:!selected {{
                background: {C_HOVER};
            }}
            QPushButton {{
                background: {C_BORDER};
                color: {C_FG};
                border: 1px solid {C_BORDER};
                border-radius: 3px;
                padding: 3px 6px;
                font-size: 11px;
            }}
            QPushButton:hover {{
                background: {C_HOVER};
                border-color: {accent};
            }}
            QPushButton:checked {{
                background: #2a1030;
                color: {C_MAGENTA};
                border-color: {C_MAGENTA};
            }}
            QStatusBar {{
                background: {C_BG};
                color: #666680;
                font-size: 10px;
            }}
            QStatusBar QLabel {{
                color: #666680;
                font-size: 10px;
            }}
            QMenu {{
                background: {C_BG_ALT};
                color: {C_FG};
                border: 1px solid {C_BORDER};
                padding: 2px;
            }}
            QMenu::item {{
                padding: 4px 20px 4px 8px;
            }}
            QMenu::item:selected {{
                background: {sel_bg};
                color: {accent};
            }}
            QScrollBar:vertical {{
                background: {C_BG_ALT};
                width: 8px;
                border: none;
            }}
            QScrollBar::handle:vertical {{
                background: {C_BORDER};
                border-radius: 4px;
                min-height: 20px;
            }}
            QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {{
                height: 0;
            }}
        """)

    def _update_sudo_theme(self):
        """Swap accent colors for sudo mode."""
        if self.sudo_mode:
            accent = C_MAGENTA
            sel_bg = C_SELECT_SUDO
            self.sudo_btn.setText("ROOT")
        else:
            accent = C_GREEN
            sel_bg = C_SELECT
            self.sudo_btn.setText("USER")

        self._current_accent = accent

        # Targeted updates - only restyle what changes
        self.search.setStyleSheet(f"""
            QLineEdit {{
                background: {C_SEARCH_BG};
                color: {C_FG};
                border: 1px solid {C_BORDER};
                border-radius: 3px;
                padding: 4px 6px;
                font-size: 12px;
                selection-background-color: {accent};
            }}
            QLineEdit:focus {{
                border-color: {accent};
            }}
        """)
        self.tool_list.setStyleSheet(f"""
            QListWidget {{
                background: {C_BG_ALT};
                border: 1px solid {C_BORDER};
                border-radius: 3px;
                outline: none;
            }}
            QListWidget::item {{
                padding: 2px 4px;
                border-radius: 2px;
            }}
            QListWidget::item:selected {{
                background: {sel_bg};
                color: {accent};
            }}
            QListWidget::item:hover:!selected {{
                background: {C_HOVER};
            }}
        """)
        self._update_status()

    # ----- Shortcuts -------------------------------------------------------
    def _setup_shortcuts(self):
        # Ctrl+S = toggle sudo
        self.sudo_shortcut = self.search.addAction(QIcon(), QLineEdit.LeadingPosition) if False else None
        # Use QAction-based shortcuts instead
        act_sudo = QAction(self)
        act_sudo.setShortcut(QKeySequence("Ctrl+S"))
        act_sudo.triggered.connect(self._toggle_sudo)
        self.addAction(act_sudo)

        act_refresh = QAction(self)
        act_refresh.setShortcut(QKeySequence("Ctrl+R"))
        act_refresh.triggered.connect(self._sync_repo_bg)
        self.addAction(act_refresh)

        act_copy = QAction(self)
        act_copy.setShortcut(QKeySequence("Ctrl+E"))
        act_copy.triggered.connect(self._export_selected)
        self.addAction(act_copy)

        act_fullscreen = QAction(self)
        act_fullscreen.setShortcut(QKeySequence("F11"))
        act_fullscreen.triggered.connect(self._toggle_fullscreen)
        self.addAction(act_fullscreen)

        act_focus = QAction(self)
        act_focus.setShortcut(QKeySequence("Escape"))
        act_focus.triggered.connect(self._escape_handler)
        self.addAction(act_focus)

    # ----- Icon download ---------------------------------------------------
    def _ensure_icons(self):
        ICON_DIR.mkdir(parents=True, exist_ok=True)
        missing = [f for f in ICON_FILES if not (ICON_DIR / f).exists()]
        if missing:
            def dl():
                for f in missing:
                    url = f"{ICON_BASE_URL}/{f}"
                    try:
                        subprocess.run(
                            ["wget", "-q", "-O", str(ICON_DIR / f), url],
                            timeout=10, capture_output=True
                        )
                    except Exception:
                        pass
            threading.Thread(target=dl, daemon=True).start()

    # ----- Repo sync -------------------------------------------------------
    def _sync_repo_bg(self):
        self.status_label.setText("Syncing repo...")
        self.refresh_btn.setEnabled(False)

        def worker():
            try:
                if (REPO_DIR / ".git").is_dir():
                    r = subprocess.run(
                        ["git", "-C", str(REPO_DIR), "pull", "--quiet", "--ff-only"],
                        capture_output=True, timeout=30
                    )
                    if r.returncode != 0:
                        subprocess.run(["rm", "-rf", str(REPO_DIR)], capture_output=True)
                        subprocess.run(
                            ["git", "clone", "--quiet", REPO_URL, str(REPO_DIR)],
                            capture_output=True, timeout=60
                        )
                else:
                    subprocess.run(["rm", "-rf", str(REPO_DIR)], capture_output=True)
                    subprocess.run(
                        ["git", "clone", "--quiet", REPO_URL, str(REPO_DIR)],
                        capture_output=True, timeout=60
                    )
                # Signal UI update on main thread
                QTimer.singleShot(0, self._load_tools)
            except Exception as e:
                QTimer.singleShot(0, lambda: self._sync_done(False, str(e)))

        threading.Thread(target=worker, daemon=True).start()

    def _sync_done(self, ok, msg=""):
        self.refresh_btn.setEnabled(True)
        if not ok:
            self.status_label.setText(f"Sync failed: {msg}")

    def _load_tools(self):
        """Scan repo dir and populate tool list."""
        self.refresh_btn.setEnabled(True)
        if not REPO_DIR.is_dir():
            self.status_label.setText("Repo not found")
            return

        self.tools = sorted(
            [f.name for f in REPO_DIR.iterdir()
             if f.is_file() and not f.name.startswith(".")
             and ".git" not in str(f)],
            key=lambda x: x.lower()
        )
        self._filter()
        self._update_status()
        self.status_label.setText("Ready")
        self.search.setFocus()

    # ----- Filtering -------------------------------------------------------
    def _filter(self):
        query = self.search.text().strip().lower()
        self.tool_list.clear()

        for idx, name in enumerate(self.tools, 1):
            if query:
                # Match by number or substring
                if query.isdigit():
                    if str(idx) != query and query not in name.lower():
                        continue
                elif query not in name.lower():
                    continue

            item = QListWidgetItem()
            # Number prefix + name
            display = f" {idx:>3}.  {name}"
            item.setText(display)
            item.setData(Qt.UserRole, name)         # store real filename
            item.setData(Qt.UserRole + 1, idx)      # store original index

            # Icon
            icon_path = icon_for_file(name)
            if icon_path:
                item.setIcon(QIcon(icon_path))

            self.tool_list.addItem(item)

        # Auto-select first result
        if self.tool_list.count() > 0:
            self.tool_list.setCurrentRow(0)

        self._update_count()

    def _update_count(self):
        shown = self.tool_list.count()
        total = len(self.tools)
        self.count_label.setText(f"{shown}/{total}")

    def _update_status(self):
        mode = "ROOT" if self.sudo_mode else "USER"
        self.status_label.setText(f"[{mode}]  {TERMINAL}")

    # ----- Actions ---------------------------------------------------------
    def _on_enter(self):
        """Enter pressed in search - run the top match."""
        if self.tool_list.count() > 0:
            # Use currently selected row, or first if none selected
            current = self.tool_list.currentItem()
            if current is None:
                current = self.tool_list.item(0)
            self._run_item(current)

    def _run_selected(self, item):
        self._run_item(item)

    def _run_item(self, item):
        if item is None:
            return
        name = item.data(Qt.UserRole)
        script_path = REPO_DIR / name
        if not script_path.exists():
            return

        self.status_label.setText(f"Running: {name}")

        # Build the command
        cmd_parts = []
        if self.sudo_mode:
            cmd_parts.append("sudo")

        if os.access(str(script_path), os.X_OK):
            cmd_parts.append(str(script_path))
        else:
            cmd_parts.append("bash")
            cmd_parts.append(str(script_path))

        # Wrap in a shell that pauses after execution
        shell_cmd = " ".join(cmd_parts)
        wrapped = f'{shell_cmd}; echo ""; echo -e "\\033[0;36mPress Enter to close...\\033[0m"; read'

        # Launch in detected terminal
        try:
            if TERMINAL == "xfce4-terminal":
                subprocess.Popen([TERMINAL, "--hold", "-e", f"bash -c '{wrapped}'"])
            elif TERMINAL == "gnome-terminal":
                subprocess.Popen([TERMINAL, "--", "bash", "-c", wrapped])
            elif TERMINAL == "konsole":
                subprocess.Popen([TERMINAL, "--hold", "-e", "bash", "-c", wrapped])
            elif TERMINAL in ("alacritty", "kitty"):
                subprocess.Popen([TERMINAL, "-e", "bash", "-c", wrapped])
            else:
                subprocess.Popen([TERMINAL, "-e", f"bash -c '{wrapped}'"])
        except Exception as e:
            QMessageBox.warning(self, "Error", f"Failed to launch:\n{e}")

    def _toggle_sudo(self):
        self.sudo_mode = not self.sudo_mode
        self.sudo_btn.setChecked(self.sudo_mode)
        self._update_sudo_theme()

    def _toggle_fullscreen(self):
        if self.isFullScreen():
            self.showNormal()
        else:
            self.showFullScreen()

    def _escape_handler(self):
        if self.isFullScreen():
            self.showNormal()
        elif self.search.text():
            self.search.clear()
        self.search.setFocus()

    # ----- Context menu ----------------------------------------------------
    def _context_menu(self, pos):
        item = self.tool_list.itemAt(pos)
        if not item:
            return

        name = item.data(Qt.UserRole)
        menu = QMenu(self)

        act_run = menu.addAction(f"Run  -  {name}")
        act_run.triggered.connect(lambda: self._run_item(item))

        act_sudo_run = menu.addAction("Run as Root")
        def run_as_root():
            was_sudo = self.sudo_mode
            self.sudo_mode = True
            self._run_item(item)
            self.sudo_mode = was_sudo
        act_sudo_run.triggered.connect(run_as_root)

        menu.addSeparator()

        act_export = menu.addAction("Export / Copy to...  [Ctrl+E]")
        act_export.triggered.connect(lambda: self._export_item(name))

        act_view = menu.addAction("View source")
        act_view.triggered.connect(lambda: self._view_source(name))

        menu.exec_(self.tool_list.mapToGlobal(pos))

    # ----- Export / Copy ---------------------------------------------------
    def _export_selected(self):
        item = self.tool_list.currentItem()
        if item:
            self._export_item(item.data(Qt.UserRole))

    def _export_item(self, name):
        src = REPO_DIR / name
        if not src.exists():
            return

        dest, _ = QFileDialog.getSaveFileName(
            self, f"Export: {name}", str(Path.home() / name),
            "All Files (*)"
        )
        if not dest:
            return

        try:
            import shutil
            shutil.copy2(str(src), dest)
            # Ask about making executable
            reply = QMessageBox.question(
                self, "Make executable?",
                f"Make {Path(dest).name} executable?",
                QMessageBox.Yes | QMessageBox.No, QMessageBox.Yes
            )
            if reply == QMessageBox.Yes:
                os.chmod(dest, 0o755)
            self.status_label.setText(f"Exported: {dest}")
        except Exception as e:
            QMessageBox.warning(self, "Export failed", str(e))

    # ----- View source -----------------------------------------------------
    def _view_source(self, name):
        script_path = REPO_DIR / name
        if not script_path.exists():
            return
        try:
            if TERMINAL == "xfce4-terminal":
                subprocess.Popen([
                    TERMINAL, "-e",
                    f"bash -c 'less \"{script_path}\"; read'"
                ])
            else:
                subprocess.Popen([
                    TERMINAL, "-e",
                    f"bash -c 'less \"{script_path}\"; read'"
                ])
        except Exception as e:
            QMessageBox.warning(self, "Error", str(e))

    # ----- Key handling on list --------------------------------------------
    def keyPressEvent(self, event):
        # Forward typing to search bar if list has focus
        if (self.tool_list.hasFocus()
                and event.text()
                and event.text().isprintable()
                and not event.modifiers() & (Qt.ControlModifier | Qt.AltModifier)):
            self.search.setFocus()
            self.search.setText(self.search.text() + event.text())
            return
        super().keyPressEvent(event)


# ---------------------------------------------------------------------------
#  Entry
# ---------------------------------------------------------------------------
def main():
    app = QApplication(sys.argv)
    app.setApplicationName("gLiTcH-ToolKit")

    # Force dark palette as fallback
    palette = QPalette()
    palette.setColor(QPalette.Window, QColor(C_BG))
    palette.setColor(QPalette.WindowText, QColor(C_FG))
    palette.setColor(QPalette.Base, QColor(C_BG_ALT))
    palette.setColor(QPalette.Text, QColor(C_FG))
    palette.setColor(QPalette.Button, QColor(C_BORDER))
    palette.setColor(QPalette.ButtonText, QColor(C_FG))
    palette.setColor(QPalette.Highlight, QColor(C_GREEN))
    palette.setColor(QPalette.HighlightedText, QColor("#000000"))
    app.setPalette(palette)

    win = ToolKitWindow()
    win.show()
    sys.exit(app.exec_())


if __name__ == "__main__":
    main()
