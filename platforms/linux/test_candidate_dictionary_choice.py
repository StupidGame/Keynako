"""Candidate right clicks preserve composition and pass the full reading."""

import importlib
from pathlib import Path
import sys
import types
import unittest
from unittest import mock


class CandidateDictionaryChoiceTest(unittest.TestCase):
    def test_right_click_opens_choice_without_committing(self) -> None:
        gi = types.ModuleType("gi")
        gi.require_version = lambda *_: None
        repository = types.ModuleType("gi.repository")
        repository.GLib = types.SimpleNamespace()
        repository.IBus = types.SimpleNamespace(Engine=object, Factory=object)
        with mock.patch.dict(sys.modules, {"gi": gi, "gi.repository": repository}):
            sys.modules.pop("keynako_engine", None)
            module = importlib.import_module("keynako_engine")
        sys.modules.pop("keynako_engine", None)

        class Session:
            def candidates(self) -> list[str]:
                return ["仮面", "仮面ライダー"]

            def candidate_reading(self, index: int) -> str:
                return "かめんらいだー" if index == 1 else "かめん"

        engine = module.KeynakoEngine.__new__(module.KeynakoEngine)
        engine.session = Session()
        engine._selection_revision = 0
        engine._commit = mock.Mock()
        with mock.patch.object(Path, "is_file", return_value=True), mock.patch.object(
            module.subprocess, "Popen"
        ) as launch:
            engine.do_candidate_clicked(1, 3, 0)

        command = launch.call_args.args[0]
        self.assertEqual(command[1:], [
            "--candidate-word", "仮面ライダー",
            "--candidate-reading", "かめんらいだー",
        ])
        engine._commit.assert_not_called()
        self.assertEqual(engine._selection_revision, 0)

        class MenuItem:
            def __init__(self, label: str) -> None:
                self.label = label
                self.callback = None
                self.arguments = ()

            def connect(self, _signal: str, callback: object, *arguments: object) -> None:
                self.callback = callback
                self.arguments = arguments

        class Menu:
            def __init__(self) -> None:
                self.items = []

            def append(self, item: MenuItem) -> None:
                self.items.append(item)

            def connect(self, *_: object) -> None:
                pass

            def show_all(self) -> None:
                pass

            def popup_at_pointer(self, _event: object) -> None:
                pass

        repository.Gtk = types.SimpleNamespace(
            init_check=lambda: (True, []),
            Menu=Menu,
            MenuItem=types.SimpleNamespace(new_with_label=MenuItem),
        )
        with mock.patch.dict(sys.modules, {"gi": gi, "gi.repository": repository}), \
                mock.patch.object(Path, "is_file", return_value=True), \
                mock.patch.object(module.subprocess, "Popen") as launch:
            engine.do_candidate_clicked(1, 3, 0)
            launch.assert_not_called()
            menu = engine._candidate_menu
            self.assertEqual([item.label for item in menu.items], [
                "共通辞書に送る", "個人辞書に登録",
            ])
            personal = menu.items[1]
            personal.callback(personal, *personal.arguments)
        self.assertEqual(launch.call_args.args[0][1:], [
            "--candidate-dictionary-personal", "仮面ライダー", "かめんらいだー",
        ])


if __name__ == "__main__":
    unittest.main()
