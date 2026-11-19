// ComandApp - comandas, caja e inventario para restaurantes (nube en tiempo real con Supabase)
// Datos compartidos entre dispositivos via Supabase. Cada pantalla esta en lib/src/ (partes de esta libreria).
import 'dart:async';
import 'dart:math' show Random;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'src/modelos.dart';
part 'src/store.dart';
part 'src/formato.dart';
part 'src/tema.dart';
part 'src/entrada.dart';
part 'src/mesas.dart';
part 'src/pedido.dart';
part 'src/cobro.dart';
part 'src/cocina.dart';
part 'src/admin.dart';
part 'src/productos.dart';
part 'src/historial.dart';
part 'src/inventario.dart';
part 'src/personal.dart';
part 'src/gastos.dart';
part 'src/reportes.dart';

// ====== CREDENCIALES DE SUPABASE (la key publishable es segura para el cliente) ======
const kSupabaseUrl = 'https://tmjejukvdcfifajnmlca.supabase.co';
const kSupabaseKey = 'sb_publishable_yb-3O7QqTE9rgtUGJWSgdw_OXeHLgFg';

// ====== FIREBASE (avisos con la app cerrada). Son datos publicos de la app, no son secretos. ======
const kFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyBwrQZniZwykxIKKgAg_i2gCnJY4k0Zwwc',
  appId: '1:269265058861:android:49a8c46cc27ca312aa8ca4',
  messagingSenderId: '269265058861',
  projectId: 'comandaapp-d7f5c',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // En la pagina web no hay avisos push (Firebase solo esta configurado para Android).
  if (!kIsWeb) {
    try {
      await Firebase.initializeApp(options: kFirebaseOptions);
    } catch (e) {
      debugPrint('Firebase no disponible: $e');
    }
  }
  try {
    await Supabase.initialize(url: kSupabaseUrl, anonKey: kSupabaseKey);
  } catch (e) {
    store.error = 'No se pudo conectar a la nube: $e';
  }
  runApp(const ComandApp());
}

SupabaseClient get sb => Supabase.instance.client;

/// PIN demasiado facil de adivinar (misma regla que private.pin_debil en la base de datos).
bool pinDebil(String p) {
  if (p.length != 6) return false;
  if (RegExp(r'^(\d)\1{5}$').hasMatch(p)) return true;          // 000000, 111111
  if (RegExp(r'^(\d\d)\1\1$').hasMatch(p)) return true;          // 121212
  if (RegExp(r'^(\d\d\d)\1$').hasMatch(p)) return true;          // 123123
  if (RegExp(r'^(\d)(\d)(\d)\3\2\1$').hasMatch(p)) return true; // 123321
  if (RegExp(r'^(\d)\1(\d)\2(\d)\3$').hasMatch(p)) return true; // 112233
  const escaleras = '0123456789012345678901234567890'; // ascendente con vuelta al 0
  final desc = escaleras.split('').reversed.join();
  return escaleras.contains(p) || desc.contains(p);
}
const kMsgPinFacil = 'Ese PIN es muy facil de adivinar (como 123456 o 111111). Elige otro.';
