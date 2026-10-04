import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/services/supabase_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  LatLng? currentLocation;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    getInitialLocation();
  }

  Future<void> getInitialLocation() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    final position = await Geolocator.getCurrentPosition();
    if (!mounted) {
      return;
    }

    setState(() {
      currentLocation = LatLng(position.latitude, position.longitude);
    });
  }

  Future<void> updateLocation() async {
    try {
      setState(() => loading = true);
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        showMessage('Permission denied', 'Location permission is required.');
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      final user = SupabaseService.currentUser;
      if (user == null) {
        showMessage('Not signed in', 'Please log in first.');
        return;
      }

      setState(() {
        currentLocation = LatLng(position.latitude, position.longitude);
      });

      await SupabaseService.client.from('users').upsert({
        'id': user.id,
        'lat': position.latitude,
        'lng': position.longitude,
      });

      showMessage('Success', 'Location updated successfully.');
    } catch (error) {
      showMessage('Error', error.toString());
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  void showMessage(String title, String message) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(title: Text(title), content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shadowColor = Colors.black.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.24 : 0.16,
    );

    if (currentLocation == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: currentLocation!,
              zoom: 15,
            ),
            markers: {
              Marker(
                markerId: const MarkerId('me'),
                position: currentLocation!,
                infoWindow: const InfoWindow(title: 'You are here'),
              ),
            },
          ),
          Positioned(
            bottom: 30,
            right: 20,
            child: FloatingActionButton(
              onPressed: loading ? null : updateLocation,
              child: loading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : const Icon(Icons.location_on),
            ),
          ),
          Positioned(
            bottom: 100,
            left: 20,
            right: 20,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: shadowColor, blurRadius: 4),
                  ],
                ),
                child: Text(
                  'Tap the location button to save your current coordinates to your account.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurface),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
