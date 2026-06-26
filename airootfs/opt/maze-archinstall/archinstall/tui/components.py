import sys
from abc import ABC, abstractmethod
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, replace
from typing import Any, ClassVar, Literal, TypeVar, cast, override

from rich.text import Text
from textual import work
from textual.app import App, ComposeResult
from textual.binding import Binding, BindingsMap
from textual.containers import Center, Horizontal, ScrollableContainer, Vertical
from textual.events import Key
from textual.geometry import Offset
from textual.screen import Screen
from textual.validation import Validator
from textual.widgets import Button, DataTable, Footer, Input, Label, LoadingIndicator, OptionList, Rule, SelectionList
from textual.widgets._data_table import RowKey
from textual.widgets.option_list import Option
from textual.widgets.selection_list import Selection
from textual.worker import WorkerCancelled

from archinstall.lib.log import debug
from archinstall.lib.translationhandler import tr
from archinstall.tui.menu_item import MenuItem, MenuItemGroup, MsgLevelType, PreviewResult
from archinstall.tui.result import Result, ResultType

ValueT = TypeVar('ValueT')


def _update_preview(widget: Label, result: str | PreviewResult | None) -> None:
	if result is None:
		widget.update('')
		return

	if isinstance(result, str):
		widget.update(result)
	else:
		text = Text()
		for i, (message, level) in enumerate(result.messages):
			if i > 0:
				text.append('\n\n')
			text.append(message, style=level.style())
		widget.update(text)


def _translate_bindings(source: BindingsMap | None, target: BindingsMap) -> None:
	"""Translate binding descriptions from source to target.

	Uses source (original, immutable class-level cache) to avoid
	double-translation on repeated calls (e.g. language switch).
	"""
	if source is None:
		return
	for key, bindings in source.key_to_bindings.items():
		target.key_to_bindings[key] = [replace(b, description=tr(b.description)) if b.description else b for b in bindings]


class BaseScreen(Screen[Result[ValueT]]):
	BINDINGS: ClassVar = [
		Binding('escape', 'cancel_operation', 'Cancel', show=True),
		Binding('ctrl+c', 'reset_operation', 'Reset', show=True),
	]

	def __init__(self, allow_skip: bool = False, allow_reset: bool = False):
		super().__init__()
		self._allow_skip = allow_skip
		self._allow_reset = allow_reset

	def action_cancel_operation(self) -> None:
		if self._allow_skip:
			_ = self.dismiss(Result(ResultType.Skip))

	async def action_reset_operation(self) -> None:
		if self._allow_reset:
			_ = self.dismiss(Result(ResultType.Reset))


class LoadingScreen(BaseScreen[ValueT]):
	CSS = """
	LoadingScreen {
		align: center middle;
		background: #1e1e1e;
	}

	.content-container {
		width: 1fr;
		height: 1fr;
		max-height: 100%;

		margin-top: 2;
		margin-bottom: 2;

		background: #1e1e1e;
	}

	LoadingIndicator {
		align: center middle;
	}
	"""

	def __init__(
		self,
		timer: int = 3,
		data_callback: Callable[[], Any] | None = None,
		header: str | None = None,
	):
		super().__init__()
		self._timer = timer
		self._header = header
		self._data_callback = data_callback

	async def run(self) -> Result[ValueT]:
		assert TApp.app
		return await TApp.app.show(self)

	@override
	def compose(self) -> ComposeResult:
		with Vertical(classes='content-container'):
			if self._header:
				with Center():
					yield Label(self._header, classes='header', id='loading_header')

			yield Center(LoadingIndicator())

		yield Footer()

	def on_mount(self) -> None:
		_translate_bindings(self._merged_bindings, self._bindings)
		if self._data_callback:
			self._exec_callback()
		else:
			self.set_timer(self._timer, self.action_pop_screen)

		self._set_cursor()

	def _set_cursor(self) -> None:
		label = self.query_one(Label)
		self.app.cursor_position = Offset(label.region.x, label.region.y)
		self.app.refresh()

	@work(thread=True)
	def _exec_callback(self) -> None:
		assert self._data_callback
		result = self._data_callback()
		# cannot call self.dismiss directly from
		# background thread (thread=true) as there's no event loop
		self.app.call_from_thread(self.dismiss, Result(ResultType.Selection, _data=result))

	def action_pop_screen(self) -> None:
		_ = self.dismiss()


class _OptionList(OptionList):
	BINDINGS: ClassVar = [
		Binding('down', 'cursor_down', 'Down', show=True),
		Binding('up', 'cursor_up', 'Up', show=True),
		Binding('j', 'cursor_down', 'Down', show=False),
		Binding('k', 'cursor_up', 'Up', show=False),
	]

	@override
	def on_mount(self) -> None:
		_translate_bindings(self._merged_bindings, self._bindings)


