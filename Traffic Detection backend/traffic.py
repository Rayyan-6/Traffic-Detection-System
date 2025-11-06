# Traffic Vehicle Detection System using YOLOv8 and OpenCV

import cv2
from ultralytics import YOLO

# ---------------------------
# ✅ Set paths here
# ---------------------------
INPUT_VIDEO = "images/traffic3.mp4"         # put your video file here
OUTPUT_VIDEO = None     # set None if you don't want to save
DISPLAY_SCALE = 0.5                    # 0.5 = 50% smaller window
# ---------------------------

# Vehicle classes from COCO dataset
SMALL_VEHICLES = [2, 3]  # car, motorcycle
BIG_VEHICLES = [5, 7]    # bus, truck


def main():
    # Load YOLOv8 nano model
    model = YOLO('yolov8n.pt')

    # Open input video
    cap = cv2.VideoCapture(INPUT_VIDEO)
    if not cap.isOpened():
        print(f"Error: Could not open video {INPUT_VIDEO}")
        return

    # Get video properties
    fps = int(cap.get(cv2.CAP_PROP_FPS))
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

    # Output video writer
    out = None
    if OUTPUT_VIDEO:
        fourcc = cv2.VideoWriter_fourcc(*'mp4v')
        out = cv2.VideoWriter(OUTPUT_VIDEO, fourcc, fps, (width, height))

    print(f"Processing video: {INPUT_VIDEO}")
    print("Press 'q' to quit.")

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        # Run YOLO inference
        results = model(frame, conf=0.5, verbose=False)
        result = results[0]

        boxes = result.boxes
        classes = result.boxes.cls.cpu().numpy() if boxes is not None else []

        small_count = 0
        big_count = 0
        total_count = 0

        # Count vehicle types
        for cls in classes:
            cls_id = int(cls)
            if cls_id in SMALL_VEHICLES:
                small_count += 1
            elif cls_id in BIG_VEHICLES:
                big_count += 1
            if cls_id in SMALL_VEHICLES or cls_id in BIG_VEHICLES:
                total_count += 1

        # Draw detections
        annotated = result.plot()

        # Add text
        cv2.putText(annotated, f"Total Vehicles: {total_count}", (10, 30),
                    cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 255, 0), 2)
        cv2.putText(annotated, f"Small: {small_count} | Big: {big_count}", (10, 70),
                    cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 255, 0), 2)

        # ✅ Resize window for smaller display
        resized_display = cv2.resize(
            annotated,
            (int(width * DISPLAY_SCALE), int(height * DISPLAY_SCALE))
        )

        # Show window
        cv2.imshow("Traffic Detection", resized_display)

        # Save output video
        if out:
            out.write(annotated)

        if cv2.waitKey(1) & 0xFF == ord('q'):
            break

    cap.release()
    if out:
        out.release()
    cv2.destroyAllWindows()
    print("Processing complete!")


if __name__ == "__main__":
    main()
