#!/usr/bin/env python3
"""Send pipeline report emails with proper HTML MIME rendering."""

from __future__ import annotations

import os
import smtplib
import ssl
import sys
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from pathlib import Path


def read_required(path: str) -> str:
    file_path = Path(path)
    if not file_path.is_file():
        raise FileNotFoundError(f"Required file not found: {path}")
    return file_path.read_text(encoding="utf-8").strip()


def read_optional(path: str | None) -> str | None:
    if not path:
        return None
    file_path = Path(path)
    if not file_path.is_file():
        return None
    return file_path.read_text(encoding="utf-8")


def main() -> int:
    try:
        subject = read_required(os.environ["EMAIL_SUBJECT_FILE"])
        html_body = read_required(os.environ["EMAIL_HTML_FILE"])
        plain_body = read_optional(os.environ.get("EMAIL_PLAIN_FILE"))

        smtp_server = os.environ["SMTP_SERVER"]
        smtp_port = int(os.environ.get("SMTP_PORT", "587"))
        smtp_from = os.environ["SMTP_FROM"]
        smtp_to = os.environ["SMTP_TO"]
        smtp_password = os.environ["SMTP_PASSWORD"]
        smtp_username = os.environ.get("SMTP_USERNAME", smtp_from)

        message = MIMEMultipart("alternative")
        message["Subject"] = subject
        message["From"] = smtp_from
        message["To"] = smtp_to

        if plain_body:
            message.attach(MIMEText(plain_body, "plain", "utf-8"))
        else:
            message.attach(
                MIMEText(
                    "Your database pipeline report is available in HTML format. "
                    "Please use an HTML-capable email client to view it.",
                    "plain",
                    "utf-8",
                )
            )

        message.attach(MIMEText(html_body, "html", "utf-8"))

        context = ssl.create_default_context()
        with smtplib.SMTP(smtp_server, smtp_port, timeout=30) as server:
            server.ehlo()
            server.starttls(context=context)
            server.ehlo()
            server.login(smtp_username, smtp_password)
            server.sendmail(smtp_from, [smtp_to], message.as_string())

        print(f"Email sent to {smtp_to}")
        return 0
    except Exception as error:  # noqa: BLE001 - surface CI failure clearly
        print(f"Failed to send email: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
