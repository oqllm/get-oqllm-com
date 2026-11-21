"""Read raw S16LE mono 16 kHz from stdin and print partial and final transcripts."""
import json
import sys
import threading
from websockets.sync.client import connect
from websockets.exceptions import ConnectionClosed

def main():
    with connect("ws://127.0.0.1:11438/v1/listen", compression=None) as ws:
        def send_audio():
            try:
                while frame := sys.stdin.buffer.read(3200):
                    ws.send(frame)
                ws.send("end")
            except ConnectionClosed:
                pass
        threading.Thread(target=send_audio, daemon=True).start()
        for message in ws:
            result = json.loads(message)
            print(result["type"], result["text"], flush=True)
            if result["type"] == "final":
                return
        raise SystemExit("Connection closed before final transcript")

if __name__ == "__main__":
    main()