class OptionListScreen(BaseScreen[ValueT]):
	"""
	Single selection menu list
	"""

	BINDINGS: ClassVar = [
		Binding('/', 'search', 'Search', show=True),
	]

	CSS = """
	OptionListScreen {
		align-horizontal: center;
		align-vertical: middle;
		background: #1e1e1e;
	}

	/* Maze Linux: height:auto lets the whole block (guide + list + details)
	   be vertically centred by the screen, instead of clinging to the top
	   with a large dead zone underneath. */
	.content-container {
		width: 1fr;
		height: auto;
		max-height: 100%;

		margin-top: 1;
		margin-left: 3;
		margin-right: 3;

		background: #1e1e1e;
	}

	.list-container {
		width: auto;
		height: auto;
		max-height: 100%;

		padding-bottom: 2;

		background: #1e1e1e;
	}

	OptionList {
		width: auto;
		height: auto;
		min-width: 44;
		max-height: 100%;

		padding: 1 1;
		border: round #323232;

		background: #1e1e1e;
	}

	OptionList:focus {
		border: round #4a4a4a;
	}

	OptionList > .option-list--option {
		padding: 0 2;
		color: #b4b4b4;
	}

	OptionList > .option-list--option-highlighted {
		background: #3a3a3a;
		color: #ffffff;
		text-style: bold;
	}

	/* ---- Right-hand "Details" information panel ---- */
	.preview-pane {
		width: 1fr;
		height: auto;
		min-height: 100%;
		padding: 1 0 0 2;
		background: #1e1e1e;
	}

	.preview-pane .preview-header {
		text-align: left;
		color: #6a6a6a;
		text-style: bold;
		padding: 0 0 1 2;
		background: #1e1e1e;
	}

	.wrap-preview {
		width: 100%;
		height: auto;
	}
	"""

	def __init__(
		self,
		group: MenuItemGroup,
		header: str | None = None,
		title: str | None = None,
		allow_skip: bool = False,
		allow_reset: bool = False,
		preview_location: Literal['right', 'bottom'] | None = None,
		enable_filter: bool = False,
		wrap_preview: bool = False,
	):
		super().__init__(allow_skip, allow_reset)
		self._group = group
		self._header = header
		self._title = title
		self._preview_location = preview_location
		self._filter = enable_filter
		self._wrap_preview = wrap_preview
		# Maze Linux: render the list inside a rounded "card" frame (see CSS).
		self._show_frame = True

		self._options = self._get_options()

	def action_search(self) -> None:
		if self.query_one(OptionList).has_focus:
			if self._filter:
				self._handle_search_action()

	@override
	def action_cancel_operation(self) -> None:
		if self._filter and self.query_one(Input).has_focus:
			self._handle_search_action()
		else:
			super().action_cancel_operation()

	def _handle_search_action(self) -> None:
		search_input = self.query_one(Input)

		if search_input.has_focus:
			self.query_one(OptionList).focus()
		else:
			search_input.focus()

	async def run(self) -> Result[ValueT]:
		assert TApp.app
		return await TApp.app.show(self)

	def _get_options(self) -> list[Option]:
		options = []
		# Maze Linux: honour the group's `checkmarks` flag by prefixing each row
		# with a status glyph so the menu doubles as a configuration checklist:
		#   ✓  this step already has a value      (green-free, bright white)
		#   ●  required step still needs a value  (dim, draws the eye)
		#      everything else is blank-padded so the labels stay aligned.
		show_marks = getattr(self._group, '_checkmarks', False)

		for item in self._group.get_enabled_items():
			disabled = True if item.read_only else False
			label = self._format_label(item) if show_marks else item.text
			options.append(Option(label, id=item.get_id(), disabled=disabled))

		return options

	def _format_label(self, item: MenuItem) -> Text:
		text = Text()
		if item.read_only:
			text.append('  ')
			text.append(item.text, style='#707070')
			return text

		# Special action rows (Install / Save / Abort) use the '__config__' key
		# prefix. Give the primary "Install" action an accent arrow so it stands
		# out as the call-to-action; the others stay quietly aligned.
		item_id = item.get_id()
		if item_id.startswith('__config__'):
			if item_id.endswith('_install'):
				text.append('▸ ', style='#ffffff')
				text.append(item.text, style='#ffffff')
			else:
				text.append('  ')
				text.append(item.text, style='#8a8a8a')
			return text

		if item.has_value():
			text.append('✓ ', style='#e0e0e0')
		elif item.mandatory:
			text.append('● ', style='#8a8a8a')
		else:
			text.append('  ')

		text.append(item.text)
		return text

	@override
	def compose(self) -> ComposeResult:
		if self._title:
			yield Label(self._title, classes='app-header')

		with Vertical(classes='content-container'):
			if self._header:
				yield Label(self._header, classes='header-text', id='header_text')

			option_list = _OptionList(id='option_list_widget')

			if not self._show_frame:
				option_list.classes = 'no-border'

			if self._preview_location is None:
				with Center():
					with Vertical(classes='list-container'):
						yield option_list
			else:
				Container = Horizontal if self._preview_location == 'right' else Vertical
				rule_orientation: Literal['horizontal', 'vertical'] = 'vertical' if self._preview_location == 'right' else 'horizontal'

				with Container():
					yield option_list
					yield Rule(orientation=rule_orientation)
					preview_label = Label('', id='preview_content', markup=False)
					if self._wrap_preview:
						preview_label.add_class('wrap-preview')
					# Maze Linux: give the preview its own titled "Details" pane so it
					# reads as an information panel rather than text floating in space.
					with Vertical(classes='preview-pane'):
						yield Label(tr('Details'), classes='preview-header')
						yield ScrollableContainer(preview_label)

		if self._filter:
			yield Input(placeholder='/filter', id='filter-input')

		yield Footer()

	def on_mount(self) -> None:
		_translate_bindings(self._merged_bindings, self._bindings)
		self._update_options(self._options)
		self.query_one(OptionList).focus()

	def on_input_changed(self, event: Input.Changed) -> None:
		search_term = event.value.lower()
		self._group.set_filter_pattern(search_term)
		filtered_options = self._get_options()
		self._update_options(filtered_options)

	def _update_options(self, options: list[Option]) -> None:
		option_list = self.query_one(OptionList)
		option_list.clear_options()
		option_list.add_options(options)

		option_list.highlighted = self._group.get_focused_index()

		if focus_item := self._group.focus_item:
			self._set_preview(focus_item.get_id())

	def on_input_submitted(self, event: Input.Submitted) -> None:
		if self.query_one(Input).has_focus:
			self._handle_search_action()

	def on_option_list_option_selected(self, event: OptionList.OptionSelected) -> None:
		selected_option = event.option
		if selected_option.id is not None:
			item = self._group.find_by_id(selected_option.id)
			_ = self.dismiss(Result(ResultType.Selection, _item=item))

	def on_option_list_option_highlighted(self, event: OptionList.OptionHighlighted) -> None:
		if event.option.id:
			self._set_preview(event.option.id)

		self._set_cursor()

	def _set_cursor(self) -> None:
		option_list = self.query_one(OptionList)
		index = option_list.highlighted

		if index is None:
			return

		target_y = sum(
			[
				1 if self._show_frame else 0,  # add top buffer for the frame
				option_list.region.y,  # padding/margin offset of the option list
				index,  # index of the highlighted option
				-option_list.scroll_offset.y,  # scroll offset
			]
		)

		self.app.cursor_position = Offset(option_list.region.x, target_y)
		self.app.refresh()

	def _set_preview(self, item_id: str) -> None:
		if self._preview_location is None:
			return

		preview_widget = self.query_one('#preview_content', Label)
		item = self._group.find_by_id(item_id)

		if item.preview_action is not None:
			_update_preview(preview_widget, item.preview_action(item))
		else:
			_update_preview(preview_widget, None)


