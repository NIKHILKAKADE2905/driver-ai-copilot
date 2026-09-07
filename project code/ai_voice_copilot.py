import os
import logging
from typing import Any, Dict, List, Optional
from dotenv import load_dotenv

from langchain.agents import create_agent
from langchain_groq import ChatGroq
from langgraph.checkpoint.memory import InMemorySaver
from route_planner import RoutePlanner
from schemas import CopilotResponse, RestStop

logger = logging.getLogger(__name__)
load_dotenv()


class DrowsinessSafetyAgent:
    """Core AI logic decoupled from OS audio hardware."""

    def __init__(self, route_planner: RoutePlanner, model_name: str = "openai/gpt-oss-20b"):
        self.route_planner = route_planner
        self.groq_api_key = os.getenv("GROQ_API_KEY")

        if not self.groq_api_key:
            raise ValueError("GROQ_API_KEY missing from environment variables.")

        self.llm = ChatGroq(
            groq_api_key=self.groq_api_key,
            model_name=model_name,
            temperature=0.5,
        )

        self._refusal_counts: Dict[str, int] = {}
        self._thread_generations: Dict[str, int] = {}

        self.system_prompt = """You are a warm, attentive friend sitting in the passenger seat driving alongside the user. You are acting as their AI Co-Pilot.

        Persona Guidelines:
        1. Speak completely naturally. Use speech contractions (e.g., "I'm", "you're", "let's", "don't").
        2. NEVER use robotic or formal phrasing like "Alert", "Detection triggered", or "Processing".
        3. Keep spoken replies short (1-2 friendly sentences max).
        4. ADAPTIVE FRICTION:
        - First time moderate fatigue: Kindly check in on them like a caring friend.
        - Continuous fatigue with past refusals: Sound genuinely concerned and slightly more persistent.
        5. If the driver agrees to stop, ask what kind of spot they're in the mood for.
        """

        self.checkpointer = InMemorySaver()
        self.agent = create_agent(
            model=self.llm,
            tools=[],
            system_prompt=self.system_prompt,
            checkpointer=self.checkpointer,
        )

    def _thread_id(self, session_id: str) -> str:
        generation = self._thread_generations.get(session_id, 0)
        return f"{session_id}:{generation}"

    def _invoke_agent(self, user_input: str, session_id: str) -> str:
        result = self.agent.invoke(
            {"messages": [{"role": "user", "content": user_input}]},
            config={"configurable": {"thread_id": self._thread_id(session_id)}},
        )
        message = result["messages"][-1]
        content = message.content
        if isinstance(content, str):
            return content
        return "".join(
            block.get("text", "")
            for block in content
            if isinstance(block, dict)
        )

    def reset_memory(self, session_id: str = "driver_session"):
        self._thread_generations[session_id] = self._thread_generations.get(session_id, 0) + 1
        self._refusal_counts[session_id] = 0

    def generate_chat_response(self, user_input: str, session_id: str = "driver_session") -> str:
        return self._invoke_agent(user_input, session_id)

    @staticmethod
    def _pack(
        speak_text: str,
        continue_dialogue: bool = False,
        stops: Optional[List[Any]] = None,
        intent: str = "",
    ) -> CopilotResponse:
        parsed: List[RestStop] = []
        for item in stops or []:
            parsed.append(RestStop.model_validate(item))
        return CopilotResponse(
            speak_text=speak_text,
            continue_dialogue=continue_dialogue,
            stops=parsed,
            intent=intent if intent in ("YES", "NO", "UNSURE", "") else "",
            copilot_offline=False,
        )

    @staticmethod
    def _has_gps(start_lat: Optional[float], start_lon: Optional[float]) -> bool:
        return start_lat is not None and start_lon is not None

    def handle_drowsiness_event(
        self,
        drowsiness_level: str,
        start_lat: Optional[float],
        start_lon: Optional[float],
        destination: str,
        session_id: str = "driver_session",
        vehicle_type: str = "",
        dest_lat: Optional[float] = None,
        dest_lon: Optional[float] = None,
    ) -> CopilotResponse:
        """Main entry point for drowsiness events."""
        drowsiness_level = drowsiness_level.upper()

        if drowsiness_level == "STRONG":
            return self._handle_strong_drowsiness(
                start_lat,
                start_lon,
                destination,
                session_id,
                vehicle_type=vehicle_type,
                dest_lat=dest_lat,
                dest_lon=dest_lon,
            )

        if drowsiness_level == "MODERATE":
            return self._handle_moderate_drowsiness(session_id)

        raise ValueError(f"Unsupported drowsiness level: {drowsiness_level}")

    def _handle_strong_drowsiness(
        self,
        start_lat: Optional[float],
        start_lon: Optional[float],
        destination: str,
        session_id: str,
        vehicle_type: str = "",
        dest_lat: Optional[float] = None,
        dest_lon: Optional[float] = None,
    ) -> CopilotResponse:
        """Automatically search for a nearby place where the driver can rest."""

        warning_prompt = (
                            f"The driver is showing strong drowsiness. They need to pull over immediately. your job is to tell them firmly that they need to stop driving because they are not only putting thier lives but also other people's lives at risk, and that you are searching for a nearby place where they can rest."
                        )
        response = self._invoke_agent(warning_prompt, session_id)

        stops: list = []
        if self._has_gps(start_lat, start_lon):
            stops = self.route_planner.plan_trip_stops(
                start_lat=start_lat,
                start_lon=start_lon,
                destination=destination,
                search_query="",
                min_distance_threshold_km=0.0,
                vehicle_type=vehicle_type,
                dest_lat=dest_lat,
                dest_lon=dest_lon,
            ) or []
            if stops:
                first = stops[0]
                speak_text = self._invoke_agent(
                    f"Found a rest stop named {first.get('displayName')} "
                    f"{first.get('distance_km')} kilometers ahead. "
                    "Tell them you are opening navigation to that stop and they should pull over immediately.",
                    session_id,
                )
            else:
                speak_text = "Hmm, I didn't spot anything right on this stretch, but try taking the next exit to rest."
        else:
            speak_text = "I don't have your GPS yet. Pull over at the next safe place you can see."

        self.reset_memory(session_id)
        return self._pack(
            speak_text=response + "............" + speak_text,
            continue_dialogue=False,
            stops=stops,
        )

    def _handle_moderate_drowsiness(self, session_id: str) -> CopilotResponse:
        """FRIENDLY CHECK-IN: Ask driver if they want to pull over."""

        refusal_count = self._refusal_counts.get(session_id, 0)

        context_prompt = (
                    f"[CONTEXT: The driver is showing moderate drowsiness. Past times they said no to resting: {refusal_count}]. "
                    "Check in on them in a friendly, conversational way. Ask if they want to pull over."
                )
        response = self._invoke_agent(context_prompt, session_id)
        return self._pack(speak_text=response, continue_dialogue=True, stops=[])

    def process_driver_response(
        self,
        driver_text: str,
        start_lat: Optional[float],
        start_lon: Optional[float],
        destination: str,
        session_id: str = "driver_session",
        vehicle_type: str = "",
        dest_lat: Optional[float] = None,
        dest_lon: Optional[float] = None,
    ) -> CopilotResponse:
        """Processes driver's transcribed text input and evaluates intent & route search."""
        refusal_count = self._refusal_counts.get(session_id, 0)

        # Classify intent via LLM
        intent_check = self.llm.invoke(
            f"Classify the driver's response using exactly one label: "
            f"YES if the driver agrees to stop for a break, "
            f"NO if the driver refuses and wants to continue driving, "
            f"UNSURE if the meaning is ambiguous. "
            f"Return only YES, NO, or UNSURE. "
            f"Driver response: {driver_text!r}"
        ).content.strip().upper()

        if intent_check == "UNSURE":
            response = self._invoke_agent(
                "You couldn't quite understand the driver's response. Ask them again in a friendly way if they want to keep driving or pull over.",
                session_id,
            )
            return self._pack(
                speak_text=response,
                continue_dialogue=True,
                stops=[],
                intent="UNSURE",
            )

        elif intent_check == "NO":
            self._refusal_counts[session_id] = refusal_count + 1
            acknowledgment = self._invoke_agent(
                f"Driver insists on continuing (Refusals: {self._refusal_counts[session_id]}). Respond with realistic human concern, tell them you'll keep an eye on them and also tell them how many warnings have they had so far by looking at the refusal count, try to not sound repetitive and wrap up.",
                session_id,
            )
            return self._pack(
                speak_text=acknowledgment,
                continue_dialogue=False,
                stops=[],
                intent="NO",
            )

        else:

            # Driver agreed to stop
            query_suggestion = self.llm.invoke(
                f"The driver agreed to stop. User text: '{driver_text}'. "
                f"Extract what kind of place they want (e.g. 'cafe', 'petrol pump', 'food', 'truck stop'). "
                f"If they did not specify, return an empty string. Return ONLY the search query string."
            ).content.strip()

            stops: list = []
            if self._has_gps(start_lat, start_lon):
                stops = self.route_planner.plan_trip_stops(
                    start_lat=start_lat,
                    start_lon=start_lon,
                    destination=destination,
                    search_query=query_suggestion,
                    min_distance_threshold_km=0.0,
                    vehicle_type=vehicle_type,
                    dest_lat=dest_lat,
                    dest_lon=dest_lon,
                ) or []
                if stops:
                    first = stops[0]
                    speak_text = self._invoke_agent(
                        f"Found {len(stops)} spots. The closest is {first.get('displayName')} "
                        f"{first.get('distance_km')} kilometers ahead. "
                        "Tell the driver you are opening navigation there.",
                        session_id,
                    )
                else:
                    speak_text = "Hmm, I didn't spot anything right on this stretch, but try taking the next exit to rest."
            else:
                speak_text = "I heard you want to stop, but I don't have your location. Take the next safe exit you can see."

            self.reset_memory(session_id)
            return self._pack(
                speak_text=speak_text,
                continue_dialogue=False,
                stops=stops,
                intent="YES",
            )