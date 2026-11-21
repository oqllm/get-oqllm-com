"""Polish streaming ASR. Each turn ends with a text WebSocket message 'end'."""
import json
import sys
from pathlib import Path
from threading import BoundedSemaphore

import numpy as np
import sherpa_onnx
from websockets.exceptions import ConnectionClosed
from websockets.sync.server import serve


def make_recognizer(root):
    return sherpa_onnx.OnlineRecognizer.from_transducer(
        tokens=str(root / "tokens.txt"),
        encoder=str(root / "encoder.int8.onnx"),
        decoder=str(root / "decoder.int8.onnx"),
        joiner=str(root / "joiner.int8.onnx"),
        num_threads=2,
    )


def connection_handler(recognizer):
    slot = BoundedSemaphore(1)

    def handle(ws):
        if ws.request.path != "/v1/listen":
            return ws.close(1008, "Use /v1/listen")
        if not slot.acquire(blocking=False):
            return ws.close(1013, "Another utterance is active")
        try:
            stream = recognizer.create_stream()
            stream.set_option("language", "pl")
            samples_seen = 0
            previous = ""
            while True:
                frame = ws.recv(timeout=20)
                final = frame == "end" if isinstance(frame, str) else False
                if final:
                    stream.accept_waveform(16000, np.zeros(16000, dtype=np.float32))
                    stream.input_finished()
                elif isinstance(frame, bytes) and frame and len(frame) % 2 == 0:
                    samples_seen += len(frame) // 2
                    if samples_seen > 16000 * 120:
                        return ws.close(1009, "Maximum utterance length is 120 seconds")
                    samples = np.frombuffer(frame, dtype="<i2").astype(np.float32) / 32768
                    stream.accept_waveform(16000, samples)
                else:
                    return ws.close(1003, "Send PCM S16LE mono 16000 Hz, then text end")
                while recognizer.is_ready(stream):
                    recognizer.decode_stream(stream)
                text = recognizer.get_result(stream).strip()
                if text != previous or final:
                    ws.send(json.dumps({"type": "final" if final else "partial", "text": text}, ensure_ascii=False))
                    previous = text
                if final:
                    return
        except TimeoutError:
            ws.close(1008, "Audio timeout")
        except ConnectionClosed:
            pass
        finally:
            slot.release()

    return handle


if __name__ == "__main__":
    model = make_recognizer(Path(sys.argv[1]))
    with serve(connection_handler(model), "127.0.0.1", 11438, origins=[None],
               max_size=64000, max_queue=4, compression=None) as server:
        server.serve_forever()