class _SelectionList(SelectionList[ValueT]):
	BINDINGS: ClassVar = [
		Binding('down', 'cursor_down', 'Down', show=True),
		Binding('up', 'cursor_up', 'Up', show=True),
		Binding('j', 'cursor_down', 'Down', show=False),
		Binding('k', 'cursor_up', 'Up', show=False),
		Binding('space', 'select', 'Toggle', show=True),
	]

	@override
	def on_mount(self) -> None:
		_translate_bindings(self._merged_bindings, self._bindings)


class SelectListScreen(BaseScreen[ValueT]):
	"""
	Multi selection menu
	"""

	BINDINGS: ClassVar = [
		Binding('/', 'search', 'Search', show=True),
		Binding('enter', '', 'Confirm', show=True),
	]

	CSS = """
	SelectListScreen {
		align-horizontal: center;
		align-vertical: middle;
		background: #1e1e1e;
	}

	.content-container {
		width: 1fr;
		height: 1fr;
		max-height: 100%;

		margin-top: 1;
		margin-left: 2;
		margin-right: 2;

		background: #1e1e1e;
	}

	.list-container {
		width: auto;
		height: auto;
		min-width: 42;
		max-height: 1fr;

		padding-bottom: 2;

		background: #1e1e1e;
	}

	SelectionList {
		width: auto;
		height: auto;
		min-width: 42;
		max-height: 1fr;

		padding: 0 1;
		border: round #323232;

		background: #1e1e1e;
	}

	SelectionList:focus {
		border: round #3a3a3a;
	}

	SelectionList > .option-list--option {
		padding: 0 1;
		color: #b4b4b4;
	}

	SelectionList > .option-list--option-highlighted {
		background: #3a3a3a;
		color: #ffffff;
		text-style: bold;
	}

	.wrap-preview {
		width: 100%;
		height: auto;
	}
	"""

	def __init__(
		self,
		group: MenuItemGroup,
		header: str | None = None,
		allow_skip: bool = False,
		allow_reset: bool = False,
		preview_location: Literal['right', 'bottom'] | None = None,
		enable_filter: bool = False,
		wrap_preview: bool = False,
	):
		super().__init__(allow_skip, allow_reset)
		self._group = group
		self._header = header
		self._preview_location = preview_location
		# Maze Linux: render the list inside a rounded "card" frame (see CSS).
		self._show_frame = True
		self._filter = enable_filter
		self._wrap_preview = wrap_preview

		self._selected_items: list[MenuItem] = self._group.selected_items
		self._options: list[Selection[MenuItem]] = self._get_selections()

	def action_search(self) -> None:
		if self.query_one(OptionList).has_focus:
			if self._filter:
				self._handle_search_action()

	@override
	def action_cancel_operation(self) -> None:
		if self._filter and self.query_one(Input).has_focus:
			self._handle_search_action()
		else:
			super().action_cancel_operation()

	def _handle_search_action(self) -> None:
		search_input = self.query_one(Input)

		if search_input.has_focus:
			self.query_one(SelectionList).focus()
		else:
			search_input.focus()

	async def run(self) -> Result[ValueT]:
		assert TApp.app
		return await TApp.app.show(self)

	def _get_selections(self) -> list[Selection[MenuItem]]:
		selections = []

		for item in self._group.get_enabled_items():
			is_selected = item in self._selected_items
			selection = Selection(item.text, item, is_selected)
			selections.append(selection)

		return selections

	@override
	def compose(self) -> ComposeResult:
		with Vertical(classes='content-container'):
			if self._header:
				yield Label(self._header, classes='header-text', id='header_text')

			selection_list = _SelectionList[MenuItem](id='select_list_widget')

			if not self._show_frame:
				selection_list.classes = 'no-border'

			if self._preview_location is None:
				with Center():
					with Vertical(classes='list-container'):
						yield selection_list
			else:
				Container = Horizontal if self._preview_location == 'right' else Vertical
				rule_orientation: Literal['horizontal', 'vertical'] = 'vertical' if self._preview_location == 'right' else 'horizontal'

				with Container():
					yield selection_list
					yield Rule(orientation=rule_orientation)
					preview_label = Label('', id='preview_content', markup=False)
					if self._wrap_preview:
						preview_label.add_class('wrap-preview')
					yield ScrollableContainer(preview_label)

		if self._filter:
			yield Input(placeholder='/filter', id='filter-input')

		yield Footer()

	def on_input_submitted(self, event: Input.Submitted) -> None:
		if self.query_one(Input).has_focus:
			self._handle_search_action()

	def on_mount(self) -> None:
		_translate_bindings(self._merged_bindings, self._bindings)
		self._update_options(self._options)
		self.query_one(SelectionList).focus()

	def on_key(self, event: Key) -> None:
		selection_list = self.query_one(SelectionList)

		if not selection_list.has_focus or event.key != 'enter':
			return

		if len(self._selected_items) < 1:
			index = selection_list.highlighted
			if index is not None:
				selection = selection_list.get_option_at_index(index)
				self._selected_items.append(selection.value)

		_ = self.dismiss(Result(ResultType.Selection, _item=self._selected_items))

	def on_input_changed(self, event: Input.Changed) -> None:
		search_term = event.value.lower()
		self._group.set_filter_pattern(search_term)
		filtered_options = self._get_selections()
		self._update_options(filtered_options)

	def _update_options(self, options: list[Selection[MenuItem]]) -> None:
		selection_list = self.query_one(SelectionList)
		selection_list.clear_options()
		selection_list.add_options(options)

		selection_list.highlighted = self._group.get_focused_index()

		if focus_item := self._group.focus_item:
			self._set_preview(focus_item)

		self._set_cursor()

	def on_selection_list_selection_highlighted(self, event: SelectionList.SelectionHighlighted[MenuItem]) -> None:
		if self._preview_location is not None:
			item: MenuItem = event.selection.value
			self._set_preview(item)

		self._set_cursor()

	def _set_cursor(self) -> None:
		selection_list = self.query_one(SelectionList)
		index = selection_list.highlighted

		if index is None:
			return

		target_y = sum(
			[
				1 if self._show_frame else 0,  # add top buffer for the frame
				selection_list.region.y,  # padding/margin offset of the option list
				index,  # index of the highlighted option
				-selection_list.scroll_offset.y,  # scroll offset
			]
		)

		self.app.cursor_position = Offset(selection_list.region.x, target_y)
		self.app.refresh()

	def on_selection_list_selection_toggled(self, event: SelectionList.SelectionToggled[MenuItem]) -> None:
		item: MenuItem = event.selection.value

		if item not in self._selected_items:
			self._selected_items.append(item)
		else:
			self._selected_items.remove(item)

	def _set_preview(self, item: MenuItem) -> None:
		if self._preview_location is None:
			return

		preview_widget = self.query_one('#preview_content', Label)

		if item.preview_action is not None:
			_update_preview(preview_widget, item.preview_action(item))
		else:
			_update_preview(preview_widget, None)


