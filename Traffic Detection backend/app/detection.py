import cv2
import numpy as np
from ultralytics import YOLO

# Load model once
model = YOLO("yolov8n.pt")

# COCO vehicle classes
CLASS_NAMES = {
    2: "car",
    3: "motorcycle",
    5: "bus",
    7: "truck"
}

SMALL_VEHICLES = [2, 3]  # car, motorcycle
BIG_VEHICLES   = [5, 7]  # bus, truck


def detect_vehicles(frame: np.ndarray):
    """
    ✅ Takes OpenCV frame
    ✅ Returns:
       small_count, big_count, total_count, bounding_boxes_list
    """

    results = model(frame, conf=0.5, verbose=False)
    result = results[0]

    boxes = result.boxes
    classes = result.boxes.cls.cpu().numpy() if boxes is not None else []
    confs = result.boxes.conf.cpu().numpy() if boxes is not None else []
    xyxy  = result.boxes.xyxy.cpu().numpy() if boxes is not None else []

    small_count = 0
    big_count = 0
    bounding_boxes = []

    for i, cls in enumerate(classes):
        cls_id = int(cls)
        conf = float(confs[i])
        x1, y1, x2, y2 = map(float, xyxy[i])

        # Count types
        if cls_id in SMALL_VEHICLES:
            small_count += 1
        elif cls_id in BIG_VEHICLES:
            big_count += 1

        # Add bounding box item
        if cls_id in CLASS_NAMES:
            bounding_boxes.append({
                "x1": x1,
                "y1": y1,
                "x2": x2,
                "y2": y2,
                "class_id": cls_id,
                "class_name": CLASS_NAMES[cls_id],
                "confidence": conf
            })

    total = small_count + big_count

    return small_count, big_count, total, bounding_boxes
