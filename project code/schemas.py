from typing import List, Literal, Optional

from pydantic import BaseModel, Field, model_validator


class StopLocation(BaseModel):
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)


class RestStop(BaseModel):
    displayName: str
    location: StopLocation
    distance_km: float = Field(..., ge=0)


class CopilotResponse(BaseModel):
    speak_text: str
    continue_dialogue: bool = False
    stops: List[RestStop] = Field(default_factory=list)
    intent: Optional[Literal["YES", "NO", "UNSURE", ""]] = ""
    copilot_offline: bool = False


class GeocodeRequest(BaseModel):
    destination: str = Field(..., min_length=2, max_length=500)


class GeocodeResponse(BaseModel):
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    destination: str


class DriverCoords(BaseModel):
    """Optional GPS pair. Both must be present or both omitted; never a single axis or 0,0 fake."""

    latitude: Optional[float] = Field(default=None, ge=-90, le=90)
    longitude: Optional[float] = Field(default=None, ge=-180, le=180)

    @model_validator(mode="after")
    def both_or_neither(self) -> "DriverCoords":
        has_lat = self.latitude is not None
        has_lon = self.longitude is not None
        if has_lat != has_lon:
            raise ValueError("latitude and longitude must both be provided or both omitted")
        if has_lat and self.latitude == 0.0 and self.longitude == 0.0:
            raise ValueError("0,0 is not a valid driver location")
        return self

    @property
    def is_set(self) -> bool:
        return self.latitude is not None and self.longitude is not None


class TriggerPayload(BaseModel):
    drowsiness_level: Literal["MODERATE", "STRONG"]
    destination: str = Field(..., min_length=1, max_length=500)
    session_id: str = Field(..., min_length=8, max_length=128)
    coords: DriverCoords
    vehicle_type: str = Field(default="", max_length=64)
    dest_lat: Optional[float] = Field(default=None, ge=-90, le=90)
    dest_lon: Optional[float] = Field(default=None, ge=-180, le=180)


class VoicePayload(BaseModel):
    destination: str = Field(..., min_length=1, max_length=500)
    session_id: str = Field(..., min_length=8, max_length=128)
    coords: DriverCoords
    vehicle_type: str = Field(default="", max_length=64)
    dest_lat: Optional[float] = Field(default=None, ge=-90, le=90)
    dest_lon: Optional[float] = Field(default=None, ge=-180, le=180)


class HealthResponse(BaseModel):
    status: Literal["ok"]
    service: str = "ai-copilot"