# DEPRECATED: Removed when switching to async
class ConfirmationScreen(BaseScreen[ValueT]):
	BINDINGS: ClassVar = [
		Binding('l', 'focus_right', 'Focus right', show=False),
		Binding('h', 'focus_left', 'Focus left', show=False),
		Binding('right', 'focus_right', 'Focus right', show=True),
		Binding('left', 'focus_left', 'Focus left', show=True),
	]

	CSS = """
	ConfirmationScreen {
		align: center top;
	}

	.content-container {
		width: 1fr;
		height: 1fr;
		max-height: 100%;

		border: none;
		background: #1e1e1e;
	}

	.buttons-container {
		align: center top;
		height: 3;
		background: #1e1e1e;
	}

	Button {
		min-width: 10;
		width: auto;
		height: 3;
		background: #1e1e1e;
		color: #b4b4b4;
		border: round #323232;
		margin: 0 1;
	}

	Button:focus {
		color: #ffffff;
		text-style: bold;
	}

	Button.-active {
		background: #ffffff;
		color: #1e1e1e;
		border: round #ffffff;
		text-style: bold;
	}
	"""

	def __init__(
		self,
		group: MenuItemGroup,
		header: str,
		allow_skip: bool = False,
		allow_reset: bool = False,
		preview_location: Literal['bottom'] | None = None,
		preview_header: str | None = None,
	):
		super().__init__(allow_skip, allow_reset)
		self._group = group
		self._header = header
		self._preview_location = preview_location
		self._preview_header = preview_header

	async def run(self) -> Result[ValueT]:
		assert TApp.app
		return await TApp.app.show(self)

	@override
	def compose(self) -> ComposeResult:
		yield Label(self._header, classes='header-text', id='header_text')

		if self._preview_location is None:
			with Vertical(classes='content-container'):
				with Horizontal(classes='buttons-container'):
					for item in self._group.items:
						yield Button(item.text, id=item.key)
		else:
			with Vertical():
				with Horizontal(classes='buttons-container'):
					for item in self._group.items:
						yield Button(item.text, id=item.key)

				yield Rule(orientation='horizontal')
				if self._preview_header is not None:
					yield Label(self._preview_header, classes='preview-header', id='preview_header')
				yield ScrollableContainer(Label('', id='preview_content', markup=False))

		yield Footer()

	def on_mount(self) -> None:
		_translate_bindings(self._merged_bindings, self._bindings)
		self._update_selection()

	def action_focus_right(self) -> None:
		if self._is_btn_focus():
			self._group.focus_next()
			self._update_selection()

	def action_focus_left(self) -> None:
		if self._is_btn_focus():
			self._group.focus_prev()
			self._update_selection()

	def _update_selection(self) -> None:
		focused = self._group.focus_item
		buttons = self.query(Button)

		if not focused:
			return

		for button in buttons:
			if button.id == focused.key:
				button.add_class('-active')
				button.focus()

				if self._preview_header is not None:
					preview = self.query_one('#preview_content', Label)
					result = focused.preview_action(focused) if focused.preview_action else None
					_update_preview(preview, result)
			else:
				button.remove_class('-active')

	def _is_btn_focus(self) -> bool:
		buttons = self.query(Button)
		for button in buttons:
			if button.has_focus:
				return True

		return False

	def on_key(self, event: Key) -> None:
		if event.key == 'enter':
			if self._is_btn_focus():
				item = self._group.focus_item
				if not item:
					return
				_ = self.dismiss(Result(ResultType.Selection, _item=item))


