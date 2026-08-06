import os

from yolo.envfile import LoadEnvFile


def _write(tmp_path, content):
    p = tmp_path / ".env"
    p.write_text(content, encoding="utf-8")
    return str(p)


def test_loads_key_values(tmp_path, monkeypatch):
    path = _write(tmp_path, "TELEGRAM_BOT_TOKEN=abc123\nTELEGRAM_CHAT_ID=42\n")
    monkeypatch.delenv("TELEGRAM_BOT_TOKEN", raising=False)
    monkeypatch.delenv("TELEGRAM_CHAT_ID", raising=False)
    LoadEnvFile(path)
    assert os.environ["TELEGRAM_BOT_TOKEN"] == "abc123"
    assert os.environ["TELEGRAM_CHAT_ID"] == "42"


def test_skips_comments_blanks_and_garbage(tmp_path, monkeypatch):
    # .env.example had stray "[TEMPLATE]" / "q" lines at some point; those
    # and any line without "=" must be ignored, not crash.
    path = _write(tmp_path, "[TEMPLATE]\n# comment\n\nq\nexport A=1\nB=2\n")
    monkeypatch.delenv("A", raising=False)
    monkeypatch.delenv("B", raising=False)
    LoadEnvFile(path)
    assert os.environ["A"] == "1"
    assert os.environ["B"] == "2"
    assert "TEMPLATE" not in os.environ


def test_strips_quotes_and_export_prefix(tmp_path, monkeypatch):
    path = _write(tmp_path, 'T="quoted"\nexport U=unquoted\n')
    monkeypatch.delenv("T", raising=False)
    monkeypatch.delenv("U", raising=False)
    LoadEnvFile(path)
    assert os.environ["T"] == "quoted"
    assert os.environ["U"] == "unquoted"


def test_does_not_override_existing_env(tmp_path, monkeypatch):
    path = _write(tmp_path, "ALREADY_SET=from_file\n")
    monkeypatch.setenv("ALREADY_SET", "from_os")
    LoadEnvFile(path)
    assert os.environ["ALREADY_SET"] == "from_os"


def test_missing_file_is_noop(tmp_path):
    LoadEnvFile(str(tmp_path / "nope.env"))  # must not raise
