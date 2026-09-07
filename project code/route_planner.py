import os
import math
import json
import logging
from typing import List, Dict, Any, Tuple, Optional
import requests
from dotenv import load_dotenv

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)

load_dotenv()


class RoutePlanner:
    """Handles route polyline extraction, search along routes, geocoding, and geospatial calculations."""

    ROUTES_API_URL = "https://routes.googleapis.com/directions/v2:computeRoutes"
    PLACES_API_URL = "https://places.googleapis.com/v1/places:searchText"
    EARTH_RADIUS_KM = 6371.0
    REQUEST_TIMEOUT_SECONDS = 12
    NEARBY_RADIUS_METERS = 15000.0
    ALONG_ROUTE_MIN_KM = 2.0
    ALONG_ROUTE_MAX_KM = 25.0
    NEARBY_MIN_KM = 0.3
    MAX_STOPS = 5

    VEHICLE_QUERIES = {
        "car / sedan": ["petrol pump", "highway dhaba", "rest area"],
        "suv / truck": ["petrol pump", "highway dhaba", "rest area"],
        "bus": ["truck stop", "dhaba", "petrol pump", "bus parking"],
        "commercial hauler": ["truck stop", "truck parking", "dhaba", "petrol pump"],
        "motorcycle": ["petrol pump", "rest area"],
    }

    def __init__(self, api_key: Optional[str] = None):
        """Initialize the client with a Google Maps API key."""
        self.api_key = api_key or os.getenv("MAPS_API_KEY")
        if not self.api_key:
            raise ValueError("Google Maps API key must be provided or set in environment variables.")

    @classmethod
    def queries_for_vehicle(cls, vehicle_type: str, extra_query: Optional[str] = None) -> List[str]:
        queries: List[str] = []
        if extra_query:
            cleaned = extra_query.strip().strip('"').strip("'")
            if cleaned and cleaned.lower() not in {"none", "empty", "n/a", "null"}:
                queries.append(cleaned)
        mapped = cls.VEHICLE_QUERIES.get(vehicle_type.strip().lower(), ["petrol pump", "rest area"])
        for item in mapped:
            if item.lower() not in {q.lower() for q in queries}:
                queries.append(item)
        return queries

    @staticmethod
    def calculate_haversine_distance(
        lat1: float, lon1: float, lat2: float, lon2: float
    ) -> float:
        """Calculate the Great Circle distance between two points on Earth in kilometers."""
        d_lat = math.radians(lat2 - lat1)
        d_lon = math.radians(lon2 - lon1)
        
        a = (
            math.sin(d_lat / 2) ** 2
            + math.cos(math.radians(lat1))
            * math.cos(math.radians(lat2))
            * math.sin(d_lon / 2) ** 2
        )
        c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
        return RoutePlanner.EARTH_RADIUS_KM * c

    @staticmethod
    def is_forward_direction(
        start_lat: float,
        start_lon: float,
        end_lat: float,
        end_lon: float,
        place_lat: float,
        place_lon: float,
    ) -> bool:
        """
        Uses a 2D vector dot product to check if a place lies in the forward 
        direction of the route vector (Start -> End).
        """
        # Vector from start to destination
        v_route_lat = end_lat - start_lat
        v_route_lon = end_lon - start_lon

        # Vector from start to target place
        v_place_lat = place_lat - start_lat
        v_place_lon = place_lon - start_lon

        # Dot product >= 0 means place is in front of or perpendicular to starting direction
        dot_product = (v_place_lat * v_route_lat) + (v_place_lon * v_route_lon)
        return dot_product >= 0

    def get_destination_coordinates(self, destination: str) -> Optional[Tuple[float, float]]:
        """Resolves a text destination address into (latitude, longitude) coordinates."""
        headers = {
            "Content-Type": "application/json",
            "X-Goog-Api-Key": self.api_key,
            "X-Goog-FieldMask": "places.location",
        }

        payload = {"textQuery": destination}

        try:
            response = requests.post(
                self.PLACES_API_URL,
                json=payload,
                headers=headers,
                timeout=self.REQUEST_TIMEOUT_SECONDS,
            )
            response.raise_for_status()

            data = response.json()
            places = data.get("places", [])
            if not places:
                logger.warning("Could not resolve coordinates for destination: %s", destination)
                return None

            location = places[0].get("location", {})
            lat = location.get("latitude")
            lon = location.get("longitude")

            if lat is not None and lon is not None:
                logger.info("📍 Resolved destination coordinates: (%.6f, %.6f)", lat, lon)
                return lat, lon
            return None

        except requests.exceptions.RequestException as e:
            logger.error("❌ Destination geocoding failed: %s", e)
            return None

    def get_route_polyline(
        self,
        start_lat: float,
        start_lon: float,
        destination: str,
        dest_lat: Optional[float] = None,
        dest_lon: Optional[float] = None,
    ) -> Optional[Tuple[str, float]]:
        """Fetch the encoded route polyline and total distance from Google Routes API."""
        headers = {
            "Content-Type": "application/json",
            "X-Goog-Api-Key": self.api_key,
            "X-Goog-FieldMask": "routes.polyline.encodedPolyline,routes.duration,routes.distanceMeters",
        }

        if dest_lat is not None and dest_lon is not None:
            destination_payload: Dict[str, Any] = {
                "location": {"latLng": {"latitude": dest_lat, "longitude": dest_lon}}
            }
        else:
            destination_payload = {"address": destination}

        payload = {
            "origin": {
                "location": {
                    "latLng": {"latitude": start_lat, "longitude": start_lon}
                }
            },
            "destination": destination_payload,
            "travelMode": "DRIVE",
        }

        try:
            response = requests.post(
                self.ROUTES_API_URL,
                json=payload,
                headers=headers,
                timeout=self.REQUEST_TIMEOUT_SECONDS,
            )
            response.raise_for_status()

            data = response.json()
            route = data["routes"][0]
            
            polyline_string = route["polyline"]["encodedPolyline"]
            distance_km = route["distanceMeters"] / 1000.0
            duration_secs = float(route.get("duration", "0s").rstrip("s"))

            logger.info("✅ Route calculation successful!")
            logger.info("🛣️ Total Distance: %.2f km", distance_km)
            logger.info("⏱️ Estimated Time: %d mins", int(duration_secs // 60))

            return polyline_string, distance_km

        except requests.exceptions.RequestException as e:
            logger.error("❌ Google Routes API request failed: %s", e)
            return None

    def search_places_along_route(
        self, polyline_string: str, query: str
    ) -> List[Dict[str, Any]]:
        """Search for places along the route polyline using Google Places API (New)."""
        headers = {
            "Content-Type": "application/json",
            "X-Goog-Api-Key": self.api_key,
            "X-Goog-FieldMask": "places.displayName,places.location,routingSummaries",
        }

        payload = {
            "textQuery": query,
            "searchAlongRouteParameters": {
                "polyline": {"encodedPolyline": polyline_string}
            },
        }

        try:
            response = requests.post(
                self.PLACES_API_URL,
                json=payload,
                headers=headers,
                timeout=self.REQUEST_TIMEOUT_SECONDS,
            )
            response.raise_for_status()
            
            data = response.json()
            return data.get("places", [])

        except requests.exceptions.RequestException as e:
            logger.error("❌ Google Places API request failed: %s", e)
            return []

    def search_places_nearby(
        self, start_lat: float, start_lon: float, query: str
    ) -> List[Dict[str, Any]]:
        """Search near the driver's current position when along-route search is empty."""
        headers = {
            "Content-Type": "application/json",
            "X-Goog-Api-Key": self.api_key,
            "X-Goog-FieldMask": "places.displayName,places.location",
        }
        payload = {
            "textQuery": query,
            "locationBias": {
                "circle": {
                    "center": {"latitude": start_lat, "longitude": start_lon},
                    "radius": self.NEARBY_RADIUS_METERS,
                }
            },
        }
        try:
            response = requests.post(
                self.PLACES_API_URL,
                json=payload,
                headers=headers,
                timeout=self.REQUEST_TIMEOUT_SECONDS,
            )
            response.raise_for_status()
            return response.json().get("places", [])
        except requests.exceptions.RequestException as e:
            logger.error("❌ Nearby Places search failed: %s", e)
            return []

    def process_and_sort_places(
        self,
        places: List[Dict[str, Any]],
        start_lat: float,
        start_lon: float,
        end_lat: Optional[float] = None,
        end_lon: Optional[float] = None,
        min_distance_km: float = 0.0,
        max_distance_km: float = 25.0,
    ) -> List[Dict[str, Any]]:
        """
        Calculates distance from origin and sorts places in ascending order.
        Filters out places that fall behind the initial trajectory if end coordinates are given.
        """
        processed_places = []
        seen = set()

        for place in places:
            location = place.get("location", {})
            plat = location.get("latitude")
            plon = location.get("longitude")

            if plat is None or plon is None:
                continue

            key = (round(float(plat), 5), round(float(plon), 5))
            if key in seen:
                continue
            seen.add(key)

            if end_lat is not None and end_lon is not None:
                if not self.is_forward_direction(start_lat, start_lon, end_lat, end_lon, plat, plon):
                    continue

            distance_km = self.calculate_haversine_distance(start_lat, start_lon, plat, plon)
            if distance_km < min_distance_km or distance_km > max_distance_km:
                continue

            processed_place = {
                "displayName": place.get("displayName", {}).get("text", "Unknown"),
                "location": {"latitude": plat, "longitude": plon},
                "distance_km": round(distance_km, 2),
            }
            processed_places.append(processed_place)

        processed_places.sort(key=lambda x: x["distance_km"])
        return processed_places[: self.MAX_STOPS]

    def plan_trip_stops(
        self,
        start_lat: float,
        start_lon: float,
        destination: str,
        search_query: str = "",
        min_distance_threshold_km: float = 0.0,
        vehicle_type: str = "",
        dest_lat: Optional[float] = None,
        dest_lon: Optional[float] = None,
    ) -> List[Dict[str, Any]]:
        """
        Along-route search for vehicle-appropriate rest/fuel stops, then nearby fallback.
        """
        queries = self.queries_for_vehicle(vehicle_type, extra_query=search_query)

        end_lat, end_lon = dest_lat, dest_lon
        if end_lat is None or end_lon is None:
            dest_coords = self.get_destination_coordinates(destination)
            if dest_coords:
                end_lat, end_lon = dest_coords

        route_info = self.get_route_polyline(
            start_lat,
            start_lon,
            destination,
            dest_lat=end_lat,
            dest_lon=end_lon,
        )
        along_route_places: List[Dict[str, Any]] = []
        if route_info:
            encoded_polyline, total_distance_km = route_info
            if total_distance_km < min_distance_threshold_km:
                logger.warning(
                    "Route is %.2f km (under threshold of %.2f km).",
                    total_distance_km,
                    min_distance_threshold_km,
                )
            else:
                for query in queries:
                    along_route_places.extend(
                        self.search_places_along_route(encoded_polyline, query)
                    )
                    ranked = self.process_and_sort_places(
                        places=along_route_places,
                        start_lat=start_lat,
                        start_lon=start_lon,
                        end_lat=end_lat,
                        end_lon=end_lon,
                        min_distance_km=self.ALONG_ROUTE_MIN_KM,
                        max_distance_km=self.ALONG_ROUTE_MAX_KM,
                    )
                    if ranked:
                        logger.info("Along-route stops found for query %r", query)
                        return ranked
        else:
            logger.error("Failed to retrieve route information.")

        logger.info("Falling back to nearby place search.")
        nearby_places: List[Dict[str, Any]] = []
        for query in queries:
            nearby_places.extend(
                self.search_places_nearby(start_lat, start_lon, query)
            )
            ranked = self.process_and_sort_places(
                places=nearby_places,
                start_lat=start_lat,
                start_lon=start_lon,
                end_lat=end_lat,
                end_lon=end_lon,
                min_distance_km=self.NEARBY_MIN_KM,
                max_distance_km=self.ALONG_ROUTE_MAX_KM,
            )
            if ranked:
                return ranked

        # Last resort: nearby without forward-direction filter
        return self.process_and_sort_places(
            places=nearby_places,
            start_lat=start_lat,
            start_lon=start_lon,
            min_distance_km=self.NEARBY_MIN_KM,
            max_distance_km=self.ALONG_ROUTE_MAX_KM,
        )


# =====================================================================
# EXECUTION / DRIVER SCRIPT
# =====================================================================
if __name__ == "__main__":
    START_LATITUDE = 19.24676742182852
    START_LONGITUDE = 73.12047607739554
    DESTINATION_ADDRESS = "Dombivli, Maharashtra, India"
    SEARCH_QUERY = "petrol pump"

    planner = RoutePlanner()

    sorted_results = planner.plan_trip_stops(
        start_lat=START_LATITUDE,
        start_lon=START_LONGITUDE,
        destination=DESTINATION_ADDRESS,
        search_query=SEARCH_QUERY,
    )

    print("\n📍 Sorted Places Along Route (Ascending Distance from Start):")
    print(json.dumps(sorted_results, indent=4))