class NotifyScreen(ConfirmationScreen[ValueT]):
	def __init__(self, header: str):
		group = MenuItemGroup([MenuItem(tr('Ok'))])
		super().__init__(group, header)


@dataclass
class InputInfo:
	message: str
	msg_level: MsgLevelType


class InputScreen(BaseScreen[str]):
	CSS = """
	InputScreen {
		align: center middle;
	}

	.container-wrapper {
		align: center top;
		width: 100%;
		height: 1fr;
	}

	.input-content {
		width: 60;
		height: 10;
	}

	.input-failure {
		color: white;
		text-style: bold;
		text-align: center;
	}

	#input-info {
		text-align: center;
	}

	.input-hint-msg-error {
		color: white;
		text-style: bold;
	}

	.input-hint-msg-warning {
		color: white;
		text-style: bold;
	}

	.input-hint-msg-info {
		color: white;
	}
	"""

	def __init__(
		self,
		header: str | None = None,
		placeholder: str | None = None,
		password: bool = False,
		default_value: str | None = None,
		allow_reset: bool = False,
		allow_skip: bool = False,
		validator: Validator | None = None,
		info_callback: Callable[[str], InputInfo | None] | None = None,
	):
		super().__init__(allow_skip, allow_reset)
		self._header = header or ''
		self._placeholder = placeholder or ''
		self._password = password
		self._default_value = default_value or ''
		self._allow_reset = allow_reset
		self._allow_skip = allow_skip
		self._validator = validator
		self._info_callback = info_callback

	async def run(self) -> Result[str]:
		assert TApp.app
		return await TApp.app.show(self)

	@override
	def compose(self) -> ComposeResult:
		yield Label(self._header, classes='header-text', id='header_text')

		with Center(classes='container-wrapper'):
			with Vertical(classes='input-content'):
				yield Input(
					placeholder=self._placeholder,
					password=self._password,
					value=self._default_value,
					id='main_input',
					validators=self._validator,
					validate_on=['submitted'],
				)
				yield Label('', classes='input-failure', id='input-failure')
				yield Label('', id='input-info')

		yield Footer()

	def on_mount(self) -> None:
		_translate_bindings(self._merged_bindings, self._bindings)
		input_field = self.query_one('#main_input', Input)
		input_field.focus()

	def on_input_submitted(self, event: Input.Submitted) -> None:
		if event.validation_result and not event.validation_result.is_valid:
			failures = [failure.description for failure in event.validation_result.failures if failure.description]
			failure_out = ', '.join(failures)

			self.query_one('#input-failure', Label).update(failure_out)
		else:
			input_value = event.value

			if not input_value and not self._allow_skip:
				self.query_one('#input-failure', Label).update(tr('Input cannot be empty'))
				return

			_ = self.dismiss(Result(ResultType.Selection, _data=event.value))

	def on_input_changed(self, event: Input.Changed) -> None:
		info_label = self.query_one('#input-info', Label)
		if self._info_callback:
			result = self._info_callback(event.value)
			if result:
				css_class = ''
				if result.msg_level == MsgLevelType.MsgError:
					css_class = 'input-hint-msg-error'
				elif result.msg_level == MsgLevelType.MsgWarning:
					css_class = 'input-hint-msg-warning'
				elif result.msg_level == MsgLevelType.MsgInfo:
					css_class = 'input-hint-msg-info'
				info_label.update(result.message)
				info_label.set_classes(css_class)
			else:
				info_label.update('')
				info_label.set_classes('')


