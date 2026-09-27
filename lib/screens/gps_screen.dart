import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../services/notification_service.dart';

enum ModoRuta { auto, pie }

class GpsScreen extends StatefulWidget {
  const GpsScreen({super.key});

  @override
  State<GpsScreen> createState() => _GpsScreenState();
}

class _GpsScreenState extends State<GpsScreen> {
  static const Color bordo = Color(0xFF670310);
  static const Color negro = Color(0xFF000000);
  static const Color blanco = Color(0xFFFFFFFF);

  bool permitirUbicacion = true;
  bool detectarProximidad = true;
  bool buscandoUbicacion = false;
  bool buscandoSugerencias = false;
  bool calculandoRuta = false;

  Position? posicionActual;
  String estadoGps = 'SIN COMPROBAR';
  String precisionGps = '--';

  String direccionActual = 'Dirección no disponible';
  bool buscandoDireccionActual = false;

  final TextEditingController direccionController = TextEditingController();
  final FocusNode direccionFocus = FocusNode();
  final MapController mapController = MapController();

  Timer? _debounce;
  List<Map<String, dynamic>> sugerencias = [];
  Map<String, dynamic>? destinoSeleccionado;
  List<LatLng> rutaReal = [];
  double? distanciaRutaKm;
  double? duracionRutaMin;
  ModoRuta modoRuta = ModoRuta.auto;

  final Set<String> lugaresNotificados = {};

  final List<Map<String, dynamic>> ubicaciones = [
    {
      'nombre': 'Campus Principal',
      'latitud': -30.9008403,
      'longitud': -55.5354775,
    },
    {
      'nombre': 'Biblioteca Central',
      'latitud': -30.9007600,
      'longitud': -55.5353900,
    },
    {
      'nombre': 'Laboratorio de Informática',
      'latitud': -30.9009200,
      'longitud': -55.5355600,
    },
  ];

  @override
  void dispose() {
    _debounce?.cancel();
    direccionController.dispose();
    direccionFocus.dispose();
    super.dispose();
  }

