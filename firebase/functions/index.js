const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const fetch = require("node-fetch");

// Secrets managed via `firebase functions:secrets:set`
const openWeatherApiKey = defineSecret("OPENWEATHER_API_KEY");

// ──────────────────────────────────────────────
// Weather Proxy — forwards requests to OpenWeatherMap
// ──────────────────────────────────────────────
exports.weatherProxy = onCall(
  {
    region: "asia-southeast1",
    secrets: [openWeatherApiKey],
  },
  async (request) => {
    // Enforce authentication
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "You must be signed in to fetch weather."
      );
    }

    const { latitude, longitude, cityName } = request.data;
    if (latitude == null || longitude == null) {
      throw new HttpsError(
        "invalid-argument",
        "'latitude' and 'longitude' are required."
      );
    }

    try {
      const apiKey = openWeatherApiKey.value();
      const url =
        `https://api.openweathermap.org/data/2.5/weather` +
        `?lat=${latitude}&lon=${longitude}&appid=${apiKey}&units=metric`;

      const response = await fetch(url, { timeout: 10000 });

      if (!response.ok) {
        // Return location-only fallback
        return {
          cityName: cityName || "Unknown",
          tempMin: 0,
          tempMax: 0,
          condition: "unavailable",
          iconCode: "",
        };
      }

      const data = await response.json();

      return {
        cityName: cityName || data.name || "Unknown",
        tempMin: data.main.temp_min,
        tempMax: data.main.temp_max,
        condition: data.weather[0].main,
        iconCode: data.weather[0].icon,
      };
    } catch (err) {
      console.error("OpenWeatherMap error:", err);
      throw new HttpsError("internal", "Failed to fetch weather data.");
    }
  }
);
