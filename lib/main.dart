import 'package:flutter/material.dart';

import 'pages/map_page.dart';

void main() {
  runApp(const KmlExplorerApp());
}

class KmlExplorerApp extends StatelessWidget {
  const KmlExplorerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KML Explorer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: const MapPage(),
    );
  }
}
