logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("fs_diff_gui")


def load_json(path: Path, fallback):
    if not path.exists():
        return fallback
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as err:
        log.error("Failed to read %s : %s", path, err)
        return fallback


def save_json(path: Path, data) -> bool:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=4, ensure_ascii=False, sort_keys=True)
        return True
    except Exception as err:
        log.error("Failed to write %s : %s", path, err)
        return False


def safe_getsize(full_path: str) -> int:
    try:
        return os.path.getsize(full_path) if os.path.exists(full_path) else 0
    except (PermissionError, FileNotFoundError):
        return 0


class PersistedStore:
    """Adapter around persisted.json ({section: {sub: [paths]}})."""

    def __init__(self, path: Path):
        self.path = path
        loaded = load_json(path, None)
        self.data = loaded if isinstance(loaded, dict) else {
            "directories": {"custom": [], "secure": []},
            "files":       {"custom": [], "secure": []},
        }

    def _bucket(self, section: str, sub: str) -> list:
        return self.data.setdefault(section, {}).setdefault(sub, [])

    def add(self, section: str, sub: str, path_str: str) -> None:
        bucket = self._bucket(section, sub)
        norm_p = os.path.normpath(path_str)
        if norm_p not in bucket:
            bucket.append(norm_p)
            bucket.sort()

    def remove(self, section: str, sub: str, path_str: str) -> bool:
        bucket = self._bucket(section, sub)
        norm_p = os.path.normpath(path_str)
        if norm_p in bucket:
            bucket.remove(norm_p)
            return True
        return False

    def save(self) -> bool:
        for section in self.data.values():
            if isinstance(section, dict):
                for bucket in section.values():
                    if isinstance(bucket, list):
                        bucket.sort()
        return save_json(self.path, self.data)

    def entries(self) -> Iterable[tuple]:
        """Yield (section, sub, is_dir, path_str) for every rule."""
        for section in ("directories", "files"):
            is_dir = section == "directories"
            for sub in ("custom", "secure"):
                for p in self.data.get(section, {}).get(sub, []):
                    yield section, sub, is_dir, os.path.normpath(p)

    def all_paths(self) -> Iterable[str]:
        return (p for _, _, _, p in self.entries())


class IgnoredStore:
    """Adapter around not-persisted.json (flat list of paths)."""

    def __init__(self, path: Path):
        self.path = path
        loaded = load_json(path, [])
        if isinstance(loaded, list):
            self.data: list = sorted([os.path.normpath(p) for p in loaded])
        else:
            self.data = []

    def add(self, path_str: str) -> None:
        norm_p = os.path.normpath(path_str)
        if norm_p not in self.data:
            self.data.append(norm_p)
            self.data.sort()

    def remove(self, path_str: str) -> bool:
        norm_p = os.path.normpath(path_str)
        if norm_p in self.data:
            self.data.remove(norm_p)
            return True
        return False

    def save(self) -> bool:
        self.data.sort()
        return save_json(self.path, self.data)


def collect_managed_paths(
    persisted: PersistedStore, ignored: IgnoredStore
) -> set:
    return {
        os.path.normpath(p)
        for p in (*persisted.all_paths(), *ignored.data)
        if p
    }


def is_path_managed_or_ignored(
    rel_p: str, full_p: str, managed: set
) -> bool:
    if os.path.islink(full_p) or os.path.ismount(full_p):
        return True

    parts = Path(rel_p).parts
    if ALWAYS_IGNORED_DIR_NAMES.intersection(parts):
        return True

    return any(
        str(Path(*parts[:i])) in managed
        for i in range(1, len(parts) + 1)
    )


def is_strict_ancestor(ancestor_rel: str, descendant_rel: str) -> bool:
    ancestor_norm = os.path.normpath(ancestor_rel)
    descendant_norm = os.path.normpath(descendant_rel)
    return descendant_norm.startswith(ancestor_norm + os.sep)


def make_themed_icon(kind: str, color_hex: str) -> QIcon:
    pixmap = QPixmap(20, 20)
    pixmap.fill(Qt.transparent)

    painter = QPainter(pixmap)
    painter.setRenderHint(QPainter.Antialiasing)
    painter.setBrush(QColor(color_hex))
    painter.setPen(Qt.NoPen)

    path = QPainterPath()
    if kind == "dir":
        path.addRoundedRect(1, 5, 18, 12, 2, 2)
        path.addRoundedRect(1, 2, 8, 4, 1.5, 1.5)
    else:
        path.moveTo(3, 1)
        path.lineTo(13, 1)
        path.lineTo(17, 5)
        path.lineTo(17, 18)
        path.lineTo(3, 18)
        path.closeSubpath()

    painter.drawPath(path)
    painter.end()
    return QIcon(pixmap)


def make_tree_item(display: str, label: str, icon: QIcon, kind: str,
                   path_str: Optional[str] = None,
                   section_info: Optional[tuple] = None
                   ) -> QTreeWidgetItem:
    item = QTreeWidgetItem([display, label])
    item.setIcon(0, icon)
    item.setData(0, ROLE_PATH, path_str if path_str is not None else display)
    item.setData(0, ROLE_KIND, kind)
    if section_info is not None:
        item.setData(0, ROLE_SECTION, section_info)
    return item


def filter_tree(tree: QTreeWidget, text: str) -> None:
    needle = text.strip().lower()

    def visit(item: QTreeWidgetItem) -> bool:
        self_match = (
            needle in item.text(0).lower()
            or needle in item.text(1).lower()
        )
        child_visibility = [
            visit(item.child(i)) for i in range(item.childCount())
        ]
        child_match = any(child_visibility)
        visible = (self_match or child_match) if needle else True
        item.setHidden(not visible)
        if child_match and needle:
            item.setExpanded(True)
        return visible

    for i in range(tree.topLevelItemCount()):
        visit(tree.topLevelItem(i))


