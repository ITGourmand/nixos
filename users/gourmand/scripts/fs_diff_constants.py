import json
import logging
import os
import sys
import getpass
from pathlib import Path
from string import Template
from typing import Callable, Iterable, Optional

from PySide6.QtCore import QThread, Signal, Qt
from PySide6.QtGui import (
    QAction, QColor, QIcon, QPainter, QPainterPath, QPixmap,
)
from PySide6.QtWidgets import (
    QApplication, QComboBox, QDialog, QDialogButtonBox, QFormLayout,
    QHBoxLayout, QHeaderView, QLabel, QLineEdit, QMainWindow, QMenu,
    QMessageBox, QProgressBar, QPushButton, QSpinBox, QTabWidget,
    QTreeWidget, QTreeWidgetItem, QVBoxLayout, QWidget,
)

CURRENT_USER = os.getenv("USER") or getpass.getuser()
PRESERVATION_DIR = (
    Path("/persist/etc/nixos/users") / CURRENT_USER / "preservation"
)
FS_DIFF_DIR = PRESERVATION_DIR / "fs-diff"

PERSISTED_JSON = PRESERVATION_DIR / "persisted.json"
NOT_PERSISTED_JSON = PRESERVATION_DIR / "not-persisted.json"
APP_CONFIG_JSON = FS_DIFF_DIR / "config.json"

ALWAYS_IGNORED_DIR_NAMES = {".cache"}
APP_TITLE = "NixOS Persistence Manager"

DEFAULT_MAX_DEPTH = 4
SNOWBALL_MAX_DEPTH = 3

DEFAULT_APP_CONFIG = {
    "max_depth": DEFAULT_MAX_DEPTH,
    "depth_mode": "custom",
    "unlimited_depth": False,
    "theme": "light",
}
SECTION_MAP = {
    "directories.custom": ("directories", "custom"),
    "directories.secure": ("directories", "secure"),
    "files.custom":       ("files",       "custom"),
    "files.secure":       ("files",       "secure"),
}
ROLE_PATH = Qt.UserRole
ROLE_KIND = Qt.UserRole + 1
ROLE_SECTION = Qt.UserRole + 2

NODE_DIRECT = "direct"
NODE_INTERMEDIATE = "intermediate"
NODE_SNOWBALL = "snowball"

TYPE_DIR = "Directory"
TYPE_FILE = "File"

ROLE_PATH = Qt.UserRole + 1
ROLE_KIND = Qt.UserRole + 2
ROLE_SECTION = Qt.UserRole + 3

LABEL_DIRECT = "Direct rule"
LABEL_SNOWBALL = "FS Item"
FALLBACK_STYLE = """
QMainWindow, QWidget {
    background-color: #ffffff;
    color: #000000;
    font-size: 13px;
}
"""
_THEME_QSS_TEMPLATE = Template("""
QMainWindow, QWidget {
    background-color: $win_bg;
    color: $win_fg;
    font-size: 13px;
}
QTabWidget::pane {
    border: 1px solid $pane_border;
    background-color: $pane_bg;
    border-radius: 8px;
}
QTabBar::tab {
    background: $tab_bg;
    color: $tab_fg;
    padding: 8px 18px;
    margin-right: 4px;
    border-top-left-radius: 6px;
    border-top-right-radius: 6px;
    font-weight: 500;
}
QTabBar::tab:selected {
    background: $tab_sel_bg;
    color: $tab_sel_fg;
    font-weight: 600;
    border: 1px solid $tab_sel_border;
    border-bottom: none;
}
QTreeWidget {
    background-color: $tree_bg;
    gridline-color: $tree_grid;
    border: 1px solid $tree_border;
    border-radius: 8px;
    outline: none;
}
QTreeWidget::item {
    padding: 5px;
    border-radius: 4px;
}
QTreeWidget::item:hover {
    background-color: $item_hover_bg;
}
QTreeWidget::item:selected {
    background-color: $item_sel_bg;
    color: $item_sel_fg;
}
QHeaderView::section {
    background-color: $header_bg;
    color: $header_fg;
    padding: 8px;
    border: none;
    font-weight: 600;
}
QLineEdit, QSpinBox, QComboBox {
    background-color: $input_bg;
    border: 1px solid $input_border;
    border-radius: 6px;
    padding: 5px 8px;
    color: $input_fg;
}
QLineEdit:focus, QSpinBox:focus, QComboBox:focus {
    border: 1px solid $focus_border;
}
QPushButton {
    background-color: $btn_bg;
    color: $btn_fg;
    font-weight: 600;
    border-radius: 6px;
    padding: 6px 14px;
    border: 1px solid $btn_border;
}
QPushButton:hover {
    background-color: $btn_hover_bg;
    border-color: $btn_hover_border;
}
QPushButton:pressed {
    background-color: $btn_pressed_bg;
}
QPushButton:disabled {
    background-color: $btn_disabled_bg;
    color: $btn_disabled_fg;
    border-color: $btn_disabled_border;
}
QProgressBar {
    border: 1px solid $progress_border;
    border-radius: 6px;
    text-align: center;
    background-color: $progress_bg;
    height: 14px;
}
QProgressBar::chunk {
    background-color: $progress_chunk;
    border-radius: 5px;
}
QMenu {
    background-color: $menu_bg;
    border: 1px solid $menu_border;
    border-radius: 6px;
    color: $menu_fg;
    padding: 4px;
}
QMenu::item {
    padding: 6px 16px;
    border-radius: 4px;
}
QMenu::item:selected {
    background-color: $menu_sel_bg;
    color: $menu_sel_fg;
}
""")

