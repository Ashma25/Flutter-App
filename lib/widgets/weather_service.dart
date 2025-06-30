import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class WeatherService {
  // Example: Open-Meteo API for Mumbai (lat: 19.0760, lon: 72.8777)
  static const double latitude = 19.0760;
  static const double longitude = 72.8777;

  Stream<double?> getTemperatureStream({Duration interval = const Duration(minutes: 1)}) async* {
    while (true) {
      final temp = await fetchCurrentTemperature();
      yield temp;
      await Future.delayed(interval);
    }
  }

  Future<double?> fetchCurrentTemperature() async {
    final url =
        'https://api.open-meteo.com/v1/forecast?latitude=$latitude&longitude=$longitude&current_weather=true';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['current_weather']?['temperature']?.toDouble();
      }
    } catch (e) {
      // Handle error
    }
    return null;
  }
}