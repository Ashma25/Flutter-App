import 'package:flutter/material.dart';
import 'weather_service.dart';

class WeatherIconWidget extends StatelessWidget {
  final WeatherService weatherService = WeatherService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double?>(
      stream: weatherService.getTemperatureStream(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return Row(
            children: [
              Icon(Icons.cloud, color: Colors.white), // Use any weather icon you like
              const SizedBox(width: 4),
              Text(
                '${snapshot.data!.toStringAsFixed(1)}°C',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          );
        } else {
          return Icon(Icons.cloud, color: Colors.white); // fallback icon
        }
      },
    );
  }
}