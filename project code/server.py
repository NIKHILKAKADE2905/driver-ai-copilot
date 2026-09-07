import asyncio
import io
import logging
import os
from typing import Optional

from pydantic import ValidationError
from dotenv import load_dotenv
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
import speech_recognition as sr

from ai_voice_copilot import DrowsinessSafetyAgent
from route_planner import RoutePlanner
from schemas import (
    CopilotResponse,
    DriverCoords,
    GeocodeRequest,
    GeocodeResponse,
    HealthResponse,
    TriggerPayload,
    VoicePayload,
)

load_dotenv()

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

STT_TIMEOUT_SECONDS = 8.0

app = FastAPI(title="AI Voice Co-Pilot API Engine")

cors_origins = [o.strip() for o in os.getenv("CORS_ORIGINS", "*").split(",") if o.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

planner = RoutePlanner()
agent = DrowsinessSafetyAgent(route_planner=planner)
recognizer = sr.Recognizer()


def _coords_or_422(start_lat: Optional[float], start_lon: Optional[float]) -> DriverCoords:
    try:
        return DriverCoords(latitude=start_lat, longitude=start_lon)
    except ValidationError as exc:
        raise HTTPException(status_code=422, detail=exc.errors()) from exc


@app.get("/health", response_model=HealthResponse)
async def health() -> HealthResponse:
    return HealthResponse(status="ok")


@app.post("/api/destination/geocode", response_model=GeocodeResponse)
async def geocode_destination(body: GeocodeRequest) -> GeocodeResponse:
    coords = planner.get_destination_coordinates(body.destination.strip())
    if not coords:
        raise HTTPException(
            status_code=404,
            detail="Could not find that destination. Try a city or a fuller address.",
        )
    lat, lon = coords
    return GeocodeResponse(
        latitude=lat,
        longitude=lon,
        destination=body.destination.strip(),
    )


@app.post("/api/drowsiness/trigger", response_model=CopilotResponse)
async def trigger_event(
    drowsiness_level: str = Form(...),
    start_lat: Optional[float] = Form(None),
    start_lon: Optional[float] = Form(None),
    destination: str = Form(...),
    session_id: str = Form(...),
    vehicle_type: str = Form(""),
    dest_lat: Optional[float] = Form(None),
    dest_lon: Optional[float] = Form(None),
) -> CopilotResponse:
    """Entry endpoint when the app detects MODERATE or STRONG drowsiness."""
    try:
        payload = TriggerPayload(
            drowsiness_level=drowsiness_level.strip().upper(),
            destination=destination.strip(),
            session_id=session_id.strip(),
            coords=_coords_or_422(start_lat, start_lon),
            vehicle_type=vehicle_type.strip(),
            dest_lat=dest_lat,
            dest_lon=dest_lon,
        )
    except HTTPException:
        raise
    except ValidationError as exc:
        raise HTTPException(status_code=422, detail=exc.errors()) from exc

    try:
        return agent.handle_drowsiness_event(
            drowsiness_level=payload.drowsiness_level,
            start_lat=payload.coords.latitude,
            start_lon=payload.coords.longitude,
            destination=payload.destination,
            session_id=payload.session_id,
            vehicle_type=payload.vehicle_type,
            dest_lat=payload.dest_lat,
            dest_lon=payload.dest_lon,
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except Exception as exc:
        logger.error("Error handling drowsiness trigger: %s", exc)
        raise HTTPException(status_code=500, detail="Copilot trigger failed") from exc


def _transcribe_wav(audio_bytes: bytes) -> str:
    with sr.AudioFile(io.BytesIO(audio_bytes)) as source:
        audio_data = recognizer.record(source)
        return recognizer.recognize_google(audio_data)


@app.post("/api/drowsiness/respond-voice", response_model=CopilotResponse)
async def respond_voice(
    audio_file: UploadFile = File(...),
    start_lat: Optional[float] = Form(None),
    start_lon: Optional[float] = Form(None),
    destination: str = Form(...),
    session_id: str = Form(...),
    vehicle_type: str = Form(""),
    dest_lat: Optional[float] = Form(None),
    dest_lon: Optional[float] = Form(None),
) -> CopilotResponse:
    """Processes recorded .wav audio from the phone mic and returns a spoken reply."""
    try:
        payload = VoicePayload(
            destination=destination.strip(),
            session_id=session_id.strip(),
            coords=_coords_or_422(start_lat, start_lon),
            vehicle_type=vehicle_type.strip(),
            dest_lat=dest_lat,
            dest_lon=dest_lon,
        )
    except HTTPException:
        raise
    except ValidationError as exc:
        raise HTTPException(status_code=422, detail=exc.errors()) from exc

    try:
        audio_bytes = await audio_file.read()
        try:
            driver_text = await asyncio.wait_for(
                asyncio.to_thread(_transcribe_wav, audio_bytes),
                timeout=STT_TIMEOUT_SECONDS,
            )
            logger.info("Driver said: %s", driver_text)
        except Exception:
            logger.warning("STT failed or timed out")
            return CopilotResponse(
                speak_text=(
                    "Sorry, I missed that. Are you okay to keep driving, "
                    "or should we pull over?"
                ),
                continue_dialogue=True,
                stops=[],
            )

        return agent.process_driver_response(
            driver_text=driver_text,
            start_lat=payload.coords.latitude,
            start_lon=payload.coords.longitude,
            destination=payload.destination,
            session_id=payload.session_id,
            vehicle_type=payload.vehicle_type,
            dest_lat=payload.dest_lat,
            dest_lon=payload.dest_lon,
        )
    except Exception as exc:
        logger.error("Error processing voice response: %s", exc)
        raise HTTPException(status_code=500, detail="Voice response failed") from exc


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "server:app",
        host="0.0.0.0",
        port=int(os.getenv("PORT", "8000")),
        reload=False,
    )