_LIGHT_PALETTE = {
    "win_bg": "#f8f9fa", "win_fg": "#1f2937",
    "pane_bg": "#ffffff", "pane_border": "#e5e7eb",
    "tab_bg": "#f3f4f6", "tab_fg": "#6b7280",
    "tab_sel_bg": "#ffffff", "tab_sel_fg": "#111827",
    "tab_sel_border": "#e5e7eb",
    "tree_bg": "#ffffff", "tree_grid": "#f3f4f6", "tree_border": "#e5e7eb",
    "item_hover_bg": "#f3f4f6",
    "item_sel_bg": "#e5e7eb", "item_sel_fg": "#111827",
    "header_bg": "#f3f4f6", "header_fg": "#4b5563",
    "input_bg": "#ffffff", "input_border": "#d1d5db", "input_fg": "#111827",
    "focus_border": "#4b5563",
    "btn_bg": "#ffffff", "btn_fg": "#1f2937", "btn_border": "#d1d5db",
    "btn_hover_bg": "#f3f4f6", "btn_hover_border": "#9ca3af",
    "btn_pressed_bg": "#e5e7eb",
    "btn_disabled_bg": "#f3f4f6", "btn_disabled_fg": "#9ca3af",
    "btn_disabled_border": "#e5e7eb",
    "progress_border": "#e5e7eb", "progress_bg": "#f3f4f6",
    "progress_chunk": "#4b5563",
    "menu_bg": "#ffffff", "menu_border": "#e5e7eb", "menu_fg": "#111827",
    "menu_sel_bg": "#f3f4f6", "menu_sel_fg": "#111827",
}

_DARK_PALETTE = {
    "win_bg": "#111827", "win_fg": "#f9fafb",
    "pane_bg": "#1f2937", "pane_border": "#374151",
    "tab_bg": "#111827", "tab_fg": "#9ca3af",
    "tab_sel_bg": "#1f2937", "tab_sel_fg": "#f9fafb",
    "tab_sel_border": "#374151",
    "tree_bg": "#1f2937", "tree_grid": "#374151", "tree_border": "#374151",
    "item_hover_bg": "#374151",
    "item_sel_bg": "#4b5563", "item_sel_fg": "#ffffff",
    "header_bg": "#374151", "header_fg": "#d1d5db",
    "input_bg": "#1f2937", "input_border": "#4b5563", "input_fg": "#f9fafb",
    "focus_border": "#9ca3af",
    "btn_bg": "#374151", "btn_fg": "#f9fafb", "btn_border": "#4b5563",
    "btn_hover_bg": "#4b5563", "btn_hover_border": "#4b5563",
    "btn_pressed_bg": "#6b7280",
    "btn_disabled_bg": "#1f2937", "btn_disabled_fg": "#6b7280",
    "btn_disabled_border": "#374151",
    "progress_border": "#374151", "progress_bg": "#1f2937",
    "progress_chunk": "#6b7280",
    "menu_bg": "#1f2937", "menu_border": "#374151", "menu_fg": "#f9fafb",
    "menu_sel_bg": "#374151", "menu_sel_fg": "#ffffff",
}

INITIAL_THEMES = {
    "light": _THEME_QSS_TEMPLATE.substitute(_LIGHT_PALETTE),
    "dark":  _THEME_QSS_TEMPLATE.substitute(_DARK_PALETTE),
}
