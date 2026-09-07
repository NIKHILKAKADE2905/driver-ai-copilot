import 'dart:convert';
import 'dart:developer' as developer;

import 'package:demo_cam_application/copilot_api.dart';
import 'package:demo_cam_application/screens/permissions_screen.dart';
import 'package:flutter/material.dart';

class TripSetupScreen extends StatefulWidget {
  final String sessionId;

  const TripSetupScreen({super.key, required this.sessionId});

  @override
  State<TripSetupScreen> createState() => _TripSetupScreenState();
}

class _TripSetupScreenState extends State<TripSetupScreen> {
  final _formKey = GlobalKey<FormState>();

  final List<String> _vehicleTypes = [
    'Car / Sedan',
    'SUV / Truck',
    'Bus',
    'Commercial Hauler',
    'Motorcycle'
  ];

  String? _selectedVehicle;
  final TextEditingController _destinationController = TextEditingController();
  bool _geocoding = false;

  Future<void> _proceedToMonitoring() async {
    if (!_formKey.currentState!.validate()) return;

    final destination = _destinationController.text.trim();
    setState(() => _geocoding = true);
    try {
      final response = await CopilotApi.geocode(destination);

      if (response.statusCode != 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not find that destination. Try a city name or a fuller address.',
            ),
          ),
        );
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PermissionsScreen(
            vehicleType: _selectedVehicle!,
            destination: destination,
            sessionId: widget.sessionId,
            destLat: (data['latitude'] as num).toDouble(),
            destLon: (data['longitude'] as num).toDouble(),
          ),
        ),
      );
    } catch (e) {
      developer.log('Geocode error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cannot verify destination. Check your internet and try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _geocoding = false);
    }
  }

  @override
  void dispose() {
    _destinationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip Setup'),
        backgroundColor: const Color(0xFF20252B),
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Driver & Trip Details',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Please fill in all mandatory fields before initiating drowsiness monitoring.',
                  style: TextStyle(color: Colors.white60, fontSize: 14),
                ),
                const SizedBox(height: 32),
                DropdownButtonFormField<String>(
                  initialValue: _selectedVehicle,
                  decoration: InputDecoration(
                    labelText: 'Select Vehicle Type *',
                    prefixIcon: const Icon(Icons.directions_car),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF252B32),
                  ),
                  items: _vehicleTypes.map((vehicle) {
                    return DropdownMenuItem(
                      value: vehicle,
                      child: Text(vehicle),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedVehicle = val),
                  validator: (val) =>
                      val == null ? 'Please select a vehicle type' : null,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _destinationController,
                  decoration: InputDecoration(
                    labelText: 'Trip Destination *',
                    prefixIcon: const Icon(Icons.location_on),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF252B32),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter your destination';
                    }
                    return null;
                  },
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _geocoding ? null : _proceedToMonitoring,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: _geocoding
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_forward),
                  label: Text(
                    _geocoding
                        ? 'CHECKING DESTINATION...'
                        : 'PROCEED TO MONITORING',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
