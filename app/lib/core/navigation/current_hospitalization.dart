import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Último episodio abierto en la bitácora. Solo orienta la navegación de la
/// barra inferior (Bitácora / Entrega); no concede acceso: cada ruta vuelve a
/// autorizar contra RLS y la pasarela.
final currentHospitalizationProvider = StateProvider<String?>((ref) => null);