class _DataTable(DataTable[ValueT]):
	BINDINGS: ClassVar = [
		Binding('down', 'cursor_down', 'Down', show=True),
		Binding('up', 'cursor_up', 'Up', show=True),
		Binding('j', 'cursor_down', 'Down', show=False),
		Binding('k', 'cursor_up', 'Up', show=False),
		Binding('space', 'select', 'Toggle', show=True),
		Binding('enter', 'select_cursor', 'Confirm', show=True),
	]

	@override
	def on_mount(self) -> None:
		_translate_bindings(self._merged_bindings, self._bindings)


class TableSelectionScreen(BaseScreen[ValueT]):
	BINDINGS: ClassVar = [
		Binding('space', 'toggle_selection', 'Toggle', show=True),  # expclit handling of space in multi-selection mode
	]

	CSS = """
	TableSelectionScreen {
		align: center top;
		background: #1e1e1e;
	}

	.content-container {
		width: 1fr;
		height: 1fr;
		max-height: 100%;

		margin-top: 2;
		margin-bottom: 2;

		background: #1e1e1e;
	}

	.table-container {
		align: center top;
		width: 1fr;
		height: 1fr;

		background: #1e1e1e;
	}

	.table-container ScrollableContainer {
		align: center top;
		height: auto;

		background: #1e1e1e;
	}

	DataTable {
		width: auto;
		height: auto;

		padding: 0 1;

		border: round #323232;
		background: #1e1e1e;
	}

	DataTable:focus {
		border: round #3a3a3a;
	}

	DataTable .datatable--header {
		background: #1e1e1e;
		border-bottom: solid #323232;
		color: #ffffff;
	}

	LoadingIndicator {
		height: auto;
		padding-top: 2;

		background: #1e1e1e;
	}
	"""

	def __init__(
		self,
		header: str | None = None,
		group: MenuItemGroup | None = None,
		group_callback: Callable[[], Awaitable[MenuItemGroup]] | None = None,
		allow_reset: bool = False,
		allow_skip: bool = False,
		loading_header: str | None = None,
		multi: bool = False,
		preview_location: Literal['bottom'] | None = None,
		preview_header: str | None = None,
	):
		super().__init__(allow_skip, allow_reset)
		self._header = header
		self._group = group
		self._group_callback = group_callback
		self._loading_header = loading_header
		self._multi = multi
		self._preview_location = preview_location
		self._preview_header = preview_header

		self._selected_keys: set[RowKey] = set()
		self._current_row_key: RowKey | None = None

		if self._group is None and self._group_callback is None:
			raise ValueError('Either data or data_callback must be provided')

	async def run(self) -> Result[ValueT]:
		assert TApp.app
		return await TApp.app.show(self)

	@override
	def compose(self) -> ComposeResult:
		if self._header:
			yield Label(self._header, classes='header-text', id='header_text')

		with Vertical(classes='content-container'):
			if self._loading_header:
				with Center():
					yield Label(self._loading_header, classes='header', id='loading_header')

			yield LoadingIndicator(id='loader')

			if self._preview_location is None:
				with Center():
					with Vertical(classes='table-container'):
						yield ScrollableContainer(_DataTable(id='data_table'))

			else:
				with Vertical(classes='table-container'):
					yield ScrollableContainer(_DataTable(id='data_table'))
					yield Rule(orientation='horizontal')
					if self._preview_header is not None:
						yield Label(self._preview_header, classes='preview-header', id='preview-header')
					yield ScrollableContainer(Label('', id='preview_content', markup=False))

		yield Footer()

	def on_mount(self) -> None:
		_translate_bindings(self._merged_bindings, self._bindings)
		self._display_header(True)
		data_table = self.query_one(DataTable)
		data_table.cell_padding = 2

		if self._group:
			self._put_data_to_table(data_table, self._group)
		else:
			self._load_data(data_table)

	@work
	async def _load_data(self, table: DataTable[ValueT]) -> None:
		assert self._group_callback is not None
		group = await self._group_callback()
		self._put_data_to_table(table, group)

	def _display_header(self, is_loading: bool) -> None:
		if self._loading_header:
			loading_header = self.query_one('#loading_header', Label)
			loading_header.display = is_loading

		if self._header:
			header = self.query_one('#header_text', Label)
			header.display = not is_loading

	def _get_column_keys(self, items: list[MenuItem]) -> list[str]:
		all_keys: list[str] = []
		for item in items:
			if item.value:
				all_keys.extend(item.value.table_data().keys())

		# Create unique list while preserving order
		unique_keys: list[str] = list(dict.fromkeys(all_keys))

		if self._multi:
			unique_keys.insert(0, '   ')

		return unique_keys

	def _put_data_to_table(self, table: DataTable[ValueT], group: MenuItemGroup) -> None:
		items = group.items
		selected = group.selected_items

		if not items:
			_ = self.dismiss(Result(ResultType.Selection))
			return

		cols = self._get_column_keys(items)

		table.add_columns(*cols)

		for item in items:
			if not item.value:
				continue

			row_values = list(item.value.table_data().values())

			if self._multi:
				if item in selected:
					row_values.insert(0, '[X]')
				else:
					row_values.insert(0, '[ ]')

			row_key = table.add_row(*row_values, key=item)  # type: ignore[arg-type]
			if item in selected:
				self._selected_keys.add(row_key)

		table.cursor_type = 'row'
		table.display = True

		loader = self.query_one('#loader')
		loader.display = False
		self._display_header(False)
		table.focus()

	def action_toggle_selection(self) -> None:
		if not self._multi:
			return

		if not self._current_row_key:
			return

		table = self.query_one(DataTable)
		cell_key = table.coordinate_to_cell_key(table.cursor_coordinate)

		if self._current_row_key in self._selected_keys:
			self._selected_keys.remove(self._current_row_key)
			table.update_cell(self._current_row_key, cell_key.column_key, '[ ]')
		else:
			self._selected_keys.add(self._current_row_key)
			table.update_cell(self._current_row_key, cell_key.column_key, '[X]')

	def on_data_table_row_highlighted(self, event: DataTable.RowHighlighted) -> None:
		self._set_cursor(event.cursor_row)

		self._current_row_key = event.row_key
		item: MenuItem = event.row_key.value  # type: ignore[assignment]

		if not item.preview_action:
			return

		preview_widget = self.query_one('#preview_content', Label)
		_update_preview(preview_widget, item.preview_action(item))

	def _set_cursor(self, row_index: int) -> None:
		data_table = self.query_one(DataTable)

		target_y = sum(
			[
				data_table.region.y,  # padding/margin offset of the option list
				1,  # table header
				row_index,  # index of the highlighted row
				-data_table.scroll_offset.y,  # scroll offset
			]
		)

		self.app.cursor_position = Offset(data_table.region.x, target_y)
		self.app.refresh()

	def on_data_table_row_selected(self, event: DataTable.RowSelected) -> None:
		if self._multi:
			if len(self._selected_keys) == 0:
				selection = [event.row_key.value]
			else:
				selection = [row_key.value for row_key in self._selected_keys]
		else:
			selection = event.row_key.value  # type: ignore[assignment]

		_ = self.dismiss(
			Result[ValueT](
				ResultType.Selection,
				_item=selection,  # type: ignore[arg-type]
			)
		)


