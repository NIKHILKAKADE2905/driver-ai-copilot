import os
import json
import logging
from typing import Dict, Any, Optional
from dotenv import load_dotenv

from langchain_groq import ChatGroq
from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder
from langchain_core.runnables.history import RunnableWithMessageHistory
from langchain_core.chat_history import InMemoryChatMessageHistory, BaseChatMessageHistory
from route_planner import RoutePlanner

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
            temperature=0.85,
        )

        self._memory_store: Dict[str, InMemoryChatMessageHistory] = {}
        self._refusal_counts: Dict[str, int] = {}

        self.prompt = ChatPromptTemplate.from_messages([
            (
                "system", """You are a warm, attentive friend sitting in the passenger seat driving alongside the user. You are acting as their AI Co-Pilot.

                Persona Guidelines:
                1. Speak completely naturally. Use speech contractions (e.g., "I'm", "you're", "let's", "don't").
                2. NEVER use robotic or formal phrasing like "Alert", "Detection triggered", or "Processing".
                3. Keep spoken replies short (1-2 friendly sentences max).
                4. ADAPTIVE FRICTION:
                - First time moderate fatigue: Kindly check in on them like a caring friend.
                - Continuous fatigue with past refusals: Sound genuinely concerned and slightly more persistent.
                5. If the driver agrees to stop, ask what kind of spot they're in the mood for.
                """
            ),
            MessagesPlaceholder(variable_name="history"),
            ("human", "{input}"),
        ])

        self.chain = self.prompt | self.llm
        self.agent_with_history = RunnableWithMessageHistory(
            self.chain,
            self._get_session_history,
            input_messages_key="input",
            history_messages_key="history",
        )

    def _get_session_history(self, session_id: str) -> BaseChatMessageHistory:
        if session_id not in self._memory_store:
            self._memory_store[session_id] = InMemoryChatMessageHistory()
        return self._memory_store[session_id]

    def reset_memory(self, session_id: str = "driver_session"):
        if session_id in self._memory_store:
            self._memory_store[session_id].clear()
        self._refusal_counts[session_id] = 0

    def generate_chat_response(self, user_input: str, session_id: str = "driver_session") -> str:
            response = self.agent_with_history.invoke(
                {"input": user_input},
                config={"configurable": {"session_id": session_id}},
            )
            return response.content

    def handle_drowsiness_event(
            self,
            drowsiness_level: str,
            start_lat: float,
            start_lon: float,
            destination: str,
            session_id: str = "driver_session",
        ) -> bool:
            """Main entry point for drowsiness events."""
            drowsiness_level = drowsiness_level.upper()
    
            if drowsiness_level == "STRONG":
                return self._handle_strong_drowsiness(start_lat, start_lon, destination, session_id)
    
            elif drowsiness_level == "MODERATE":
                return self._handle_moderate_drowsiness(session_id)

    def _handle_strong_drowsiness(
            self, start_lat: float, start_lon: float, destination: str, session_id: str
        ) -> bool:
            """AUTOMATED INTERVENTION: Urgent safety warning + immediate rest stop search."""
    
            urgent_warning = (
                "Whoa, pull over! You're drifting off and it's really unsafe to keep driving like this. "
                "I'm pulling up the nearest rest stops right now so you can take a quick nap."
            )
            
            # self.audio.speak(urgent_warning)
    
            stops = self.route_planner.plan_trip_stops(
                start_lat=start_lat,
                start_lon=start_lon,
                destination=destination,
                search_query="petrol pump",
                min_distance_threshold_km=0.0,
            )
    
            if stops:
                        final_response = self.agent_with_history.invoke(
                            {"input": f"Found {len(stops)} spots for 'petrol pump'. Tell driver they are on screen."},
                            config={"configurable": {"session_id": session_id}}
                        )
                        speak_text = final_response.content
            else:
                speak_text = "Hmm, I didn't spot anything right on this stretch, but try taking the next exit to rest."
    
            self.reset_memory(session_id)
            return {
                "speak_text": speak_text,
                "continue_dialogue": False,
                "stops": stops or []
            }

    # def get_initial_greeting(self, level: str, session_id: str = "driver_session") -> str:
    #     """Returns the initial co-pilot greeting string for Flutter TTS."""
    #     level = level.upper()
    #     refusal_count = self._refusal_counts.get(session_id, 0)

    #     if level == "STRONG":
    #         return "Whoa, pull over! You're drifting off and it's really unsafe. I'm pulling up the nearest rest stops right now."
        
    #     context_prompt = (
    #         f"[CONTEXT: Moderate drowsiness. Past refusals: {refusal_count}]. "
    #         "Check in on them in a friendly, conversational way. Ask if they want to pull over."
    #     )
    #     response = self.agent_with_history.invoke(
    #         {"input": context_prompt},
    #         config={"configurable": {"session_id": session_id}}
    #     )
    #     return response.content

    def _handle_moderate_drowsiness(self, session_id: str) -> Dict[str, Any]:
        """FRIENDLY CHECK-IN: Ask driver if they want to pull over."""

        refusal_count = self._refusal_counts.get(session_id, 0)

        context_prompt = (
                    f"[CONTEXT: The driver is showing moderate drowsiness. Past times they said no to resting: {refusal_count}]. "
                    "Check in on them in a friendly, conversational way. Ask if they want to pull over."
                )
        response = self.agent_with_history.invoke(
            {"input": context_prompt},
            config={"configurable": {"session_id": session_id}}
        )
        return {
            "speak_text": response.content,
            "continue_dialogue": True,
            "stops": []
        }

    def process_driver_response(
        self,
        driver_text: str,
        start_lat: float,
        start_lon: float,
        destination: str,
        session_id: str = "driver_session"
    ) -> Dict[str, Any]:
        """Processes driver's transcribed text input and evaluates intent & route search."""
        refusal_count = self._refusal_counts.get(session_id, 0)

        # Classify intent via LLM
        intent_check = self.llm.invoke(
            f"Does the user want to KEEP driving or refuse to stop? "
            f"Answer strictly with 'YES', 'NO' or 'UNSURE', whether they are agreeing to stop for taking break or not. If the user is clearly refusing then, it is a 'no', if the user is agreeing then, it is a 'yes', Do not make a decision until you fully understand what the driver is saying. if you are unsure about what driver said then just answer unsure. User text: '{driver_text}'"
        ).content.strip().upper()

        if "UNSURE" in intent_check:
            response = self.agent_with_history.invoke(
                {"input": "You couldn't quite understand the driver's response. Ask them again in a friendly way if they want to keep driving or pull over."},
                config={"configurable": {"session_id": session_id}}
            )
            return {
                "speak_text": response.content,
                "continue_dialogue": True,
                "stops": []
            }

        if "NO" in intent_check:
            self._refusal_counts[session_id] = refusal_count + 1
            acknowledgment = self.agent_with_history.invoke(
                {"input": f"Driver insists on continuing (Refusals: {self._refusal_counts[session_id]}). Respond with realistic human concern, tell them you'll keep an eye on them, try to not sound repetitive and wrap up."},
                config={"configurable": {"session_id": session_id}}
            )
            return {
                "speak_text": acknowledgment.content,
                "continue_dialogue": False,
                "stops": []
            }

        # Driver agreed to stop
        query_suggestion = self.llm.invoke(
            f"The driver agreed to stop. User text: '{driver_text}'. "
            f"Extract what kind of place they want (e.g. 'cafe', 'petrol pump', 'food'). "
            f"Default to 'petrol pump'. Return ONLY the search query string."
        ).content.strip()

        stops = self.route_planner.plan_trip_stops(
            start_lat=start_lat,
            start_lon=start_lon,
            destination=destination,
            search_query=query_suggestion,
            min_distance_threshold_km=0.0
        )

        if stops:
            final_response = self.agent_with_history.invoke(
                {"input": f"Found {len(stops)} spots for '{query_suggestion}'. Tell driver they are on screen."},
                config={"configurable": {"session_id": session_id}}
            )
            speak_text = final_response.content
        else:
            speak_text = "Hmm, I didn't spot anything right on this stretch, but try taking the next exit to rest."

        self.reset_memory(session_id)
        return {
            "speak_text": speak_text,
            "continue_dialogue": False,
            "stops": stops or []
        }