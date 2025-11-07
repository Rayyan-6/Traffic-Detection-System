import base64
import cv2
import numpy as np
from detection import detect_vehicles  # Assumes detection.py in same dir; adjust import if in subdir (e.g., from app.detection)
from fastapi import FastAPI, WebSocket
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    print("WebSocket connected!")  # Debug log

    while True:
        try:
            data = await websocket.receive_text()
            print(f"Received frame data (len: {len(data)})")  # Debug log

            # Decode Base64 → bytes
            img_bytes = base64.b64decode(data)

            # Convert bytes → numpy array
            nparr = np.frombuffer(img_bytes, np.uint8)

            # Decode image
            frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
            if frame is None:
                print("Failed to decode frame—skipping")
                continue

            # Run detection
            small, big, total, boxes = detect_vehicles(frame)

            # Send response with dimensions
            await websocket.send_json({
                "small": small,
                "big": big,
                "total": total,
                "boxes": boxes,
                "frame_width": frame.shape[1],  # Width
                "frame_height": frame.shape[0],  # Height
            })
            print(f"Sent response: small={small}, big={big}, total={total}, boxes={len(boxes)}")  # Debug log

        except Exception as e:
            print(f"WebSocket error: {e}")
            break

    print("WebSocket disconnected")