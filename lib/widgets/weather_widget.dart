import 'package:flutter/material.dart';
import 'weather_service.dart';

class WeatherWidget extends StatelessWidget {
  final WeatherService weatherService = WeatherService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double?>(
      stream: weatherService.getTemperatureStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildCard('Loading temperature...');
        } else if (snapshot.hasError) {
          return _buildCard('Error fetching weather');
        } else if (!snapshot.hasData || snapshot.data == null) {
          return _buildCard('No data');
        } else {
          return _buildCard('Current Temp: ${snapshot.data!.toStringAsFixed(1)}°C');
        }
      },
    );
  }

  Widget _buildCard(String text) {
    return Card(
      color: Colors.lightBlue[50],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.thermostat, color: Colors.blue[700]),
            SizedBox(width: 8),
            Text(
              text,
              style: TextStyle(fontSize: 16, color: Colors.blue[900]),
            ),
          ],
        ),
      ),
    );
  }
}