def populate_snowball(parent: QTreeWidgetItem, full_path: Path,
                      home_dir: Path, dir_icon: QIcon, file_icon: QIcon,
                      depth: int = 0,
                      max_depth: int = SNOWBALL_MAX_DEPTH) -> None:
    if depth >= max_depth or not full_path.exists():
        return
    try:
        entries = sorted(
            full_path.iterdir(), key=lambda p: (not p.is_dir(), p.name)
        )
    except (PermissionError, FileNotFoundError):
        return

    for entry in entries:
        rel_path = str(entry.relative_to(home_dir))
        is_dir = entry.is_dir()
        icon = dir_icon if is_dir else file_icon
        node = make_tree_item(
            entry.name, LABEL_SNOWBALL, icon, NODE_SNOWBALL,
            path_str=rel_path,
        )
        parent.addChild(node)
        if is_dir and not entry.is_symlink():
            populate_snowball(
                node, entry, home_dir, dir_icon, file_icon,
                depth + 1, max_depth,
            )


def build_tree(headers: list, context_handler: Callable) -> QTreeWidget:
    tree = QTreeWidget()
    tree.setHeaderLabels(headers)
    tree.header().setSectionResizeMode(0, QHeaderView.Stretch)
    tree.header().setSectionResizeMode(1, QHeaderView.ResizeToContents)
    tree.setContextMenuPolicy(Qt.CustomContextMenu)
    tree.customContextMenuRequested.connect(context_handler)
    tree.setSelectionMode(QAbstractItemView.ExtendedSelection)
    return tree


def resolve_context_selection(
    tree: QTreeWidget, pos,
) -> list:
    """Return the items a right-click at `pos` should act on.

    If the right-clicked item is already part of the current multi-
    selection, act on the whole selection (standard multi-select
    behaviour). Otherwise, right-clicking selects just that item first,
    matching how most file managers behave.
    """
    item = tree.itemAt(pos)
    if item is None:
        return []
    selected = tree.selectedItems()
    if item in selected and len(selected) > 1:
        return selected
    tree.setCurrentItem(item)
    return [item]


def build_search_input(
    placeholder: str, tree: QTreeWidget, debounce_ms: int = 150
) -> QLineEdit:
    """Search box that filters `tree` after a short pause in typing
    instead of on every keystroke — with hundreds of scanned items,
    filtering on each keystroke visibly lags the UI."""
    field = QLineEdit()
    field.setPlaceholderText(placeholder)

    timer = QTimer(field)
    timer.setSingleShot(True)
    timer.timeout.connect(lambda: filter_tree(tree, field.text()))
    field.textChanged.connect(lambda _t: timer.start(debounce_ms))

    return field


def add_menu_action(menu: QMenu, label: str, callback: Callable) -> None:
    action = QAction(label, menu)
    action.triggered.connect(callback)
    menu.addAction(action)


def find_owning_rule(item: QTreeWidgetItem) -> Optional[QTreeWidgetItem]:
    """Walk up from item to the nearest ancestor that is an actual rule
    (NODE_DIRECT), not the absolute top of the tree.

    A rule can be wrapped in one or more NODE_INTERMEDIATE nodes (e.g. a
    rule on '.config/google-chrome' puts an intermediate '.config' node
    above it) and/or contain several levels of NODE_SNOWBALL filesystem
    children below it. Blindly walking to the tree's absolute root
    overshoots past the rule and lands on an intermediate node with no
    ROLE_SECTION data, which is what caused the 'cannot unpack
    non-iterable NoneType object' crash.
    """
    node = item.parent()
    while node is not None:
        if node.data(0, ROLE_KIND) == NODE_DIRECT:
            return node
        node = node.parent()
    return None


def snapshot_tree_state(tree: QTreeWidget) -> tuple:
    """Capture (all_paths, expanded_paths, selected_path) before a tree is
    cleared and rebuilt, so the caller can restore what the user had open
    and selected afterwards instead of collapsing everything back to
    square one on every refresh."""
    all_paths: set = set()
    expanded: set = set()

    def visit(item: QTreeWidgetItem) -> None:
        path = item.data(0, ROLE_PATH)
        if path:
            all_paths.add(path)
            if item.isExpanded():
                expanded.add(path)
        for i in range(item.childCount()):
            visit(item.child(i))

    for i in range(tree.topLevelItemCount()):
        visit(tree.topLevelItem(i))

    current = tree.currentItem()
    selected_path = current.data(0, ROLE_PATH) if current else None
    return all_paths, expanded, selected_path


def find_item_by_path(
    tree: QTreeWidget, path_str: str
) -> Optional[QTreeWidgetItem]:
    def visit(item: QTreeWidgetItem) -> Optional[QTreeWidgetItem]:
        if item.data(0, ROLE_PATH) == path_str:
            return item
        for i in range(item.childCount()):
            found = visit(item.child(i))
            if found is not None:
                return found
        return None

    for i in range(tree.topLevelItemCount()):
        found = visit(tree.topLevelItem(i))
        if found is not None:
            return found
    return None