class InstanceRunnable[ValueT](ABC):
	@abstractmethod
	async def run(self) -> ValueT | None:
		pass


class _AppInstance(App[ValueT]):
	ENABLE_COMMAND_PALETTE = False

	BINDINGS: ClassVar = [
		Binding('f1', 'trigger_help', 'Show/Hide help', show=True),
		Binding('ctrl+q', 'quit', 'Quit', show=True, priority=True),
	]

	# ===================================================================
	# Maze Linux "Graphite" theme — modern, single-surface monochrome.
	#
	# Design language: ONE neutral dark-grey surface (#1e1e1e) for the entire
	# UI — no pure black, no second background colour. Depth comes from a tight
	# elevation ladder of greys (recessed slots, hairlines, selection bar), a
	# soft near-white for body text, dimmed greys for secondary text, and a
	# single high-contrast white accent for the active button / checkbox.
	# No coloured accents — the whole UI is greyscale on purpose. Selection is
	# an elevated-grey bar instead of a harsh full-white inversion, and content
	# sits inside rounded "card" frames so it no longer reads as stock
	# archinstall.
	#
	# Palette (low → high elevation):
	#   #1e1e1e  base surface (the single background — everywhere)
	#   #252525  recessed slot (unchecked checkbox well)
	#   #323232  hairlines, card borders, dividers
	#   #3a3a3a  selection bar / highlighted row / input border
	#   #4a4a4a  focused card border
	#   #707070  dimmed / secondary text
	#   #c8c8c8  body text
	#   #e0e0e0  bright text (input, key hints)
	#   #ffffff  accent / active button / focused input border / checkmark
	# ===================================================================
	CSS = """
	Screen {
		background: #1e1e1e;
		color: #c8c8c8;
	}

	* {
		/* Maze Linux: Textual auto-applies `background-tint: $foreground 5%` to
		   OptionList / DataTable / Input / Button, which lightens our flat
		   #1e1e1e surface into a second grey. Kill it everywhere so the whole
		   UI stays one uniform colour. */
		background-tint: #1e1e1e 0%;

		scrollbar-size: 1 1;

		scrollbar-color: #3a3a3a;
		scrollbar-background: #1e1e1e;
		scrollbar-color-hover: #5a5a5a;
		scrollbar-color-active: #ffffff;
	}

	/* ---- Top title bar (Maze branding) ---- */
	.app-header {
		dock: top;
		height: 3;
		width: 100%;
		content-align: center middle;
		background: #1e1e1e;
		color: #ffffff;
		text-style: bold;
		border-bottom: solid #323232;
	}

	.header-text {
		text-align: center;
		width: 100%;
		height: auto;

		padding-top: 1;
		padding-bottom: 2;

		color: #9a9a9a;
		background: #1e1e1e;
	}

	.preview-header {
		text-align: center;
		color: #ffffff;
		text-style: bold;
		width: 100%;

		padding-bottom: 1;

		background: #1e1e1e;
	}

	.no-border {
		border: none;
	}

	/* ---- Dividers between panes ---- */
	Rule {
		color: #323232;
	}

	#preview_content {
		color: #9a9a9a;
		padding: 0 2;
	}

	/* ---- Text input ---- */
	Input {
		border: round #3a3a3a;
		background: #1e1e1e;
		height: 3;
		color: #e0e0e0;
	}

	Input .input--cursor {
		color: #ffffff;
	}

	Input:focus {
		border: round #ffffff;
	}

	/* ---- Footer / status bar ---- */
	Footer {
		dock: bottom;
		width: 100%;
		background: #1e1e1e;
		color: #707070;
		height: 1;
	}

	.footer-key--key {
		background: #1e1e1e;
		color: #e0e0e0;
		text-style: bold;
	}

	.footer-key--description {
		background: #1e1e1e;
		color: #6a6a6a;
		padding-right: 2;
	}

	FooterKey.-command-palette {
		background: #1e1e1e;
		border-left: vkey #323232;
	}

	/* Maze Linux: pure greyscale checkboxes — no green checkmarks or coloured
	   cursors. Checked = bright white mark, the highlighted row reuses the
	   selection bar so it reads consistently with single-select lists. */
	SelectionList > .selection-list--button {
		background: #252525;
		color: #252525;
	}
	SelectionList > .selection-list--button-highlighted {
		background: #ffffff;
		color: #ffffff;
	}
	SelectionList > .selection-list--button-selected {
		background: #252525;
		color: #ffffff;
	}
	SelectionList > .selection-list--button-selected-highlighted {
		background: #ffffff;
		color: #1e1e1e;
	}

	DataTable > .datatable--cursor {
		background: #ffffff;
		color: #1e1e1e;
		text-style: bold;
	}
	DataTable > .datatable--header {
		background: #1e1e1e;
		color: #ffffff;
		text-style: bold;
	}

	LoadingIndicator {
		color: #ffffff;
		background: #1e1e1e;
	}
	"""

	def __init__(self, main: InstanceRunnable[ValueT] | Callable[[], Awaitable[ValueT]]) -> None:
		# Maze Linux: ansi_color=False forces Textual's own true-color rendering so
		# the #1e1e1e surface is rendered exactly as specified instead of being
		# remapped to the host terminal's (Konsole/Breeze) palette. The installer
		# always runs in Konsole (truecolor-capable), so this is safe and gives a
		# uniform single-grey UI.
		super().__init__(ansi_color=False)
		self._main = main

	@override
	async def _on_exit_app(self) -> None:
		from archinstall.lib.translationhandler import translation_handler

		translation_handler.restore_console_font()
		await super()._on_exit_app()

	def action_trigger_help(self) -> None:
		from textual.widgets import HelpPanel

		if self.screen.query('HelpPanel'):
			_ = self.screen.query('HelpPanel').remove()
		else:
			_ = self.screen.mount(HelpPanel())

	def on_mount(self) -> None:
		from archinstall.lib.translationhandler import translation_handler

		translation_handler.apply_console_font()
		_translate_bindings(self._merged_bindings, self._bindings)
		self._run_worker()

	@work
	async def _run_worker(self) -> None:
		try:
			if isinstance(self._main, InstanceRunnable):
				result: ValueT | None = await self._main.run()
			else:
				result = await self._main()

			tui.exit(result)
		except WorkerCancelled:
			debug('Worker was cancelled')
		except Exception as err:
			debug(f'Error while running main app: {err}')
			# this will terminate the textual app and return the exception
			self.exit(cast(ValueT, err))

	@work
	async def _show_async(self, screen: Screen[Result[ValueT]]) -> Result[ValueT]:
		return await self.push_screen_wait(screen)

	async def show(self, screen: Screen[Result[ValueT]]) -> Result[ValueT]:
		return await self._show_async(screen).wait()


class TApp:
	app: _AppInstance[Any] | None = None

	def run(self, main: InstanceRunnable[ValueT] | Callable[[], Awaitable[ValueT]]) -> ValueT:
		from archinstall.lib import log as _log

		TApp.app = _AppInstance(main)
		# Don't echo log lines to the terminal while the full-screen UI is up —
		# it would corrupt the Textual display. Re-enabled as soon as it exits.
		_log.suppress_console = True
		try:
			result: ValueT | Exception | None = TApp.app.run()
		finally:
			_log.suppress_console = False

		if isinstance(result, Exception):
			raise result

		if result is None:
			debug('App returned no result, assuming exit')
			sys.exit(0)

		return result

	def exit(self, result: Any) -> None:
		assert TApp.app
		TApp.app.exit(result)

	def translate_bindings(self) -> None:
		"""Re-translate app-level binding descriptions after language change."""
		if TApp.app is not None:
			_translate_bindings(TApp.app._merged_bindings, TApp.app._bindings)


tui = TApp()
