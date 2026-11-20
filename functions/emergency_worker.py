"""Render Background Worker: durable Firestore-backed emergency timer.

Render worker start command: python emergency_worker.py
"""
import time
import logging
from main import process_overdue_pending_alerts

logging.basicConfig(level=logging.INFO)
POLL_SECONDS = 3

if __name__ == "__main__":
    logging.info("Guardian Alert emergency timer worker started")
    while True:
        try:
            count = process_overdue_pending_alerts()
            if count:
                logging.info("Escalated %s overdue alert(s)", count)
        except Exception:
            logging.exception("Emergency timer polling failed")
        time.sleep(POLL_SECONDS)
