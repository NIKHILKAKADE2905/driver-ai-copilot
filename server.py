import io
import logging
from fastapi import FastAPI, UploadFile, File, Form, HTTPException
import speech_recognition as sr

from route_planner import RoutePlanner
from ai_voice_copilot import DrowsinessSafetyAgent

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="AI Voice Co-Pilot API Engine")

# Instantiate dependencies
planner = RoutePlanner()
agent = DrowsinessSafetyAgent(route_planner=planner)
recognizer = sr.Recognizer()


@app.post("/api/drowsiness/trigger")
async def trigger_event(
    drowsiness_level: str = Form(...),
    start_lat: float = Form(...),
    start_lon: float = Form(...),
    destination: str = Form(...),
    session_id: str = Form("driver_session")
):
    """Entry endpoint when Android/Flutter detects MODERATE or STRONG drowsiness."""
    try:
        result = agent.handle_drowsiness_event(
            drowsiness_level=drowsiness_level,
            start_lat=start_lat,
            start_lon=start_lon,
            destination=destination,
            session_id=session_id
        )
        return result
    except Exception as e:
        logger.error("Error handling drowsiness trigger: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/drowsiness/respond-voice")
async def respond_voice(
    audio_file: UploadFile = File(...),
    start_lat: float = Form(...),
    start_lon: float = Form(...),
    destination: str = Form(...),
    session_id: str = Form("driver_session")
):
    """Processes recorded .wav audio upload from mobile mic and generates AI response."""
    try:
        audio_bytes = await audio_file.read()

        # Speech-To-Text Transcription
        try:
            with sr.AudioFile(io.BytesIO(audio_bytes)) as source:
                audio_data = recognizer.record(source)
                driver_text = recognizer.recognize_google(audio_data)
                logger.info(f"Driver Said: '{driver_text}'")
        except Exception:
            return {
                "speak_text": "Sorry, I missed that. Are you okay to keep driving or should we pull over?",
                "continue_dialogue": True,
                "stops": []
            }

        # Process Driver Text through LLM Workflow
        result = agent.process_driver_response(
            driver_text=driver_text,
            start_lat=start_lat,
            start_lon=start_lon,
            destination=destination,
            session_id=session_id
        )
        return result

    except Exception as e:
        logger.error("Error processing voice response: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


# if __name__ == "__main__":
#     import uvicorn
#     # Clean launch for Windows environments
#     uvicorn.run(app, host="0.0.0.0", port=8000)