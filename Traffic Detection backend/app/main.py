# from fastapi import FastAPI, WebSocket, UploadFile, File
# import numpy as np
# import cv2
# import base64

# from app.detection import detect_vehicles

# app = FastAPI()

# @app.get("/")
# def home():
#     return {"status": "FastAPI backend is running 🚀"}

# @app.websocket("/ws")
# async def websocket_endpoint(websocket: WebSocket):
#     await websocket.accept()

#     while True:
#         try:
#             data = await websocket.receive_text()

#             # Decode Base64 → bytes
#             img_bytes = base64.b64decode(data)

#             # Convert bytes → numpy array
#             nparr = np.frombuffer(img_bytes, np.uint8)

#             # Decode image
#             frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

#             # Run detection
#             small, big, total, boxes = detect_vehicles(frame)

#             await websocket.send_json({
#                 "small": small,
#                 "big": big,
#                 "total": total,
#                 "boxes": boxes
#             })


#         except Exception as e:
#             print("WebSocket closed:", e)
#             break

# @app.post("/upload")
# async def upload_file(file: UploadFile = File(...)):
#     contents = await file.read()

#     # Convert to numpy image
#     np_img = np.frombuffer(contents, np.uint8)

#     # ✅ This handles BOTH image & video
#     if file.filename.endswith((".jpg", ".jpeg", ".png")):
#         frame = cv2.imdecode(np_img, cv2.IMREAD_COLOR)
#         result = model(frame)[0]

#         return {
#             "total": len(result.boxes),
#             "boxes": result.boxes.xyxy.tolist(),
#             "classes": result.boxes.cls.tolist(),
#         }

#     elif file.filename.endswith((".mp4", ".mov", ".avi")):
#         # ✅ You can implement full video processing later
#         return {"status": "Video received — implement processing next."}

#     return {"error": "Unsupported file type"}

import base64
import cv2
import numpy as np
from ultralytics import YOLO
from fastapi import FastAPI, WebSocket
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()
model = YOLO("yolov8n.pt")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()

    while True:
        data = await websocket.receive_text()

        img_bytes = base64.b64decode(data)
        nparr = np.frombuffer(img_bytes, np.uint8)
        frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

        results = model(frame)[0]

        boxes_list = []
        small = big = total = 0

        for box in results.boxes:
            x1, y1, x2, y2 = box.xyxy[0].tolist()
            cls = int(box.cls)
            conf = float(box.conf)

            if cls in [2, 3]:   # small
                small += 1
                total += 1
            elif cls in [5, 7]: # big
                big += 1
                total += 1

            boxes_list.append({
                "x1": x1,
                "y1": y1,
                "x2": x2,
                "y2": y2,
                "class": model.names[cls],
                "conf": round(conf, 2),
            })

        await websocket.send_json({
            "small": small,
            "big": big,
            "total": total,
            "boxes": boxes_list
        })