def restore_tree_state(
    tree: QTreeWidget, expanded: set, selected_path: Optional[str],
    force_expand: frozenset = frozenset(),
) -> None:
    """Re-open folders that were open before the rebuild (or are brand
    new top-level entries listed in force_expand), then re-select and
    scroll to whatever the user had selected. If the exact item is gone
    (e.g. it was just deleted), fall back to the nearest surviving
    ancestor so the user doesn't lose their place in the tree."""

    def visit(item: QTreeWidgetItem) -> None:
        path = item.data(0, ROLE_PATH)
        if path and (path in expanded or path in force_expand):
            item.setExpanded(True)
        for i in range(item.childCount()):
            visit(item.child(i))

    for i in range(tree.topLevelItemCount()):
        visit(tree.topLevelItem(i))

    if not selected_path:
        return

    parts = Path(selected_path).parts
    for end in range(len(parts), 0, -1):
        candidate = str(Path(*parts[:end]))
        match = find_item_by_path(tree, candidate)
        if match is not None:
            parent = match.parent()
            while parent is not None:
                parent.setExpanded(True)
                parent = parent.parent()
            tree.setCurrentItem(match)
            tree.scrollToItem(match)
            return


class ScannerThread(QThread):
    finished = Signal(list)

    def __init__(self, home_dir: Path, managed: set, max_depth: Optional[int]):
        super().__init__()
        self.home = str(home_dir)
        self.managed = managed
        self.max_depth = max_depth

    @staticmethod
    def _rel(rel_root: str, name: str) -> str:
        return os.path.normpath(
            os.path.join("" if rel_root == "." else rel_root, name)
        )

    def _classify(
        self, root: str, rel_root: str, name: str, type_label: str
    ) -> Optional[tuple]:
        full_p = os.path.join(root, name)
        rel_p = self._rel(rel_root, name)
        try:
            if is_path_managed_or_ignored(rel_p, full_p, self.managed):
                return None
            return (rel_p, type_label, safe_getsize(full_p))
        except (PermissionError, FileNotFoundError):
            return None

    def run(self) -> None:
        log.info(
            "Scan started on %s (max depth: %s)", self.home, self.max_depth
        )
        results: list = []

        for root, dirs, files in os.walk(self.home):
            rel_root = os.path.relpath(root, self.home)
            depth = 0 if rel_root == "." else rel_root.count(os.sep) + 1

            if self.max_depth is not None and depth >= self.max_depth:
                dirs.clear()
                continue

            kept_dirs = []
            for d in dirs:
                item = self._classify(root, rel_root, d, TYPE_DIR)
                if item is not None:
                    results.append(item)
                    kept_dirs.append(d)
            dirs[:] = kept_dirs

            for f in files:
                item = self._classify(root, rel_root, f, TYPE_FILE)
                if item is not None:
                    results.append(item)

        log.info("Scan finished: %d unpersisted item(s) found.", len(results))
        self.finished.emit(results)


class SettingsDialog(QDialog):

    def __init__(self, parent, current_config: dict):
        super().__init__(parent)
        self.setWindowTitle("Application Settings")

        layout = QVBoxLayout(self)
        form = QFormLayout()

        self.depth_mode_combo = QComboBox()
        self.depth_mode_combo.addItems(["Custom", "Unlimited"])
        self.depth_label = QLabel("Max depth:")
        self.depth_spinbox = QSpinBox()
        self.depth_spinbox.setRange(1, 99)

        is_custom = current_config.get("depth_mode", "custom") != "unlimited"
        self.depth_mode_combo.setCurrentText(
            "Custom" if is_custom else "Unlimited"
        )
        self.depth_spinbox.setValue(
            current_config.get("max_depth", DEFAULT_MAX_DEPTH)
        )
        self._set_depth_visible(is_custom)
        self.depth_mode_combo.currentTextChanged.connect(
            lambda t: self._set_depth_visible(t == "Custom")
        )
        form.addRow("Scan depth:", self.depth_mode_combo)
        form.addRow(self.depth_label, self.depth_spinbox)

        self.theme_combo = QComboBox()
        themes = self._available_themes()
        self.theme_combo.addItems(themes)
        current_theme = current_config.get("theme", "light")
        if current_theme in themes:
            self.theme_combo.setCurrentText(current_theme)
        form.addRow("Theme:", self.theme_combo)

        layout.addLayout(form)

        buttons = QDialogButtonBox(
            QDialogButtonBox.Ok | QDialogButtonBox.Cancel,
            Qt.Horizontal, self,
        )
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

        self.adjustSize()

    def _set_depth_visible(self, visible: bool) -> None:
        self.depth_label.setVisible(visible)
        self.depth_spinbox.setVisible(visible)
        self.adjustSize()

    @staticmethod
    def _available_themes() -> list:
        if FS_DIFF_DIR.exists():
            found = sorted(f.stem for f in FS_DIFF_DIR.glob("*.qss"))
            if found:
                return found
        return sorted(INITIAL_THEMES)

    def result_config(self) -> dict:
        unlimited = self.depth_mode_combo.currentText() == "Unlimited"
        return {
            "max_depth": self.depth_spinbox.value(),
            "depth_mode": "unlimited" if unlimited else "custom",
            "unlimited_depth": unlimited,
            "theme": self.theme_combo.currentText(),
        }