  Future<void> obtenerUbicacion() async {
    if (!permitirUbicacion) {
      mostrarMensaje('Activa "Permitir geolocalización" para utilizar el GPS.');
      return;
    }

    setState(() {
      buscandoUbicacion = true;
      estadoGps = 'BUSCANDO...';
    });

    try {
      final servicioActivo = await Geolocator.isLocationServiceEnabled();
      if (!servicioActivo) {
        if (!mounted) return;
        setState(() {
          buscandoUbicacion = false;
          estadoGps = 'GPS DESACTIVADO';
          precisionGps = '--';
        });
        mostrarMensaje('Activa el servicio de ubicación del dispositivo.');
        return;
      }

      LocationPermission permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
      }
      if (permiso == LocationPermission.denied) {
        if (!mounted) return;
        setState(() {
          buscandoUbicacion = false;
          estadoGps = 'PERMISO DENEGADO';
          precisionGps = '--';
        });
        mostrarMensaje('El permiso de ubicación fue denegado.');
        return;
      }
      if (permiso == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          buscandoUbicacion = false;
          estadoGps = 'PERMISO BLOQUEADO';
          precisionGps = '--';
        });
        mostrarMensaje('El permiso está bloqueado. Actívalo desde los ajustes.');
        return;
      }

      final posicion = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;

      setState(() {
        posicionActual = posicion;
        buscandoUbicacion = false;
        estadoGps = 'ACTIVO';
        precisionGps = '${posicion.accuracy.toStringAsFixed(1)} m';
      });

      await verificarProximidad();
      await obtenerDireccionActual();
      try {
        mapController.move(LatLng(posicion.latitude, posicion.longitude), 16);
      } catch (_) {}
      mostrarMensaje('Posición actualizada correctamente.');
    } catch (e) {
      debugPrint('ERROR GPS: $e');
      if (!mounted) return;
      setState(() {
        buscandoUbicacion = false;
        estadoGps = 'ERROR';
        precisionGps = '--';
      });
      mostrarMensaje('No fue posible obtener la ubicación.');
    }
  }

  Future<void> obtenerDireccionActual() async {
    if (posicionActual == null) return;

    setState(() {
      buscandoDireccionActual = true;
      direccionActual = 'Buscando dirección...';
    });

    try {
      final uri = Uri.https(
        'nominatim.openstreetmap.org',
        '/reverse',
        {
          'lat': posicionActual!.latitude.toString(),
          'lon': posicionActual!.longitude.toString(),
          'format': 'jsonv2',
          'addressdetails': '1',
          'zoom': '18',
        },
      );

      final respuesta = await http.get(
        uri,
        headers: const {
          'User-Agent': 'StudyTrack/1.0 (com.example.studytrack)',
          'Accept': 'application/json',
          'Accept-Language': 'es,pt-BR;q=0.9',
        },
      );

      if (respuesta.statusCode != 200) {
        throw Exception('Nominatim reverse ${respuesta.statusCode}');
      }

      final datos = Map<String, dynamic>.from(
        jsonDecode(respuesta.body) as Map,
      );

      final address = datos['address'] is Map
          ? Map<String, dynamic>.from(datos['address'] as Map)
          : <String, dynamic>{};

      final calle = address['road'] ??
          address['pedestrian'] ??
          address['residential'] ??
          address['path'];
      final numero = address['house_number'];
      final ciudad = address['city'] ??
          address['town'] ??
          address['municipality'] ??
          address['village'];
      final estado = address['state'];

      final partes = <String>[];

      if (calle != null) {
        partes.add(
          numero == null ? calle.toString() : '${calle.toString()}, $numero',
        );
      }
      if (ciudad != null) partes.add(ciudad.toString());
      if (estado != null) partes.add(estado.toString());

      final direccion = partes.isNotEmpty
          ? partes.join(' - ')
          : (datos['display_name']?.toString() ?? 'Dirección no disponible');

      if (!mounted) return;
      setState(() {
        direccionActual = direccion;
        buscandoDireccionActual = false;
      });
    } catch (e) {
      debugPrint('ERROR DIRECCIÓN GPS: $e');
      if (!mounted) return;
      setState(() {
        direccionActual = 'Dirección no disponible';
        buscandoDireccionActual = false;
      });
    }
  }

  Future<void> verificarProximidad() async {
    if (!detectarProximidad || posicionActual == null) return;
    for (final lugar in ubicaciones) {
      final nombre = lugar['nombre'] as String;
      final distancia = Geolocator.distanceBetween(
        posicionActual!.latitude,
        posicionActual!.longitude,
        lugar['latitud'] as double,
        lugar['longitud'] as double,
      );
      if (distancia <= 200) {
        if (!lugaresNotificados.contains(nombre)) {
          lugaresNotificados.add(nombre);
          await NotificationService.mostrarProximidad(nombre);
        }
      } else {
        lugaresNotificados.remove(nombre);
      }
    }
  }

  void alCambiarBusqueda(String texto) {
    _debounce?.cancel();
    final consulta = texto.trim();
    if (consulta.length < 3) {
      setState(() => sugerencias = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 550), () {
      buscarSugerencias(consulta);
    });
  }

  Future<void> buscarSugerencias(String consulta) async {
    if (consulta.trim().length < 3) return;
    setState(() => buscandoSugerencias = true);

    try {
      final params = <String, String>{
        'q': consulta,
        'format': 'jsonv2',
        'limit': '6',
        'addressdetails': '1',
      };

      // Prioriza resultados cercanos a la posición actual sin impedir búsquedas lejanas.
      if (posicionActual != null) {
        final lat = posicionActual!.latitude;
        final lon = posicionActual!.longitude;
        params['viewbox'] = '${lon - 0.8},${lat + 0.8},${lon + 0.8},${lat - 0.8}';
        params['bounded'] = '0';
      }

      final uri = Uri.https('nominatim.openstreetmap.org', '/search', params);
      final respuesta = await http.get(uri, headers: const {
        'User-Agent': 'StudyTrack/1.0 (com.example.studytrack)',
        'Accept': 'application/json',
        'Accept-Language': 'es,pt-BR;q=0.9',
      });
      if (respuesta.statusCode != 200) throw Exception('Nominatim ${respuesta.statusCode}');

      final datos = jsonDecode(respuesta.body);
      if (datos is! List) return;

      final resultados = datos.map<Map<String, dynamic>>((item) {
        final m = Map<String, dynamic>.from(item as Map);
        return {
          'nombre': m['display_name']?.toString() ?? consulta,
          'latitud': double.parse(m['lat'].toString()),
          'longitud': double.parse(m['lon'].toString()),
          'tipo': m['type']?.toString() ?? '',
        };
      }).toList();

      if (!mounted || direccionController.text.trim() != consulta) return;
      setState(() => sugerencias = resultados);
    } catch (e) {
      debugPrint('ERROR SUGERENCIAS: $e');
    } finally {
      if (mounted) setState(() => buscandoSugerencias = false);
    }
  }

  Future<void> seleccionarSugerencia(Map<String, dynamic> lugar) async {
    direccionController.text = lugar['nombre'] as String;
    direccionController.selection = TextSelection.collapsed(offset: direccionController.text.length);
    direccionFocus.unfocus();
    setState(() {
      sugerencias = [];
      destinoSeleccionado = Map<String, dynamic>.from(lugar);
    });
    await calcularRutaReal(lugar['latitud'] as double, lugar['longitud'] as double);
  }

  Future<void> buscarDireccion() async {
    if (posicionActual == null) {
      mostrarMensaje('Primero presiona ACTUALIZAR POSICIÓN para obtener tu GPS.');
      return;
    }
    final consulta = direccionController.text.trim();
    if (consulta.isEmpty) {
      mostrarMensaje('Escribe una dirección o lugar.');
      return;
    }

    // Si hay sugerencias visibles, usa la primera. Si no, hace una búsqueda puntual.
    if (sugerencias.isNotEmpty) {
      await seleccionarSugerencia(sugerencias.first);
      return;
    }

    await buscarSugerencias(consulta);
    if (!mounted) return;
    if (sugerencias.isEmpty) {
      mostrarMensaje('No encontré ese lugar. Prueba con lugar, ciudad y país.');
      return;
    }
    await seleccionarSugerencia(sugerencias.first);
  }

  Future<void> seleccionarDestino(Map<String, dynamic> lugar) async {
    if (posicionActual == null) {
      mostrarMensaje('Primero actualiza tu posición GPS.');
      return;
    }
    setState(() {
      destinoSeleccionado = Map<String, dynamic>.from(lugar);
      direccionController.text = lugar['nombre'] as String;
      sugerencias = [];
    });
    await calcularRutaReal(lugar['latitud'] as double, lugar['longitud'] as double);
  }

  Future<void> cambiarModo(ModoRuta nuevoModo) async {
    if (modoRuta == nuevoModo) return;
    setState(() => modoRuta = nuevoModo);
    final destino = destinoSeleccionado;
    if (destino != null && posicionActual != null) {
      await calcularRutaReal(destino['latitud'] as double, destino['longitud'] as double);
    }
  }

  Future<void> calcularRutaReal(double latitudDestino, double longitudDestino) async {
    if (posicionActual == null) return;
    setState(() {
      calculandoRuta = true;
      rutaReal = [];
      distanciaRutaKm = null;
      duracionRutaMin = null;
    });

    try {
      final origenLat = posicionActual!.latitude;
      final origenLon = posicionActual!.longitude;
      final base = modoRuta == ModoRuta.auto
          ? 'router.project-osrm.org'
          : 'routing.openstreetmap.de';
      final path = modoRuta == ModoRuta.auto
          ? '/route/v1/driving/$origenLon,$origenLat;$longitudDestino,$latitudDestino'
          : '/routed-foot/route/v1/driving/$origenLon,$origenLat;$longitudDestino,$latitudDestino';

      final uri = Uri.https(base, path, {
        'overview': 'full',
        'geometries': 'geojson',
        'steps': 'false',
      });

      final respuesta = await http.get(uri, headers: const {
        'User-Agent': 'StudyTrack/1.0 (com.example.studytrack)',
      });
      if (respuesta.statusCode != 200) throw Exception('Ruta ${respuesta.statusCode}');

      final datos = Map<String, dynamic>.from(jsonDecode(respuesta.body));
      if (datos['code'] != 'Ok') throw Exception('NoRoute');
      final rutas = datos['routes'] as List<dynamic>;
      if (rutas.isEmpty) throw Exception('Sin rutas');

      final ruta = Map<String, dynamic>.from(rutas.first as Map);
      final geometria = Map<String, dynamic>.from(ruta['geometry'] as Map);
      final coordenadas = geometria['coordinates'] as List<dynamic>;
      final puntos = coordenadas.map((c) {
        final p = c as List<dynamic>;
        return LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble());
      }).toList();

      if (!mounted) return;
      setState(() {
        rutaReal = puntos;
        distanciaRutaKm = (ruta['distance'] as num).toDouble() / 1000;
        duracionRutaMin = (ruta['duration'] as num).toDouble() / 60;
        calculandoRuta = false;
      });

      if (puntos.isNotEmpty) {
        try {
          mapController.fitCamera(CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(puntos),
            padding: const EdgeInsets.all(45),
          ));
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('ERROR RUTA: $e');
      if (!mounted) return;
      setState(() {
        calculandoRuta = false;
        rutaReal = [];
        distanciaRutaKm = null;
        duracionRutaMin = null;
      });
      mostrarMensaje('No fue posible calcular la ruta para este modo de viaje.');
    }
  }

  void limpiarRuta() {
    direccionController.clear();
    direccionFocus.unfocus();
    setState(() {
      sugerencias = [];
      destinoSeleccionado = null;
      rutaReal = [];
      distanciaRutaKm = null;
      duracionRutaMin = null;
    });
    if (posicionActual != null) {
      try {
        mapController.move(LatLng(posicionActual!.latitude, posicionActual!.longitude), 16);
      } catch (_) {}
    }
  }

  double calcularDistancia(double lat, double lon) {
    if (posicionActual == null) return -1;
    return Geolocator.distanceBetween(
      posicionActual!.latitude,
      posicionActual!.longitude,
      lat,
      lon,
    );
  }

  String formatearDistancia(double distancia) {
    if (distancia < 0) return 'Actualiza tu posición';
    if (distancia < 1000) return '${distancia.toStringAsFixed(0)} m';
    return '${(distancia / 1000).toStringAsFixed(2)} km';
  }

  void mostrarMensaje(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje), behavior: SnackBarBehavior.floating));
  }

  Color get colorEstadoGps {
    switch (estadoGps) {
      case 'ACTIVO': return Colors.green;
      case 'BUSCANDO...': return Colors.orange;
      case 'GPS DESACTIVADO':
      case 'PERMISO DENEGADO':
      case 'PERMISO BLOQUEADO':
      case 'ERROR': return Colors.red;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: bordo,
        foregroundColor: blanco,
        elevation: 0,
        title: const Text('Ubicación y GPS', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none))],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _cabecera(),
                  const SizedBox(height: 18),
                  const Text('Servicios de Ubicación', textAlign: TextAlign.center,
                      style: TextStyle(color: bordo, fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 5),
                  const Text('Busca destinos y calcula rutas reales desde tu ubicación.',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
                  const SizedBox(height: 25),
                  _permisos(),
                  const SizedBox(height: 16),
                  _estadoGps(),
                  const SizedBox(height: 16),
                  SizedBox(height: 50, child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: bordo, foregroundColor: blanco),
                    onPressed: buscandoUbicacion ? null : obtenerUbicacion,
                    icon: buscandoUbicacion
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: blanco))
                        : const Icon(Icons.my_location),
                    label: Text(buscandoUbicacion ? 'OBTENIENDO POSICIÓN...' : 'ACTUALIZAR POSICIÓN',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  )),
                  if (posicionActual != null) ...[
                    const SizedBox(height: 22),
                    _buscador(),
                    const SizedBox(height: 22),
                    _mapa(),
                    const SizedBox(height: 14),
                    _posicionActual(),
                    if (destinoSeleccionado != null) ...[
                      const SizedBox(height: 12),
                      _infoRuta(),
                    ],
                    const SizedBox(height: 22),
                    _ubicacionesGuardadas(),
                  ],
                  const SizedBox(height: 15),
                ]),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        selectedItemColor: bordo,
        unselectedItemColor: negro,
        currentIndex: 0,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Inicio'),
          BottomNavigationBarItem(icon: Icon(Icons.menu_book_outlined), label: 'Materias'),
          BottomNavigationBarItem(icon: Icon(Icons.check_box_outlined), label: 'Tareas'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month_outlined), label: 'Calendario'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Perfil'),
        ],
      ),
    );
  }

  Widget _cabecera() => Container(
    height: 120,
    decoration: BoxDecoration(color: const Color(0xFF101923), borderRadius: BorderRadius.circular(14)),
    child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.location_on, color: Colors.blueAccent, size: 55),
      SizedBox(height: 5),
      Text('GPS LOCATION', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2)),
    ]),
  );

  Widget _permisos() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('⚙ CONFIGURACIÓN DE PERMISOS', style: TextStyle(color: bordo, fontSize: 17, fontWeight: FontWeight.bold)),
    const SizedBox(height: 10),
    _card(Column(children: [
      SwitchListTile(
        activeThumbColor: bordo,
        title: const Text('Permitir geolocalización', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('Permite que StudyTrack acceda a tu ubicación.'),
        value: permitirUbicacion,
        onChanged: (v) => setState(() {
          permitirUbicacion = v;
          if (!v) {
            posicionActual = null;
            destinoSeleccionado = null;
            rutaReal = [];
            sugerencias = [];
            estadoGps = 'DESACTIVADO';
            precisionGps = '--';
            direccionActual = 'Dirección no disponible';
            buscandoDireccionActual = false;
          }
        }),
      ),
      const Divider(height: 1),
      SwitchListTile(
        activeThumbColor: bordo,
        title: const Text('Detección de proximidad', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('Detecta cuando estás cerca de una institución.'),
        value: detectarProximidad,
        onChanged: (v) {
          setState(() {
            detectarProximidad = v;
            if (!v) lugaresNotificados.clear();
          });
          if (v && posicionActual != null) verificarProximidad();
        },
      ),
    ])),
  ]);

  Widget _estadoGps() => _card(Padding(
    padding: const EdgeInsets.all(16),
    child: Row(children: [
      const Icon(Icons.gps_fixed, color: bordo),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Estado del GPS', style: TextStyle(fontWeight: FontWeight.bold)),
        Text(estadoGps, style: TextStyle(color: colorEstadoGps, fontWeight: FontWeight.bold)),
      ])),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        const Text('Precisión', style: TextStyle(color: Colors.black54)),
        Text(precisionGps, style: const TextStyle(color: bordo, fontWeight: FontWeight.bold)),
      ]),
    ]),
  ), padding: EdgeInsets.zero);

  Widget _buscador() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    const Text('BUSCAR DESTINO', style: TextStyle(color: bordo, fontSize: 17, fontWeight: FontWeight.bold)),
    const SizedBox(height: 10),
    _card(Padding(
      padding: const EdgeInsets.all(14),
      child: Column(children: [
        TextField(
          controller: direccionController,
          focusNode: direccionFocus,
          textInputAction: TextInputAction.search,
          onChanged: alCambiarBusqueda,
          onSubmitted: (_) => buscarDireccion(),
          decoration: InputDecoration(
            labelText: '¿A dónde quieres ir?',
            hintText: 'Ej: IFSul Santana do Livramento',
            prefixIcon: const Icon(Icons.search, color: bordo),
            suffixIcon: direccionController.text.isNotEmpty
                ? IconButton(onPressed: limpiarRuta, icon: const Icon(Icons.clear))
                : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        if (buscandoSugerencias) const LinearProgressIndicator(minHeight: 2, color: bordo),
        if (sugerencias.isNotEmpty) _listaSugerencias(),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _botonModo(ModoRuta.auto, Icons.directions_car, 'Auto')),
          const SizedBox(width: 10),
          Expanded(child: _botonModo(ModoRuta.pie, Icons.directions_walk, 'A pie')),
        ]),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, height: 48, child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: bordo, foregroundColor: blanco),
          onPressed: calculandoRuta ? null : buscarDireccion,
          icon: calculandoRuta
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: blanco))
              : const Icon(Icons.route),
          label: Text(calculandoRuta ? 'CALCULANDO...' : 'BUSCAR RUTA', style: const TextStyle(fontWeight: FontWeight.bold)),
        )),
      ]),
    ), padding: EdgeInsets.zero),
  ]);

  Widget _listaSugerencias() => Container(
    margin: const EdgeInsets.only(top: 4),
    constraints: const BoxConstraints(maxHeight: 260),
    decoration: BoxDecoration(color: blanco, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10)),
    child: ListView.separated(
      shrinkWrap: true,
      itemCount: sugerencias.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final s = sugerencias[i];
        return ListTile(
          dense: true,
          leading: const Icon(Icons.location_on_outlined, color: bordo),
          title: Text(s['nombre'] as String, maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: () => seleccionarSugerencia(s),
        );
      },
    ),
  );

  Widget _botonModo(ModoRuta modo, IconData icono, String texto) {
    final activo = modoRuta == modo;
    return OutlinedButton.icon(
      onPressed: () => cambiarModo(modo),
      icon: Icon(icono),
      label: Text(texto),
      style: OutlinedButton.styleFrom(
        foregroundColor: activo ? blanco : bordo,
        backgroundColor: activo ? bordo : blanco,
        side: const BorderSide(color: bordo),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }

  Widget _mapa() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    const Text('MAPA Y RUTA', style: TextStyle(color: bordo, fontSize: 17, fontWeight: FontWeight.bold)),
    const SizedBox(height: 10),
    Container(
      height: 400,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade300)),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        FlutterMap(
          mapController: mapController,
          options: MapOptions(initialCenter: LatLng(posicionActual!.latitude, posicionActual!.longitude), initialZoom: 16),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.studytrack'),
            if (rutaReal.isNotEmpty) PolylineLayer(polylines: [Polyline(points: rutaReal, strokeWidth: 6, color: bordo)]),
            MarkerLayer(markers: [
              Marker(point: LatLng(posicionActual!.latitude, posicionActual!.longitude), width: 60, height: 60,
                child: Container(decoration: BoxDecoration(color: Colors.blue.withOpacity(.15), shape: BoxShape.circle),
                  child: const Icon(Icons.my_location, color: Colors.blue, size: 35))),
              if (destinoSeleccionado != null)
                Marker(point: LatLng(destinoSeleccionado!['latitud'] as double, destinoSeleccionado!['longitud'] as double),
                  width: 60, height: 60, child: const Icon(Icons.location_pin, color: Colors.red, size: 50)),
              ...ubicaciones.map((l) => Marker(
                point: LatLng(l['latitud'] as double, l['longitud'] as double), width: 48, height: 48,
                child: GestureDetector(onTap: () => seleccionarDestino(l), child: const Icon(Icons.location_on, color: bordo, size: 40)),
              )),
            ]),
          ],
        ),
        if (calculandoRuta) Positioned.fill(child: Container(color: Colors.black.withOpacity(.12),
          child: const Center(child: CircularProgressIndicator(color: bordo)))),
        Positioned(right: 10, bottom: 10, child: FloatingActionButton.small(
          heroTag: 'centrarGps', backgroundColor: blanco, foregroundColor: bordo,
          onPressed: () => mapController.move(LatLng(posicionActual!.latitude, posicionActual!.longitude), 16),
          child: const Icon(Icons.my_location),
        )),
      ]),
    ),
  ]);

  Widget _posicionActual() => _card(
    Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.my_location, color: bordo),
              SizedBox(width: 8),
              Text(
                'Desde: tu ubicación actual',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_on_outlined, color: bordo, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: buscandoDireccionActual
                    ? const Text(
                        'Buscando dirección...',
                        style: TextStyle(color: Colors.black54),
                      )
                    : Text(
                        direccionActual,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Latitud: ${posicionActual!.latitude.toStringAsFixed(6)}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 3),
                Text(
                  'Longitud: ${posicionActual!.longitude.toStringAsFixed(6)}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    padding: EdgeInsets.zero,
  );

  Widget _infoRuta() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: bordo.withOpacity(.06), borderRadius: BorderRadius.circular(14), border: Border.all(color: bordo.withOpacity(.3))),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(modoRuta == ModoRuta.auto ? Icons.directions_car : Icons.directions_walk, color: bordo, size: 32),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Ruta calculada', style: TextStyle(fontWeight: FontWeight.bold, color: bordo, fontSize: 16)),
        const SizedBox(height: 6),
        Text(destinoSeleccionado!['nombre'] as String, maxLines: 3, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        if (calculandoRuta) const Text('Calculando ruta por las calles...'),
        if (!calculandoRuta && distanciaRutaKm != null)
          Text('📏 Distancia: ${distanciaRutaKm!.toStringAsFixed(2)} km'),
        if (!calculandoRuta && duracionRutaMin != null) ...[
          const SizedBox(height: 6),
          Text('⏱️ Tiempo estimado: ${duracionRutaMin!.ceil()} min'),
          const SizedBox(height: 6),
          Text(modoRuta == ModoRuta.auto ? '🚗 Ruta en automóvil' : '🚶 Ruta a pie'),
        ],
      ])),
      IconButton(onPressed: limpiarRuta, icon: const Icon(Icons.close, color: bordo)),
    ]),
  );

  Widget _ubicacionesGuardadas() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    const Text('UBICACIONES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
    const SizedBox(height: 6),
    const Text('Selecciona una ubicación para calcular la ruta real desde tu posición.',
        style: TextStyle(color: Colors.black54, fontSize: 13)),
    const SizedBox(height: 10),
    ...ubicaciones.map((l) {
      final d = calcularDistancia(l['latitud'] as double, l['longitud'] as double);
      final enRango = d >= 0 && d <= 200;
      final estado = !detectarProximidad ? 'DESACTIVADO' : enRango ? 'EN RANGO' : 'FUERA DE RANGO';
      final color = !detectarProximidad ? Colors.grey : enRango ? Colors.green : Colors.orange;
      return _tarjetaUbicacion(l, formatearDistancia(d), estado, color);
    }),
  ]);

  Widget _tarjetaUbicacion(Map<String, dynamic> lugar, String distancia, String estado, Color color) {
    final seleccionado = destinoSeleccionado?['nombre'] == lugar['nombre'];
    return InkWell(
      onTap: () => seleccionarDestino(lugar),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 9), padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: seleccionado ? bordo.withOpacity(.06) : blanco,
          borderRadius: BorderRadius.circular(10), border: Border.all(color: seleccionado ? bordo : Colors.grey.shade300, width: seleccionado ? 2 : 1)),
        child: Row(children: [
          Icon(seleccionado ? Icons.navigation : Icons.location_on_outlined, color: bordo),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(lugar['nombre'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 3),
            Text(distancia, style: const TextStyle(color: Colors.black54, fontSize: 12)),
          ])),
          Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(color: color.withOpacity(.12), borderRadius: BorderRadius.circular(20)),
            child: Text(estado, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold))),
        ]),
      ),
    );
  }

  Widget _card(Widget child, {EdgeInsets padding = const EdgeInsets.all(0)}) => Container(
    padding: padding,
    decoration: BoxDecoration(color: blanco, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade300)),
    child: child,
  );
}