class PersistManagerApp(QMainWindow):

    def __init__(self):
        super().__init__()
        log.info("Initialising (%s)", CURRENT_USER)

        self._ensure_theme_files()

        self.app_config = (
            load_json(APP_CONFIG_JSON, None) or dict(DEFAULT_APP_CONFIG)
        )

        title = "FS Diff Persist"
        self.setWindowTitle(f"{title} — {CURRENT_USER}")
        self.resize(980, 680)

        self.home_dir = Path.home()
        self.persisted = PersistedStore(PERSISTED_JSON)
        self.ignored = IgnoredStore(NOT_PERSISTED_JSON)

        self.dir_icon: Optional[QIcon] = None
        self.file_icon: Optional[QIcon] = None
        self._scanner: Optional[ScannerThread] = None

        self._apply_theme(self.app_config.get("theme", "light"))
        self._build_ui()
        self._refresh_everything()

    @staticmethod
    def _ensure_theme_files() -> None:
        try:
            FS_DIFF_DIR.mkdir(parents=True, exist_ok=True)
            for name, content in INITIAL_THEMES.items():
                p = FS_DIFF_DIR / f"{name}.qss"
                if not p.exists():
                    p.write_text(content, encoding="utf-8")
        except Exception as err:
            log.error(
                "Failed to initialise theme files in %s : %s",
                FS_DIFF_DIR, err,
            )

    def _apply_theme(self, theme_name: str) -> None:
        qss_file = FS_DIFF_DIR / f"{theme_name}.qss"
        icon_color = "#f9fafb" if theme_name == "dark" else "#4b5563"
        self.dir_icon = make_themed_icon("dir", icon_color)
        self.file_icon = make_themed_icon("file", icon_color)

        stylesheet = FALLBACK_STYLE
        if qss_file.exists():
            try:
                stylesheet = qss_file.read_text(encoding="utf-8")
                log.info("Theme '%s.qss' loaded.", theme_name)
            except Exception as err:
                log.error("Failed to read %s : %s", qss_file, err)
        self.setStyleSheet(stylesheet)

        if hasattr(self, "persisted_tree"):
            self._reload_all_tabs()

    def _build_ui(self) -> None:
        root = QWidget()
        layout = QVBoxLayout(root)
        layout.setContentsMargins(12, 12, 12, 12)

        self.tabs = QTabWidget()
        self.tabs.addTab(self._build_scan_tab(), "Home Scan")
        self.tabs.addTab(
            self._build_persisted_tab(), "Manage persisted.json"
        )
        self.tabs.addTab(
            self._build_ignored_tab(), "Manage not-persisted.json"
        )
        layout.addWidget(self.tabs)
        self.setCentralWidget(root)

    def _build_scan_tab(self) -> QWidget:
        tab = QWidget()
        layout = QVBoxLayout(tab)

        top = QHBoxLayout()
        self.status_label = QLabel("Analysing filesystem...")
        self.refresh_btn = QPushButton("Refresh (Scan)")
        self.refresh_btn.clicked.connect(self._refresh_everything)
        self.settings_btn = QPushButton("⚙")
        self.settings_btn.setToolTip("Settings")
        self.settings_btn.setFixedWidth(36)
        self.settings_btn.clicked.connect(self._open_settings)
        top.addWidget(self.status_label)
        top.addStretch()
        top.addWidget(self.refresh_btn)
        top.addWidget(self.settings_btn)
        layout.addLayout(top)

        self.scan_tree = build_tree(
            ["Files / Directories", "Type"],
            self._show_scan_context_menu,
        )
        self.scan_search = build_search_input(
            "Search in $HOME...", self.scan_tree,
        )
        layout.addWidget(self.scan_search)
        layout.addWidget(self.scan_tree)

        self.progress_bar = QProgressBar()
        self.progress_bar.setRange(0, 0)
        layout.addWidget(self.progress_bar)
        return tab

    def _build_management_tab(
        self, tree_attr: str, search_attr: str, input_attr: str,
        headers: list, search_placeholder: str, input_placeholder: str,
        context_handler: Callable, add_handler: Callable,
        category_combo_attr: Optional[str] = None
    ) -> QWidget:
        tab = QWidget()
        layout = QVBoxLayout(tab)

        tree = build_tree(headers, context_handler)
        search = build_search_input(search_placeholder, tree)
        setattr(self, tree_attr, tree)
        setattr(self, search_attr, search)
        layout.addWidget(search)
        layout.addWidget(tree)

        add_row = QHBoxLayout()
        line = QLineEdit()
        line.setPlaceholderText(input_placeholder)
        setattr(self, input_attr, line)
        add_row.addWidget(line)

        browse_dir_btn = QPushButton("📁")
        browse_dir_btn.setToolTip("Browse for a folder")
        browse_dir_btn.setFixedWidth(36)
        browse_dir_btn.clicked.connect(
            lambda: self._browse_and_fill(line, "dir")
        )
        add_row.addWidget(browse_dir_btn)

        browse_file_btn = QPushButton("📄")
        browse_file_btn.setToolTip("Browse for a file")
        browse_file_btn.setFixedWidth(36)
        browse_file_btn.clicked.connect(
            lambda: self._browse_and_fill(line, "file")
        )
        add_row.addWidget(browse_file_btn)

        if category_combo_attr:
            combo = QComboBox()
            combo.addItems(list(SECTION_MAP.keys()))
            setattr(self, category_combo_attr, combo)
            add_row.addWidget(combo)

        add_btn = QPushButton("Add manually")
        add_btn.clicked.connect(add_handler)
        add_row.addWidget(add_btn)
        layout.addLayout(add_row)
        return tab

    def _build_persisted_tab(self) -> QWidget:
        return self._build_management_tab(
            tree_attr="persisted_tree",
            search_attr="persisted_search",
            input_attr="persisted_input",
            headers=["Path / Nested items", "Category / Status"],
            search_placeholder="Search in persisted.json...",
            input_placeholder="Example: Documents/Projects or .config/myapp",
            context_handler=self._show_persisted_context_menu,
            add_handler=self._add_manual_persisted,
            category_combo_attr="persisted_category",
        )

    def _build_ignored_tab(self) -> QWidget:
        return self._build_management_tab(
            tree_attr="ignored_tree",
            search_attr="ignored_search",
            input_attr="ignored_input",
            headers=["Path / Nested items", "Status"],
            search_placeholder="Search in not-persisted.json...",
            input_placeholder="Example: Downloads/temp.iso or .cache",
            context_handler=self._show_ignored_context_menu,
            add_handler=self._add_manual_ignored,
        )

    def _reload_all_tabs(self) -> None:
        self._reload_persisted_tab()
        self._reload_ignored_tab()

    def _reload_persisted_tab(self) -> None:
        rules = [
            (path_str, is_dir, f"{section}.{sub}", (section, sub))
            for section, sub, is_dir, path_str in self.persisted.entries()
        ]
        self._build_rule_tree(
            self.persisted_tree, self.persisted_search, rules
        )

    def _reload_ignored_tab(self) -> None:
        rules = [
            (path_str, True, LABEL_DIRECT, None)
            for path_str in self.ignored.data
        ]
        self._build_rule_tree(self.ignored_tree, self.ignored_search, rules)

    def _build_rule_tree(
        self, tree: QTreeWidget, search_field: QLineEdit, rules: list,
    ) -> None:
        """Shared builder for the persisted/ignored management trees.

        rules: list of (path_str, is_dir_hint, rule_label, section_info).
        section_info is (section, sub) for persisted rules, or None for
        ignored rules (which don't have a section/sub split).

        Preserves whichever folders were expanded and whatever was
        selected before the rebuild — clear()+rebuild would otherwise
        collapse and deselect everything on every single refresh, which
        happens after every persist/ignore/delete action.
        """
        _, expanded, selected_path = snapshot_tree_state(tree)

        tree.setUpdatesEnabled(False)
        tree.clear()
        nodes: dict = {}

        for path_str, is_dir_hint, rule_label, section_info in rules:
            parts = Path(path_str).parts
            parent = None
            for i, part in enumerate(parts):
                current_rel = str(Path(*parts[:i + 1]))
                is_target_rule = (i == len(parts) - 1)

                if current_rel not in nodes:
                    full_p = self.home_dir / current_rel
                    if full_p.exists():
                        is_d = full_p.is_dir()
                    else:
                        is_d = is_dir_hint if is_target_rule else True

                    icon = self.dir_icon if is_d else self.file_icon

                    if is_target_rule:
                        label, kind = rule_label, NODE_DIRECT
                        sec_info = section_info
                    else:
                        label, kind = "Intermediate path", NODE_INTERMEDIATE
                        sec_info = None

                    node = make_tree_item(
                        part, label, icon, kind,
                        path_str=current_rel, section_info=sec_info,
                    )
                    if parent is None:
                        tree.addTopLevelItem(node)
                    else:
                        parent.addChild(node)
                    nodes[current_rel] = node
                elif is_target_rule:
                    node = nodes[current_rel]
                    node.setText(1, rule_label)
                    node.setData(0, ROLE_KIND, NODE_DIRECT)
                    if section_info is not None:
                        node.setData(0, ROLE_SECTION, section_info)

                parent = nodes[current_rel]

                target_p = self.home_dir / current_rel
                if is_target_rule and target_p.is_dir():
                    populate_snowball(
                        nodes[current_rel], target_p,
                        self.home_dir, self.dir_icon, self.file_icon,
                    )

        restore_tree_state(tree, expanded, selected_path)
        tree.setUpdatesEnabled(True)
        filter_tree(tree, search_field.text())

    def start_scan(self) -> None:
        self.status_label.setText("Scanning $HOME...")
        self.refresh_btn.setEnabled(False)
        self.progress_bar.setVisible(True)

        self._scan_tree_snapshot = snapshot_tree_state(self.scan_tree)
        self.scan_tree.clear()

        max_depth = (
            None
            if self.app_config.get("depth_mode") == "unlimited"
            else self.app_config.get("max_depth", DEFAULT_MAX_DEPTH)
        )
        managed = collect_managed_paths(self.persisted, self.ignored)

        self._scanner = ScannerThread(self.home_dir, managed, max_depth)
        self._scanner.finished.connect(self._on_scan_finished)
        self._scanner.start()

    def _on_scan_finished(self, items: list) -> None:
        self.progress_bar.setVisible(False)
        self.refresh_btn.setEnabled(True)
        self.status_label.setText(
            f"{len(items)} unpersisted item(s) found — "
            "right-click an item to act."
        )

        all_paths_before, expanded, selected_path = getattr(
            self, "_scan_tree_snapshot", (set(), set(), None)
        )

        self.scan_tree.setUpdatesEnabled(False)
        nodes: dict = {}
        new_top_level: set = set()
        for path_str, item_type, _ in items:
            parts = Path(path_str).parts
            parent = None
            for i, part in enumerate(parts):
                current_rel = str(Path(*parts[:i + 1]))
                if current_rel not in nodes:
                    is_leaf = (i == len(parts) - 1)
                    kind = item_type if is_leaf else TYPE_DIR
                    icon = (
                        self.dir_icon if kind == TYPE_DIR else self.file_icon
                    )
                    node = make_tree_item(
                        part, kind, icon, kind, path_str=current_rel,
                    )
                    if parent is None:
                        self.scan_tree.addTopLevelItem(node)
                        if current_rel not in all_paths_before:
                            new_top_level.add(current_rel)
                    else:
                        parent.addChild(node)
                    nodes[current_rel] = node
                parent = nodes[current_rel]

        # Re-open whatever was open before (or is a brand new top-level
        # folder, matching the old "always expand top level" behaviour),
        # and re-select/scroll back to where the user was.
        restore_tree_state(
            self.scan_tree, expanded, selected_path,
            force_expand=frozenset(new_top_level),
        )
        self.scan_tree.setUpdatesEnabled(True)
        filter_tree(self.scan_tree, self.scan_search.text())

    def _open_settings(self) -> None:
        dialog = SettingsDialog(self, self.app_config)
        if dialog.exec():
            self.app_config = dialog.result_config()
            save_json(APP_CONFIG_JSON, self.app_config)
            self._apply_theme(self.app_config.get("theme", "light"))
            self._refresh_everything()

    def _show_scan_context_menu(self, pos) -> None:
        items = resolve_context_selection(self.scan_tree, pos)
        entries = [
            (it.data(0, ROLE_PATH), it.data(0, ROLE_KIND))
            for it in items if it.data(0, ROLE_PATH)
        ]
        if not entries:
            return

        menu = QMenu(self)
        if len(entries) == 1:
            path_str, item_type = entries[0]
            prefix = "directories" if item_type == TYPE_DIR else "files"
            for sub in ("custom", "secure"):
                key = f"{prefix}.{sub}"
                add_menu_action(
                    menu, f"Persist in: {key}",
                    lambda _=False, p=path_str, k=key: (
                        self._persist_path(p, k)
                    ),
                )
            menu.addSeparator()
            add_menu_action(
                menu, "Ignore in: not-persisted.json",
                lambda _=False, p=path_str: self._ignore_path(p),
            )
        else:
            suffix = f" ({len(entries)} items)"
            for sub in ("custom", "secure"):
                add_menu_action(
                    menu, f"Persist selected in: {sub}{suffix}",
                    lambda _=False, s=sub, e=entries: (
                        self._persist_paths(e, s)
                    ),
                )
            menu.addSeparator()
            add_menu_action(
                menu, f"Ignore selected in: not-persisted.json{suffix}",
                lambda _=False, e=entries: self._ignore_paths(e),
            )
        menu.exec(self.scan_tree.mapToGlobal(pos))

    def _persist_paths(self, entries: list, sub: str) -> None:
        """Persist several (path_str, item_type) entries at once under
        the given category ('custom' or 'secure'), each routed to the
        directories/files bucket matching its own type."""
        count = 0
        for path_str, item_type in entries:
            if not self._resolve_nixos_conflicts(path_str, "persisted"):
                continue
            section = "directories" if item_type == TYPE_DIR else "files"
            self.persisted.add(section, sub, path_str)
            count += 1
        if count and self.persisted.save():
            self.statusBar().showMessage(
                f"{count} item(s) persisted ({sub}).", 4000
            )
            self._refresh_everything()

    def _ignore_paths(self, entries: list) -> None:
        """Add several (path_str, item_type) entries to not-persisted.json
        at once."""
        count = 0
        for path_str, _item_type in entries:
            if not self._resolve_nixos_conflicts(path_str, "ignored"):
                continue
            self.ignored.add(path_str)
            count += 1
        if count and self.ignored.save():
            self.statusBar().showMessage(
                f"{count} item(s) added to not-persisted.json.", 4000
            )
            self._refresh_everything()

    def _show_persisted_context_menu(self, pos) -> None:
        self._show_delete_menu(
            self.persisted_tree, pos,
            self._smart_delete_persisted, self._batch_delete_persisted,
        )

    def _show_ignored_context_menu(self, pos) -> None:
        self._show_delete_menu(
            self.ignored_tree, pos,
            self._smart_delete_ignored, self._batch_delete_ignored,
        )

    def _show_delete_menu(
        self, tree: QTreeWidget, pos,
        single_handler: Callable, batch_handler: Callable,
    ) -> None:
        items = resolve_context_selection(tree, pos)
        valid = [
            it for it in items
            if it.data(0, ROLE_PATH)
            and it.data(0, ROLE_KIND) != NODE_INTERMEDIATE
        ]
        if not valid:
            return

        menu = QMenu(self)

        if len(valid) == 1:
            item = valid[0]
            path_str = item.data(0, ROLE_PATH)
            kind = item.data(0, ROLE_KIND)
            if kind == NODE_DIRECT:
                label = f"Delete rule for '{path_str}'"
                confirm_msg = f"Remove the rule for '{path_str}'?"
            else:
                # This node is just a filesystem preview under an
                # ancestor rule (a NODE_SNOWBALL item), not a rule of
                # its own — say so explicitly, since assuming it's a
                # standalone rule is what caused the original crash
                # further down the line.
                owner = find_owning_rule(item)
                owner_path = owner.data(0, ROLE_PATH) if owner else path_str
                label = f"Exclude '{path_str}' from rule '{owner_path}'"
                confirm_msg = (
                    f"'{path_str}' isn't a rule on its own — it's part "
                    f"of the rule on '{owner_path}'.\n\nThis will remove "
                    f"that rule and re-create individual rules for "
                    f"everything else under '{owner_path}', excluding "
                    f"'{path_str}'. Continue?"
                )
            add_menu_action(
                menu, label,
                lambda: self._confirm_and_run(
                    confirm_msg, single_handler, item
                ),
            )
        else:
            label = f"Delete {len(valid)} selected rule(s)"
            confirm_msg = (
                f"Remove {len(valid)} selected item(s)? Any that are "
                f"just filesystem previews under a rule will have that "
                f"rule split into individual entries, excluding them. "
                f"This cannot be undone."
            )
            add_menu_action(
                menu, label,
                lambda: self._confirm_and_run_batch(
                    confirm_msg, batch_handler, valid
                ),
            )
        menu.exec(tree.mapToGlobal(pos))

    def _confirm_and_run(
        self, message: str, handler: Callable, item: QTreeWidgetItem
    ) -> None:
        reply = QMessageBox.question(
            self, "Confirm deletion", message,
            QMessageBox.Yes | QMessageBox.No, QMessageBox.No,
        )
        if reply == QMessageBox.Yes:
            handler(item)

    def _confirm_and_run_batch(
        self, message: str, handler: Callable, items: list
    ) -> None:
        reply = QMessageBox.question(
            self, "Confirm deletion", message,
            QMessageBox.Yes | QMessageBox.No, QMessageBox.No,
        )
        if reply == QMessageBox.Yes:
            handler(items)

    def _batch_delete_persisted(self, items: list) -> None:
        """Delete several persisted-tab selections at once. Direct rules
        are removed outright; snowball previews are grouped by their
        owning rule so each rule is only split into individual entries
        once, excluding every selected item under it together."""
        direct_items = [
            it for it in items if it.data(0, ROLE_KIND) == NODE_DIRECT
        ]
        direct_paths = {it.data(0, ROLE_PATH) for it in direct_items}

        snowball_by_root: dict = {}
        for it in items:
            if it.data(0, ROLE_KIND) != NODE_SNOWBALL:
                continue
            root = find_owning_rule(it)
            if root is None or root.data(0, ROLE_PATH) in direct_paths:
                continue  # whole rule is already being deleted outright
            snowball_by_root.setdefault(root, set()).add(
                it.data(0, ROLE_PATH)
            )

        count = 0
        for it in direct_items:
            section, sub = it.data(0, ROLE_SECTION)
            if self.persisted.remove(section, sub, it.data(0, ROLE_PATH)):
                count += 1

        for root, targets in snowball_by_root.items():
            root_path = root.data(0, ROLE_PATH)
            section, sub = root.data(0, ROLE_SECTION)
            if (self.home_dir / root_path).is_dir():
                self.persisted.remove(section, sub, root_path)
                self._reexpand_persisted_except(root_path, targets, sub)
                count += len(targets)

        self.persisted.save()
        self.statusBar().showMessage(f"{count} rule(s) removed.", 4000)
        self._refresh_everything()

    def _batch_delete_ignored(self, items: list) -> None:
        """Same as _batch_delete_persisted, for the not-persisted.json
        tab (single flat list, no section/sub split)."""
        direct_items = [
            it for it in items if it.data(0, ROLE_KIND) == NODE_DIRECT
        ]
        direct_paths = {it.data(0, ROLE_PATH) for it in direct_items}

        snowball_by_root: dict = {}
        for it in items:
            if it.data(0, ROLE_KIND) != NODE_SNOWBALL:
                continue
            root = find_owning_rule(it)
            if root is None or root.data(0, ROLE_PATH) in direct_paths:
                continue
            snowball_by_root.setdefault(root, set()).add(
                it.data(0, ROLE_PATH)
            )

        count = 0
        for it in direct_items:
            if self.ignored.remove(it.data(0, ROLE_PATH)):
                count += 1

        for root, targets in snowball_by_root.items():
            root_path = root.data(0, ROLE_PATH)
            if (self.home_dir / root_path).is_dir():
                self.ignored.remove(root_path)
                self._reexpand_ignored_except(root_path, targets)
                count += len(targets)

        self.ignored.save()
        self.statusBar().showMessage(f"{count} rule(s) removed.", 4000)
        self._refresh_everything()

    def _resolve_nixos_conflicts(
        self, path_str: str, target_store: str
    ) -> bool:
        """Résolution automatique des conflits (Impermanence)."""
        norm_target = os.path.normpath(path_str)

        if target_store == "persisted":
            for p in self.persisted.all_paths():
                if norm_target == p or is_strict_ancestor(p, norm_target):
                    msg = (
                        f"'{norm_target}' est déjà englobé "
                        f"par la règle persistance '{p}'."
                    )
                    QMessageBox.information(self, "NixOS Rule Notice", msg)
                    return False

            ignored_to_remove = [
                i for i in self.ignored.data
                if (
                    i == norm_target
                    or is_strict_ancestor(i, norm_target)
                    or is_strict_ancestor(norm_target, i)
                )
            ]
            for ig in ignored_to_remove:
                self.ignored.remove(ig)
            if ignored_to_remove:
                self.ignored.save()

            for section, sub, _, p in list(self.persisted.entries()):
                if is_strict_ancestor(norm_target, p):
                    self.persisted.remove(section, sub, p)

        elif target_store == "ignored":
            persisted_to_remove = [
                (section, sub, p)
                for section, sub, _, p in self.persisted.entries()
                if p == norm_target or is_strict_ancestor(norm_target, p)
            ]
            for section, sub, p in persisted_to_remove:
                self.persisted.remove(section, sub, p)
            if persisted_to_remove:
                self.persisted.save()

            ignored_to_remove = [
                i for i in self.ignored.data
                if is_strict_ancestor(norm_target, i)
            ]
            for ig in ignored_to_remove:
                self.ignored.remove(ig)

        return True

    def _persist_path(self, path_str: str, section_key: str) -> None:
        if not self._resolve_nixos_conflicts(path_str, "persisted"):
            return
        section, sub = SECTION_MAP[section_key]
        self.persisted.add(section, sub, path_str)
        if self.persisted.save():
            self.statusBar().showMessage(
                f"Persisted '{path_str}' ({section_key}).", 4000
            )
            self._refresh_everything()

    def _ignore_path(self, path_str: str) -> None:
        if not self._resolve_nixos_conflicts(path_str, "ignored"):
            return
        self.ignored.add(path_str)
        if self.ignored.save():
            self.statusBar().showMessage(
                f"'{path_str}' added to not-persisted.json.", 4000
            )
            self._refresh_everything()

    def _refresh_everything(self) -> None:
        self._reload_all_tabs()
        self.start_scan()

    def _browse_and_fill(self, line_edit: QLineEdit, mode: str) -> None:
        """Open the system file/folder picker and fill line_edit with the
        chosen path, expressed relative to $HOME like every other path
        in this app. mode is 'dir' or 'file' — Qt's native dialog can't
        pick both at once, hence the two separate buttons."""
        if mode == "dir":
            chosen = QFileDialog.getExistingDirectory(
                self, "Choose a folder", str(self.home_dir),
            )
        else:
            chosen, _ = QFileDialog.getOpenFileName(
                self, "Choose a file", str(self.home_dir),
            )
        if not chosen:
            return

        try:
            rel_path = Path(chosen).resolve().relative_to(
                self.home_dir.resolve()
            )
        except ValueError:
            QMessageBox.warning(
                self, "Invalid path",
                f"The chosen path must be inside your home directory "
                f"({self.home_dir}).",
            )
            return
        line_edit.setText(str(rel_path))

    def _add_manual_persisted(self) -> None:
        path_str = self.persisted_input.text().strip()
        if not path_str:
            return
        self._persist_path(path_str, self.persisted_category.currentText())
        self.persisted_input.clear()

    def _add_manual_ignored(self) -> None:
        path_str = self.ignored_input.text().strip()
        if not path_str:
            return
        self._ignore_path(path_str)
        self.ignored_input.clear()

    def _smart_delete_persisted(self, item: QTreeWidgetItem) -> None:
        path_str = item.data(0, ROLE_PATH)
        kind = item.data(0, ROLE_KIND)

        if kind == NODE_DIRECT:
            section, sub = item.data(0, ROLE_SECTION)
            self.persisted.remove(section, sub, path_str)
            message = f"Rule for '{path_str}' removed."
        else:
            root = find_owning_rule(item)
            if root is None:
                log.error(
                    "No owning persisted rule found above '%s'; "
                    "not deleting.", path_str,
                )
                return
            root_path = root.data(0, ROLE_PATH)
            section, sub = root.data(0, ROLE_SECTION)
            message = f"'{path_str}' excluded from '{root_path}'."
            if (self.home_dir / root_path).is_dir():
                self.persisted.remove(section, sub, root_path)
                self._reexpand_persisted_except(
                    root_path, {path_str}, sub
                )

        self.persisted.save()
        self.statusBar().showMessage(message, 4000)
        self._refresh_everything()

    def _smart_delete_ignored(self, item: QTreeWidgetItem) -> None:
        path_str = item.data(0, ROLE_PATH)
        kind = item.data(0, ROLE_KIND)

        if kind == NODE_DIRECT:
            self.ignored.remove(path_str)
            message = f"Rule for '{path_str}' removed."
        else:
            root = find_owning_rule(item)
            if root is None:
                log.error(
                    "No owning ignored rule found above '%s'; "
                    "not deleting.", path_str,
                )
                return
            root_path = root.data(0, ROLE_PATH)
            message = f"'{path_str}' excluded from '{root_path}'."
            if (self.home_dir / root_path).is_dir():
                self.ignored.remove(root_path)
                self._reexpand_ignored_except(root_path, {path_str})

        self.ignored.save()
        self.statusBar().showMessage(message, 4000)
        self._refresh_everything()

    def _reexpand_except(
        self, root_rel: str, target_rels: set, add_child: Callable,
    ) -> None:
        """Walk everything under root_rel except target_rels, re-adding
        each sibling as its own individual rule via
        add_child(child_rel, is_dir). Shared by the persisted and ignored
        'exclude one-or-more items from a directory rule' flows.
        target_rels can hold several paths at once so that excluding
        multiple items from the same rule (multi-select delete) is done
        in a single pass instead of re-expanding once per item."""
        root_full = self.home_dir / root_rel
        if not root_full.is_dir():
            return
        try:
            children = list(root_full.iterdir())
        except (PermissionError, FileNotFoundError):
            return
        for child in children:
            child_rel = str(child.relative_to(self.home_dir))
            if child_rel in target_rels:
                continue
            nested = {
                t for t in target_rels if is_strict_ancestor(child_rel, t)
            }
            if nested:
                self._reexpand_except(child_rel, nested, add_child)
                continue
            add_child(child_rel, child.is_dir())

    def _reexpand_persisted_except(
        self, root_rel: str, target_rels: set, sub: str
    ) -> None:
        def add_child(child_rel: str, is_dir: bool) -> None:
            section = "directories" if is_dir else "files"
            self.persisted.add(section, sub, child_rel)

        self._reexpand_except(root_rel, target_rels, add_child)

    def _reexpand_ignored_except(
        self, root_rel: str, target_rels: set
    ) -> None:
        self._reexpand_except(
            root_rel, target_rels,
            lambda child_rel, _is_dir: self.ignored.add(child_rel),
        )


if __name__ == "__main__":
    app = QApplication(sys.argv)
    window = PersistManagerApp()
    window.show()
    sys.exit(app.exec())